package backend;

import haxe.Int64;

/**
 * Segmented compact storage for chart-editor generated notes.
 *
 * Logical note counts and indexes are 64-bit. Segment indexes and indexes
 * inside one segment remain 32-bit because each segment is bounded to 1M rows.
 * This allows one section to exceed the signed 32-bit row-count boundary
 * without allocating a single multi-billion-element native array.
 */
class PackedNoteBuffer
{
	private static inline var CHUNK_SIZE:Int = 1048576;
	private static var MAX_ROWS:Int64 = Int64.parseString("5000000000");
	private static var INT_MAX_64:Int64 = Int64.ofInt(2147483647);
	private static var LEGACY_MATERIALIZE_LIMIT:Int64 = Int64.ofInt(2000000);

	private var timeChunks:Array<Array<Float>> = [];
	private var laneChunks:Array<Array<Int>> = [];
	private var sustainChunks:Array<Array<Float>> = [];
	private var typeChunks:Array<Array<Int>> = [];
	private var typeValues:Array<Dynamic> = [];
	private var typeLookup:Map<String, Int> = new Map<String, Int>();
	private var extraFields:Map<String, Array<Dynamic>> = new Map<String, Array<Dynamic>>();
	private var nonDecreasingTime:Bool = true;
	private var lastTime:Float = -1.0e30;
	private var _length64:Int64 = Int64.ofInt(0);
	// Hot append cursor. Keeping these as 32-bit segment/local indexes avoids
	// dividing a 64-bit row index for every appended note.
	private var writeChunkIndex:Int = 0;
	private var writeChunkOffset:Int = 0;

	/** Legacy Int view for older editor/render code. Saturates instead of wrapping. */
	public var length(get, never):Int;
	/** Exact logical count, safe above 2,147,483,647. */
	public var length64(get, never):Int64;

	private inline function get_length():Int
	{
		return _length64 > INT_MAX_64 ? 2147483647 : Int64.toInt(_length64);
	}

	private inline function get_length64():Int64
	{
		return _length64;
	}

	public function new() {}

	private function reserveFloatArray(values:Array<Float>, requiredCapacity:Int):Void
	{
		#if cpp
		if (requiredCapacity > cpp.NativeArray.capacity(values))
			cpp.NativeArray.reserve(values, requiredCapacity);
		#end
	}

	private function reserveIntArray(values:Array<Int>, requiredCapacity:Int):Void
	{
		#if cpp
		if (requiredCapacity > cpp.NativeArray.capacity(values))
			cpp.NativeArray.reserve(values, requiredCapacity);
		#end
	}

	/** Reserve the segments needed for a 64-bit logical row capacity. */
	public function reserve(requiredCapacity:Int64):Bool
	{
		if (requiredCapacity < _length64 || requiredCapacity < Int64.ofInt(0) || requiredCapacity > MAX_ROWS) return false;
		if (requiredCapacity == Int64.ofInt(0)) return true;

		var chunkSize64:Int64 = Int64.ofInt(CHUNK_SIZE);
		var quotient:Int64 = requiredCapacity / chunkSize64;
		var requiredChunks:Int = Int64.toInt(quotient);
		if ((requiredCapacity % chunkSize64) != Int64.ofInt(0)) requiredChunks++;

		try
		{
			while (timeChunks.length < requiredChunks)
			{
				var times:Array<Float> = [];
				var lanes:Array<Int> = [];
				var sustains:Array<Float> = [];
				reserveFloatArray(times, CHUNK_SIZE);
				reserveIntArray(lanes, CHUNK_SIZE);
				reserveFloatArray(sustains, CHUNK_SIZE);
				timeChunks.push(times);
				laneChunks.push(lanes);
				sustainChunks.push(sustains);
				typeChunks.push(null);
			}
			return timeChunks.length >= requiredChunks && laneChunks.length >= requiredChunks
				&& sustainChunks.length >= requiredChunks && typeChunks.length >= requiredChunks;
		}
		catch (error:Dynamic)
		{
			return false;
		}
	}

