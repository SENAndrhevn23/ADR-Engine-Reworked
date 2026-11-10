package backend;

import haxe.Json;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.Eof;
import haxe.io.Path;
import sys.io.File;
import sys.io.FileInput;
import sys.io.FileOutput;

/**
 * File-backed JSON chart reader.
 *
 * During the metadata pass, sectionNotes rows are copied one-at-a-time to a
 * temporary binary sidecar. The JSON parser never creates the full chart text
 * or full sectionNotes object graph. PlayState later reads sidecar records
 * sequentially in bounded batches. Sequential IO avoids FileInput.seek's Int
 * offset limitation for files larger than 2 GB.
 *
 * This class is only called from #if sys code. Embedded assets use the normal
 * in-memory Song.loadFromJson fallback.
 */
class ChartJsonStream
{
	// Keep the just-created sidecar reader open across the Freeplay/Story -> PlayState
	// state transition. This avoids reopening a large temporary file after the loader
	// has returned and also keeps the underlying file handle valid if the path changes.
	private static var preparedReaders:Map<String, ChartJsonStream> = new Map<String, ChartJsonStream>();
	private static var deletePreparedOnDiscard:Map<String, Bool> = new Map<String, Bool>();
	// The sidecar belongs to the loaded SONG, not to one PlayState instance.
	// Keep its path across state resets so Retry can reopen it from byte zero.
	private static var currentSidecarPath:String = null;
	private static var currentSidecarReader:ChartJsonStream = null;

	private var file:FileInput;
	private var additionalPartPaths:Array<String> = [];
	private var additionalPartIndex:Int = 0;
	private var binaryPartFiles:Bool = false;
	private var binaryVersion:Int = 1;
	private var byteBuffer:Bytes = Bytes.alloc(65536);
	private var bufferPosition:Int = 0;
	private var bufferLength:Int = 0;
	private var logicalPosition:Float = 0;
	private var lookahead:Int = -2;
	private var sidecarOutput:FileOutput = null;
	private var currentSectionIndex:Int = -1;
	private var noteRowBuffer:Bytes = Bytes.alloc(4096);

	/** Open a completed sidecar for sequential gameplay reads. */
	public function new(path:String, ?additionalPaths:Array<String>, ?binaryParts:Bool = false)
	{
		if (path == null || path.length == 0 || !sys.FileSystem.exists(path))
			throw 'Chart stream file does not exist: ' + path;
		additionalPartPaths = additionalPaths == null ? [] : additionalPaths.copy();
		additionalPartIndex = 0;
		binaryPartFiles = binaryParts;
		openPart(path);
	}

	private function openPart(path:String):Void
	{
		if (file != null) file.close();
		file = File.read(path, true);
		bufferPosition = 0;
		bufferLength = 0;
		lookahead = -2;
		currentSectionIndex = -1;
		if (binaryPartFiles)
		{
			var h:Int = file.readByte();
			var s:Int = file.readByte();
			var c:Int = file.readByte();
			var b:Int = file.readByte();
			file.bigEndian = true;
			var version:Int = file.readInt32();
			if (h != 72 || s != 83 || c != 67 || b != 66 || (version != 1 && version != 2))
				throw 'Invalid H-Slice binary chart part: ' + path;
			binaryVersion = version;
		}
	}

	private function advancePart():Bool
	{
		if (additionalPartIndex >= additionalPartPaths.length) return false;
		var nextPath:String = additionalPartPaths[additionalPartIndex++];
		if (!sys.FileSystem.exists(nextPath))
			throw 'Missing split chart part: ' + nextPath;
		openPart(nextPath);
		return true;
	}

	/** Reuse the sidecar reader opened immediately after the write completed. */
	public static function takePreparedReader(path:String):ChartJsonStream
	{
		var key = normalizeSidecarPath(path);
		var prepared = preparedReaders.get(key);
		if (prepared != null)
			preparedReaders.remove(key);
		else
			prepared = new ChartJsonStream(key);

		currentSidecarPath = key;
		currentSidecarReader = prepared;
		return prepared;
	}

