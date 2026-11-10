package backend;

#if sys
import haxe.Json;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.Int64;
import haxe.io.Path;
import haxe.Timer;
import sys.FileSystem;
import sys.io.File;
import sys.io.FileOutput;
import sys.thread.Thread;
import sys.thread.Mutex;
import sys.thread.Lock;

/**
 * Incremental split chart exporter.
 *
 * JSON mode writes standard song JSON part files. Note rows are streamed one at
 * a time and sections may be continued in the next part. Each row fragment
 * carries its original section index so ChartJsonStream can reconstruct the
 * original chart without loading a multi-gigabyte string into memory.
 *
 * Binary mode writes HSCB v2 containers. Packed rows are serialized directly
 * into buffered fixed-field records; legacy rows use a JSON fallback record.
 * A small JSON manifest carries song and section metadata.
 */
class SplitChartSaveJob
{
	public static inline var FORMAT_JSON:Int = 0;
	public static inline var FORMAT_BINARY:Int = 1;
	public static inline var CHECKPOINT_1GB:Float = 1000000000.0;
	public static inline var CHECKPOINT_1_5GB:Float = 1500000000.0;
	public static inline var CHECKPOINT_2GB:Float = 2000000000.0;
	public static inline var HARD_PART_LIMIT:Float = 2100000000.0;
	private static inline var FOOTER_RESERVE:Float = 4096.0;
	private static inline var PROCESS_ROWS_PER_BATCH:Int = 8192;
	private static inline var PROCESS_BUDGET_MS:Float = 18.0;
	private static inline var BINARY_BUFFER_FLUSH_BYTES:Int = 4194304;

	private var _complete:Bool = false;
	private var _paused:Bool = false;
	private var _error:String = null;
	private var _checkpointLabel:String = null;
	private var _cancelled:Bool = false;
	private var _backgroundRunning:Bool = false;
	public var complete(get, never):Bool;
	public var paused(get, never):Bool;
	public var error(get, never):String;
	public var checkpointLabel(get, never):String;
	public var cancelled(get, never):Bool;
	public var backgroundRunning(get, never):Bool;
	public var rowsWritten:Int64 = Int64.ofInt(0);
	public var totalRows:Int64 = Int64.ofInt(0);
	public var currentPart(default, null):Int = 1;
	public var bytesInCurrentPart(default, null):Float = 0;
	public var outputBase(default, null):String;

	private var workerThread:Thread = null;
	private var workerMutex:Mutex = null;
	private var workerWake:Lock = null;
	private var cancelRequested:Bool = false;
	private var binaryBuffer:BytesBuffer = null;
	
	private var binary:Bool;
	private var song:Dynamic;
	private var sections:Array<Dynamic>;
	private var events:Array<Dynamic>;
	private var packedSections:Map<Int, PackedNoteBuffer>;
	private var sectionMetadata:Array<Dynamic> = [];
	private var sectionMetaBodies:Array<String> = [];
	private var headerFields:Dynamic = {};
	private var output:FileOutput;
	private var activeTempPath:String = null;
	private var activeFinalPath:String = null;
	private var generatedPaths:Array<String> = [];
	private var stage:Int = 0; // 0 = note rows, 1 = events (JSON only), 2 = finished
	private var sectionIndex:Int = 0;
	private var rowIndex:Int64 = Int64.ofInt(0);
	private var eventIndex:Int = 0;
	private var sectionOpen:Bool = false;
	private var sectionHasRows:Bool = false;
	private var partFragmentCount:Int = 0;
	private var partEventCount:Int = 0;
	private var binarySectionMarkerWritten:Bool = false;
	private var nextCheckpoint:Int = 0;
	private var rolloverRequested:Bool = false;
	private var manifestPath:String;