	private inline function chunkIndex64(index:Int64):Int
	{
		return Int64.toInt(index / Int64.ofInt(CHUNK_SIZE));
	}

	private inline function localIndex64(index:Int64):Int
	{
		return Int64.toInt(index % Int64.ofInt(CHUNK_SIZE));
	}

	private inline function asIndex64(index:Int):Int64
	{
		return Int64.ofInt(index);
	}

	private function internType(value:Dynamic):Int
	{
		if (value == null) return -1;
		var key:String = (Std.isOfType(value, String) ? 's:' : 'v:') + Std.string(value);
		var existing:Null<Int> = typeLookup.get(key);
		if (existing != null) return existing;
		var index:Int = typeValues.length;
		typeValues.push(value);
		typeLookup.set(key, index);
		return index;
	}

	public function internTypeValue(value:Dynamic):Int
	{
		return internType(value);
	}

	private function ensureTypeChunk(segment:Int, usedBefore:Int):Bool
	{
		if (segment < 0 || segment >= typeChunks.length) return false;
		if (typeChunks[segment] != null) return true;
		try
		{
			var values:Array<Int> = [];
			reserveIntArray(values, CHUNK_SIZE);
			for (_ in 0...usedBefore) values.push(-1);
			typeChunks[segment] = values;
			return true;
		}
		catch (error:Dynamic)
		{
			return false;
		}
	}

	public function appendValues(time:Float, lane:Int, sustain:Float, ?noteType:Dynamic):Void
	{
		appendEncoded(time, lane, sustain, internType(noteType));
	}

	/** Append one packed record without doing 64-bit division on the hot path. */
	public function appendEncoded(time:Float, lane:Int, sustain:Float, typeId:Int):Bool
	{
		if (_length64 >= MAX_ROWS) return false;
		if (writeChunkIndex >= timeChunks.length)
		{
			var nextLength:Int64 = _length64 + Int64.ofInt(1);
			if (!reserve(nextLength)) return false;
		}

		var segment:Int = writeChunkIndex;
		var local:Int = writeChunkOffset;
		if (_length64 == Int64.ofInt(0)) lastTime = time;
		else if (time < lastTime) nonDecreasingTime = false;

		var typeColumn:Array<Int> = typeChunks[segment];
		if (typeId >= 0 && typeColumn == null)
		{
			if (!ensureTypeChunk(segment, local)) return false;
			typeColumn = typeChunks[segment];
		}

		timeChunks[segment].push(time);
		laneChunks[segment].push(lane);
		sustainChunks[segment].push(sustain);
		if (typeColumn != null) typeColumn.push(typeId);
		lastTime = time;
		_length64 += Int64.ofInt(1);
		writeChunkOffset++;
		if (writeChunkOffset >= CHUNK_SIZE)
		{
			writeChunkOffset = 0;
			writeChunkIndex++;
		}
		return true;
	}