	/** Close and remove a prepared reader when a chart load is abandoned. */
	public static function discardPreparedReader(path:String):Void
	{
		if (path == null || path.length == 0) return;
		var key = normalizeSidecarPath(path);
		var prepared = preparedReaders.get(key);
		if (prepared != null)
		{
			preparedReaders.remove(key);
			prepared.close();
		}

		var currentKey:String = normalizeSidecarPath(currentSidecarPath);
		if (currentKey != null && currentKey == key)
		{
			if (currentSidecarReader != null) currentSidecarReader.close();
			currentSidecarReader = null;
			currentSidecarPath = null;
		}
		var shouldDelete:Bool = deletePreparedOnDiscard.exists(key) && deletePreparedOnDiscard.get(key);
		deletePreparedOnDiscard.remove(key);
		if (shouldDelete && sys.FileSystem.exists(key) && !sys.FileSystem.isDirectory(key)) sys.FileSystem.deleteFile(key);
	}

	private static function normalizeSidecarPath(path:String):String
	{
		// C++ FileSystem.fullPath() may return null for a path that does not
		// exist yet. Never replace a valid candidate with that null result.
		if (path == null || path.length == 0) return null;
		try
		{
			var resolved:String = sys.FileSystem.fullPath(path);
			if (resolved != null && resolved.length > 0) return resolved;
		}
		catch (error:Dynamic) {}
		return path;
	}

	/** Read only the start of a file to detect split manifests without loading a huge part. */
	public static function isSplitChart(path:String):Bool
	{
		if (path == null || path.length == 0 || !sys.FileSystem.exists(path)) return false;
		var input:FileInput = null;
		try
		{
			var fileSize:Float = sys.FileSystem.stat(path).size;
			var prefixLength:Int = Std.int(Math.min(1048576.0, fileSize));
			if (prefixLength <= 0) return false;
			input = File.read(path, true);
			var prefix:Bytes = input.read(prefixLength);
			var text:String = prefix.toString();
			input.close();
			return text.indexOf('"__hscSplitJson"') >= 0 || text.indexOf('"__hscBinarySplit"') >= 0;
		}
		catch (error:Dynamic)
		{
			if (input != null) input.close();
			return false;
		}
	}

	/** Parse song metadata and stream raw note rows into a temporary sidecar. */
	public static function loadSong(path:String):Dynamic
	{
		if (currentSidecarPath != null) discardPreparedReader(currentSidecarPath);
		var reader = new ChartJsonStream(path);
		var outputPath:String = null;
		var preparedReader:ChartJsonStream = null;
		try
		{
			outputPath = createSidecarPath();
			if (outputPath == null || outputPath.length == 0)
				throw 'Chart stream sidecar path creation returned an empty path';
			reader.sidecarOutput = File.write(outputPath, true);
			reader.sidecarOutput.bigEndian = true;
			var song = reader.parseRootSong();

			if (Reflect.field(song, '__hscBinarySplit') == true)
			{
				// Binary manifest contains section metadata only. The note stream lives
				// in adjacent HSCB parts and is read directly without a RAM copy.
				reader.sidecarOutput.close();
				reader.sidecarOutput = null;
				reader.close();
				if (sys.FileSystem.exists(outputPath)) sys.FileSystem.deleteFile(outputPath);
				var partCount:Int = Std.int(Reflect.field(song, '__hscBinaryPartCount'));
				if (partCount < 1) throw 'Invalid binary chart manifest: no data parts were recorded';
				var base:String = Path.withoutExtension(path);
				var firstPart:String = base + '.bin';
				var additional:Array<String> = [];
				for (partIndex in 2...(partCount + 1)) additional.push(base + '-' + partIndex + '.bin');
				preparedReader = new ChartJsonStream(firstPart, additional, true);
				var key:String = normalizeSidecarPath(firstPart);
				preparedReaders.set(key, preparedReader);
				deletePreparedOnDiscard.set(key, false);
				currentSidecarPath = key;
				currentSidecarReader = preparedReader;
				Reflect.setField(song, '__chartStreamPath', key);
				Reflect.setField(song, '__chartSourcePath', normalizeSidecarPath(path));
				return song;
			}

			if (Reflect.field(song, '__hscSplitJson') == true)
			{
				var base:String = Path.withoutExtension(path);
				var partIndex:Int = 2;
				while (partIndex <= 100000)
				{
					var partPath:String = base + '-' + partIndex + '.json';
					if (!sys.FileSystem.exists(partPath)) break;
					var partReader = new ChartJsonStream(partPath);
					partReader.sidecarOutput = reader.sidecarOutput;
					var partSong:Dynamic = partReader.parseRootSong();
					reader.sidecarOutput = partReader.sidecarOutput;
					partReader.sidecarOutput = null;
					partReader.close();
					var moreEvents:Array<Dynamic> = Reflect.field(partSong, 'events');
					if (moreEvents != null && moreEvents.length > 0)
					{
						var mergedEvents:Array<Dynamic> = Reflect.field(song, 'events');
						if (mergedEvents == null) { mergedEvents = []; Reflect.setField(song, 'events', mergedEvents); }
						for (event in moreEvents) mergedEvents.push(event);
					}
					partIndex++;
				}
				var metadataSections:Array<Dynamic> = Reflect.field(song, '__hscSectionMetadata');
				if (metadataSections == null) throw 'Split JSON chart is missing section metadata';
				Reflect.setField(song, 'notes', metadataSections);
			}

			reader.sidecarOutput.close();
			reader.sidecarOutput = null;
			reader.close();
			outputPath = normalizeSidecarPath(outputPath);
			if (!sys.FileSystem.exists(outputPath))
				throw 'Chart stream sidecar was not created. Check that the cache directory is writable and has enough free space: ' + outputPath;
			preparedReader = new ChartJsonStream(outputPath);
			preparedReaders.set(outputPath, preparedReader);
			deletePreparedOnDiscard.set(outputPath, true);
			currentSidecarPath = outputPath;
			currentSidecarReader = preparedReader;
			Reflect.setField(song, '__chartStreamPath', outputPath);
			Reflect.setField(song, '__chartSourcePath', normalizeSidecarPath(path));
			return song;
		}
		catch (error:Dynamic)
		{
			reader.close();
			if (preparedReader != null) preparedReader.close();
			if (outputPath != null && outputPath.length > 0 && sys.FileSystem.exists(outputPath))
				try sys.FileSystem.deleteFile(outputPath) catch (cleanupError:Dynamic) {}
			throw error;
		}
	}