	// The final warning is shown shortly before the hard 2.1 GB boundary so
	// the user can save the current part or let the writer roll over safely.
	private var checkpointBytes:Array<Float> = [CHECKPOINT_1GB, CHECKPOINT_1_5GB, CHECKPOINT_2GB, HARD_PART_LIMIT - 50000000.0];
	private var checkpointNames:Array<String> = ["1 GB", "1.5 GB", "2 GB", "2.1 GB limit approaching (50 MB early)"];

	public function new(song:Dynamic, packedSections:Map<Int, PackedNoteBuffer>, selectedPath:String, binary:Bool)
	{
		if (song == null) throw 'Cannot save an empty chart';
		if (selectedPath == null || selectedPath.length == 0) throw 'No output filename was selected';
		this.song = song;
		this.sections = Reflect.field(song, 'notes');
		this.events = Reflect.field(song, 'events');
		this.packedSections = packedSections == null ? new Map<Int, PackedNoteBuffer>() : packedSections;
		this.binary = binary;
		this.outputBase = Path.withoutExtension(selectedPath);
		if (outputBase == null || outputBase.length == 0) throw 'Could not determine the output filename';
		if (sections == null) sections = [];
		if (events == null) events = [];

		buildMetadata();
		for (i in 0...sections.length) totalRows += getSectionRowCount(i);

		if (binary)
		{
			manifestPath = outputBase + '.json';
			if (FileSystem.exists(manifestPath))
				throw 'Binary manifest already exists: ' + manifestPath + '. Choose a new filename.';
			beginBinaryPart();
		}
		else
		{
			beginJsonPart(false);
		}
	}


	private inline function lockState():Bool
	{
		if (workerMutex == null) return false;
		workerMutex.acquire();
		return true;
	}

	private inline function unlockState(locked:Bool):Void
	{
		if (locked) workerMutex.release();
	}

	private function get_complete():Bool { var locked = lockState(); var value = _complete; unlockState(locked); return value; }
	private function get_paused():Bool { var locked = lockState(); var value = _paused; unlockState(locked); return value; }
	private function get_error():String { var locked = lockState(); var value = _error; unlockState(locked); return value; }
	private function get_checkpointLabel():String { var locked = lockState(); var value = _checkpointLabel; unlockState(locked); return value; }
	private function get_cancelled():Bool { var locked = lockState(); var value = _cancelled; unlockState(locked); return value; }
	private function get_backgroundRunning():Bool { var locked = lockState(); var value = _backgroundRunning; unlockState(locked); return value; }

	/**
	 * Start the export on a worker thread. ChartingState must keep the source
	 * chart immutable until the worker completes or is cancelled.
	 *
	 * The mutex is held only for one bounded batch so progress, checkpoint, and
	 * cancel requests cannot wait behind a multi-second write operation.
	 */
	public function startBackground():Void
	{
		if (workerThread != null || _complete || _error != null) return;
		workerMutex = new Mutex();
		workerWake = new Lock();
		_backgroundRunning = true;
		try
		{
			workerThread = Thread.create(function()
			{
				while (true)
				{
					workerMutex.acquire();
					if (cancelRequested)
					{
						cleanupOutputFiles();
						_cancelled = true;
						_backgroundRunning = false;
						workerMutex.release();
						return;
					}
					if (_complete || _error != null)
					{
						_backgroundRunning = false;
						workerMutex.release();
						return;
					}
					if (_paused)
					{
						workerMutex.release();
						workerWake.wait();
						continue;
					}
					processFrame(PROCESS_ROWS_PER_BATCH, PROCESS_BUDGET_MS);
					workerMutex.release();
					Sys.sleep(0.001);
				}
			});
		}
		catch (error:Dynamic)
		{
			_backgroundRunning = false;
			throw error;
		}
	}

