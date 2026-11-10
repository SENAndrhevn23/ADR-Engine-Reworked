package backend;

#if desktop

import flixel.FlxG;
import haxe.io.Bytes;
import lime.graphics.Image;
import lime.math.Rectangle;
import lime.ui.Window;
import sys.FileSystem;
import sys.io.Process;

import states.PlayState;

class FFMpeg
{
	public static var instance:FFMpeg;

	public var target:String = "render_video";
	public var fileName:String = "";
	public var fileExts:String = ".mp4";

	var window:Window;
	var buffer:Rectangle;
	var image:Image;
	var bytes:Bytes;
	var process:Process;
	var outputPath:String;

	public function new() {}

	public function init():Void
	{
		if (FileSystem.exists(target))
		{
			if (!FileSystem.isDirectory(target))
			{
				FileSystem.deleteFile(target);
				FileSystem.createDirectory(target);
			}
		}
		else
		{
			FileSystem.createDirectory(target);
		}

		window = FlxG.stage.application.window;
		buffer = new Rectangle(0, 0, window.width, window.height);
	}

	public function setup(testMode:Bool = false):Void
	{
		var executable:String = #if windows "ffmpeg.exe" #else "ffmpeg" #end;

		if (!FFmpegUtil.exists())
			throw '"' + executable + '" was not found on PATH. Install FFmpeg and try again.';

		var safeSong:String = Paths.formatToSongPath(PlayState.SONG.song);
		if (safeSong == null || safeSong.length < 1)
			safeSong = "song";

		outputPath = target + '/' + safeSong;
		if (!testMode && FileSystem.exists(outputPath + fileExts))
		{
			var millis = Std.int(haxe.Timer.stamp() * 1000.0) % 1000;
			outputPath += "-" + DateTools.format(Date.now(), "%Y-%m-%d_%H-%M-%S-") + millis;
		}

		var fps:Int = Std.int(ClientPrefs.data.videoRenderFPS);
		if (fps < 1) fps = 60;

		var quality:Int = Std.int(ClientPrefs.data.videoRenderQuality);
		if (quality < 1) quality = 1;
		if (quality > 10) quality = 10;

		var crf:Int = 40 - (quality * 3);
		if (crf < 0) crf = 0;
		if (crf > 51) crf = 51;

		var args:Array<String> = [
			'-y',
			'-loglevel', 'error',
			'-nostats',
			'-f', 'rawvideo',
			'-pix_fmt', 'rgba',
			'-s', window.width + 'x' + window.height,
			'-r', Std.string(fps),
			'-i', '-',
			'-c:v', 'libx264',
			'-preset', 'veryfast',
			'-crf', Std.string(crf),
			'-pix_fmt', 'yuv420p',
			'-movflags', '+faststart',
			outputPath + fileExts
		];

		process = new Process(executable, args);
		FlxG.autoPause = false;
	}

	public function pipeFrame():Void
	{
		if (process == null || process.stdin == null || window == null)
			return;

		image = window.readPixels();
		if (image == null)
			return;

		bytes = image.getPixels(buffer);
		if (bytes == null || bytes.length <= 0)
			return;

		process.stdin.write(bytes);
	}

	public function destroy():Void
	{
		if (process != null)
		{
			try
			{
				if (process.stdin != null)
					process.stdin.close();
				// Closing stdin sends EOF; FFmpeg finalizes the MP4 before close returns.
				process.close();
			}
			catch (e:Dynamic) {}

			process = null;
		}

		FlxG.autoPause = ClientPrefs.data.autoPause;
	}
}
#end