	private static function createSidecarPath():String
	{
		// Try persistent user cache locations first, then OS temp and the launch
		// directory. Do not canonicalize the not-yet-created filename: on C++,
		// FileSystem.fullPath() can return null for a missing file, which used to
		// turn the next File.write(null) into the reported [file_open,null] error.
		var roots:Array<String> = [];
		var xdg:String = Sys.getEnv('XDG_CACHE_HOME');
		if (xdg != null && xdg.length > 0 && !roots.contains(xdg)) roots.push(xdg);

		var home:String = Sys.getEnv('HOME');
		if (home != null && home.length > 0)
		{
			var homeCache:String = Path.join([home, '.cache']);
			if (homeCache != null && homeCache.length > 0 && !roots.contains(homeCache)) roots.push(homeCache);
		}

		var temp:String = Sys.getEnv('TMPDIR');
		if (temp != null && temp.length > 0 && !roots.contains(temp)) roots.push(temp);
		#if windows
		var winTemp:String = Sys.getEnv('TEMP');
		if (winTemp != null && winTemp.length > 0 && !roots.contains(winTemp)) roots.push(winTemp);
		var winTmp:String = Sys.getEnv('TMP');
		if (winTmp != null && winTmp.length > 0 && !roots.contains(winTmp)) roots.push(winTmp);
		#else
		if (!roots.contains('/tmp')) roots.push('/tmp');
		#end
		var cwd:String = Sys.getCwd();
		if (cwd != null && cwd.length > 0 && !roots.contains(cwd)) roots.push(cwd);

		var lastError:String = 'No candidate cache or temporary directory was available';
		for (root in roots)
		{
			var probePath:String = null;
			try
			{
				if (root == null || root.length == 0)
					throw 'Empty cache root';

				var directory:String = Path.join([root, 'hslice', 'chart-streams']);
				if (directory == null || directory.length == 0)
					throw 'Could not construct sidecar directory from root: ' + root;
				ensureDirectory(directory);
				if (!sys.FileSystem.exists(directory) || !sys.FileSystem.isDirectory(directory))
					throw 'Sidecar cache path is not a directory: ' + directory;

				// The directory exists, so resolving it is safe. Join the filename only
				// after that; never call fullPath() on a file that does not exist yet.
				var absoluteDirectory:String = normalizeSidecarPath(directory);
				if (absoluteDirectory == null || absoluteDirectory.length == 0)
					absoluteDirectory = directory;
				var unique:String = Std.string(Date.now().getTime()) + '_' + Std.string(Std.random(1000000));
				probePath = Path.join([absoluteDirectory, 'hslice_chart_stream_' + unique + '.bin']);
				if (probePath == null || probePath.length == 0)
					throw 'Could not construct chart-stream filename in: ' + absoluteDirectory;

				var probe:FileOutput = File.write(probePath, true);
				probe.close();
				if (!sys.FileSystem.exists(probePath) || sys.FileSystem.isDirectory(probePath))
					throw 'Sidecar write probe did not create a regular file: ' + probePath;

				// Keep the empty file. loadSong() will reopen and truncate this exact
				// path for the real stream, avoiding a delete/recreate race.
				var resolvedPath:String = normalizeSidecarPath(probePath);
				return (resolvedPath != null && resolvedPath.length > 0) ? resolvedPath : probePath;
			}
			catch (error:Dynamic)
			{
				lastError = Std.string(error) + ' (candidate: ' + (probePath == null ? '<null>' : probePath) + ')';
				if (probePath != null && probePath.length > 0 && sys.FileSystem.exists(probePath) && !sys.FileSystem.isDirectory(probePath))
				{
					try
					{
						sys.FileSystem.deleteFile(probePath);
					}
					catch (cleanupError:Dynamic) {}
				}
			}
		}
		throw 'Unable to create a chart-stream sidecar. Checked ' + roots.length + ' locations. Last error: ' + lastError;
	}