	private function buildMetadata():Void
	{
		for (field in Reflect.fields(song))
		{
			if (field == 'notes' || field == 'events' || field == '__chartStreamPath' || field == '__chartSourcePath'
				|| field.indexOf('__hsc') == 0) continue;
			Reflect.setField(headerFields, field, Reflect.field(song, field));
		}

		for (i in 0...sections.length)
		{
			var section:Dynamic = sections[i];
			if (section == null)
			{
				sectionMetadata.push(null);
				sectionMetaBodies.push('');
				continue;
			}
			var meta:Dynamic = {};
			for (field in Reflect.fields(section))
				if (field != 'sectionNotes' && field != '__hscSectionIndex')
					Reflect.setField(meta, field, Reflect.field(section, field));
			var metaForManifest:Dynamic = Reflect.copy(meta);
			Reflect.setField(metaForManifest, 'sectionNotes', []);
			sectionMetadata.push(metaForManifest);
			var metaJson:String = Json.stringify(meta);
			sectionMetaBodies.push(metaJson.length > 2 ? metaJson.substring(1, metaJson.length - 1) : '');
		}
	}

	private function getSectionRowCount(index:Int):Int64
	{
		if (index < 0 || index >= sections.length || sections[index] == null) return Int64.ofInt(0);
		var raw:Array<Dynamic> = Reflect.field(sections[index], 'sectionNotes');
		var count:Int64 = Int64.ofInt(raw == null ? 0 : raw.length);
		var packed:PackedNoteBuffer = packedSections.get(index);
		if (packed != null) count += packed.length64;
		return count;
	}

	private function getRow(index:Int, row:Int64):Dynamic
	{
		var section:Dynamic = sections[index];
		var raw:Array<Dynamic> = section == null ? null : Reflect.field(section, 'sectionNotes');
		var rawCount:Int = raw == null ? 0 : raw.length;
		if (row < Int64.ofInt(rawCount)) return raw[Int64.toInt(row)];
		var packed:PackedNoteBuffer = packedSections.get(index);
		if (packed != null) return packed.getRow64(row - Int64.ofInt(rawCount));
		return null;
	}

	private function partPath(index:Int):String
	{
		var suffix:String = index == 1 ? '' : '-' + index;
		return outputBase + suffix + (binary ? '.bin' : '.json');
	}

	private function openOutput(path:String):Void
	{
		if (FileSystem.exists(path) && FileSystem.isDirectory(path)) throw 'Output path is a directory: ' + path;
		if (FileSystem.exists(path)) throw 'A split output part already exists: ' + path + '. Choose a new filename to avoid overwriting existing chart data.';
		activeFinalPath = path;
		activeTempPath = path + '.hscsave-tmp';
		if (FileSystem.exists(activeTempPath)) FileSystem.deleteFile(activeTempPath);
		output = File.write(activeTempPath, true);
		output.bigEndian = true;
		generatedPaths.push(activeTempPath);
		bytesInCurrentPart = 0;
	}

	private function writeText(text:String):Int
	{
		var bytes:Bytes = Bytes.ofString(text);
		output.writeFullBytes(bytes, 0, bytes.length);
		bytesInCurrentPart += bytes.length;
		return bytes.length;
	}

	private function jsonHeader(part:Int):String
	{
		// Put the split marker first so the loader can identify the format with a
		// short prefix read even if ordinary song metadata is unusually large.
		var header:Dynamic = {};
		Reflect.setField(header, '__hscSplitJson', true);
		Reflect.setField(header, '__hscSplitVersion', 1);
		Reflect.setField(header, '__hscPartIndex', part);
		Reflect.setField(header, '__hscSectionMetadata', sectionMetadata);
		for (field in Reflect.fields(headerFields))
			Reflect.setField(header, field, Reflect.field(headerFields, field));
		var encoded:String = Json.stringify(header);
		// Psych Engine stores notes inside the song object, not at the root.
		// Keeping them nested allows the normal chart parser to stream each part.
		return '{"song":' + encoded.substring(0, encoded.length - 1) + ',"notes":[';
	}

	private function beginJsonPart(eventOnly:Bool):Void
	{
		openOutput(partPath(currentPart));
		writeText(jsonHeader(currentPart));
		partFragmentCount = 0;
		partEventCount = 0;
		sectionOpen = false;
		sectionHasRows = false;
		if (eventOnly) writeText('],"events":[');
	}