	/**
	 * Generate a batch directly into the packed columns. This avoids one public
	 * appendEncoded() call and one Int64 length update per generated note.
	 * Returns the number of rows committed; partial batches are retained if a
	 * later optional type-column allocation fails.
	 */
	public function appendGeneratedBatch(count:Int, startTime:Float, startLane:Int, timeStep:Float,
		laneStep:Int, sustain:Float, typeId:Int):Int
	{
		if (count <= 0) return 0;
		var available:Int64 = MAX_ROWS - _length64;
		if (available <= Int64.ofInt(0)) return 0;
		if (available < Int64.ofInt(count)) count = Int64.toInt(available);
		if (count <= 0 || !reserve(_length64 + Int64.ofInt(count))) return 0;

		var written:Int = 0;
		var time:Float = startTime;
		var lane:Int = startLane;
		while (written < count)
		{
			var segment:Int = writeChunkIndex;
			var local:Int = writeChunkOffset;
			if (segment < 0 || segment >= timeChunks.length) break;

			var typeColumn:Array<Int> = typeChunks[segment];
			if (typeId >= 0 && typeColumn == null)
			{
				if (!ensureTypeChunk(segment, local)) break;
				typeColumn = typeChunks[segment];
			}

			var times:Array<Float> = timeChunks[segment];
			var lanes:Array<Int> = laneChunks[segment];
			var sustains:Array<Float> = sustainChunks[segment];
			var rowsInChunk:Int = CHUNK_SIZE - local;
			var remaining:Int = count - written;
			if (rowsInChunk > remaining) rowsInChunk = remaining;
			var chunkEnd:Int = written + rowsInChunk;
			while (written < chunkEnd)
			{
				time += timeStep;
				lane += laneStep;
				if (_length64 == Int64.ofInt(0) && written == 0) lastTime = time;
				else if (time < lastTime) nonDecreasingTime = false;
				times.push(time);
				lanes.push(lane);
				sustains.push(sustain);
				if (typeColumn != null) typeColumn.push(typeId);
				lastTime = time;
				written++;
				local++;
			}

			writeChunkOffset = local;
			if (writeChunkOffset >= CHUNK_SIZE)
			{
				writeChunkOffset = 0;
				writeChunkIndex++;
			}
		}
		if (written > 0) _length64 += Int64.ofInt(written);
		return written;
	}

	/** Last timestamp committed to this buffer, used to continue a generated batch. */
	public inline function getLastWrittenTime():Float return lastTime;

	/** Last lane committed to this buffer, used to continue a generated batch. */
	public function getLastWrittenLane():Int
	{
		if (_length64 <= Int64.ofInt(0)) return 0;
		var lastIndex:Int64 = _length64 - Int64.ofInt(1);
		return laneChunks[chunkIndex64(lastIndex)][localIndex64(lastIndex)];
	}

	public function appendRow(row:Dynamic):Void
	{
		if (row == null || row.length < 2) return;
		var time:Float = row[0] == null ? 0 : row[0];
		var lane:Int = row[1] == null ? 0 : Std.int(row[1]);
		var sustain:Float = row.length > 2 && row[2] != null ? row[2] : 0;
		var noteType:Dynamic = row.length > 3 ? row[3] : null;
		var index:Int64 = _length64;
		if (!appendValuesChecked(time, lane, sustain, noteType)) return;
		if (row.length > 4)
		{
			var extras:Array<Dynamic> = [];
			for (i in 4...row.length) extras.push(row[i]);
			extraFields.set(Int64.toStr(index), extras);
		}
	}

	private function appendValuesChecked(time:Float, lane:Int, sustain:Float, noteType:Dynamic):Bool
	{
		return appendEncoded(time, lane, sustain, internType(noteType));
	}

	public inline function getTime64(index:Int64):Float
	{
		return timeChunks[chunkIndex64(index)][localIndex64(index)];
	}

	public inline function getLane64(index:Int64):Int
	{
		return laneChunks[chunkIndex64(index)][localIndex64(index)];
	}

	public inline function getSustain64(index:Int64):Float
	{
		return sustainChunks[chunkIndex64(index)][localIndex64(index)];
	}

	private inline function getTypeId64(index:Int64):Int
	{
		var values:Array<Int> = typeChunks[chunkIndex64(index)];
		if (values == null) return -1;
		var local:Int = localIndex64(index);
		return local >= 0 && local < values.length ? values[local] : -1;
	}

	public inline function getTime(index:Int):Float return getTime64(asIndex64(index));
	public inline function getLane(index:Int):Int return getLane64(asIndex64(index));
	public inline function getSustain(index:Int):Float return getSustain64(asIndex64(index));

	private function setTypeId64(index:Int64, typeId:Int):Void
	{
		var segment:Int = chunkIndex64(index);
		var local:Int = localIndex64(index);
		var values:Array<Int> = typeChunks[segment];
		if (values == null)
		{
			if (typeId < 0 || !ensureTypeChunk(segment, local)) return;
			values = typeChunks[segment];
		}
		while (values.length < local) values.push(-1);
		if (local == values.length) values.push(typeId);
		else values[local] = typeId;
	}

