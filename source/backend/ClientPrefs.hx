package backend;

import flixel.util.FlxSave;
import flixel.input.keyboard.FlxKey;
import flixel.input.gamepad.FlxGamepadInputID;

import states.TitleState;

// Add a variable here and it will get automatically saved
@:structInit class SaveVariables {
	public var downScroll:Bool = false;
	public var middleScroll:Bool = false;
	public var opponentStrums:Bool = true;
	public var showFPS:Bool = true;
	public var flashing:Bool = true;
	public var autoPause:Bool = true;
	public var antialiasing:Bool = true;
	public var noteSkin:String = 'Default';
	public var splashSkin:String = 'Psych';
	public var splashAlpha:Float = 0.6;
	public var lowQuality:Bool = false;
	public var shaders:Bool = true;
	public var cacheOnGPU:Bool = #if !switch false #else true #end; //From Stilic
	public var framerate:Int = 60;
	public var camZooms:Bool = true;
	public var hideHud:Bool = false;
	public var noteOffset:Int = 0;
	public var arrowRGB:Array<Array<FlxColor>> = [
		[0xFFC24B99, 0xFFFFFFFF, 0xFF3C1F56],
		[0xFF00FFFF, 0xFFFFFFFF, 0xFF1542B7],
		[0xFF12FA05, 0xFFFFFFFF, 0xFF0A4447],
		[0xFFF9393F, 0xFFFFFFFF, 0xFF651038]];
	public var arrowRGBPixel:Array<Array<FlxColor>> = [
		[0xFFE276FF, 0xFFFFF9FF, 0xFF60008D],
		[0xFF3DCAFF, 0xFFF4FFFF, 0xFF003060],
		[0xFF71E300, 0xFFF6FFE6, 0xFF003100],
		[0xFFFF884E, 0xFFFFFAF5, 0xFF6C0000]];

	public var ghostTapping:Bool = true;
	public var timeBarType:String = 'Time Left';
	public var scoreZoom:Bool = true;
	public var noReset:Bool = false;
	public var healthBarAlpha:Float = 1;
	public var hitsoundVolume:Float = 0;
	public var pauseMusic:String = 'Tea Time';
	public var checkForUpdates:Bool = true;
	public var comboStacking:Bool = true;
	public var gameplaySettings:Map<String, Dynamic> = [
		'scrollspeed' => 1.0,
		'scrolltype' => 'multiplicative', 
		// anyone reading this, amod is multiplicative speed mod, cmod is constant speed mod, and xmod is bpm based speed mod.
		// an amod example would be chartSpeed * multiplier
		// cmod would just be constantSpeed = chartSpeed
		// and xmod basically works by basing the speed on the bpm.
		// iirc (beatsPerSecond * (conductorToNoteDifference / 1000)) * noteSize (110 or something like that depending on it, prolly just use note.height)
		// bps is calculated by bpm / 60
		// oh yeah and you'd have to actually convert the difference to seconds which I already do, because this is based on beats and stuff. but it should work
		// just fine. but I wont implement it because I don't know how you handle sustains and other stuff like that.
		// oh yeah when you calculate the bps divide it by the songSpeed or rate because it wont scroll correctly when speeds exist.
		// -kade
		'songspeed' => 1.0,
		'healthgain' => 1.0,
		'healthloss' => 1.0,
		'instakill' => false,
		'practice' => false,
		'botplay' => false,
		'opponentplay' => false
	];

	public var comboOffset:Array<Int> = [0, 0, 0, 0];
	public var ratingOffset:Int = 0;
	public var sickWindow:Int = 45;
	public var goodWindow:Int = 90;
	public var badWindow:Int = 135;
	public var safeFrames:Float = 10;
	public var guitarHeroSustains:Bool = true;
	// Optional in-game performance overlay: Off, NPS, Rendered, or Both.
	public var infoDisplay:String = 'Off';

	// PlayState visibility and performance options. Gameplay-critical calculations stay enabled.
	public var showNotes:Bool = true;
	public var showComboPopup:Bool = true;
	public var showRatingPopup:Bool = true;
	public var showNumPopup:Bool = true;
	// Compatibility switches brought forward from the original ADR Engine.
	public var disablePopUpScore:Bool = false;
	public var disableGCLag:Bool = false;
	public var disableLuaHScriptCalls:Bool = false;
	public var disableLuaHScriptStageCalls:Bool = false;
	public var disableLuaHScriptEventCalls:Bool = false;
	// Desktop-only FFmpeg game capture settings. Recording is opt-in.
	public var gameRenderer:Bool = false;
	public var videoRenderFPS:Int = 60;
	public var videoRenderQuality:Int = 8;

	// Caps visible note sprites while preserving all chart rows and note judgement.
	// 0 means unlimited. Keep all authored note visuals by default; users may opt into a cap.
	public var renderedNotesLimit:Int = 0;
	// Suppresses visually duplicate tap-note heads in the same lane/side/type within this many milliseconds.
	// This never deletes chart data or changes note judgement. 0 disables overlap suppression.
	public var overlapRemovalWindowMs:Float = 0.0;

	// Converts disk-backed chart note rows into runtime notes in bounded 50K-row batches.
	public var jsonStreamingEnabled:Bool = false;

	// Converts chart rows into compact pending records in bounded batches. Enabled by default
	// so large charts do not allocate/expand the entire note queue during PlayState creation.
	public var chunkedNoteGeneration:Bool = true;
	public var releaseProcessedChartData:Bool = true;

	// Note rendering, storage and processing controls.
	// The render processor separates logical gameplay notes from Flixel's sprite traversal.
	public var noteRenderProcessingEnabled:Bool = true;
	public var notePerformancePreset:String = 'Optimized';
	public var noteAnimationResourceCaching:Bool = true;
	public var compactCastNoteStorageEnabled:Bool = true;
	public var reuseSustainClipRects:Bool = true;
	public var noteCullingUpdateInterval:Int = 1;
	public var noteCullingHysteresis:Bool = true;

	// Note processing fast paths. Some options can change draw order or mod compatibility.
	public var fastNoteSpawning:Bool = true;
	// Reuses plain tap-note sprites after removal; sustains/custom note types are excluded for safety.
	public var noteObjectPooling:Bool = true; // Allows eligible new notes to reuse previously pooled Note instances.
	public var notePoolEnabled:Bool = true; // Allows removed eligible notes to be retained in the bounded pool.
	// Defers ordinary tap-note atlas/animation/shader creation until a sprite is actually rendered.
	public var lazyNoteGraphics:Bool = true;
	// Limits Note object creation per update so a large spawn-ahead window cannot burst-spawn a whole chart.
	public var maxNoteSpawnsPerFrame:Int = 4096;
	// Count, Time, or Hybrid (both count and time limits).
	public var noteSpawnBudgetMode:String = 'Count';
	// CPU time allowed for note spawning on each update; 0 disables the time limit.
	public var maxNoteSpawnTimeMs:Float = 2.0;
	// How far ahead of song time notes are converted into live Note objects.
	public var noteSpawnAheadMs:Float = 1500;
	// Number of raw chart rows converted into compact records per update.
	public var noteGenerationRowsPerFrame:Int = 2048;
	// Target pending head records before another chart-generation batch is requested.
	public var noteGenerationQueueTarget:Int = 25000;
	// Expand sustain chains just-in-time instead of materializing every tail segment at chart load.
	public var deferredSustainSpawning:Bool = true;
	// Optional hard ceiling on live logical Note objects. 0 means unlimited.
	public var maxActiveNoteObjects:Int = 0;
	// Maximum recycled tap sprites retained per lane. 0 disables retention.
	public var maxPooledNotesPerLane:Int = 512;
	public var maxPooledNotesTotal:Int = 4096;
	public var optimizedNoteInput:Bool = true;
	public var fastNoteTransformCache:Bool = true;
	public var disableNoteSplashes:Bool = false;
	public var sustainNoteClipping:Bool = true;
	public var noteSorting:Bool = true;
	// High-density paths: these keep judgement/scoring enabled while reducing array and sprite work.
	public var fastNoteLogicQueue:Bool = true;
	public var fastNoteGroupRemoval:Bool = true;
	public var fastNoteInputIndex:Bool = true;
	public var noteViewportCulling:Bool = true;
	public var noteViewportCullMargin:Int = 128;
	// Additional per-note rendering quality controls. These affect visuals only, not judgement.
	public var renderPlayerNotes:Bool = true;
	public var renderOpponentNotes:Bool = true;
	public var noteRenderingAnimations:Bool = true;
	public var noteRenderingRGBShaders:Bool = true;
	public var noteRenderingAntialiasing:Bool = true;

	// Script execution controls. These disable callbacks/scripts, not core chart or judgement logic.
	public var disableLuaScripts:Bool = false;
	public var disableHScriptScripts:Bool = false;
	public var disableScriptUpdateEvents:Bool = false;
	public var disableNoteHitEvents:Bool = false;
	public var disableNoteMissEvents:Bool = false;
	public var disableNoteSpawnEvents:Bool = false;
	public var disableChartEventCallbacks:Bool = false;
	public var disableBeatStepCallbacks:Bool = false;
	public var disableInputCallbacks:Bool = false;
	public var disableLifecycleCallbacks:Bool = false;
	public var disableCameraCallbacks:Bool = false;
	public var disableDialogueCallbacks:Bool = false;
	public var disableScoreCallbacks:Bool = false;
	public var disableCustomSubstateCallbacks:Bool = false;
	public var disableScriptVariableSync:Bool = false;

	public var discordRPC:Bool = true;
}