	private function beginBinaryPart():Void
	{
		openOutput(partPath(currentPart));
		output.writeByte(72); // H
		output.writeByte(83); // S
		output.writeByte(67); // C
		output.writeByte(66); // B
		output.writeInt32(2);
		bytesInCurrentPart = 8;
		binaryBuffer = new BytesBuffer();
		binarySectionMarkerWritten = false;
	}

	private function startJsonSectionFragment(index:Int):Void
	{
		if (partFragmentCount > 0) writeText(',');
		writeText('{"__hscSectionIndex":' + index);
		var body:String = index >= 0 && index < sectionMetaBodies.length ? sectionMetaBodies[index] : '';
		if (body.length > 0) writeText(',' + body);
		writeText(',"sectionNotes":[');
		partFragmentCount++;
		sectionOpen = true;
		sectionHasRows = false;
	}

	private function closeJsonSectionFragment():Void
	{
		if (!sectionOpen) return;
		writeText(']}');
		sectionOpen = false;
		sectionHasRows = false;
	}

	private function writeVarUInt(value:Int):Int
	{
		var count:Int = 0;
		var remaining:Int = value;
		while (remaining >= 0x80)
		{
			output.writeByte((remaining & 0x7F) | 0x80);
			remaining = remaining >>> 7;
			count++;
		}
		output.writeByte(remaining);
		return count + 1;
	}

	private function varUIntBytes(value:Int):Int
	{
		var count:Int = 1;
		var remaining:Int = value;
		while (remaining >= 0x80) { remaining = remaining >>> 7; count++; }
		return count;
	}

	private function flushBinaryBuffer(?force:Bool = false):Void
	{
		if (!binary || binaryBuffer == null || binaryBuffer.length == 0) return;
		if (!force && binaryBuffer.length < BINARY_BUFFER_FLUSH_BYTES) return;
		var bytes:Bytes = binaryBuffer.getBytes();
		output.writeFullBytes(bytes, 0, bytes.length);
		bytesInCurrentPart += bytes.length;
		binaryBuffer = new BytesBuffer();
	}

	private function bufferedPartSize():Float
	{
		return bytesInCurrentPart + (binaryBuffer == null ? 0 : binaryBuffer.length);
	}

	private function writeBinaryPackedRow(packed:PackedNoteBuffer, rowIndex:Int64):Int
	{
		var noteType:Dynamic = packed.getType64(rowIndex);
		var typeBytes:Bytes = noteType == null ? null : Bytes.ofString(Json.stringify(noteType));
		var typeLength:Int = typeBytes == null ? 0 : typeBytes.length;
		var typePrefix:Int = varUIntBytes(typeLength);
		binaryBuffer.addByte(1); // typed packed-note record
		binaryBuffer.addDouble(packed.getTime64(rowIndex));
		binaryBuffer.addInt32(packed.getLane64(rowIndex));
		binaryBuffer.addDouble(packed.getSustain64(rowIndex));
		appendVarUIntToBuffer(typeLength);
		if (typeBytes != null) binaryBuffer.add(typeBytes);
		var recordSize:Int = 1 + 8 + 4 + 8 + typePrefix + typeLength;
		if (binaryBuffer.length >= BINARY_BUFFER_FLUSH_BYTES) flushBinaryBuffer(true);
		return recordSize;
	}

	private function writeBinaryLegacyRow(bytes:Bytes):Int
	{
		binaryBuffer.addByte(2); // JSON fallback for legacy rows with arbitrary fields
		appendVarUIntToBuffer(bytes.length);
		binaryBuffer.add(bytes);
		var recordSize:Int = 1 + varUIntBytes(bytes.length) + bytes.length;
		if (binaryBuffer.length >= BINARY_BUFFER_FLUSH_BYTES) flushBinaryBuffer(true);
		return recordSize;
	}