	private static function ensureDirectory(path:String):Void
	{
		if (path == null || path.length == 0)
			throw 'Cannot create an empty chart-stream directory path';
		if (sys.FileSystem.exists(path))
		{
			if (!sys.FileSystem.isDirectory(path))
				throw 'Chart-stream path exists but is not a directory: ' + path;
			return;
		}
		var parent:String = Path.directory(path);
		if (parent != null && parent.length > 0 && parent != path && !sys.FileSystem.exists(parent))
			ensureDirectory(parent);
		sys.FileSystem.createDirectory(path);
		if (!sys.FileSystem.exists(path) || !sys.FileSystem.isDirectory(path))
			throw 'Unable to create chart-stream directory: ' + path;
	}

	/** Read one sequential sidecar record. HSCB v1 is JSON-row based; v2 uses direct packed fields and JSON fallback records. */
	public function readNextRecord():Dynamic
	{
		try
		{
			while (true)
			{
				if (binaryPartFiles && binaryVersion >= 2)
				{
					var marker:Int = readBufferedByte();
					if (marker == 0)
					{
						currentSectionIndex = readBufferedInt32LE();
						continue;
					}
					if (marker == 1)
					{
						var time:Float = readBufferedDoubleLE();
						var lane:Int = readBufferedInt32LE();
						var sustain:Float = readBufferedDoubleLE();
						var typeLength:Int = readVarUInt();
						var packedRow:Array<Dynamic> = [time, lane, sustain];
						if (typeLength > 0) packedRow.push(Json.parse(readBufferedBytes(typeLength).toString()));
						return {sectionIndex: currentSectionIndex, row: packedRow};
					}
					if (marker == 2)
					{
						var fallbackLength:Int = readVarUInt();
						if (fallbackLength <= 0) throw 'Invalid HSCB v2 fallback row length';
						return {sectionIndex: currentSectionIndex, row: Json.parse(readBufferedBytes(fallbackLength).toString())};
					}
					throw 'Invalid HSCB v2 record marker: ' + marker;
				}

				var byteLength:Int = readVarUInt();
				if (byteLength == 0)
				{
					currentSectionIndex = readBufferedInt32();
					continue;
				}
				if (byteLength < 0) throw 'Invalid chart stream record length';
				var raw:Bytes = readBufferedBytes(byteLength);
				return {sectionIndex: currentSectionIndex, row: Json.parse(raw.toString())};
			}
		}
		catch (error:Eof)
		{
			if (advancePart()) return readNextRecord();
			return null;
		}
	}