	public inline function setTime64(index:Int64, value:Float):Void
	{
		timeChunks[chunkIndex64(index)][localIndex64(index)] = value;
		nonDecreasingTime = false;
	}

	public inline function setLane64(index:Int64, value:Int):Void
	{
		laneChunks[chunkIndex64(index)][localIndex64(index)] = value;
	}

	public inline function setSustain64(index:Int64, value:Float):Void
	{
		sustainChunks[chunkIndex64(index)][localIndex64(index)] = value;
	}

	public inline function setTime(index:Int, value:Float):Void setTime64(asIndex64(index), value);
	public inline function setLane(index:Int, value:Int):Void setLane64(asIndex64(index), value);
	public inline function setSustain(index:Int, value:Float):Void setSustain64(asIndex64(index), value);

	public function getType64(index:Int64):Dynamic
	{
		var typeId:Int = getTypeId64(index);
		return typeId >= 0 && typeId < typeValues.length ? typeValues[typeId] : null;
	}

	/** True when a packed row has fields beyond time/lane/sustain/type. */
	public inline function hasExtraFields64(index:Int64):Bool
	{
		return extraFields.exists(Int64.toStr(index));
	}

	public function getType(index:Int):Dynamic return getType64(asIndex64(index));

	/** Materialize exactly one row; intended for selection/UI, not bulk export. */
	public function getRow64(index:Int64):Array<Dynamic>
	{
		if (index < Int64.ofInt(0) || index >= _length64) return null;
		var row:Array<Dynamic> = [getTime64(index), getLane64(index), getSustain64(index)];
		var typeValue:Dynamic = getType64(index);
		var extras:Array<Dynamic> = extraFields.get(Int64.toStr(index));
		if (typeValue != null || extras != null) row.push(typeValue);
		if (extras != null) for (extra in extras) row.push(extra);
		return row;
	}

	public function getRow(index:Int):Array<Dynamic> return getRow64(asIndex64(index));

	public function find(time:Float, lane:Int):Int
	{
		// Existing editor selection APIs return Int. Search only the Int-indexable
		// prefix; the save/export path uses the 64-bit accessors directly.
		var searchable:Int = length;
		if (nonDecreasingTime)
		{
			var low:Int = 0;
			var high:Int = searchable - 1;
			while (low <= high)
			{
				var middle:Int = low + Std.int((high - low) / 2);
				var middleTime:Float = getTime(middle);
				if (middleTime < time) low = middle + 1;
				else if (middleTime > time) high = middle - 1;
				else
				{
					var scan:Int = middle;
					while (scan >= 0 && getTime(scan) == time)
					{
						if (getLane(scan) == lane) return scan;
						scan--;
					}
					scan = middle + 1;
					while (scan < searchable && getTime(scan) == time)
					{
						if (getLane(scan) == lane) return scan;
						scan++;
					}
					return -1;
				}
			}
			return -1;
		}
		for (i in 0...searchable)
			if (getTime(i) == time && getLane(i) == lane) return i;
		return -1;
	}

	public function takeAt(index:Int):Array<Dynamic>
	{
		var row:Array<Dynamic> = getRow(index);
		if (row == null || !removeAt(index)) return null;
		return row;
	}

	private inline function popLastFromChunks():Void
	{
		var segment:Int = chunkIndex64(_length64 - Int64.ofInt(1));
		timeChunks[segment].pop();
		laneChunks[segment].pop();
		sustainChunks[segment].pop();
		if (typeChunks[segment] != null) typeChunks[segment].pop();
	}