	private function appendVarUIntToBuffer(value:Int):Void
	{
		var remaining:Int = value;
		while (remaining >= 0x80)
		{
			binaryBuffer.addByte((remaining & 0x7F) | 0x80);
			remaining = remaining >>> 7;
		}
		binaryBuffer.addByte(remaining);
	}

	private function writeBinarySectionMarker(index:Int):Void
	{
		binaryBuffer.addByte(0);
		binaryBuffer.addInt32(index);
		binarySectionMarkerWritten = true;
	}

	private function closeCurrentOutput(?publish:Bool = true):Void
	{
		if (output != null)
		{
			if (binary) flushBinaryBuffer(true);
			output.flush();
			output.close();
			output = null;
		}
		if (activeTempPath != null)
		{
			if (publish)
			{
				if (activeFinalPath != null && FileSystem.exists(activeFinalPath))
					throw 'A split output part already exists: ' + activeFinalPath;
				FileSystem.rename(activeTempPath, activeFinalPath);
				generatedPaths.remove(activeTempPath);
				generatedPaths.push(activeFinalPath);
			}
			activeTempPath = null;
			activeFinalPath = null;
		}
	}

	private function closeJsonPartWithEmptyEvents():Void
	{
		closeJsonSectionFragment();
		writeText('],"events":[]}}');
		closeCurrentOutput();
	}

	private function closeJsonEventPart():Void
	{
		writeText(']}}');
		closeCurrentOutput();
	}

	private function rolloverPart():Void
	{
		if (binary)
		{
			closeCurrentOutput();
			currentPart++;
			beginBinaryPart();
			binarySectionMarkerWritten = false;
		}
		else if (stage == 0)
		{
			closeJsonPartWithEmptyEvents();
			currentPart++;
			beginJsonPart(false);
		}
		else
		{
			closeJsonEventPart();
			currentPart++;
			beginJsonPart(true);
		}
		nextCheckpoint = 0;
		rolloverRequested = false;
	}

	private function checkCheckpoint():Void
	{
		var currentSize:Float = bufferedPartSize();
		if (nextCheckpoint < checkpointBytes.length && currentSize >= checkpointBytes[nextCheckpoint])
		{
			_checkpointLabel = checkpointNames[nextCheckpoint];
			flushBinaryBuffer(true);
			_paused = true;
			if (output != null) output.flush();
		}
		if (currentSize >= HARD_PART_LIMIT - FOOTER_RESERVE)
			rolloverRequested = true;
	}