	private function readVarUInt():Int
	{
		var value:Int = 0;
		var shift:Int = 0;
		while (true)
		{
			var byte:Int = readBufferedByte();
			value |= (byte & 0x7F) << shift;
			if ((byte & 0x80) == 0) return value;
			shift += 7;
			if (shift > 28) throw 'Invalid chart stream variable-length integer';
		}
		return value;
	}

	private function writeVarUInt(value:Int):Void
	{
		var remaining:Int = value;
		while (remaining >= 0x80)
		{
			sidecarOutput.writeByte((remaining & 0x7F) | 0x80);
			remaining = remaining >>> 7;
		}
		sidecarOutput.writeByte(remaining);
	}

	public function close():Void
	{
		if (sidecarOutput != null)
		{
			sidecarOutput.close();
			sidecarOutput = null;
		}
		if (file != null)
		{
			file.close();
			file = null;
		}
		// Closing a PlayState reader does not delete its sidecar: a reset may
		// immediately create another PlayState for the same SONG. The path is
		// cleared only by discardPreparedReader() after EOF or chart replacement.
		if (currentSidecarReader == this) currentSidecarReader = null;
	}

	private function parseRootSong():Dynamic
	{
		skipWhitespace();
		// Accept an optional UTF-8 BOM produced by some Windows chart editors.
		if (peekByte() == 239)
		{
			var bom1 = readByte();
			var bom2 = readByte();
			var bom3 = readByte();
			if (bom1 != 239 || bom2 != 187 || bom3 != 191)
				throw 'Invalid UTF-8 BOM at start of chart JSON';
			skipWhitespace();
		}
		expect(123); // {
		var song:Dynamic = null;
		var flatSong:Dynamic = {};
		skipWhitespace();
		while (peekByte() != 125)
		{
			var key:String = readString();
			expect(58); // :
			if (key == 'song' && peekNextValueIsObject())
				song = parseSongObject();
			else
			{
				// Also accept charts whose song fields are directly at the JSON root.
				var value:Dynamic = key == 'notes' ? parseNotesArray() : parseValue();
				Reflect.setField(flatSong, key, value);
			}
			skipWhitespace();
			if (peekByte() == 44)
			{
				readByte();
				skipWhitespace();
			}
			else break;
		}
		expect(125); // }
		if (song == null && Reflect.hasField(flatSong, 'notes')) song = flatSong;
		if (song == null) throw 'Invalid chart JSON: missing song object or root notes array';
		return song;
	}

	private function peekNextValueIsObject():Bool
	{
		skipWhitespace();
		return peekByte() == 123;
	}

	private function parseSongObject():Dynamic
	{
		expect(123);
		var song:Dynamic = {};
		skipWhitespace();
		while (peekByte() != 125)
		{
			var key:String = readString();
			expect(58);
			var value:Dynamic = key == 'notes' ? parseNotesArray() : parseValue();
			Reflect.setField(song, key, value);
			skipWhitespace();
			if (peekByte() == 44)
			{
				readByte();
				skipWhitespace();
			}
			else break;
		}
		expect(125);
		return song;
	}

	private function parseNotesArray():Dynamic
	{
		skipWhitespace();
		if (peekByte() != 91) return parseValue();
		expect(91);
		var sections:Array<Dynamic> = [];
		skipWhitespace();
		while (peekByte() != 93)
		{
			var sectionIndex:Int = sections.length;
			var value:Dynamic = peekByte() == 123 ? parseSectionObject(sectionIndex) : parseValue();
			sections.push(value);
			skipWhitespace();
			if (peekByte() == 44)
			{
				readByte();
				skipWhitespace();
			}
			else break;
		}
		expect(93);
		return sections;
	}