class ClientPrefs {
	public static var data:SaveVariables = {};
	public static var defaultData:SaveVariables = {};

	//Every key has two binds, add your key bind down here and then add your control on options/ControlsSubState.hx and Controls.hx
	public static var keyBinds:Map<String, Array<FlxKey>> = [
		//Key Bind, Name for ControlsSubState
		'note_up'		=> [W, UP],
		'note_left'		=> [A, LEFT],
		'note_down'		=> [S, DOWN],
		'note_right'	=> [D, RIGHT],
		
		'ui_up'			=> [W, UP],
		'ui_left'		=> [A, LEFT],
		'ui_down'		=> [S, DOWN],
		'ui_right'		=> [D, RIGHT],
		
		'accept'		=> [SPACE, ENTER],
		'back'			=> [BACKSPACE, ESCAPE],
		'pause'			=> [ENTER, ESCAPE],
		'reset'			=> [R],
		
		'volume_mute'	=> [ZERO],
		'volume_up'		=> [NUMPADPLUS, PLUS],
		'volume_down'	=> [NUMPADMINUS, MINUS],
		
		'debug_1'		=> [SEVEN],
		'debug_2'		=> [EIGHT]
	];
	public static var gamepadBinds:Map<String, Array<FlxGamepadInputID>> = [
		'note_up'		=> [DPAD_UP, Y],
		'note_left'		=> [DPAD_LEFT, X],
		'note_down'		=> [DPAD_DOWN, A],
		'note_right'	=> [DPAD_RIGHT, B],
		
		'ui_up'			=> [DPAD_UP, LEFT_STICK_DIGITAL_UP],
		'ui_left'		=> [DPAD_LEFT, LEFT_STICK_DIGITAL_LEFT],
		'ui_down'		=> [DPAD_DOWN, LEFT_STICK_DIGITAL_DOWN],
		'ui_right'		=> [DPAD_RIGHT, LEFT_STICK_DIGITAL_RIGHT],
		
		'accept'		=> [A, START],
		'back'			=> [B],
		'pause'			=> [START],
		'reset'			=> [BACK]
	];
	public static var defaultKeys:Map<String, Array<FlxKey>> = null;
	public static var defaultButtons:Map<String, Array<FlxGamepadInputID>> = null;