	/**
	 * Process a bounded amount of file output. The editor calls this once per
	 * frame so saving a large chart does not require one giant JSON string.
	 */
	public function processFrame(?maxRows:Int = PROCESS_ROWS_PER_BATCH, ?budgetMs:Float = PROCESS_BUDGET_MS):Void
	{
		if (_complete || _paused || _error != null) return;
		var started:Float = Timer.stamp();
		var processed:Int = 0;
		try
		{
			while (!_complete && processed < maxRows && (Timer.stamp() - started) * 1000.0 < budgetMs)
			{
				if (rolloverRequested)
				{
					rolloverPart();
					continue;
				}

				if (stage == 0)
				{
					if (sectionIndex >= sections.length)
					{
						closeJsonSectionFragment();
						if (binary)
						{
							closeCurrentOutput();
							writeBinaryManifest();
							_complete = true;
							break;
						}
						else
						{
							writeText('],"events":[');
							stage = 1;
						}
						continue;
					}

					var sectionCount:Int64 = getSectionRowCount(sectionIndex);
					if (rowIndex >= sectionCount)
					{
						closeJsonSectionFragment();
						sectionIndex++;
						rowIndex = Int64.ofInt(0);
						binarySectionMarkerWritten = false;
						continue;
					}

					var raw:Array<Dynamic> = sections[sectionIndex] == null ? null : Reflect.field(sections[sectionIndex], 'sectionNotes');
					var rawCount:Int = raw == null ? 0 : raw.length;
					var prefixBytes:Float = 0;
					var estimatedRecordBytes:Float = 0;
					var row:Dynamic = null;
					var encodedBytes:Bytes = null;
					var packed:PackedNoteBuffer = packedSections.get(sectionIndex);
					var packedIndex:Int64 = rowIndex - Int64.ofInt(rawCount);
					var isPackedRecord:Bool = binary && rowIndex >= Int64.ofInt(rawCount) && packed != null
						&& !packed.hasExtraFields64(packedIndex);
					if (isPackedRecord)
					{
						var typeValue:Dynamic = packed.getType64(packedIndex);
						var typeLength:Int = typeValue == null ? 0 : Bytes.ofString(Json.stringify(typeValue)).length;
						estimatedRecordBytes = 1 + 8 + 4 + 8 + varUIntBytes(typeLength) + typeLength;
					}
					else
					{
						row = (binary && rowIndex >= Int64.ofInt(rawCount) && packed != null)
							? packed.getRow64(packedIndex) : getRow(sectionIndex, rowIndex);
						if (row == null) throw 'Encountered an empty note row in section ' + sectionIndex + ' at row ' + Int64.toStr(rowIndex);
						var encoded:String = Json.stringify(row);
						encodedBytes = Bytes.ofString(encoded);
						if (binary)
							estimatedRecordBytes = 1 + varUIntBytes(encodedBytes.length) + encodedBytes.length;
						else
							prefixBytes = encodedBytes.length + (sectionHasRows ? 1 : 0) + (sectionOpen ? 0 : ((sectionIndex >= 0 && sectionIndex < sectionMetaBodies.length) ? sectionMetaBodies[sectionIndex].length + 64 : 64));
					}

					var currentPartBytes:Float = bufferedPartSize();
					var nextRecordBytes:Float = binary ? estimatedRecordBytes + (binarySectionMarkerWritten ? 0 : 5) : prefixBytes;
					if (currentPartBytes + nextRecordBytes + FOOTER_RESERVE > HARD_PART_LIMIT && currentPartBytes > (binary ? 8 : 512))
					{
						rolloverPart();
						continue;
					}
					if (currentPartBytes + nextRecordBytes + FOOTER_RESERVE > HARD_PART_LIMIT)
						throw 'A single serialized note row is too large for the 2.1 GB part limit';

					if (binary)
					{
						if (!binarySectionMarkerWritten) writeBinarySectionMarker(sectionIndex);
						if (isPackedRecord)
							writeBinaryPackedRow(packed, rowIndex - Int64.ofInt(rawCount));
						else
							writeBinaryLegacyRow(encodedBytes);
					}
					else
					{
						if (!sectionOpen) startJsonSectionFragment(sectionIndex);
						if (sectionHasRows) writeText(',');
						output.writeFullBytes(encodedBytes, 0, encodedBytes.length);
						bytesInCurrentPart += encodedBytes.length;
						sectionHasRows = true;
					}
					rowIndex += Int64.ofInt(1);
					rowsWritten += Int64.ofInt(1);
					processed++;
					checkCheckpoint();
					if (_paused) return;
				}
				else if (stage == 1)
				{
					if (eventIndex >= events.length)
					{
						closeJsonEventPart();
						_complete = true;
						break;
					}
					var eventRow:Dynamic = events[eventIndex];
					var encodedEvent:String = Json.stringify(eventRow);
					var eventBytes:Bytes = Bytes.ofString(encodedEvent);
					var need:Float = eventBytes.length + (partEventCount > 0 ? 1 : 0) + FOOTER_RESERVE;
					if (bytesInCurrentPart + need > HARD_PART_LIMIT && bytesInCurrentPart > 512)
					{
						rolloverPart();
						continue;
					}
					if (bytesInCurrentPart + need > HARD_PART_LIMIT)
						throw 'A single chart event is too large for the 2.1 GB part limit';
					if (partEventCount > 0) writeText(',');
					output.writeFullBytes(eventBytes, 0, eventBytes.length);
					bytesInCurrentPart += eventBytes.length;
					partEventCount++;
					eventIndex++;
					processed++;
					checkCheckpoint();
					if (_paused) return;
				}
				else break;
			}

			if (binary && !_complete && stage == 0 && sectionIndex >= sections.length)
			{
				closeCurrentOutput();
				writeBinaryManifest();
				_complete = true;
			}
			else if (!binary && stage == 1 && eventIndex >= events.length && !_complete)
			{
				closeJsonEventPart();
				_complete = true;
			}
		}
		catch (error:Dynamic)
		{
			_error = Std.string(error);
			closeCurrentOutput(false);
			if (activeTempPath != null) generatedPaths.push(activeTempPath);
		}
	}