	private function parseSectionObject(sectionIndex:Int):Dynamic
	{
		expect(123);
		var section:Dynamic = {};
		var foundNotes:Bool = false;
		var actualSectionIndex:Int = sectionIndex;
		skipWhitespace();
		while (peekByte() != 125)
		{
			var key:String = readString();
			expect(58);
			var value:Dynamic;
			if (key == '__hscSectionIndex')
			{
				value = parseValue();
				actualSectionIndex = Std.int(value);
				Reflect.setField(section, key, actualSectionIndex);
			}
			else if (key == 'sectionNotes')
			{
				foundNotes = true;
				value = streamSectionNotes(actualSectionIndex);
				Reflect.setField(section, key, value);
			}
			else
			{
				value = parseValue();
				Reflect.setField(section, key, value);
			}
			skipWhitespace();
			if (peekByte() == 44)
			{
				readByte();
				skipWhitespace();
			}
			else break;
		}
		expect(125);
		if (!foundNotes) Reflect.setField(section, 'sectionNotes', []);
		return section;
	}

	/** Copy each note row directly to disk; never keep the section array in RAM. */
	private function streamSectionNotes(sectionIndex:Int):Dynamic
	{
		skipWhitespace();
		if (peekByte() != 91) return parseValue();
		expect(91);
		sidecarOutput.writeByte(0); // Section marker; zero-length rows are invalid JSON.
		sidecarOutput.writeInt32(sectionIndex);
		skipWhitespace();
		while (peekByte() != 93)
		{
			var rowLength:Int = readNoteRowIntoBuffer();
			writeVarUInt(rowLength);
			sidecarOutput.writeFullBytes(noteRowBuffer, 0, rowLength);
			skipWhitespace();
			if (peekByte() == 44)
			{
				readByte();
				skipWhitespace();
			}
			else break;
		}
		expect(93);
		return [];
	}

	private function parseValue():Dynamic
	{
		skipWhitespace();
		var next = peekByte();
		if (next == 123) return parseGenericObject();
		if (next == 91) return parseGenericArray();
		if (next == 34) return readString();
		return parseScalar();
	}

	private function parseGenericObject():Dynamic
	{
		expect(123);
		var value:Dynamic = {};
		skipWhitespace();
		while (peekByte() != 125)
		{
			var key:String = readString();
			expect(58);
			Reflect.setField(value, key, parseValue());
			skipWhitespace();
			if (peekByte() == 44)
			{
				readByte();
				skipWhitespace();
			}
			else break;
		}
		expect(125);
		return value;
	}

	private function parseGenericArray():Dynamic
	{
		expect(91);
		var value:Array<Dynamic> = [];
		skipWhitespace();
		while (peekByte() != 93)
		{
			value.push(parseValue());
			skipWhitespace();
			if (peekByte() == 44)
			{
				readByte();
				skipWhitespace();
			}
			else break;
		}
		expect(93);
		return value;
	}

	private function parseScalar():Dynamic
	{
		return Json.parse(readRawJsonValue().toString());
	}

	private function readString():String
	{
		return cast Json.parse(readRawJsonValue().toString());
	}

	/** Capture one note-row value into a reusable buffer to avoid per-row allocations. */
	private function readNoteRowIntoBuffer():Int
	{
		skipWhitespace();
		var length:Int = 0;
		var first:Int = readByte();
		if (first < 0) throw new Eof();
		length = appendNoteByte(length, first);
		if (first == 34)
		{
			var escaped:Bool = false;
			while (true)
			{
				var c = readByte();
				if (c < 0) throw new Eof();
				length = appendNoteByte(length, c);
				if (escaped) escaped = false;
				else if (c == 92) escaped = true;
				else if (c == 34) break;
			}
		}
		else if (first == 123 || first == 91)
		{
			var depth:Int = 1;
			var inString:Bool = false;
			var escaped:Bool = false;
			while (depth > 0)
			{
				var c = readByte();
				if (c < 0) throw new Eof();
				length = appendNoteByte(length, c);
				if (inString)
				{
					if (escaped) escaped = false;
					else if (c == 92) escaped = true;
					else if (c == 34) inString = false;
				}
				else if (c == 34) inString = true;
				else if (c == 123 || c == 91) depth++;
				else if (c == 125 || c == 93) depth--;
			}
		}
		else
		{
			while (true)
			{
				var c = peekByte();
				if (c < 0 || c <= 32 || c == 44 || c == 93 || c == 125) break;
				length = appendNoteByte(length, readByte());
			}
		}
		return length;
	}

	private function appendNoteByte(length:Int, value:Int):Int
	{
		if (length >= noteRowBuffer.length)
		{
			var expanded = Bytes.alloc(noteRowBuffer.length * 2);
			expanded.blit(0, noteRowBuffer, 0, noteRowBuffer.length);
			noteRowBuffer = expanded;
		}
		noteRowBuffer.set(length, value);
		return length + 1;
	}

