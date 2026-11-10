package debug;

import flixel.FlxG;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFieldAutoSize;
import openfl.text.Font;
import states.PlayState;
import backend.ClientPrefs;
import backend.Conductor;

/** Original ADR-style FPS and memory HUD, adapted to the Reworked PlayState. */
class FPSCounter extends Sprite
{
	public var currentFPS(default, null):Int;
	public var memoryMegas(get, never):Float;
	public static var highestMemoryMegas:Float = 0;
	public var fpsText(default, null):TextField;
	private var times:Array<Float> = [];
	private var deltaTimeout:Float = 0;
	private var fontLoaded:Bool = false;

	private static inline var BOX_PADDING_X:Float = 14;
	private static inline var BOX_PADDING_Y:Float = 10;
	private static inline var BRACKET:Float = 8;
	private static inline var THICKNESS:Int = 2;

	public function new(x:Float = 10, y:Float = 3, color:Int = 0xFFFFFF)
	{
		super();
		this.x = x;
		this.y = y;
		currentFPS = 0;
		mouseEnabled = false;
		mouseChildren = false;

		var format:TextFormat = new TextFormat('_sans', 14, color);
		#if sys
		try
		{
			var font:Font = Font.fromFile(backend.Paths.font('fps.ttf'));
			if (font != null)
			{
				fontLoaded = true;
				format = new TextFormat(font.fontName, 16, color);
			}
		}
		catch (e:Dynamic) {}
		#end
		fpsText = new TextField();
		fpsText.selectable = false;
		fpsText.mouseEnabled = false;
		fpsText.embedFonts = fontLoaded;
		fpsText.defaultTextFormat = format;
		fpsText.autoSize = TextFieldAutoSize.LEFT;
		fpsText.multiline = true;
		fpsText.x = BOX_PADDING_X;
		fpsText.y = BOX_PADDING_Y;
		addChild(fpsText);
		updateText();
	}

	private function redrawBox():Void
	{
		var w:Float = Math.max(fpsText.textWidth, 150) + BOX_PADDING_X * 2;
		var h:Float = fpsText.height + BOX_PADDING_Y * 2 + 6;
		graphics.clear();
		graphics.beginFill(0x000000, 0.60);
		graphics.drawRect(0, 0, w, h);
		graphics.endFill();
		graphics.beginFill(0xFFFFFF, 1);
		graphics.drawRect(12, h - 10, Math.max(0, w - 24), THICKNESS);
		graphics.endFill();
		graphics.lineStyle(THICKNESS, 0xFFFFFF, 1, true);
		graphics.moveTo(0, BRACKET); graphics.lineTo(0, 0); graphics.lineTo(BRACKET, 0);
		graphics.moveTo(w - BRACKET, 0); graphics.lineTo(w, 0); graphics.lineTo(w, BRACKET);
		graphics.moveTo(0, h - BRACKET); graphics.lineTo(0, h); graphics.lineTo(BRACKET, h);
		graphics.moveTo(w - BRACKET, h); graphics.lineTo(w, h); graphics.lineTo(w, h - BRACKET);
		graphics.lineStyle();
	}

	private override function __enterFrame(deltaTime:Float):Void
	{
		var now:Float = haxe.Timer.stamp() * 1000;
		times.push(now);
		while (times.length > 0 && times[0] < now - 1000) times.shift();
		if (deltaTimeout < 50)
		{
			deltaTimeout += deltaTime;
			return;
		}
		currentFPS = times.length < FlxG.updateFramerate ? times.length : FlxG.updateFramerate;
		var current:Float = memoryMegas;
		if (current > highestMemoryMegas) highestMemoryMegas = current;
		updateText();
		deltaTimeout = 0;
	}

	public dynamic function updateText():Void
	{
		var fpsLine:String = 'FPS: ' + currentFPS;
		#if desktop
		if (PlayState.instance != null && PlayState.instance.isRendering)
			fpsLine = 'FPS: ' + PlayState.instance.renderFPS + ' (RENDERING MODE)';
		#end
		var memLine:String = 'MEM: ' + formatMem(memoryMegas * 1024 * 1024)
			+ ' / ' + formatMem(highestMemoryMegas * 1024 * 1024);
		fpsText.text = fpsLine + '\n' + memLine;
		if (PlayState.instance != null && ClientPrefs.data.infoDisplay != 'Off')
		{
			var seconds:Float = Conductor.songPosition / 1000;
			var nps:Float = seconds > 0 ? PlayState.instance.totalPlayed / seconds : 0;
			if (ClientPrefs.data.infoDisplay == 'NPS' || ClientPrefs.data.infoDisplay == 'Both')
				fpsText.appendText('\n' + (Math.round(nps * 10) / 10) + ' NPS');
		}
		if (fontLoaded)
		{
			if (currentFPS >= 60) fpsText.textColor = 0xFFFFFF;
			else if (currentFPS >= 30) fpsText.textColor = 0xFFFF00 + Std.int(255 * ((currentFPS - 30) / 30));
			else if (currentFPS >= 15) fpsText.textColor = 0xFF0000 + (Std.int(255 * ((currentFPS - 15) / 15)) << 8);
			else fpsText.textColor = 0xFF0000;
		}
		redrawBox();
	}

	public static function formatMem(bytes:Float):String
	{
		if (bytes <= 0) return '0B';
		if (bytes < 1024) return Math.floor(bytes) + 'B';
		if (bytes < 1024 * 1024) return (Math.floor(bytes / 102.4) / 10) + 'KB';
		if (bytes < 1024 * 1024 * 1024) return (Math.floor(bytes / (1024 * 1024) * 100) / 100) + 'MB';
		return (Math.floor(bytes / (1024 * 1024 * 1024) * 100) / 100) + 'GB';
	}

	private function get_memoryMegas():Float
	{
		#if cpp
		return cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE) / (1024 * 1024);
		#else
		return openfl.system.System.totalMemory / (1024 * 1024);
		#end
	}
}