	public function respondToCheckpoint(saveCurrentPart:Bool):Void
	{
		var locked:Bool = lockState();
		if (!_paused) { unlockState(locked); return; }
		_paused = false;
		_checkpointLabel = null;
		if (saveCurrentPart) rolloverRequested = true;
		else nextCheckpoint++;
		unlockState(locked);
		if (workerWake != null) workerWake.release();
	}

	private function writeBinaryManifest():Void
	{
		if (FileSystem.exists(manifestPath)) throw 'Binary manifest already exists: ' + manifestPath + '. Choose a new filename.';
		var manifest:Dynamic = {};
		// Put the format marker first so the loader can identify this compact
		// manifest with a small prefix read, before scanning the metadata arrays.
		Reflect.setField(manifest, '__hscBinarySplit', true);
		Reflect.setField(manifest, '__hscSplitVersion', 2);
		Reflect.setField(manifest, '__hscBinaryPartCount', currentPart);
		Reflect.setField(manifest, '__hscTotalNoteRows64', Int64.toStr(totalRows));
		for (field in Reflect.fields(headerFields)) Reflect.setField(manifest, field, Reflect.field(headerFields, field));
		Reflect.setField(manifest, 'notes', sectionMetadata);
		Reflect.setField(manifest, 'events', events);
		var wrapped:Dynamic = {song: manifest};
		var manifestTemp:String = manifestPath + '.hscsave-tmp';
		if (FileSystem.exists(manifestTemp)) FileSystem.deleteFile(manifestTemp);
		generatedPaths.push(manifestTemp);
		File.saveContent(manifestTemp, Json.stringify(wrapped));
		FileSystem.rename(manifestTemp, manifestPath);
		generatedPaths.remove(manifestTemp);
		generatedPaths.push(manifestPath);
	}

	public function getProgressText():String
	{
		var locked:Bool = lockState();
		var sizeMB:Int = Std.int(bytesInCurrentPart / 1000000.0);
		var text:String = (binary ? 'Binary' : 'JSON') + ' split save | Part ' + currentPart + ' | '
			+ Int64.toStr(rowsWritten) + '/' + Int64.toStr(totalRows) + ' note rows | ' + sizeMB + ' MB';
		unlockState(locked);
		return text;
	}

	public function getOutputFiles():Array<String>
	{
		var locked:Bool = lockState();
		var result:Array<String> = generatedPaths.copy();
		unlockState(locked);
		return result;
	}

	private function cleanupOutputFiles():Void
	{
		closeCurrentOutput(false);
		if (activeTempPath != null) generatedPaths.push(activeTempPath);
		for (path in generatedPaths)
		{
			try { if (FileSystem.exists(path) && !FileSystem.isDirectory(path)) FileSystem.deleteFile(path); }
			catch (error:Dynamic) {}
		}
		generatedPaths = [];
		_complete = false;
	}

	public function cancel():Void
	{
		var locked:Bool = lockState();
		if (workerThread != null && _backgroundRunning && !_complete)
		{
			cancelRequested = true;
			unlockState(locked);
			if (workerWake != null) workerWake.release();
			return;
		}
		cleanupOutputFiles();
		_cancelled = true;
		_backgroundRunning = false;
		unlockState(locked);
	}
}
#end