	public static function resetKeys(controller:Null<Bool> = null) //Null = both, False = Keyboard, True = Controller
	{
		if(controller != true)
			for (key in keyBinds.keys())
				if(defaultKeys.exists(key))
					keyBinds.set(key, defaultKeys.get(key).copy());

		if(controller != false)
			for (button in gamepadBinds.keys())
				if(defaultButtons.exists(button))
					gamepadBinds.set(button, defaultButtons.get(button).copy());
	}

	public static function clearInvalidKeys(key:String)
	{
		var keyBind:Array<FlxKey> = keyBinds.get(key);
		var gamepadBind:Array<FlxGamepadInputID> = gamepadBinds.get(key);
		while(keyBind != null && keyBind.contains(NONE)) keyBind.remove(NONE);
		while(gamepadBind != null && gamepadBind.contains(NONE)) gamepadBind.remove(NONE);
	}

	public static function loadDefaultKeys()
	{
		defaultKeys = keyBinds.copy();
		defaultButtons = gamepadBinds.copy();
	}

	public static function saveSettings() {
		for (key in Reflect.fields(data))
			Reflect.setField(FlxG.save.data, key, Reflect.field(data, key));

		#if ACHIEVEMENTS_ALLOWED Achievements.save(); #end
		FlxG.save.flush();

		//Placing this in a separate save so that it can be manually deleted without removing your Score and stuff
		var save:FlxSave = new FlxSave();
		save.bind('controls_v3', CoolUtil.getSavePath());
		save.data.keyboard = keyBinds;
		save.data.gamepad = gamepadBinds;
		save.flush();
		FlxG.log.add("Settings saved!");
	}