	private function readRawJsonValue():Bytes
	{
		skipWhitespace();
		var output = new BytesBuffer();
		var first:Int = readByte();
		if (first < 0) throw new Eof();
		output.addByte(first);

		if (first == 34)
		{
			var escaped:Bool = false;
			while (true)
			{
				var c = readByte();
				if (c < 0) throw new Eof();
				output.addByte(c);
				if (escaped) escaped = false;
				else if (c == 92) escaped = true;
				else if (c == 34) break;
			}
		}
		else if (first == 123 || first == 91)
		{
			var depth:Int = 1;
			var inString:Bool = false;
			var escaped:Bool = false;
			while (depth > 0)
			{
				var c = readByte();
				if (c < 0) throw new Eof();
				output.addByte(c);
				if (inString)
				{
					if (escaped) escaped = false;
					else if (c == 92) escaped = true;
					else if (c == 34) inString = false;
				}
				else if (c == 34) inString = true;
				else if (c == 123 || c == 91) depth++;
				else if (c == 125 || c == 93) depth--;
			}
		}
		else
		{
			while (true)
			{
				var c = peekByte();
				if (c < 0 || c <= 32 || c == 44 || c == 93 || c == 125) break;
				output.addByte(readByte());
			}
		}
		return output.getBytes();
	}

	private function skipWhitespace():Void
	{
		while (true)
		{
			var c = peekByte();
			if (c == 32 || c == 9 || c == 10 || c == 13) readByte();
			else break;
		}
	}

	private function expect(character:Int):Void
	{
		skipWhitespace();
		var actual = readByte();
		if (actual != character) throw 'Invalid chart JSON: expected "' + String.fromCharCode(character) + '"';
	}

	/** Refill a bounded 64 KiB input buffer from the file. */
	private function readBufferedByte():Int
	{
		if (bufferPosition >= bufferLength)
		{
			try
			{
				bufferLength = file.readBytes(byteBuffer, 0, byteBuffer.length);
			}
			catch (error:Eof)
			{
				bufferLength = 0;
			}
			bufferPosition = 0;
			if (bufferLength <= 0) throw new Eof();
		}
		return byteBuffer.get(bufferPosition++);
	}

	private function readBufferedInt32():Int
	{
		var b0 = readBufferedByte();
		var b1 = readBufferedByte();
		var b2 = readBufferedByte();
		var b3 = readBufferedByte();
		return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
	}

	private function readBufferedInt32LE():Int
	{
		var b0 = readBufferedByte();
		var b1 = readBufferedByte();
		var b2 = readBufferedByte();
		var b3 = readBufferedByte();
		return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
	}

	private function readBufferedDoubleLE():Float
	{
		return readBufferedBytes(8).getDouble(0);
	}

	private function readBufferedBytes(length:Int):Bytes
	{
		var result = Bytes.alloc(length);
		var written:Int = 0;
		while (written < length)
		{
			if (bufferPosition >= bufferLength)
			{
				try
				{
					bufferLength = file.readBytes(byteBuffer, 0, byteBuffer.length);
				}
				catch (error:Eof)
				{
					bufferLength = 0;
				}
				bufferPosition = 0;
				if (bufferLength <= 0) throw new Eof();
			}
			var available:Int = bufferLength - bufferPosition;
			var amount:Int = length - written;
			if (amount > available) amount = available;
			result.blit(written, byteBuffer, bufferPosition, amount);
			bufferPosition += amount;
			written += amount;
		}
		return result;
	}

	private function peekByte():Int
	{
		if (lookahead == -2)
		{
			try
			{
				lookahead = readBufferedByte();
			}
			catch (e:Eof)
			{
				lookahead = -1;
			}
		}
		return lookahead;
	}

	private function readByte():Int
	{
		var value:Int;
		if (lookahead != -2)
		{
			value = lookahead;
			lookahead = -2;
		}
		else
		{
			try
			{
				value = readBufferedByte();
			}
			catch (e:Eof)
			{
				value = -1;
			}
		}
		if (value >= 0) logicalPosition += 1;
		return value;
	}
}
