package debug;

import backend.PackedNoteBuffer;
import haxe.Int64;

/**
 * Standalone throughput benchmark for compact chart-note storage.
 *
 * Run with:
 *   haxe -cp source --run debug.PackedNoteBufferBenchmark 1100000
 *
 * For a native C++ benchmark build:
 *   haxe -cp source -main debug.PackedNoteBufferBenchmark -cpp export/packed-note-bench
 *   cd export/packed-note-bench && make -j2 && ./PackedNoteBufferBenchmark 1100000
 *
 * The reported rates are storage/generation throughput only. They do not
 * measure JSON parsing, Flixel sprite creation, gameplay updates, or drawing.
 */
class PackedNoteBufferBenchmark
{
	private static inline var DEFAULT_COUNT:Int = 1100000;
	private static inline var MAX_COUNT:Int = 10000000;
	private static inline var BATCH_SIZE:Int = 65536;

	private static function requestedCount():Int
	{
		var args:Array<String> = Sys.args();
		if (args.length == 0) return DEFAULT_COUNT;
		var parsed:Null<Int> = Std.parseInt(args[0]);
		if (parsed == null || parsed <= 0) return DEFAULT_COUNT;
		return parsed > MAX_COUNT ? MAX_COUNT : parsed;
	}

	private static function sample(buffer:PackedNoteBuffer, index:Int):Array<Float>
	{
		return [buffer.getTime(index), buffer.getLane(index)];
	}

	private static function rate(count:Int, elapsed:Float):Float
	{
		return count / (elapsed <= 0.000001 ? 0.000001 : elapsed);
	}

	private static function printRate(label:String, count:Int, elapsed:Float):Void
	{
		Sys.println(label + ': ' + Std.string(Math.round(rate(count, elapsed))) + ' records/s ('
			+ Std.string(Math.round(elapsed * 1000) / 1000) + ' s)');
	}

	public static function main():Void
	{
		var count:Int = requestedCount();
		Sys.println('PackedNoteBuffer benchmark');
		Sys.println('Rows: ' + count + ' | Chunk size: 1,048,576 | Batch size: ' + BATCH_SIZE);
		Sys.println('Timing excludes initial reserve and post-run sample checks.');

		var scalar:PackedNoteBuffer = new PackedNoteBuffer();
		if (!scalar.reserve(Int64.ofInt(count))) throw 'Scalar benchmark reserve failed';
		var scalarTime:Float = 0;
		var scalarLane:Int = 0;
		var started:Float = Sys.time();
		for (_ in 0...count)
		{
			scalarTime += 0.125;
			scalarLane++;
			if (!scalar.appendEncoded(scalarTime, scalarLane, 0, -1))
				throw 'Scalar benchmark append failed';
		}
		var scalarElapsed:Float = Sys.time() - started;
		var firstIndex:Int = 0;
		var middleIndex:Int = Std.int((count - 1) / 2);
		var lastIndex:Int = count - 1;
		var scalarFirst:Array<Float> = sample(scalar, firstIndex);
		var scalarMiddle:Array<Float> = sample(scalar, middleIndex);
		var scalarLast:Array<Float> = sample(scalar, lastIndex);
		printRate('Scalar appendEncoded', count, scalarElapsed);
		scalar.clear();

		var batched:PackedNoteBuffer = new PackedNoteBuffer();
		if (!batched.reserve(Int64.ofInt(count))) throw 'Batched benchmark reserve failed';
		var written:Int = 0;
		var batchTime:Float = 0;
		var batchLane:Int = 0;
		started = Sys.time();
		while (written < count)
		{
			var batchCount:Int = count - written;
			if (batchCount > BATCH_SIZE) batchCount = BATCH_SIZE;
			var appended:Int = batched.appendGeneratedBatch(batchCount, batchTime, batchLane, 0.125, 1, 0, -1);
			if (appended <= 0) throw 'Batched benchmark append failed';
			written += appended;
			batchTime = batched.getLastWrittenTime();
			batchLane = batched.getLastWrittenLane();
		}
		var batchElapsed:Float = Sys.time() - started;
		var batchFirst:Array<Float> = sample(batched, firstIndex);
		var batchMiddle:Array<Float> = sample(batched, middleIndex);
		var batchLast:Array<Float> = sample(batched, lastIndex);
		if (scalarFirst[0] != batchFirst[0] || scalarFirst[1] != batchFirst[1]
			|| scalarMiddle[0] != batchMiddle[0] || scalarMiddle[1] != batchMiddle[1]
			|| scalarLast[0] != batchLast[0] || scalarLast[1] != batchLast[1])
			throw 'Benchmark validation failed: scalar and batched samples differ';

		printRate('Batched generation', written, batchElapsed);
		Sys.println('Sample validation: PASS (first, middle, and last records match)');
		Sys.println('Note: compare results only between builds using the same Haxe target and compiler flags.');
	}
}