	/** Removal shifts following records, so refuse the legacy O(n) operation on 64-bit-sized sections. */
	public function removeAt(index:Int):Bool
	{
		if (_length64 > INT_MAX_64 || index < 0 || index >= length) return false;
		for (i in index...(length - 1))
		{
			setTime(i, getTime(i + 1));
			setLane(i, getLane(i + 1));
			setSustain(i, getSustain(i + 1));
			setTypeId64(asIndex64(i), getTypeId64(asIndex64(i + 1)));
		}
		popLastFromChunks();
		_length64 -= Int64.ofInt(1);
		writeChunkIndex = chunkIndex64(_length64);
		writeChunkOffset = localIndex64(_length64);
		extraFields.remove(Int64.toStr(asIndex64(index)));
		nonDecreasingTime = false;
		return true;
	}

	public function shiftTimes(delta:Float):Void
	{
		// Walk contiguous segments so the hot loop does not repeatedly divide a
		// 64-bit logical index into chunk/local indexes.
		for (times in timeChunks)
			for (i in 0...times.length) times[i] += delta;
		if (_length64 > Int64.ofInt(0)) lastTime = getTime64(_length64 - Int64.ofInt(1));
		nonDecreasingTime = false;
	}

	public function stretchFrom(minimumTime:Float, sectionStart:Float, multiplier:Float):Void
	{
		for (segment in 0...timeChunks.length)
		{
			var times:Array<Float> = timeChunks[segment];
			var sustains:Array<Float> = sustainChunks[segment];
			for (local in 0...times.length)
			{
				var sustain:Float = sustains[local];
				if (sustain > 0) sustains[local] = sustain * multiplier;
				var relative:Float = times[local] - sectionStart;
				times[local] = Math.max(sectionStart + (relative * multiplier), minimumTime);
			}
		}
		nonDecreasingTime = false;
		if (_length64 > Int64.ofInt(0)) lastTime = getTime64(_length64 - Int64.ofInt(1));
	}

	public function swapSides():Void
	{
		for (lanes in laneChunks)
			for (i in 0...lanes.length) lanes[i] = (lanes[i] + 4) % 8;
	}

	public function mirrorLanes():Void
	{
		for (lanes in laneChunks)
			for (i in 0...lanes.length)
			{
				var original:Int = lanes[i];
				var lane:Int = 3 - (original % 4);
				if (original > 3) lane += 4;
				lanes[i] = lane;
			}
	}

	public function duetTo(target:PackedNoteBuffer):Void
	{
		if (target == null) return;
		var i:Int64 = Int64.ofInt(0);
		while (i < _length64)
		{
			var lane:Int = getLane64(i) > 3 ? getLane64(i) - 4 : getLane64(i) + 4;
			target.appendValues(getTime64(i), lane, getSustain64(i), getType64(i));
			i += Int64.ofInt(1);
		}
	}

	/** Legacy expansion API. Deliberately bounded to avoid huge RAM copies. */
	public function appendRowsTo(target:Array<Dynamic>):Void
	{
		if (target == null || _length64 > LEGACY_MATERIALIZE_LIMIT) return;
		var i:Int64 = Int64.ofInt(0);
		while (i < _length64) { target.push(getRow64(i)); i += Int64.ofInt(1); }
	}

	public function toRows():Array<Dynamic>
	{
		var result:Array<Dynamic> = [];
		appendRowsTo(result);
		return result;
	}

	public function getEstimatedAllocatedBytes():Float
	{
		var allocatedRows:Float = timeChunks.length * CHUNK_SIZE;
		var bytes:Float = allocatedRows * 20.0;
		for (typeColumn in typeChunks) if (typeColumn != null) bytes += CHUNK_SIZE * 4.0;
		return bytes;
	}

	public function getAllocatedChunkCount():Int return timeChunks.length;

	public function clear():Void
	{
		timeChunks = [];
		laneChunks = [];
		sustainChunks = [];
		typeChunks = [];
		typeValues = [];
		typeLookup = new Map<String, Int>();
		extraFields = new Map<String, Array<Dynamic>>();
		nonDecreasingTime = true;
		lastTime = -1.0e30;
		_length64 = Int64.ofInt(0);
		writeChunkIndex = 0;
		writeChunkOffset = 0;
	}
}
