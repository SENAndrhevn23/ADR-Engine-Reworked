package options;

class VideoRenderingSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = 'Video Rendering';
		rpcTitle = 'Video Rendering Menu';

		addOption(new Option('Game Renderer',
			'Records the gameplay window to an MP4 using FFmpeg. Desktop only; FFmpeg must be installed and available on PATH.',
			'gameRenderer', 'bool'));

		var fps:Option = new Option('Record FPS',
			'Frame rate used for the recorded video. Higher values take more processing power.',
			'videoRenderFPS', 'int');
		fps.minValue = 24;
		fps.maxValue = 240;
		fps.changeValue = 1;
		fps.scrollSpeed = 30;
		fps.decimals = 0;
		fps.displayFormat = '%v FPS';
		addOption(fps);

		var quality:Option = new Option('Recording Quality',
			'Quality from 1 to 10. Higher values produce better-looking, larger files.',
			'videoRenderQuality', 'int');
		quality.minValue = 1;
		quality.maxValue = 10;
		quality.changeValue = 1;
		quality.decimals = 0;
		addOption(quality);

		super();
	}
}
