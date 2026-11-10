package backend;

import sys.io.Process;

class FFmpegUtil
{
	public static function exists():Bool
	{
		try
		{
			var executable:String = #if windows "ffmpeg.exe" #else "ffmpeg" #end;
			var proc = new Process(executable, ["-version"]);
			proc.close();
			return true;
		}
		catch(e)
		{
			return false;
		}
	}
}