	public static function loadPrefs() {
		#if ACHIEVEMENTS_ALLOWED Achievements.load(); #end

		for (key in Reflect.fields(data))
			if (key != 'gameplaySettings' && Reflect.hasField(FlxG.save.data, key))
				Reflect.setField(data, key, Reflect.field(FlxG.save.data, key));
		
		if(Main.fpsVar != null)
			Main.fpsVar.visible = data.showFPS;

		#if (!html5 && !switch)
		FlxG.autoPause = ClientPrefs.data.autoPause;

		if(FlxG.save.data.framerate == null) {
			final refreshRate:Int = FlxG.stage.application.window.displayMode.refreshRate;
			data.framerate = Std.int(FlxMath.bound(refreshRate, 60, 240));
		}
		#end

		if(data.framerate > FlxG.drawFramerate)
		{
			FlxG.updateFramerate = data.framerate;
			FlxG.drawFramerate = data.framerate;
		}
		else
		{
			FlxG.drawFramerate = data.framerate;
			FlxG.updateFramerate = data.framerate;
		}

		if(FlxG.save.data.gameplaySettings != null)
		{
			var savedMap:Map<String, Dynamic> = FlxG.save.data.gameplaySettings;
			for (name => value in savedMap)
				data.gameplaySettings.set(name, value);
		}
		
		// flixel automatically saves your volume!
		if(FlxG.save.data.volume != null)
			FlxG.sound.volume = FlxG.save.data.volume;
		if (FlxG.save.data.mute != null)
			FlxG.sound.muted = FlxG.save.data.mute;

		#if DISCORD_ALLOWED
		DiscordClient.check();
		#end

		// controls on a separate save file
		var save:FlxSave = new FlxSave();
		save.bind('controls_v3', CoolUtil.getSavePath());
		if(save != null)
		{
			if(save.data.keyboard != null)
			{
				var loadedControls:Map<String, Array<FlxKey>> = save.data.keyboard;
				for (control => keys in loadedControls)
					if(keyBinds.exists(control)) keyBinds.set(control, keys);
			}
			if(save.data.gamepad != null)
			{
				var loadedControls:Map<String, Array<FlxGamepadInputID>> = save.data.gamepad;
				for (control => keys in loadedControls)
					if(gamepadBinds.exists(control)) gamepadBinds.set(control, keys);
			}
			reloadVolumeKeys();
		}
	}

	inline public static function getGameplaySetting(name:String, defaultValue:Dynamic = null, ?customDefaultValue:Bool = false):Dynamic
	{
		if(!customDefaultValue) defaultValue = defaultData.gameplaySettings.get(name);
		return /*PlayState.isStoryMode ? defaultValue : */ (data.gameplaySettings.exists(name) ? data.gameplaySettings.get(name) : defaultValue);
	}

	public static function reloadVolumeKeys()
	{
		TitleState.muteKeys = keyBinds.get('volume_mute').copy();
		TitleState.volumeDownKeys = keyBinds.get('volume_down').copy();
		TitleState.volumeUpKeys = keyBinds.get('volume_up').copy();
		toggleVolumeKeys(true);
	}
	public static function toggleVolumeKeys(?turnOn:Bool = true)
	{
		FlxG.sound.muteKeys = turnOn ? TitleState.muteKeys : [];
		FlxG.sound.volumeDownKeys = turnOn ? TitleState.volumeDownKeys : [];
		FlxG.sound.volumeUpKeys = turnOn ? TitleState.volumeUpKeys : [];
	}
}
