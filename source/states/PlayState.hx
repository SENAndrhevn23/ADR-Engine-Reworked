package states;

import backend.Highscore;
#if desktop
import backend.FFMpeg;
#end
import backend.StageData;
import backend.WeekData;
import backend.Song;
#if sys
import backend.ChartJsonStream;
#end
import backend.Section;
import backend.Rating;

import flixel.FlxBasic;
import flixel.FlxObject;
import flixel.FlxSubState;
import flixel.addons.transition.FlxTransitionableState;
import flixel.util.FlxSort;
import flixel.util.FlxStringUtil;
import flixel.util.FlxSave;
import flixel.input.keyboard.FlxKey;
import flixel.animation.FlxAnimationController;
import lime.utils.Assets;
import openfl.utils.Assets as OpenFlAssets;
import openfl.events.KeyboardEvent;
import haxe.Json;

import cutscenes.CutsceneHandler;
import cutscenes.DialogueBoxPsych;

import states.StoryMenuState;
import states.FreeplayState;
import states.editors.ChartingState;
import states.editors.CharacterEditorState;

import substates.PauseSubState;
import substates.GameOverSubstate;

#if !flash
import flixel.addons.display.FlxRuntimeShader;
import openfl.filters.ShaderFilter;
#end

#if VIDEOS_ALLOWED
#if (hxCodec >= "3.0.0") import hxcodec.flixel.FlxVideo as VideoHandler;
#elseif (hxCodec >= "2.6.1") import hxcodec.VideoHandler as VideoHandler;
#elseif (hxCodec == "2.6.0") import VideoHandler;
#else import vlc.MP4Handler as VideoHandler; #end
#end

import objects.Note.EventNote;
import objects.Note.CastNote;
import objects.Note.CastNoteFlags;
import objects.*;
import states.stages.objects.*;

#if LUA_ALLOWED
import psychlua.*;
#else
import psychlua.LuaUtils;
import psychlua.HScript;
#end

#if SScript
import tea.SScript;
#end

/** One descriptor represents an entire sustain chain. Individual tail CastNotes are
 * materialized only when they enter the spawn-ahead window. */
private typedef PendingSustainSpawn = {
	var nextTime:Float;
	var stepCrochet:Float;
	var remaining:Int;
	var noteData:Int;
	var chainId:Int;
	var nextSortOrder:Int;
	var noteType:String;
}

/**
 * This is where all the Gameplay stuff happens and is managed
 *
 * here's some useful tips if you are making a mod in source:
 *
 * If you want to add your stage to the game, copy states/stages/Template.hx,
 * and put your stage code there, then, on PlayState, search for
 * "switch (curStage)", and add your stage to that list.
 *
 * If you want to code Events, you can either code it on a Stage file or on PlayState, if you're doing the latter, search for:
 *
 * "function eventPushed" - Only called *one time* when the game loads, use it for precaching events that use the same assets, no matter the values
 * "function eventPushedUnique" - Called one time per event, use it for precaching events that uses different assets based on its values
 * "function eventEarlyTrigger" - Used for making your event start a few MILLISECONDS earlier
 * "function triggerEvent" - Called when the song hits your event's timestamp, this is probably what you were looking for
**/
class PlayState extends MusicBeatState
{
	public static var STRUM_X = 42;
	public static var STRUM_X_MIDDLESCROLL = -278;

	public static var ratingStuff:Array<Dynamic> = [
		['You Suck!', 0.2], //From 0% to 19%
		['Shit', 0.4], //From 20% to 39%
		['Bad', 0.5], //From 40% to 49%
		['Bruh', 0.6], //From 50% to 59%
		['Meh', 0.69], //From 60% to 68%
		['Nice', 0.7], //69%
		['Good', 0.8], //From 70% to 79%
		['Great', 0.9], //From 80% to 89%
		['Sick!', 1], //From 90% to 99%
		['Perfect!!', 1] //The value on this one isn't used actually, since Perfect is always "1"
	];

	//event variables
	private var isCameraOnForcedPos:Bool = false;

	public var boyfriendMap:Map<String, Character> = new Map<String, Character>();
	public var dadMap:Map<String, Character> = new Map<String, Character>();
	public var gfMap:Map<String, Character> = new Map<String, Character>();
	public var variables:Map<String, Dynamic> = new Map<String, Dynamic>();

	#if HSCRIPT_ALLOWED
	public var hscriptArray:Array<HScript> = [];
	public var instancesExclude:Array<String> = [];
	#end

	#if LUA_ALLOWED
	public var modchartTweens:Map<String, FlxTween> = new Map<String, FlxTween>();
	public var modchartSprites:Map<String, ModchartSprite> = new Map<String, ModchartSprite>();
	public var modchartTimers:Map<String, FlxTimer> = new Map<String, FlxTimer>();
	public var modchartSounds:Map<String, FlxSound> = new Map<String, FlxSound>();
	public var modchartTexts:Map<String, FlxText> = new Map<String, FlxText>();
	public var modchartSaves:Map<String, FlxSave> = new Map<String, FlxSave>();
	#end

	public var BF_X:Float = 770;
	public var BF_Y:Float = 100;
	public var DAD_X:Float = 100;
	public var DAD_Y:Float = 100;
	public var GF_X:Float = 400;
	public var GF_Y:Float = 130;

	public var songSpeedTween:FlxTween;
	public var songSpeed(default, set):Float = 1;
	public var songSpeedType:String = "multiplicative";
	public var noteKillOffset:Float = 350;

	public var playbackRate(default, set):Float = 1;
	#if desktop
	public var renderFPS:Int = 60;
	public var isRendering(get, never):Bool;
	private var renderActive:Bool = false;
	private var renderPrevUpdateFramerate:Int = 60;
	private var renderPrevDrawFramerate:Int = 60;
	private var renderPrevFixedTimestep:Bool = false;
	private var renderPrevAutoPause:Bool = true;
	private function get_isRendering():Bool return renderActive;
	#end
	private var gcTimer:Float = 0;

	public var boyfriendGroup:FlxSpriteGroup;
	public var dadGroup:FlxSpriteGroup;
	public var gfGroup:FlxSpriteGroup;
	public static var curStage:String = '';
	public static var stageUI:String = "normal";
	public static var isPixelStage(get, never):Bool;

	@:noCompletion
	static function get_isPixelStage():Bool
		return stageUI == "pixel" || stageUI.endsWith("-pixel");

	public static var SONG:SwagSong = null;
	public static var isStoryMode:Bool = false;
	public static var storyWeek:Int = 0;
	public static var storyPlaylist:Array<String> = [];
	public static var storyDifficulty:Int = 1;

	public var spawnTime:Float = 2000;

	public var inst:FlxSound;
	public var vocals:FlxSound;
	public var opponentVocals:FlxSound;

	public var dad:Character = null;
	public var gf:Character = null;
	public var boyfriend:Character = null;

	// Logical gameplay collection: contains every spawned note, including render-budget-hidden notes.
	// Do NOT attach this group to the Flixel display tree; that would make Flixel traverse every note
	// during state update/draw even when the notes are hidden.
	public var notes:NoteGroup;
	// Only notes admitted by the render budget are attached to this group and visited by Flixel.
	public var grpRenderedNotes:FlxTypedGroup<Note>;
	public var unspawnNotes:Array<CastNote> = [];
	// Min-heap of one descriptor per active sustain chain, not one CastNote per tail.
	private var pendingSustainSpawns:Array<PendingSustainSpawn> = [];
	// Reused temporary record: NoteGroup consumes it synchronously and never retains it.
	private var deferredSustainCastScratch:CastNote = {
		strumTime: 0, noteData: 0, sortOrder: 0, chainId: 0,
		hasSustain: false, skipOnSpawn: false, chainEnd: false,
		tailCount: 0, stepCrochet: 0, sustainLength: 0, noteType: null
	};
	private var nextCastChainId:Int = 1;
	private var nextCastSortOrder:Int = 0;
	private var unspawnNoteIndex:Int = 0; // Head of the fast note-spawn queue.
	// All spawned notes are indexed by lane for fast input candidate lookup.
	private var notesByLane:Array<Array<Note>> = [[], [], [], []];
	// Optional event-driven judgement queue. Pending notes are ordered by strumTime;
	// active notes are limited to the judgement-to-expiry window.
	private var pendingJudgementHead:Note = null;
	private var pendingJudgementTail:Note = null;
	private var activeJudgementNotes:Array<Note> = []; // O(1) swap-pop index for compatibility fallbacks.
	private var activeJudgementNotesByLane:Array<Array<Note>> = [[], [], [], []];
	private var activeJudgementSustainsByLane:Array<Array<Note>> = [[], [], [], []];
	// Activated notes share Note.pendingJudgementPrev/Next as an ordered expiry queue.
	// The action cursor advances once through note timestamps; no active-note scan per frame.
	private var activeJudgementHead:Note = null;
	private var activeJudgementTail:Note = null;
	private var activeJudgementActionHead:Note = null;
	private var maxJudgementEarlyHitMult:Float = 1;
	public var fastNoteLogicActive:Bool = false;

	// Render budget: hidden notes stay in the gameplay group but skip FlxSprite updates and drawing.
	private var renderedNoteCount:Int = 0;
	private var hiddenNoteCount:Int = 0;
	private var renderedNoteDrawCount:Int = 0;
	private var pendingRenderHead:Note = null;
	private var pendingRenderTail:Note = null;
	private var renderBudgetHeadsByLane:Map<String, Float> = new Map<String, Float>();
	private var suspendRenderBudgetPromotion:Bool = false;
	private var noteCullFrameCounter:Int = 0;
	private var lastRenderProcessorSetting:Bool = true;
	private var lastShowNotesSetting:Bool = true;
	private var lastRenderPlayerSetting:Bool = true;
	private var lastRenderOpponentSetting:Bool = true;
	private var lastRenderedNoteLimit:Int = 0;
	private var lastOverlapWindowSetting:Float = 0.01;
	private var lastNotePoolRetentionSetting:Bool = true;
	private var lastNoteObjectPoolingSetting:Bool = true;
	private var lastNotePoolPerLaneLimit:Int = 512;
	private var lastNotePoolTotalLimit:Int = 4096;
	private var lastNoteAnimationSetting:Bool = true;
	private var lastNoteRGBSetting:Bool = true;
	private var lastNoteAntialiasSetting:Bool = true;
	private var lastGlobalAntialiasSetting:Bool = true;

	// Rolling one-second note-density counters. Pending queues are fed in strum-time order
	// as Note objects spawn; active queues contain only events from the last 1,000 ms.
	private var pendingOppNpsTimes:Array<Float> = [];
	private var pendingPlayNpsTimes:Array<Float> = [];
	private var pendingOppNpsHead:Int = 0;
	private var pendingPlayNpsHead:Int = 0;
	private var activeOppNpsTimes:Array<Float> = [];
	private var activePlayNpsTimes:Array<Float> = [];
	private var activeOppNpsHead:Int = 0;
	private var activePlayNpsHead:Int = 0;
	private var currentOppNps:Int = 0;
	private var currentPlayNps:Int = 0;
	private var currentBothNps:Int = 0;
	private var maxOppNps:Int = 0;
	private var maxPlayNps:Int = 0;
	private var maxBothNps:Int = 0;
	private var gameplayInfoRefresh:Float = 0;

	// Reused per-frame strum transforms: player lanes 0-3, opponent lanes 4-7.
	private var cachedStrumX:Array<Float> = [0, 0, 0, 0, 0, 0, 0, 0];
	private var cachedStrumY:Array<Float> = [0, 0, 0, 0, 0, 0, 0, 0];
	private var cachedStrumAngle:Array<Float> = [0, 0, 0, 0, 0, 0, 0, 0];
	private var cachedStrumAlpha:Array<Float> = [1, 1, 1, 1, 1, 1, 1, 1];
	private var cachedStrumDirection:Array<Float> = [90, 90, 90, 90, 90, 90, 90, 90];
	private var cachedStrumCos:Array<Float> = [0, 0, 0, 0, 0, 0, 0, 0];
	private var cachedStrumSin:Array<Float> = [1, 1, 1, 1, 1, 1, 1, 1];
	private var cachedStrumDownScroll:Array<Bool> = [false, false, false, false, false, false, false, false];
	private var cachedStrumRefs:Array<StrumNote> = [null, null, null, null, null, null, null, null];
	public var eventNotes:Array<EventNote> = [];

	public var camFollow:FlxObject;
	private static var prevCamFollow:FlxObject;

	public var strumLineNotes:FlxTypedGroup<StrumNote>;
	public var opponentStrums:FlxTypedGroup<StrumNote>;
	public var playerStrums:FlxTypedGroup<StrumNote>;
	public var grpNoteSplashes:FlxTypedGroup<NoteSplash>;

	public var camZooming:Bool = false;
	public var camZoomingMult:Float = 1;
	public var camZoomingDecay:Float = 1;
	private var curSong:String = "";

	public var gfSpeed:Int = 1;
	public var health(default, set):Float = 1;
	public var combo:Int = 0;

	public var healthBar:Bar;
	public var timeBar:Bar;
	var songPercent:Float = 0;

	public var ratingsData:Array<Rating> = Rating.loadDefault();

	private var generatedMusic:Bool = false;
	public var endingSong:Bool = false;
	public var startingSong:Bool = false;
	private var updateTime:Bool = true;
	public static var changedDifficulty:Bool = false;
	public static var chartingMode:Bool = false;

	//Gameplay settings
	public var healthGain:Float = 1;
	public var healthLoss:Float = 1;

	public var guitarHeroSustains:Bool = false;
	public var instakillOnMiss:Bool = false;
	public var cpuControlled:Bool = false;
	public var practiceMode:Bool = false;

	public var botplaySine:Float = 0;
	public var botplayTxt:FlxText;

	public var iconP1:HealthIcon;
	public var iconP2:HealthIcon;
	public var camHUD:FlxCamera;
	public var camGame:FlxCamera;
	public var camOther:FlxCamera;
	public var cameraSpeed:Float = 1;

	public var songScore:Int = 0;
	public var songHits:Int = 0;
	public var songMisses:Int = 0;
	public var scoreTxt:FlxText;
	public var gameplayInfoText:FlxText;
	var timeTxt:FlxText;
	var scoreTxtTween:FlxTween;

	public static var campaignScore:Int = 0;
	public static var campaignMisses:Int = 0;
	public static var seenCutscene:Bool = false;
	public static var deathCounter:Int = 0;

	public var defaultCamZoom:Float = 1.05;

	// how big to stretch the pixel art assets
	public static var daPixelZoom:Float = 6;
	private var singAnimations:Array<String> = ['singLEFT', 'singDOWN', 'singUP', 'singRIGHT'];

	public var inCutscene:Bool = false;
	public var skipCountdown:Bool = false;
	var songLength:Float = 0;

	public var boyfriendCameraOffset:Array<Float> = null;
	public var opponentCameraOffset:Array<Float> = null;
	public var girlfriendCameraOffset:Array<Float> = null;

	#if DISCORD_ALLOWED
	// Discord RPC variables
	var storyDifficultyText:String = "";
	var detailsText:String = "";
	var detailsPausedText:String = "";
	#end

	//Achievement shit
	var keysPressed:Array<Int> = [];
	var boyfriendIdleTime:Float = 0.0;
	var boyfriendIdled:Bool = false;

	// Lua shit
	public static var instance:PlayState;
	#if LUA_ALLOWED public var luaArray:Array<FunkinLua> = []; #end

	#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
	private var luaDebugGroup:FlxTypedGroup<psychlua.DebugLuaText>;
	#end
	public var introSoundsSuffix:String = '';

	// Less laggy controls
	private var keysArray:Array<String>;
	public var songName:String;

	// Callbacks for stages
	public var startCallback:Void->Void = null;
	public var endCallback:Void->Void = null;

	override public function create()
	{
		//trace('Playback Rate: ' + playbackRate);
		Paths.clearStoredMemory();

		startCallback = startCountdown;
		endCallback = endSong;

		// for lua
		instance = this;

		PauseSubState.songName = null; //Reset to default
		playbackRate = ClientPrefs.getGameplaySetting('songspeed');

		keysArray = [
			'note_left',
			'note_down',
			'note_up',
			'note_right'
		];

		if(FlxG.sound.music != null)
			FlxG.sound.music.stop();

		// Gameplay settings
		healthGain = ClientPrefs.getGameplaySetting('healthgain');
		healthLoss = ClientPrefs.getGameplaySetting('healthloss');
		instakillOnMiss = ClientPrefs.getGameplaySetting('instakill');
		practiceMode = ClientPrefs.getGameplaySetting('practice');
		cpuControlled = ClientPrefs.getGameplaySetting('botplay');
		guitarHeroSustains = ClientPrefs.data.guitarHeroSustains;

		// var gameCam:FlxCamera = FlxG.camera;
		camGame = initPsychCamera();
		camHUD = new FlxCamera();
		camOther = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		camOther.bgColor.alpha = 0;

		FlxG.cameras.add(camHUD, false);
		FlxG.cameras.add(camOther, false);
		grpNoteSplashes = new FlxTypedGroup<NoteSplash>();

		persistentUpdate = true;
		persistentDraw = true;

		if (SONG == null)
			SONG = Song.loadFromJson('tutorial');

		Conductor.mapBPMChanges(SONG);
		Conductor.bpm = SONG.bpm;


		#if DISCORD_ALLOWED
		// String that contains the mode defined here so it isn't necessary to call changePresence for each mode
		storyDifficultyText = Difficulty.getString();

		if (isStoryMode)
			detailsText = "Story Mode: " + WeekData.getCurrentWeek().weekName;
		else
			detailsText = "Freeplay";

		// String for when the game is paused
		detailsPausedText = "Paused - " + detailsText;
		#end

		GameOverSubstate.resetVariables();
		songName = Paths.formatToSongPath(SONG.song);
		if(SONG.stage == null || SONG.stage.length < 1) {
			SONG.stage = StageData.vanillaSongStage(songName);
		}
		curStage = SONG.stage;

		var stageData:StageFile = StageData.getStageFile(curStage);
		if(stageData == null) { //Stage couldn't be found, create a dummy stage for preventing a crash
			stageData = StageData.dummy();
		}

		defaultCamZoom = stageData.defaultZoom;

		stageUI = "normal";
		if (stageData.stageUI != null && stageData.stageUI.trim().length > 0)
			stageUI = stageData.stageUI;
		else {
			if (stageData.isPixelStage)
				stageUI = "pixel";
		}

		BF_X = stageData.boyfriend[0];
		BF_Y = stageData.boyfriend[1];
		GF_X = stageData.girlfriend[0];
		GF_Y = stageData.girlfriend[1];
		DAD_X = stageData.opponent[0];
		DAD_Y = stageData.opponent[1];

		if(stageData.camera_speed != null)
			cameraSpeed = stageData.camera_speed;

		boyfriendCameraOffset = stageData.camera_boyfriend;
		if(boyfriendCameraOffset == null) //Fucks sake should have done it since the start :rolling_eyes:
			boyfriendCameraOffset = [0, 0];

		opponentCameraOffset = stageData.camera_opponent;
		if(opponentCameraOffset == null)
			opponentCameraOffset = [0, 0];

		girlfriendCameraOffset = stageData.camera_girlfriend;
		if(girlfriendCameraOffset == null)
			girlfriendCameraOffset = [0, 0];

		boyfriendGroup = new FlxSpriteGroup(BF_X, BF_Y);
		dadGroup = new FlxSpriteGroup(DAD_X, DAD_Y);
		gfGroup = new FlxSpriteGroup(GF_X, GF_Y);

		switch (curStage)
		{
			case 'stage': new states.stages.StageWeek1(); //Week 1
			case 'spooky': new states.stages.Spooky(); //Week 2
			case 'philly': new states.stages.Philly(); //Week 3
			case 'limo': new states.stages.Limo(); //Week 4
			case 'mall': new states.stages.Mall(); //Week 5 - Cocoa, Eggnog
			case 'mallEvil': new states.stages.MallEvil(); //Week 5 - Winter Horrorland
			case 'school': new states.stages.School(); //Week 6 - Senpai, Roses
			case 'schoolEvil': new states.stages.SchoolEvil(); //Week 6 - Thorns
			case 'tank': new states.stages.Tank(); //Week 7 - Ugh, Guns, Stress
		}

		if(isPixelStage) {
			introSoundsSuffix = '-pixel';
		}

		add(gfGroup);
		add(dadGroup);
		add(boyfriendGroup);

		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		luaDebugGroup = new FlxTypedGroup<psychlua.DebugLuaText>();
		luaDebugGroup.cameras = [camOther];
		add(luaDebugGroup);
		#end

		// "GLOBAL" SCRIPTS
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'scripts/'))
			for (file in FileSystem.readDirectory(folder))
			{
				#if LUA_ALLOWED
				if(!ClientPrefs.data.disableLuaScripts && file.toLowerCase().endsWith('.lua'))
					new FunkinLua(folder + file);
				#end

				#if HSCRIPT_ALLOWED
				if(!ClientPrefs.data.disableHScriptScripts && file.toLowerCase().endsWith('.hx'))
					initHScript(folder + file);
				#end
			}
		#end

		// STAGE SCRIPTS
		#if LUA_ALLOWED
		startLuasNamed('stages/' + curStage + '.lua');
		#end

		#if HSCRIPT_ALLOWED
		startHScriptsNamed('stages/' + curStage + '.hx');
		#end

		if (!stageData.hide_girlfriend)
		{
			if(SONG.gfVersion == null || SONG.gfVersion.length < 1) SONG.gfVersion = 'gf'; //Fix for the Chart Editor
			gf = new Character(0, 0, SONG.gfVersion);
			startCharacterPos(gf);
			gf.scrollFactor.set(0.95, 0.95);
			gfGroup.add(gf);
			startCharacterScripts(gf.curCharacter);
		}

		dad = new Character(0, 0, SONG.player2);
		startCharacterPos(dad, true);
		dadGroup.add(dad);
		startCharacterScripts(dad.curCharacter);

		boyfriend = new Character(0, 0, SONG.player1, true);
		startCharacterPos(boyfriend);
		boyfriendGroup.add(boyfriend);
		startCharacterScripts(boyfriend.curCharacter);

		var camPos:FlxPoint = FlxPoint.get(girlfriendCameraOffset[0], girlfriendCameraOffset[1]);
		if(gf != null)
		{
			camPos.x += gf.getGraphicMidpoint().x + gf.cameraPosition[0];
			camPos.y += gf.getGraphicMidpoint().y + gf.cameraPosition[1];
		}

		if(dad.curCharacter.startsWith('gf')) {
			dad.setPosition(GF_X, GF_Y);
			if(gf != null)
				gf.visible = false;
		}
		stagesFunc(function(stage:BaseStage) stage.createPost());

		comboGroup = new FlxSpriteGroup();
		add(comboGroup);
		noteGroup = new FlxTypedGroup<FlxBasic>();
		add(noteGroup);
		uiGroup = new FlxSpriteGroup();
		add(uiGroup);

		Conductor.songPosition = -5000 / Conductor.songPosition;
		var showTime:Bool = (ClientPrefs.data.timeBarType != 'Disabled');
		timeTxt = new FlxText(STRUM_X + (FlxG.width / 2) - 248, 19, 400, "", 32);
		timeTxt.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		timeTxt.scrollFactor.set();
		timeTxt.alpha = 0;
		timeTxt.borderSize = 2;
		timeTxt.visible = updateTime = showTime;
		if(ClientPrefs.data.downScroll) timeTxt.y = FlxG.height - 44;
		if(ClientPrefs.data.timeBarType == 'Song Name') timeTxt.text = SONG.song;

		timeBar = new Bar(0, timeTxt.y + (timeTxt.height / 4), 'timeBar', function() return songPercent, 0, 1);
		timeBar.scrollFactor.set();
		timeBar.screenCenter(X);
		timeBar.alpha = 0;
		timeBar.visible = showTime;
		uiGroup.add(timeBar);
		uiGroup.add(timeTxt);

		strumLineNotes = new FlxTypedGroup<StrumNote>();
		noteGroup.add(strumLineNotes);

		if(ClientPrefs.data.timeBarType == 'Song Name')
		{
			timeTxt.size = 24;
			timeTxt.y += 3;
		}

		var splash:NoteSplash = new NoteSplash(100, 100);
		grpNoteSplashes.add(splash);
		splash.alpha = 0.000001; //cant make it invisible or it won't allow precaching

		opponentStrums = new FlxTypedGroup<StrumNote>();
		playerStrums = new FlxTypedGroup<StrumNote>();

		generateSong(SONG.song);

		noteGroup.add(grpNoteSplashes);

		camFollow = new FlxObject(0, 0, 1, 1);
		camFollow.setPosition(camPos.x, camPos.y);
		camPos.put();

		if (prevCamFollow != null)
		{
			camFollow = prevCamFollow;
			prevCamFollow = null;
		}
		add(camFollow);

		FlxG.camera.follow(camFollow, LOCKON, 0);
		FlxG.camera.zoom = defaultCamZoom;
		FlxG.camera.snapToTarget();

		FlxG.worldBounds.set(0, 0, FlxG.width, FlxG.height);
		moveCameraSection();

		healthBar = new Bar(0, FlxG.height * (!ClientPrefs.data.downScroll ? 0.89 : 0.11), 'healthBar', function() return health, 0, 2);
		healthBar.screenCenter(X);
		healthBar.leftToRight = false;
		healthBar.scrollFactor.set();
		healthBar.visible = !ClientPrefs.data.hideHud;
		healthBar.alpha = ClientPrefs.data.healthBarAlpha;
		reloadHealthBarColors();
		uiGroup.add(healthBar);

		iconP1 = new HealthIcon(boyfriend.healthIcon, true);
		iconP1.y = healthBar.y - 75;
		iconP1.visible = !ClientPrefs.data.hideHud;
		iconP1.alpha = ClientPrefs.data.healthBarAlpha;
		uiGroup.add(iconP1);

		iconP2 = new HealthIcon(dad.healthIcon, false);
		iconP2.y = healthBar.y - 75;
		iconP2.visible = !ClientPrefs.data.hideHud;
		iconP2.alpha = ClientPrefs.data.healthBarAlpha;
		uiGroup.add(iconP2);

		scoreTxt = new FlxText(0, healthBar.y + 40, FlxG.width, "", 20);
		scoreTxt.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		scoreTxt.scrollFactor.set();
		scoreTxt.borderSize = 1.25;
		scoreTxt.visible = !ClientPrefs.data.hideHud;
		updateScore(false);
		uiGroup.add(scoreTxt);

		botplayTxt = new FlxText(400, timeBar.y + 55, FlxG.width - 800, "BOTPLAY", 32);
		botplayTxt.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		botplayTxt.scrollFactor.set();
		botplayTxt.borderSize = 1.25;
		botplayTxt.visible = cpuControlled;
		uiGroup.add(botplayTxt);
		if(ClientPrefs.data.downScroll)
			botplayTxt.y = timeBar.y - 78;

		gameplayInfoText = new FlxText(FlxG.width - 470, 10, 460, '', 16);
		gameplayInfoText.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.WHITE, RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		gameplayInfoText.scrollFactor.set();
		gameplayInfoText.borderSize = 1.25;
		gameplayInfoText.cameras = [camHUD];
		gameplayInfoText.visible = ClientPrefs.data.infoDisplay != 'Off';
		uiGroup.add(gameplayInfoText);
		refreshGameplayInfo(true);

		uiGroup.cameras = [camHUD];
		noteGroup.cameras = [camHUD];
		comboGroup.cameras = [camHUD];

		startingSong = true;

		#if LUA_ALLOWED
		for (notetype in noteTypes)
		{
			startLuasNamed('custom_notetypes/' + notetype + '.lua');
			if (!streamLoadedNoteTypes.contains(notetype)) streamLoadedNoteTypes.push(notetype);
		}
		for (event in eventsPushed)
			startLuasNamed('custom_events/' + event + '.lua');
		#end

		#if HSCRIPT_ALLOWED
		for (notetype in noteTypes)
		{
			startHScriptsNamed('custom_notetypes/' + notetype + '.hx');
			if (!streamLoadedNoteTypes.contains(notetype)) streamLoadedNoteTypes.push(notetype);
		}
		for (event in eventsPushed)
			startHScriptsNamed('custom_events/' + event + '.hx');
		#end
		noteTypes = null;
		eventsPushed = null;

		if(eventNotes.length > 1)
		{
			for (event in eventNotes) event.strumTime -= eventEarlyTrigger(event);
			eventNotes.sort(sortByTime);
		}

		// SONG SPECIFIC SCRIPTS
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'data/$songName/'))
			for (file in FileSystem.readDirectory(folder))
			{
				#if LUA_ALLOWED
				if(!ClientPrefs.data.disableLuaScripts && file.toLowerCase().endsWith('.lua'))
					new FunkinLua(folder + file);
				#end

				#if HSCRIPT_ALLOWED
				if(!ClientPrefs.data.disableHScriptScripts && file.toLowerCase().endsWith('.hx'))
					initHScript(folder + file);
				#end
			}
		#end

		startCallback();
		RecalculateRating();

		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyRelease);

		//PRECACHING THINGS THAT GET USED FREQUENTLY TO AVOID LAGSPIKES
		if(ClientPrefs.data.hitsoundVolume > 0) Paths.sound('hitsound');
		for (i in 1...4) Paths.sound('missnote$i');
		Paths.image('alphabet');

		if (PauseSubState.songName != null)
			Paths.music(PauseSubState.songName);
		else if(Paths.formatToSongPath(ClientPrefs.data.pauseMusic) != 'none')
			Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic));

		resetRPC();

		callOnScripts('onCreatePost');

		cacheCountdown();
		cachePopUpScore();

		super.create();
		Paths.clearUnusedMemory();

		if(eventNotes.length < 1) checkEventNote();
	}

	function set_songSpeed(value:Float):Float
	{
		value = Song.clampScrollSpeed(value);
		if(generatedMusic)
		{
			var ratio:Float = value / songSpeed; //funny word huh
			if(ratio != 1)
			{
				if (notes != null && notes.members != null)
					for (note in notes.members)
						if (note != null && note.exists && note.alive && note.isSustainNote) note.resizeByRatio(ratio);
			}
		}
		songSpeed = value;
		noteKillOffset = Math.max(Conductor.stepCrochet, 350 / songSpeed * playbackRate);
		return value;
	}

	function set_playbackRate(value:Float):Float
	{
		#if desktop
		if (ClientPrefs.data.gameRenderer) value = 1;
		#end
		#if FLX_PITCH
		if(generatedMusic)
		{
			vocals.pitch = value;
			opponentVocals.pitch = value;
			FlxG.sound.music.pitch = value;

			var ratio:Float = playbackRate / value; //funny word huh
			if(ratio != 1)
			{
				if (notes != null && notes.members != null)
					for (note in notes.members)
						if (note != null && note.exists && note.alive && note.isSustainNote) note.resizeByRatio(ratio);
			}
		}
		playbackRate = value;
		FlxG.animationTimeScale = value;
		Conductor.safeZoneOffset = (ClientPrefs.data.safeFrames / 60) * 1000 * value;
		setOnScripts('playbackRate', playbackRate);
		#else
		playbackRate = 1.0; // ensuring -Crow
		#end
		return playbackRate;
	}

	#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
	public function addTextToDebug(text:String, color:FlxColor) {
		var newText:psychlua.DebugLuaText = luaDebugGroup.recycle(psychlua.DebugLuaText);
		newText.text = text;
		newText.color = color;
		newText.disableTime = 6;
		newText.alpha = 1;
		newText.setPosition(10, 8 - newText.height);

		luaDebugGroup.forEachAlive(function(spr:psychlua.DebugLuaText) {
			spr.y += newText.height + 2;
		});
		luaDebugGroup.add(newText);

		Sys.println(text);
	}
	#end

	public function reloadHealthBarColors() {
		healthBar.setColors(FlxColor.fromRGB(dad.healthColorArray[0], dad.healthColorArray[1], dad.healthColorArray[2]),
			FlxColor.fromRGB(boyfriend.healthColorArray[0], boyfriend.healthColorArray[1], boyfriend.healthColorArray[2]));
	}

	public function addCharacterToList(newCharacter:String, type:Int) {
		switch(type) {
			case 0:
				if(!boyfriendMap.exists(newCharacter)) {
					var newBoyfriend:Character = new Character(0, 0, newCharacter, true);
					boyfriendMap.set(newCharacter, newBoyfriend);
					boyfriendGroup.add(newBoyfriend);
					startCharacterPos(newBoyfriend);
					newBoyfriend.alpha = 0.00001;
					startCharacterScripts(newBoyfriend.curCharacter);
				}

			case 1:
				if(!dadMap.exists(newCharacter)) {
					var newDad:Character = new Character(0, 0, newCharacter);
					dadMap.set(newCharacter, newDad);
					dadGroup.add(newDad);
					startCharacterPos(newDad, true);
					newDad.alpha = 0.00001;
					startCharacterScripts(newDad.curCharacter);
				}

			case 2:
				if(gf != null && !gfMap.exists(newCharacter)) {
					var newGf:Character = new Character(0, 0, newCharacter);
					newGf.scrollFactor.set(0.95, 0.95);
					gfMap.set(newCharacter, newGf);
					gfGroup.add(newGf);
					startCharacterPos(newGf);
					newGf.alpha = 0.00001;
					startCharacterScripts(newGf.curCharacter);
				}
		}
	}

	function startCharacterScripts(name:String)
	{
		// Lua
		#if LUA_ALLOWED
		if(!ClientPrefs.data.disableLuaScripts) {
		var doPush:Bool = false;
		var luaFile:String = 'characters/$name.lua';
		#if MODS_ALLOWED
		var replacePath:String = Paths.modFolders(luaFile);
		if(FileSystem.exists(replacePath))
		{
			luaFile = replacePath;
			doPush = true;
		}
		else
		{
			luaFile = Paths.getSharedPath(luaFile);
			if(FileSystem.exists(luaFile))
				doPush = true;
		}
		#else
		luaFile = Paths.getSharedPath(luaFile);
		if(Assets.exists(luaFile)) doPush = true;
		#end

		if(doPush)
		{
			for (script in luaArray)
			{
				if(script.scriptName == luaFile)
				{
					doPush = false;
					break;
				}
			}
			if(doPush) new FunkinLua(luaFile);
		}
		}
		#end

		// HScript
		#if HSCRIPT_ALLOWED
		if(!ClientPrefs.data.disableHScriptScripts) {
		var doPush:Bool = false;
		var scriptFile:String = 'characters/' + name + '.hx';
		#if MODS_ALLOWED
		var replacePath:String = Paths.modFolders(scriptFile);
		if(FileSystem.exists(replacePath))
		{
			scriptFile = replacePath;
			doPush = true;
		}
		else
		#end
		{
			scriptFile = Paths.getSharedPath(scriptFile);
			if(FileSystem.exists(scriptFile))
				doPush = true;
		}

		if(doPush)
		{
			if(SScript.global.exists(scriptFile))
				doPush = false;

			if(doPush) initHScript(scriptFile);
		}
		}
		#end
	}

	public function getLuaObject(tag:String, text:Bool=true):FlxSprite {
		#if LUA_ALLOWED
		if(modchartSprites.exists(tag)) return modchartSprites.get(tag);
		if(text && modchartTexts.exists(tag)) return modchartTexts.get(tag);
		if(variables.exists(tag)) return variables.get(tag);
		#end
		return null;
	}

	function startCharacterPos(char:Character, ?gfCheck:Bool = false) {
		if(gfCheck && char.curCharacter.startsWith('gf')) { //IF DAD IS GIRLFRIEND, HE GOES TO HER POSITION
			char.setPosition(GF_X, GF_Y);
			char.scrollFactor.set(0.95, 0.95);
			char.danceEveryNumBeats = 2;
		}
		char.x += char.positionArray[0];
		char.y += char.positionArray[1];
	}

	public function startVideo(name:String)
	{
		#if VIDEOS_ALLOWED
		inCutscene = true;

		var filepath:String = Paths.video(name);
		#if sys
		if(!FileSystem.exists(filepath))
		#else
		if(!OpenFlAssets.exists(filepath))
		#end
		{
			FlxG.log.warn('Couldnt find video file: ' + name);
			startAndEnd();
			return;
		}

		var video:VideoHandler = new VideoHandler();
			#if (hxCodec >= "3.0.0")
			// Recent versions
			video.play(filepath);
			video.onEndReached.add(function()
			{
				video.dispose();
				startAndEnd();
				return;
			}, true);
			#else
			// Older versions
			video.playVideo(filepath);
			video.finishCallback = function()
			{
				startAndEnd();
				return;
			}
			#end
		#else
		FlxG.log.warn('Platform not supported!');
		startAndEnd();
		return;
		#end
	}

	function startAndEnd()
	{
		if(endingSong)
			endSong();
		else
			startCountdown();
	}

	var dialogueCount:Int = 0;
	public var psychDialogue:DialogueBoxPsych;
	//You don't have to add a song, just saying. You can just do "startDialogue(DialogueBoxPsych.parseDialogue(Paths.json(songName + '/dialogue')))" and it should load dialogue.json
	public function startDialogue(dialogueFile:DialogueFile, ?song:String = null):Void
	{
		// TO DO: Make this more flexible, maybe?
		if(psychDialogue != null) return;

		if(dialogueFile.dialogue.length > 0) {
			inCutscene = true;
			psychDialogue = new DialogueBoxPsych(dialogueFile, song);
			psychDialogue.scrollFactor.set();
			if(endingSong) {
				psychDialogue.finishThing = function() {
					psychDialogue = null;
					endSong();
				}
			} else {
				psychDialogue.finishThing = function() {
					psychDialogue = null;
					startCountdown();
				}
			}
			psychDialogue.nextDialogueThing = startNextDialogue;
			psychDialogue.skipDialogueThing = skipDialogue;
			psychDialogue.cameras = [camHUD];
			add(psychDialogue);
		} else {
			FlxG.log.warn('Your dialogue file is badly formatted!');
			startAndEnd();
		}
	}

	var startTimer:FlxTimer;
	var finishTimer:FlxTimer = null;

	// For being able to mess with the sprites on Lua
	public var countdownReady:FlxSprite;
	public var countdownSet:FlxSprite;
	public var countdownGo:FlxSprite;
	public static var startOnTime:Float = 0;

	function cacheCountdown()
	{
		var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
		var introImagesArray:Array<String> = switch(stageUI) {
			case "pixel": ['${stageUI}UI/ready-pixel', '${stageUI}UI/set-pixel', '${stageUI}UI/date-pixel'];
			case "normal": ["ready", "set" ,"go"];
			default: ['${stageUI}UI/ready', '${stageUI}UI/set', '${stageUI}UI/go'];
		}
		introAssets.set(stageUI, introImagesArray);
		var introAlts:Array<String> = introAssets.get(stageUI);
		for (asset in introAlts) Paths.image(asset);

		Paths.sound('intro3' + introSoundsSuffix);
		Paths.sound('intro2' + introSoundsSuffix);
		Paths.sound('intro1' + introSoundsSuffix);
		Paths.sound('introGo' + introSoundsSuffix);
	}

	public function startCountdown()
	{
		if(startedCountdown) {
			callOnScripts('onStartCountdown');
			return false;
		}

		seenCutscene = true;
		inCutscene = false;
		var ret:Dynamic = callOnScripts('onStartCountdown', null, true);
		if(ret != LuaUtils.Function_Stop) {
			if (skipCountdown || startOnTime > 0) skipArrowStartTween = true;

			generateStaticArrows(0);
			generateStaticArrows(1);
			for (i in 0...playerStrums.length) {
				setOnScripts('defaultPlayerStrumX' + i, playerStrums.members[i].x);
				setOnScripts('defaultPlayerStrumY' + i, playerStrums.members[i].y);
			}
			for (i in 0...opponentStrums.length) {
				setOnScripts('defaultOpponentStrumX' + i, opponentStrums.members[i].x);
				setOnScripts('defaultOpponentStrumY' + i, opponentStrums.members[i].y);
				//if(ClientPrefs.data.middleScroll) opponentStrums.members[i].visible = false;
			}

			startedCountdown = true;
			Conductor.songPosition = -Conductor.crochet * 5;
			setOnScripts('startedCountdown', true);
			callOnScripts('onCountdownStarted', null);

			var swagCounter:Int = 0;
			if (startOnTime > 0) {
				clearNotesBefore(startOnTime);
				setSongTime(startOnTime - 350);
				return true;
			}
			else if (skipCountdown)
			{
				setSongTime(0);
				return true;
			}
			moveCameraSection();

			startTimer = new FlxTimer().start(Conductor.crochet / 1000 / playbackRate, function(tmr:FlxTimer)
			{
				characterBopper(tmr.loopsLeft);

				var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
				var introImagesArray:Array<String> = switch(stageUI) {
					case "pixel": ['${stageUI}UI/ready-pixel', '${stageUI}UI/set-pixel', '${stageUI}UI/date-pixel'];
					case "normal": ["ready", "set" ,"go"];
					default: ['${stageUI}UI/ready', '${stageUI}UI/set', '${stageUI}UI/go'];
				}
				introAssets.set(stageUI, introImagesArray);

				var introAlts:Array<String> = introAssets.get(stageUI);
				var antialias:Bool = (ClientPrefs.data.antialiasing && !isPixelStage);
				var tick:Countdown = THREE;

				switch (swagCounter)
				{
					case 0:
						FlxG.sound.play(Paths.sound('intro3' + introSoundsSuffix), 0.6);
						tick = THREE;
					case 1:
						countdownReady = createCountdownSprite(introAlts[0], antialias);
						FlxG.sound.play(Paths.sound('intro2' + introSoundsSuffix), 0.6);
						tick = TWO;
					case 2:
						countdownSet = createCountdownSprite(introAlts[1], antialias);
						FlxG.sound.play(Paths.sound('intro1' + introSoundsSuffix), 0.6);
						tick = ONE;
					case 3:
						countdownGo = createCountdownSprite(introAlts[2], antialias);
						FlxG.sound.play(Paths.sound('introGo' + introSoundsSuffix), 0.6);
						tick = GO;
					case 4:
						tick = START;
				}

				notes.forEachAlive(function(note:Note) {
					if(ClientPrefs.data.opponentStrums || note.mustPress)
					{
						note.copyAlpha = false;
						note.alpha = note.multAlpha;
						if(ClientPrefs.data.middleScroll && !note.mustPress)
							note.alpha *= 0.35;
					}
				});

				stagesFunc(function(stage:BaseStage) stage.countdownTick(tick, swagCounter));
				callOnLuas('onCountdownTick', [swagCounter]);
				callOnHScript('onCountdownTick', [tick, swagCounter]);

				swagCounter += 1;
			}, 5);
		}
		return true;
	}

	inline private function createCountdownSprite(image:String, antialias:Bool):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite().loadGraphic(Paths.image(image));
		spr.cameras = [camHUD];
		spr.scrollFactor.set();
		spr.updateHitbox();

		if (PlayState.isPixelStage)
			spr.setGraphicSize(Std.int(spr.width * daPixelZoom));

		spr.screenCenter();
		spr.antialiasing = antialias;
		insert(members.indexOf(noteGroup), spr);
		FlxTween.tween(spr, {/*y: spr.y + 100,*/ alpha: 0}, Conductor.crochet / 1000, {
			ease: FlxEase.cubeInOut,
			onComplete: function(twn:FlxTween)
			{
				remove(spr);
				spr.destroy();
			}
		});
		return spr;
	}

	public function addBehindGF(obj:FlxBasic)
	{
		insert(members.indexOf(gfGroup), obj);
	}
	public function addBehindBF(obj:FlxBasic)
	{
		insert(members.indexOf(boyfriendGroup), obj);
	}
	public function addBehindDad(obj:FlxBasic)
	{
		insert(members.indexOf(dadGroup), obj);
	}

	public function clearNotesBefore(time:Float)
	{
		// A seek/restart changes the spawn timeline; do not deduplicate against old timestamps.
		renderBudgetHeadsByLane = new Map<String, Float>();
		if (ClientPrefs.data.fastNoteSpawning)
		{
			// Preserve hidden sustain heads before the future queue so spawnCastNote can
			// rebuild their parent object before any still-relevant tail pieces spawn.
			var preservedParents:Array<CastNote> = [];
			var scanIndex:Int = unspawnNoteIndex;
			while (scanIndex < unspawnNotes.length)
			{
				var castNote:CastNote = unspawnNotes[scanIndex];
				if (castNote == null) { scanIndex++; continue; }
				if (castNote.strumTime - 350 >= time) break;
				var lastTailTime:Float = castNote.strumTime;
				if (castNote.hasSustain == true)
				{
					if (castNote.tailCount != null && castNote.tailCount > 0 && castNote.stepCrochet != null)
						lastTailTime += (castNote.tailCount - 1) * castNote.stepCrochet;
					else lastTailTime += Math.floor((castNote.sustainLength == null ? 0 : castNote.sustainLength) / Conductor.stepCrochet) * Conductor.stepCrochet;
				}
				if (castNote.hasSustain == true && lastTailTime - 350 >= time)
				{
					castNote.skipOnSpawn = true;
					preservedParents.push(castNote);
				}
				scanIndex++;
			}
			if (scanIndex > unspawnNoteIndex)
			{
				var rebuilt:Array<CastNote> = preservedParents;
				for (i in scanIndex...unspawnNotes.length)
					if (unspawnNotes[i] != null) rebuilt.push(unspawnNotes[i]);
				unspawnNotes = rebuilt;
				unspawnNoteIndex = 0;
			}
		}
		else
		{
			var i:Int = unspawnNotes.length - 1;
			while (i >= 0)
			{
				var castNote:CastNote = unspawnNotes[i];
				if (castNote != null && castNote.strumTime - 350 < time)
				{
					var lastTailTime:Float = castNote.strumTime;
					if (castNote.hasSustain == true)
					{
						if (castNote.tailCount != null && castNote.tailCount > 0 && castNote.stepCrochet != null)
							lastTailTime += (castNote.tailCount - 1) * castNote.stepCrochet;
						else lastTailTime += Math.floor((castNote.sustainLength == null ? 0 : castNote.sustainLength) / Conductor.stepCrochet) * Conductor.stepCrochet;
					}
					if (castNote.hasSustain == true && lastTailTime - 350 >= time)
						castNote.skipOnSpawn = true;
					else unspawnNotes.splice(i, 1);
				}
				i--;
			}
			unspawnNoteIndex = 0;
		}

		// Deferred tail events use one heap entry per chain. Fast-forward only the
		// already-passed segments; never allocate a Note for a tail before its time.
		advanceDeferredSustainsPast(time);

		var i:Int = notes.length - 1;
		while (i >= 0 && i < notes.members.length) {
			var daNote:Note = notes.members[i];
			if(daNote != null && daNote.strumTime - 350 < time)
			{
				daNote.active = false;
				daNote.visible = false;
				daNote.ignoreNote = true;
				invalidateNote(daNote);
				i--;
			}
			else --i;
		}

		// Rebuild the density timeline after a seek so old maxima/events do not leak
		// into the new position, while already-spawned future notes remain counted.
		rebuildNpsTrackingFromSpawnedNotes();
	}

	private inline function isNpsInfoEnabled():Bool
		return ClientPrefs.data.infoDisplay == 'NPS' || ClientPrefs.data.infoDisplay == 'Both';

	/** Add a spawned chart note to the time-ordered NPS feed. Sustain pieces count individually. */
	private inline function registerNpsNote(note:Note):Void
	{
		if (note == null || !isNpsInfoEnabled()) return;
		if (note.mustPress) pendingPlayNpsTimes.push(note.strumTime);
		else pendingOppNpsTimes.push(note.strumTime);
	}

	private function resetNpsTracking():Void
	{
		pendingOppNpsTimes = [];
		pendingPlayNpsTimes = [];
		pendingOppNpsHead = pendingPlayNpsHead = 0;
		activeOppNpsTimes = [];
		activePlayNpsTimes = [];
		activeOppNpsHead = activePlayNpsHead = 0;
		currentOppNps = currentPlayNps = currentBothNps = 0;
		maxOppNps = maxPlayNps = maxBothNps = 0;
	}

	private function rebuildNpsTrackingFromSpawnedNotes():Void
	{
		resetNpsTracking();
		if (!isNpsInfoEnabled() || notes == null) return;

		for (note in notes.members)
			if (note != null && note.exists && note.alive)
				registerNpsNote(note);

		// A seek can leave spawned notes in swap-pop order, so restore timestamp order.
		var sortTimes = function(a:Float, b:Float):Int return a < b ? -1 : (a > b ? 1 : 0);
		pendingOppNpsTimes.sort(sortTimes);
		pendingPlayNpsTimes.sort(sortTimes);
	}

	private function updateNpsStats(songPosition:Float):Void
	{
		if (!isNpsInfoEnabled()) return;
		var oldestTime:Float = songPosition - 1000;

		// Merge both side queues by strum time. Updating the maximum at each event
		// preserves short density spikes even when a slow frame skips over them.
		while (true)
		{
			var hasOpp:Bool = pendingOppNpsHead < pendingOppNpsTimes.length;
			var hasPlay:Bool = pendingPlayNpsHead < pendingPlayNpsTimes.length;
			if (!hasOpp && !hasPlay) break;

			var takeOpp:Bool = hasOpp && (!hasPlay
				|| pendingOppNpsTimes[pendingOppNpsHead] <= pendingPlayNpsTimes[pendingPlayNpsHead]);
			var nextTime:Float = takeOpp
				? pendingOppNpsTimes[pendingOppNpsHead]
				: pendingPlayNpsTimes[pendingPlayNpsHead];
			if (nextTime > songPosition) break;

			if (takeOpp)
			{
				pendingOppNpsHead++;
				activeOppNpsTimes.push(nextTime);
			}
			else
			{
				pendingPlayNpsHead++;
				activePlayNpsTimes.push(nextTime);
			}

			var eventWindowStart:Float = nextTime - 1000;
			while (activeOppNpsHead < activeOppNpsTimes.length && activeOppNpsTimes[activeOppNpsHead] < eventWindowStart)
				activeOppNpsHead++;
			while (activePlayNpsHead < activePlayNpsTimes.length && activePlayNpsTimes[activePlayNpsHead] < eventWindowStart)
				activePlayNpsHead++;

			var oppAtEvent:Int = activeOppNpsTimes.length - activeOppNpsHead;
			var playAtEvent:Int = activePlayNpsTimes.length - activePlayNpsHead;
			if (oppAtEvent > maxOppNps) maxOppNps = oppAtEvent;
			if (playAtEvent > maxPlayNps) maxPlayNps = playAtEvent;
			if (oppAtEvent + playAtEvent > maxBothNps) maxBothNps = oppAtEvent + playAtEvent;
		}

		// The live values are the events inside [songPosition - 1 second, songPosition].
		while (activeOppNpsHead < activeOppNpsTimes.length && activeOppNpsTimes[activeOppNpsHead] < oldestTime)
			activeOppNpsHead++;
		while (activePlayNpsHead < activePlayNpsTimes.length && activePlayNpsTimes[activePlayNpsHead] < oldestTime)
			activePlayNpsHead++;

		currentOppNps = activeOppNpsTimes.length - activeOppNpsHead;
		currentPlayNps = activePlayNpsTimes.length - activePlayNpsHead;
		currentBothNps = currentOppNps + currentPlayNps;
		if (currentOppNps > maxOppNps) maxOppNps = currentOppNps;
		if (currentPlayNps > maxPlayNps) maxPlayNps = currentPlayNps;
		if (currentBothNps > maxBothNps) maxBothNps = currentBothNps;

		// Periodically discard consumed prefixes. This keeps long songs bounded without
		// shifting the arrays on every frame.
		if (pendingOppNpsHead >= 4096 && pendingOppNpsHead * 2 >= pendingOppNpsTimes.length)
		{
			pendingOppNpsTimes.splice(0, pendingOppNpsHead);
			pendingOppNpsHead = 0;
		}
		if (pendingPlayNpsHead >= 4096 && pendingPlayNpsHead * 2 >= pendingPlayNpsTimes.length)
		{
			pendingPlayNpsTimes.splice(0, pendingPlayNpsHead);
			pendingPlayNpsHead = 0;
		}
		if (activeOppNpsHead >= 4096 && activeOppNpsHead * 2 >= activeOppNpsTimes.length)
		{
			activeOppNpsTimes.splice(0, activeOppNpsHead);
			activeOppNpsHead = 0;
		}
		if (activePlayNpsHead >= 4096 && activePlayNpsHead * 2 >= activePlayNpsTimes.length)
		{
			activePlayNpsTimes.splice(0, activePlayNpsHead);
			activePlayNpsHead = 0;
		}
	}

	private function formatInfoCount(value:Int):String
	{
		var raw:String = Std.string(value);
		var result:StringBuf = new StringBuf();
		for (i in 0...raw.length)
		{
			if (i > 0 && (raw.length - i) % 3 == 0) result.add(',');
			result.add(raw.charAt(i));
		}
		return result.toString();
	}

	private function refreshGameplayInfo(force:Bool = false):Void
	{
		if (gameplayInfoText == null) return;
		var mode:String = ClientPrefs.data.infoDisplay;
		var showNps:Bool = mode == 'NPS' || mode == 'Both';
		var showRendered:Bool = mode == 'Rendered' || mode == 'Both';
		gameplayInfoText.visible = showNps || showRendered;
		if (!gameplayInfoText.visible) return;

		gameplayInfoRefresh += FlxG.elapsed;
		if (!force && gameplayInfoRefresh < 0.1) return;
		gameplayInfoRefresh = 0;

		var lines:Array<String> = [];
		if (showNps)
		{
			lines.push('Opp NPS: ${formatInfoCount(currentOppNps)} / ${formatInfoCount(maxOppNps)}');
			lines.push('Play NPS: ${formatInfoCount(currentPlayNps)} / ${formatInfoCount(maxPlayNps)}');
			lines.push('Both NPS: ${formatInfoCount(currentBothNps)} / ${formatInfoCount(maxBothNps)}');
		}
		if (showRendered)
		{
			var activeNotes:Int = notes == null ? 0 : notes.length;
			var skippedNotes:Int = activeNotes - renderedNoteDrawCount;
			if (skippedNotes < 0) skippedNotes = 0;
			lines.push('Rendered/Skipped: ${formatInfoCount(renderedNoteDrawCount)} / ${formatInfoCount(skippedNotes)}');
			lines.push('Budget Visible/Hidden: ${formatInfoCount(renderedNoteCount)} / ${formatInfoCount(hiddenNoteCount)}');
		}
		gameplayInfoText.text = lines.join('\n');
	}

	// fun fact: Dynamic Functions can be overriden by just doing this
	// `updateScore = function(miss:Bool = false) { ... }
	// its like if it was a variable but its just a function!
	// cool right? -Crow
	public dynamic function updateScore(miss:Bool = false)
	{
		var ret:Dynamic = callOnScripts('preUpdateScore', [miss], true);
		if (ret == LuaUtils.Function_Stop)
			return;

		var str:String = ratingName;
		if(totalPlayed != 0)
		{
			var percent:Float = CoolUtil.floorDecimal(ratingPercent * 100, 2);
			str += ' (${percent}%) - ${ratingFC}';
		}

		var tempScore:String = 'Score: ${songScore}'
		+ (!instakillOnMiss ? ' | Misses: ${songMisses}' : "")
		+ ' | Rating: ${str}';
		// "tempScore" variable is used to prevent another memory leak, just in case
		// "\n" here prevents the text from being cut off by beat zooms
		scoreTxt.text = '${tempScore}\n';

		if (!miss && !cpuControlled)
			doScoreBop();

		callOnScripts('onUpdateScore', [miss]);
	}

	public dynamic function fullComboFunction()
	{
		var sicks:Int = ratingsData[0].hits;
		var goods:Int = ratingsData[1].hits;
		var bads:Int = ratingsData[2].hits;
		var shits:Int = ratingsData[3].hits;

		ratingFC = "";
		if(songMisses == 0)
		{
			if (bads > 0 || shits > 0) ratingFC = 'FC';
			else if (goods > 0) ratingFC = 'GFC';
			else if (sicks > 0) ratingFC = 'SFC';
		}
		else {
			if (songMisses < 10) ratingFC = 'SDCB';
			else ratingFC = 'Clear';
		}
	}

	public function doScoreBop():Void {
		if(!ClientPrefs.data.scoreZoom)
			return;

		if(scoreTxtTween != null)
			scoreTxtTween.cancel();

		scoreTxt.scale.x = 1.075;
		scoreTxt.scale.y = 1.075;
		scoreTxtTween = FlxTween.tween(scoreTxt.scale, {x: 1, y: 1}, 0.2, {
			onComplete: function(twn:FlxTween) {
				scoreTxtTween = null;
			}
		});
	}

	public function setSongTime(time:Float)
	{
		if(time < 0) time = 0;

		FlxG.sound.music.pause();
		vocals.pause();
		opponentVocals.pause();

		FlxG.sound.music.time = time;
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		FlxG.sound.music.play();

		if (Conductor.songPosition <= vocals.length)
		{
			vocals.time = time;
			opponentVocals.time = time;
			#if FLX_PITCH
			vocals.pitch = playbackRate;
			opponentVocals.pitch = playbackRate;
			#end
		}
		vocals.play();
		opponentVocals.play();
		Conductor.songPosition = time;
	}

	public function startNextDialogue() {
		dialogueCount++;
		callOnScripts('onNextDialogue', [dialogueCount]);
	}

	public function skipDialogue() {
		callOnScripts('onSkipDialogue', [dialogueCount]);
	}

	#if desktop
	private function startGameRenderer():Void
	{
		if (renderActive) return;
		renderFPS = Std.int(Math.max(24, Math.min(240, ClientPrefs.data.videoRenderFPS)));
		renderPrevUpdateFramerate = FlxG.updateFramerate;
		renderPrevDrawFramerate = FlxG.drawFramerate;
		renderPrevFixedTimestep = FlxG.fixedTimestep;
		renderPrevAutoPause = FlxG.autoPause;
		try
		{
			if (FFMpeg.instance == null) FFMpeg.instance = new FFMpeg();
			FFMpeg.instance.init();
			FFMpeg.instance.setup();
			FlxG.fixedTimestep = true;
			FlxG.updateFramerate = renderFPS;
			FlxG.drawFramerate = renderFPS;
			FlxG.autoPause = false;
			renderActive = true;
			trace('[ADR Video Renderer] Recording at ' + renderFPS + ' FPS');
		}
		catch (e:Dynamic)
		{
			trace('[ADR Video Renderer] Could not start: ' + Std.string(e));
			if (FFMpeg.instance != null) FFMpeg.instance.destroy();
			FFMpeg.instance = null;
			FlxG.fixedTimestep = renderPrevFixedTimestep;
			FlxG.updateFramerate = renderPrevUpdateFramerate;
			FlxG.drawFramerate = renderPrevDrawFramerate;
			FlxG.autoPause = renderPrevAutoPause;
			renderActive = false;
		}
	}

	private function captureRenderFrame():Void
	{
		if (!renderActive || FFMpeg.instance == null) return;
		try
		{
			FFMpeg.instance.pipeFrame();
		}
		catch (e:Dynamic)
		{
			trace('[ADR Video Renderer] Frame capture failed: ' + Std.string(e));
			stopGameRenderer();
		}
	}

	private function stopGameRenderer():Void
	{
		if (!renderActive && FFMpeg.instance == null) return;
		renderActive = false;
		try
		{
			if (FFMpeg.instance != null) FFMpeg.instance.destroy();
		}
		catch (e:Dynamic)
			trace('[ADR Video Renderer] Finalization warning: ' + Std.string(e));
		FFMpeg.instance = null;
		FlxG.fixedTimestep = renderPrevFixedTimestep;
		FlxG.updateFramerate = renderPrevUpdateFramerate;
		FlxG.drawFramerate = renderPrevDrawFramerate;
		FlxG.autoPause = renderPrevAutoPause;
		trace('[ADR Video Renderer] Recording finalized.');
	}
	#end

	function startSong():Void
	{
		startingSong = false;

		@:privateAccess
		FlxG.sound.playMusic(inst._sound, 1, false);
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		FlxG.sound.music.onComplete = finishSong.bind();
		#if desktop
		if (ClientPrefs.data.gameRenderer) startGameRenderer();
		#end
		vocals.play();
		opponentVocals.play();

		if(startOnTime > 0) setSongTime(startOnTime - 500);
		startOnTime = 0;

		if(paused) {
			//trace('Oopsie doopsie! Paused sound');
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}

		// Song duration in a float, useful for the time left feature
		songLength = FlxG.sound.music.length;
		FlxTween.tween(timeBar, {alpha: 1}, 0.5, {ease: FlxEase.circOut});
		FlxTween.tween(timeTxt, {alpha: 1}, 0.5, {ease: FlxEase.circOut});

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence (with Time Left)
		if(autoUpdateRPC) DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter(), true, songLength);
		#end
		setOnScripts('songLength', songLength);
		callOnScripts('onSongStart');
	}

	var debugNum:Int = 0;
	private var noteTypes:Array<String> = [];
	private var eventsPushed:Array<String> = [];
	// The queue stores chart heads only when deferred sustain generation is enabled.
	// Rows/frame and low-watermark are user-adjustable in Optimizations.
	private var chunkedChartSections:Array<SwagSection> = null;
	private var chunkedSectionIndex:Int = 0;
	private var chunkedSectionNoteIndex:Int = 0;
	private var chunkedNotesComplete:Bool = true;
	private var useRollingNoteGeneration:Bool = false;
	private var streamLoadedNoteTypes:Array<String> = [];
	#if sys
	private var jsonStreamReader:ChartJsonStream = null;
	private var jsonStreamSidecarPath:String = null;
	private var jsonStreamComplete:Bool = true;
	#end

	/** Called by Note.draw() as a final hard cap, even if another code path changes visible. */
	public function canDrawBudgetedNote(note:Note):Bool
	{
		if (note == null || !ClientPrefs.data.showNotes || !note.renderBudgetVisible || note.renderBudgetSuppressed)
			return false;
		if (!ClientPrefs.data.noteRenderProcessingEnabled) return true;
		var limit:Int = ClientPrefs.data.renderedNotesLimit;
		if (limit > 0 && renderedNoteDrawCount >= limit) return false;
		renderedNoteDrawCount++;
		return true;
	}

	private function resetRenderedNoteBudget():Void
	{
		renderedNoteCount = 0;
		hiddenNoteCount = 0;
		pendingRenderHead = null;
		pendingRenderTail = null;
		renderBudgetHeadsByLane = new Map<String, Float>();
		suspendRenderBudgetPromotion = false;
		noteCullFrameCounter = 0;
	}

	/** Register a newly spawned note with the visual budget. Gameplay data is never removed. */
	private function registerRenderedNote(note:Note):Void
	{
		note.renderBudgetManaged = true;
		note.renderBudgetVisible = false;
		note.renderBudgetPending = false;
		note.renderBudgetSuppressed = false;
		note.renderBudgetPrev = null;
		note.renderBudgetNext = null;

		if (!ClientPrefs.data.showNotes)
		{
			note.active = false;
			note.visible = false;
			hiddenNoteCount++;
			return;
		}

		// Hide either side without removing its logical note or changing gameplay.
		if ((note.mustPress && !ClientPrefs.data.renderPlayerNotes)
			|| (!note.mustPress && !ClientPrefs.data.renderOpponentNotes))
		{
			note.renderBudgetSuppressed = true;
			note.active = false;
			note.visible = false;
			hiddenNoteCount++;
			return;
		}

		// Legacy rendering mode puts every logical note through the original Flixel group.
		// It intentionally ignores the render budget but still respects Show Notes and side toggles.
		if (!ClientPrefs.data.noteRenderProcessingEnabled)
		{
			note.renderBudgetManaged = false;
			note.renderBudgetVisible = false;
			note.renderBudgetPending = false;
			note.renderBudgetSuppressed = false;
			note.ensureVisuals();
			note.active = note.visible = true;
			return;
		}

		// The default 0.01 ms window catches exact/near-exact duplicate tap heads, not sustains.
		// Side, lane and note type are part of the key to preserve distinct gameplay notes.
		var overlapWindow:Float = ClientPrefs.data.overlapRemovalWindowMs;
		if (!note.isSustainNote && note.sustainLength <= 0 && overlapWindow > 0)
		{
			var overlapKey:String = (note.mustPress ? 'player:' : 'opponent:') + note.noteData + ':' + (note.noteType == null ? '' : note.noteType);
			var previousTime:Null<Float> = renderBudgetHeadsByLane.get(overlapKey);
			if (previousTime != null && Math.abs(note.strumTime - previousTime) <= overlapWindow)
			{
				// Keep the duplicate alive for normal judgement, but skip sprite/animation updates.
				note.renderBudgetSuppressed = true;
				note.active = false;
				note.visible = false;
				hiddenNoteCount++;
				return;
			}
			renderBudgetHeadsByLane.set(overlapKey, note.strumTime);
		}

		var limit:Int = ClientPrefs.data.renderedNotesLimit;
		if (limit <= 0 || renderedNoteCount < limit)
		{
			note.ensureVisuals();
			note.renderBudgetVisible = true;
			note.active = true;
			note.visible = true;
			addRenderedBudgetNote(note);
			renderedNoteCount++;
		}
		else
		{
			note.renderBudgetPending = true;
			note.active = false;
			note.visible = false;
			hiddenNoteCount++;
			note.renderBudgetPrev = pendingRenderTail;
			if (pendingRenderTail == null) pendingRenderHead = note;
			else pendingRenderTail.renderBudgetNext = note;
			pendingRenderTail = note;
		}
	}

	/** Remove a pending note from the intrusive queue without retaining expired notes. */
	private function unlinkPendingRenderedNote(note:Note):Void
	{
		if (note == null || !note.renderBudgetPending) return;
		if (note.renderBudgetPrev != null) note.renderBudgetPrev.renderBudgetNext = note.renderBudgetNext;
		else if (pendingRenderHead == note) pendingRenderHead = note.renderBudgetNext;
		if (note.renderBudgetNext != null) note.renderBudgetNext.renderBudgetPrev = note.renderBudgetPrev;
		else if (pendingRenderTail == note) pendingRenderTail = note.renderBudgetPrev;
		note.renderBudgetPrev = null;
		note.renderBudgetNext = null;
		note.renderBudgetPending = false;
	}

	/** Promote the next queued note when a visible note leaves the active group. */
	private function promoteNextRenderedNote():Void
	{
		if (suspendRenderBudgetPromotion || !ClientPrefs.data.showNotes || !ClientPrefs.data.noteRenderProcessingEnabled) return;
		var limit:Int = ClientPrefs.data.renderedNotesLimit;
		if (limit > 0 && renderedNoteCount >= limit) return;

		while (pendingRenderHead != null)
		{
			var candidate:Note = pendingRenderHead;
			unlinkPendingRenderedNote(candidate);
			if (!candidate.alive) continue;

			if (hiddenNoteCount > 0) hiddenNoteCount--;
			candidate.ensureVisuals();
			candidate.renderBudgetVisible = true;
			candidate.active = true;
			candidate.visible = true;
			addRenderedBudgetNote(candidate);
			renderedNoteCount++;
			break;
		}
	}

	private function generateSong(dataPath:String):Void
	{
		unspawnNotes = [];
		unspawnNoteIndex = 0;
		pendingSustainSpawns = [];
		nextCastChainId = 1;
		nextCastSortOrder = 0;
		// A reset can happen after the stream reached EOF (and its sidecar was
		// deleted). Rebuild from the source JSON so Retry works in that case too.
		#if sys
		if (SONG != null)
		{
			var savedSidecar:String = Reflect.field(SONG, "__chartStreamPath");
			var sourcePath:String = Reflect.field(SONG, "__chartSourcePath");
			if ((savedSidecar == null || !FileSystem.exists(savedSidecar))
				&& sourcePath != null && sourcePath.length > 0 && FileSystem.exists(sourcePath))
				SONG = Song.reloadStreamedSong(SONG);
		}
		#end
		// FlxG.log.add(ChartParser.parse());
		songSpeed = PlayState.SONG.speed;
		songSpeedType = ClientPrefs.getGameplaySetting('scrolltype');
		switch(songSpeedType)
		{
			case "multiplicative":
				songSpeed = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed');
			case "constant":
				songSpeed = ClientPrefs.getGameplaySetting('scrollspeed');
		}

		var songData = SONG;
		Conductor.bpm = songData.bpm;

		curSong = songData.song;

		vocals = new FlxSound();
		opponentVocals = new FlxSound();
		try
		{
			if (songData.needsVoices)
			{
				var playerVocals = Paths.voices(songData.song, (boyfriend.vocalsFile == null || boyfriend.vocalsFile.length < 1) ? 'Player' : boyfriend.vocalsFile);
				vocals.loadEmbedded(playerVocals != null ? playerVocals : Paths.voices(songData.song));
				
				var oppVocals = Paths.voices(songData.song, (dad.vocalsFile == null || dad.vocalsFile.length < 1) ? 'Opponent' : dad.vocalsFile);
				if(oppVocals != null) opponentVocals.loadEmbedded(oppVocals);
			}
		}
		catch(e:Dynamic) {}

		#if FLX_PITCH
		vocals.pitch = playbackRate;
		opponentVocals.pitch = playbackRate;
		#end
		FlxG.sound.list.add(vocals);
		FlxG.sound.list.add(opponentVocals);

		inst = new FlxSound();
		try {
			inst.loadEmbedded(Paths.inst(songData.song));
		}
		catch(e:Dynamic) {}
		FlxG.sound.list.add(inst);

		notes = new NoteGroup();
		grpRenderedNotes = new FlxTypedGroup<Note>();
		// The optimized processor keeps the logical group out of Flixel traversal and
		// visits only admitted sprites. Turning it off restores the legacy all-note group.
		var useRenderProcessor:Bool = ClientPrefs.data.noteRenderProcessingEnabled;
		notes.active = !useRenderProcessor;
		notes.visible = !useRenderProcessor;
		grpRenderedNotes.active = useRenderProcessor;
		grpRenderedNotes.visible = useRenderProcessor;
		lastRenderProcessorSetting = ClientPrefs.data.noteRenderProcessingEnabled;
		lastShowNotesSetting = ClientPrefs.data.showNotes;
		lastRenderPlayerSetting = ClientPrefs.data.renderPlayerNotes;
		lastRenderOpponentSetting = ClientPrefs.data.renderOpponentNotes;
		lastRenderedNoteLimit = ClientPrefs.data.renderedNotesLimit;
		lastOverlapWindowSetting = ClientPrefs.data.overlapRemovalWindowMs;
		lastNotePoolRetentionSetting = ClientPrefs.data.notePoolEnabled;
		lastNoteObjectPoolingSetting = ClientPrefs.data.noteObjectPooling;
		lastNotePoolPerLaneLimit = ClientPrefs.data.maxPooledNotesPerLane;
		lastNotePoolTotalLimit = ClientPrefs.data.maxPooledNotesTotal;
		lastNoteAnimationSetting = ClientPrefs.data.noteRenderingAnimations;
		lastNoteRGBSetting = ClientPrefs.data.noteRenderingRGBShaders;
		lastNoteAntialiasSetting = ClientPrefs.data.noteRenderingAntialiasing;
			lastGlobalAntialiasSetting = ClientPrefs.data.antialiasing;
		noteGroup.add(notes);
		noteGroup.add(grpRenderedNotes);
		resetRenderedNoteBudget();

		var noteData:Array<SwagSection>;

		// NEW SHIT
		noteData = songData.notes;

		if (Song.chartExists('events', songName))
		{
			var eventsData:Array<Dynamic> = Song.loadFromJson('events', songName).events;
			if (eventsData != null)
			{
				for (event in eventsData) // Event Notes
				{
					if (event == null || !Std.isOfType(event, Array) || event.length < 2 || event[1] == null || !Std.isOfType(event[1], Array)) continue;
					for (i in 0...event[1].length) makeEvent(event, i);
				}
			}
		}

		var usingJsonStream:Bool = false;
		#if sys
		var streamPath:String = Reflect.field(songData, "__chartStreamPath");
		if (streamPath != null)
		{
			jsonStreamReader = ChartJsonStream.takePreparedReader(streamPath);
			jsonStreamSidecarPath = streamPath;
			jsonStreamComplete = false;
			useRollingNoteGeneration = true;
			usingJsonStream = true;
			generateNextJsonNoteChunk(ClientPrefs.data.noteGenerationRowsPerFrame);
		}
		#end

		if (!usingJsonStream && ClientPrefs.data.chunkedNoteGeneration)
		{
			chunkedChartSections = noteData;
			chunkedSectionIndex = 0;
			chunkedSectionNoteIndex = 0;
			chunkedNotesComplete = false;
			useRollingNoteGeneration = true;
				generateNextChartNoteChunk(ClientPrefs.data.noteGenerationRowsPerFrame);
		}
		else if (!usingJsonStream)
		{
			for (section in noteData)
				for (songNotes in section.sectionNotes)
					addChartNote(section, songNotes);
		}

		for (event in songData.events) //Event Notes
			for (i in 0...event[1].length)
				makeEvent(event, i);

		if (!ClientPrefs.data.chunkedNoteGeneration) unspawnNotes.sort(sortCastNoteByTime);
		unspawnNoteIndex = 0;
		generatedMusic = true;
	}

	/**
	 * Converts one raw chart row into a tap note and its sustain pieces.
	 * Keeping this in one function ensures the legacy and chunked paths share
	 * identical note construction and positioning rules.
	 */
	private function addChartNote(section:SwagSection, songNotes:Array<Dynamic>):Void
	{
		if (songNotes == null || songNotes.length < 2) return;

		var strumTime:Float = songNotes[0];
		var lane:Int = Std.int(songNotes[1] % 4);
		var mustPress:Bool = section.mustHitSection;
		if (songNotes[1] > 3) mustPress = !section.mustHitSection;
		var gfNote:Bool = section.gfSection && songNotes[1] < 4;
		var sustainLength:Float = songNotes.length > 2 ? songNotes[2] : 0;
		var noteType:String = null;
		if (songNotes.length > 3)
		{
			if (Std.isOfType(songNotes[3], String)) noteType = cast songNotes[3];
			else
			{
				var typeIndex:Int = Std.int(songNotes[3]);
				if (typeIndex >= 0 && typeIndex < ChartingState.noteTypeList.length)
					noteType = ChartingState.noteTypeList[typeIndex];
			}
		}

		var chainId:Int = nextCastChainId++;
		var stepMs:Float = Conductor.stepCrochet;
		var steps:Float = stepMs > 0 ? sustainLength / stepMs : 0;
		var floorSus:Int = Std.int(Math.floor(steps));
		var sustainCount:Int = floorSus > 0 ? floorSus + 1 : 0;
		var hasSustain:Bool = sustainCount > 0;
		var deferTail:Bool = hasSustain && ClientPrefs.data.deferredSustainSpawning;
		var rootSortOrder:Int = nextCastSortOrder;
		// Reserve stable sort-order slots for tails without allocating each tail record now.
		nextCastSortOrder += 1 + (hasSustain ? sustainCount : 0);

		var root:CastNote = {
			strumTime: strumTime + ClientPrefs.data.noteOffset,
			noteData: lane,
			sortOrder: rootSortOrder,
			chainId: chainId,
			hasSustain: hasSustain,
			skipOnSpawn: false,
			chainEnd: !hasSustain,
			tailCount: deferTail ? sustainCount : 0,
			expectedTailCount: sustainCount,
			stepCrochet: stepMs,
			sustainLength: sustainLength,
			noteType: noteType
		};
		Note.writeCastNoteFlags(root, lane, mustPress, false, false, gfNote, false, false, false, false);
		unspawnNotes.push(root);

		// Compatibility path: materialize tails into the legacy queue when the option is off.
		// The default path keeps only one descriptor on the root and creates tails at spawn time.
		if (hasSustain && !deferTail)
		{
			for (susIndex in 0...sustainCount)
			{
				var isLast:Bool = susIndex == sustainCount - 1;
				var castSustain:CastNote = {
					strumTime: strumTime + ClientPrefs.data.noteOffset + (stepMs * susIndex),
					noteData: lane,
					sortOrder: rootSortOrder + 1 + susIndex,
					chainId: chainId,
					hasSustain: false,
					skipOnSpawn: false,
					chainEnd: isLast,
					tailCount: 0,
					stepCrochet: stepMs,
					sustainLength: 0,
					noteType: noteType
				};
				Note.writeCastNoteFlags(castSustain, lane, mustPress, true, isLast, gfNote, false, false, false, false);
				unspawnNotes.push(castSustain);
			}
		}

		if (noteType != null && noteTypes != null && !noteTypes.contains(noteType))
			noteTypes.push(noteType);
		else if (noteType != null && noteTypes == null)
			loadStreamNoteType(noteType);
	}

	/**
	 * Merge only the newly generated notes into the already sorted spawn queue.
	 * Sorting the entire (possibly very large) future-note queue every update was
	 * an O(N log N) hot path for dense charts. Each generated tail is sorted once,
	 * then merged with the previous sorted prefix in linear time.
	 */
	private static inline function sortCastNoteByTime(a:CastNote, b:CastNote):Int
	{
		if (a == null) return b == null ? 0 : 1;
		if (b == null) return -1;
		if (a.strumTime < b.strumTime) return -1;
		if (a.strumTime > b.strumTime) return 1;
		return a.sortOrder - b.sortOrder;
	}

	private function mergeNewUnspawnNotes(oldLength:Int):Void
	{
		var added:Array<CastNote> = unspawnNotes.splice(oldLength, unspawnNotes.length - oldLength);
		if (added.length <= 0)
		{
			unspawnNoteIndex = 0;
			return;
		}

		// Most chart sections arrive chronologically. Skip the O(batch log batch) sort
		// when the generated batch is already ordered; only sort unusual/interleaved mods.
		var batchSorted:Bool = true;
		var sortIndex:Int = 1;
		while (sortIndex < added.length)
		{
			if (sortCastNoteByTime(added[sortIndex - 1], added[sortIndex]) > 0)
			{
				batchSorted = false;
				break;
			}
			sortIndex++;
		}
		if (!batchSorted) added.sort(sortCastNoteByTime);
		if (oldLength <= 0)
		{
			unspawnNotes = added;
			unspawnNoteIndex = 0;
			return;
		}

		var existing:Array<CastNote> = unspawnNotes;
		// Charts are normally stored in chronological section order. In that common
		// case append the sorted batch in O(batch) instead of copying/merging the
		// entire pending queue on every generation update.
		if (existing.length > 0 && sortCastNoteByTime(existing[existing.length - 1], added[0]) <= 0)
		{
			for (castNote in added) existing.push(castNote);
			unspawnNoteIndex = 0;
			return;
		}

		var merged:Array<CastNote> = [];
		var left:Int = 0;
		var right:Int = 0;
		while (left < existing.length && right < added.length)
		{
			if (sortCastNoteByTime(existing[left], added[right]) <= 0)
				merged.push(existing[left++]);
			else
				merged.push(added[right++]);
		}
		while (left < existing.length) merged.push(existing[left++]);
		while (right < added.length) merged.push(added[right++]);
		unspawnNotes = merged;
		unspawnNoteIndex = 0;
	}

	private inline function pendingSustainLess(a:PendingSustainSpawn, b:PendingSustainSpawn):Bool
	{
		return a.nextTime < b.nextTime || (a.nextTime == b.nextTime && a.nextSortOrder < b.nextSortOrder);
	}

	private function pushPendingSustain(state:PendingSustainSpawn):Void
	{
		var i:Int = pendingSustainSpawns.length;
		pendingSustainSpawns.push(state);
		while (i > 0)
		{
			var parent:Int = (i - 1) >> 1;
			var parentState:PendingSustainSpawn = pendingSustainSpawns[parent];
			if (!pendingSustainLess(state, parentState)) break;
			pendingSustainSpawns[i] = parentState;
			i = parent;
		}
		pendingSustainSpawns[i] = state;
	}

	private function popPendingSustain():PendingSustainSpawn
	{
		if (pendingSustainSpawns.length == 0) return null;
		var first:PendingSustainSpawn = pendingSustainSpawns[0];
		var last:PendingSustainSpawn = pendingSustainSpawns.pop();
		if (pendingSustainSpawns.length > 0)
		{
			var i:Int = 0;
			var count:Int = pendingSustainSpawns.length;
			while (true)
			{
				var left:Int = i * 2 + 1;
				if (left >= count) break;
				var right:Int = left + 1;
				var smallest:Int = right < count && pendingSustainLess(pendingSustainSpawns[right], pendingSustainSpawns[left]) ? right : left;
				if (!pendingSustainLess(pendingSustainSpawns[smallest], last)) break;
				pendingSustainSpawns[i] = pendingSustainSpawns[smallest];
				i = smallest;
			}
			pendingSustainSpawns[i] = last;
		}
		return first;
	}

	private function addDeferredSustainChain(root:CastNote):Void
	{
		if (root == null || root.tailCount == null || root.tailCount <= 0) return;
		var stepMs:Float = root.stepCrochet == null || root.stepCrochet <= 0 ? Conductor.stepCrochet : root.stepCrochet;
		var rootFlags:CastNoteFlags = Note.decodeCastNoteFlags(root);
		var state:PendingSustainSpawn = {
			nextTime: root.strumTime,
			stepCrochet: stepMs,
			remaining: root.tailCount,
			// The internal heap always uses a compact flag word, regardless of the selected
			// CastNote queue representation. Each emitted CastNote is then encoded separately.
			noteData: Note.encodeCastNoteData(rootFlags.lane, rootFlags.mustPress, true, false, rootFlags.gfNote,
				rootFlags.altAnim, rootFlags.noAnimation, rootFlags.blockHit, rootFlags.ignoreNote),
			chainId: root.chainId,
			nextSortOrder: root.sortOrder + 1,
			noteType: root.noteType
		};
		// A seek can preserve a skipped head solely to parent the remaining hold.
		// Do not recreate tail segments that are already outside their judgement window.
		if (root.skipOnSpawn == true)
		{
			while (state.remaining > 0 && state.nextTime - 350 < Conductor.songPosition)
			{
				state.remaining--;
				state.nextTime += state.stepCrochet;
				state.nextSortOrder++;
			}
		}
		if (state.remaining > 0) pushPendingSustain(state);
		else if (notes != null) notes.discardCastChain(state.chainId);
	}

	private function makeDeferredSustainCastNote(state:PendingSustainSpawn):CastNote
	{
		var isLast:Bool = state.remaining == 1;
		var castNote:CastNote = deferredSustainCastScratch;
		castNote.strumTime = state.nextTime;
		var stateFlags:CastNoteFlags = Note.decodeCastNoteData(state.noteData);
		Note.writeCastNoteFlags(castNote, stateFlags.lane, stateFlags.mustPress, true, isLast, stateFlags.gfNote, stateFlags.altAnim, stateFlags.noAnimation, stateFlags.blockHit, stateFlags.ignoreNote);
		castNote.sortOrder = state.nextSortOrder;
		castNote.chainId = state.chainId;
		castNote.hasSustain = false;
		castNote.skipOnSpawn = false;
		castNote.chainEnd = isLast;
		castNote.tailCount = 0;
		castNote.stepCrochet = state.stepCrochet;
		castNote.sustainLength = 0;
		castNote.noteType = state.noteType;
		state.remaining--;
		state.nextTime += state.stepCrochet;
		state.nextSortOrder++;
		return castNote;
	}

	private function advanceDeferredSustainsPast(time:Float):Void
	{
		if (pendingSustainSpawns.length == 0) return;
		var kept:Array<PendingSustainSpawn> = [];
		for (state in pendingSustainSpawns)
		{
			while (state.remaining > 0 && state.nextTime - 350 < time)
			{
				state.remaining--;
				state.nextTime += state.stepCrochet;
				state.nextSortOrder++;
			}
			if (state.remaining > 0) kept.push(state);
			else if (notes != null) notes.discardCastChain(state.chainId);
		}
		pendingSustainSpawns = [];
		for (state in kept) pushPendingSustain(state);
	}

	#if sys
	/** Read at most maxRows raw JSON note rows from the sequential sidecar. */
	private function generateNextJsonNoteChunk(maxRows:Int):Void
	{
		if (jsonStreamComplete || jsonStreamReader == null) return;
		maxRows = Std.int(Math.max(1, maxRows));
		if (ClientPrefs.data.fastNoteSpawning && unspawnNoteIndex > 0)
		{
			unspawnNotes = unspawnNotes.slice(unspawnNoteIndex);
			unspawnNoteIndex = 0;
		}
		var oldLength:Int = unspawnNotes.length;
		var loadedRows:Int = 0;
		try
		{
			while (loadedRows < maxRows)
			{
				var record:Dynamic = jsonStreamReader.readNextRecord();
				if (record == null)
				{
					jsonStreamComplete = true;
					break;
				}
				loadedRows++;
				var sectionIndex:Int = Std.int(record.sectionIndex);
				var rawRow:Dynamic = record.row;
				if (rawRow == null || !Std.isOfType(rawRow, Array) || rawRow.length < 2) continue;
				if (sectionIndex < 0 || SONG.notes == null || sectionIndex >= SONG.notes.length) continue;
				var section:SwagSection = cast SONG.notes[sectionIndex];
				if (rawRow[1] < 0)
				{
					// Legacy charts stored event notes as negative note-data rows.
					makeEvent([rawRow[0], [[rawRow[2], rawRow[3], rawRow[4]]]], 0);
				}
				else if (section != null) addChartNote(section, cast rawRow);
			}
		}
		catch (error:Dynamic)
		{
			jsonStreamComplete = true;
			jsonStreamReader.close();
			jsonStreamReader = null;
			if (jsonStreamSidecarPath != null) ChartJsonStream.discardPreparedReader(jsonStreamSidecarPath);
			jsonStreamSidecarPath = null;
			throw 'JSON streaming failed while reading chart rows: ' + error;
		}

		if (jsonStreamComplete)
		{
			jsonStreamReader.close();
			jsonStreamReader = null;
			if (jsonStreamSidecarPath != null) ChartJsonStream.discardPreparedReader(jsonStreamSidecarPath);
			jsonStreamSidecarPath = null;
			Reflect.setField(SONG, "__chartStreamPath", null);
		}

		mergeNewUnspawnNotes(oldLength);
	}
	#end

	/** Loads at most maxRows chart rows, then sorts the pending queue by strum time. */
	private function generateNextChartNoteChunk(maxRows:Int):Void
	{
		if (chunkedNotesComplete || chunkedChartSections == null) return;
		maxRows = Std.int(Math.max(1, maxRows));
		if (ClientPrefs.data.fastNoteSpawning && unspawnNoteIndex > 0)
		{
			unspawnNotes = unspawnNotes.slice(unspawnNoteIndex);
			unspawnNoteIndex = 0;
		}
		var oldLength:Int = unspawnNotes.length;
		var loadedRows:Int = 0;
		while (loadedRows < maxRows && chunkedSectionIndex < chunkedChartSections.length)
		{
			var section:SwagSection = chunkedChartSections[chunkedSectionIndex];
			if (section == null || section.sectionNotes == null)
			{
				chunkedSectionIndex++;
				chunkedSectionNoteIndex = 0;
				continue;
			}

			if (chunkedSectionNoteIndex >= section.sectionNotes.length)
			{
				if (ClientPrefs.data.releaseProcessedChartData) section.sectionNotes = [];
				chunkedSectionIndex++;
				chunkedSectionNoteIndex = 0;
				continue;
			}

			var row:Array<Dynamic> = cast section.sectionNotes[chunkedSectionNoteIndex];
			if (ClientPrefs.data.releaseProcessedChartData) section.sectionNotes[chunkedSectionNoteIndex] = null;
			chunkedSectionNoteIndex++;
			if (row == null) continue;
			addChartNote(section, row);
			loadedRows++;
		}

		if (chunkedSectionIndex >= chunkedChartSections.length)
		{
			chunkedNotesComplete = true;
			chunkedChartSections = null;
		}

		mergeNewUnspawnNotes(oldLength);
	}

	private function pendingChunkedNoteCount():Int
	{
		return ClientPrefs.data.fastNoteSpawning ? unspawnNotes.length - unspawnNoteIndex : unspawnNotes.length;
	}

	private function loadStreamNoteType(noteType:String):Void
	{
		if (noteType == null || noteType.length < 1 || streamLoadedNoteTypes.contains(noteType)) return;
		streamLoadedNoteTypes.push(noteType);
		#if LUA_ALLOWED
		startLuasNamed('custom_notetypes/' + noteType + '.lua');
		#end
		#if HSCRIPT_ALLOWED
		startHScriptsNamed('custom_notetypes/' + noteType + '.hx');
		#end
	}

	// called only once per different event (Used for precaching)
	function eventPushed(event:EventNote) {
		eventPushedUnique(event);
		if(eventsPushed.contains(event.event)) {
			return;
		}

		stagesFunc(function(stage:BaseStage) stage.eventPushed(event));
		eventsPushed.push(event.event);
	}

	// called by every event with the same name
	function eventPushedUnique(event:EventNote) {
		switch(event.event) {
			case "Change Character":
				var charType:Int = 0;
				switch(event.value1.toLowerCase()) {
					case 'gf' | 'girlfriend' | '1':
						charType = 2;
					case 'dad' | 'opponent' | '0':
						charType = 1;
					default:
						var val1:Int = Std.parseInt(event.value1);
						if(Math.isNaN(val1)) val1 = 0;
						charType = val1;
				}

				var newCharacter:String = event.value2;
				addCharacterToList(newCharacter, charType);

			case 'Play Sound':
				Paths.sound(event.value1); //Precache sound
		}
		stagesFunc(function(stage:BaseStage) stage.eventPushedUnique(event));
	}

	function eventEarlyTrigger(event:EventNote):Float {
		var returnedValue:Null<Float> = callOnScripts('eventEarlyTrigger', [event.event, event.value1, event.value2, event.strumTime], true, [], [0]);
		if(returnedValue != null && returnedValue != 0 && returnedValue != LuaUtils.Function_Continue) {
			return returnedValue;
		}

		switch(event.event) {
			case 'Kill Henchmen': //Better timing so that the kill sound matches the beat intended
				return 280; //Plays 280ms before the actual position
		}
		return 0;
	}

	public static function sortByTime(Obj1:Dynamic, Obj2:Dynamic):Int
		return FlxSort.byValues(FlxSort.ASCENDING, Obj1.strumTime, Obj2.strumTime);

	private inline function cacheOneStrumTransform(strum:StrumNote, index:Int):Void
	{
		if (strum == null) return;
		var radians:Float = strum.direction * 0.017453292519943295;
		cachedStrumX[index] = strum.x;
		cachedStrumY[index] = strum.y;
		cachedStrumAngle[index] = strum.angle;
		cachedStrumAlpha[index] = strum.alpha;
		cachedStrumDirection[index] = strum.direction;
		cachedStrumCos[index] = Math.cos(radians);
		cachedStrumSin[index] = Math.sin(radians);
		cachedStrumDownScroll[index] = strum.downScroll;
		cachedStrumRefs[index] = strum;
	}

	private inline function cacheNoteStrumTransforms():Void
	{
		for (lane in 0...4)
		{
			cacheOneStrumTransform(playerStrums.members[lane], lane);
			cacheOneStrumTransform(opponentStrums.members[lane], lane + 4);
		}
	}


	/** Mods may inspect Note.frames, width, animation or shader state from callbacks.
	 * Disable lazy graphics for those sessions to preserve their expected Note API. */
	public function hasNoteScriptsLoaded():Bool
	{
		if (hscriptArray != null && hscriptArray.length > 0) return true;
		#if LUA_ALLOWED
		if (luaArray != null && luaArray.length > 0) return true;
		#end
		return false;
	}

	/** The render group is capped (normally 512), so use the normal signal-aware API. */
	private inline function addRenderedBudgetNote(note:Note):Void
	{
		if (grpRenderedNotes != null) grpRenderedNotes.add(note);
	}

	/** Expand per-lane indexes lazily. CastNote stores lane 0..255 in the low byte. */
	private function ensureNoteLaneStorage(lane:Int):Bool
	{
		if (lane < 0 || lane > Note.CAST_LANE_MASK) return false;
		while (notesByLane.length <= lane) notesByLane.push([]);
		while (activeJudgementNotesByLane.length <= lane) activeJudgementNotesByLane.push([]);
		while (activeJudgementSustainsByLane.length <= lane) activeJudgementSustainsByLane.push([]);
		return true;
	}

	/** Register a spawned note in the fast input and logical-group indexes. */
	private function registerNoteIndexes(note:Note):Void
	{
		if (note == null) return;

		// Fast spawning appends to the logical group, so the index is known without a search.
		if (ClientPrefs.data.fastNoteSpawning && notes != null && notes.members.length > 0
			&& notes.members[notes.members.length - 1] == note)
			note.playStateGroupIndex = notes.members.length - 1;
		else
			note.playStateGroupIndex = -1;

		var lane:Int = note.noteData;
		if (ensureNoteLaneStorage(lane))
		{
			var laneNotes:Array<Note> = notesByLane[lane];
			note.inputLaneIndex = lane;
			note.inputLaneSlot = laneNotes.length;
			laneNotes.push(note);
		}
		if (fastNoteLogicActive) enqueuePendingJudgementNote(note);
	}

	/** Return the note's current logical-group index without an O(n) scan on the fast path. */
	private inline function getNoteGroupIndex(note:Note):Int
	{
		if (note == null || notes == null || notes.members == null) return -1;
		var index:Int = note.playStateGroupIndex;
		if (index >= 0 && index < notes.members.length && notes.members[index] == note)
			return index;
		return notes.members.indexOf(note);
	}

	/** Unlink lane and logical-group indexes. Fast removal swaps the final member into the gap. */
	private function unregisterNoteIndexes(note:Note):Void
	{
		if (note == null) return;
		unlinkPendingJudgementNote(note);
		unregisterActiveJudgementLane(note);

		var lane:Int = note.inputLaneIndex;
		var slot:Int = note.inputLaneSlot;
		if (lane >= 0 && lane < notesByLane.length)
		{
			var laneNotes:Array<Note> = notesByLane[lane];
			if (slot >= 0 && slot < laneNotes.length && laneNotes[slot] == note)
			{
				var lastLaneIndex:Int = laneNotes.length - 1;
				var movedLaneNote:Note = laneNotes[lastLaneIndex];
				laneNotes.pop();
				if (movedLaneNote != note)
				{
					laneNotes[slot] = movedLaneNote;
					movedLaneNote.inputLaneSlot = slot;
				}
			}
			else
			{
				// Defensive fallback for mods that have directly modified the lane list.
				var found:Int = laneNotes.indexOf(note);
				if (found >= 0) laneNotes.splice(found, 1);
			}
		}
		note.inputLaneIndex = -1;
		note.inputLaneSlot = -1;

		if (notes != null && notes.members != null)
		{
			var index:Int = getNoteGroupIndex(note);
			if (index >= 0)
			{
				var canSwapRemove:Bool = ClientPrefs.data.fastNoteGroupRemoval && ClientPrefs.data.fastNoteSpawning;
				if (canSwapRemove)
				{
					// This logical group is not rendered. Swap-pop the known index directly:
					// FlxTypedGroup.remove() would first search the entire members array.
					var lastIndex:Int = notes.members.length - 1;
					var movedNote:Note = notes.members[lastIndex];
					if (index != lastIndex)
					{
						notes.members[index] = movedNote;
						if (movedNote != null) movedNote.playStateGroupIndex = index;
					}
					notes.members.pop();
					// FlxTypedGroup keeps a separate length counter from members.length.
					@:privateAccess notes.length--;
				}
				else
				{
					notes.remove(note, true);
					// Ordered removal shifts every later index; invalidate cached indexes safely.
					for (member in notes.members)
						if (member != null) member.playStateGroupIndex = -1;
				}
			}
		}
		note.playStateGroupIndex = -1;
	}


	/** Index player notes that are currently inside the judgement window by lane. */
	private function registerActiveJudgementLane(note:Note):Void
	{
		if (note == null || !note.mustPress) return;
		var lane:Int = note.noteData;
		if (!ensureNoteLaneStorage(lane)) return;
		var laneNotes:Array<Note> = activeJudgementNotesByLane[lane];
		note.judgementLaneIndex = lane;
		note.judgementLaneSlot = laneNotes.length;
		laneNotes.push(note);
		if (note.isSustainNote)
		{
			var sustainNotes:Array<Note> = activeJudgementSustainsByLane[lane];
			note.sustainJudgementLaneIndex = lane;
			note.sustainJudgementLaneSlot = sustainNotes.length;
			sustainNotes.push(note);
		}
	}

	private function removeJudgementLaneEntry(note:Note, lane:Int, slot:Int, lanes:Array<Array<Note>>, sustainIndex:Bool):Void
	{
		if (lane < 0 || lane >= lanes.length) return;
		var laneNotes:Array<Note> = lanes[lane];
		var found:Int = slot;
		if (found < 0 || found >= laneNotes.length || laneNotes[found] != note) found = laneNotes.indexOf(note);
		if (found >= 0)
		{
			var lastSlot:Int = laneNotes.length - 1;
			var movedNote:Note = laneNotes[lastSlot];
			laneNotes.pop();
			if (found < laneNotes.length)
			{
				laneNotes[found] = movedNote;
				if (sustainIndex) movedNote.sustainJudgementLaneSlot = found;
				else movedNote.judgementLaneSlot = found;
			}
		}
	}

	/** Constant-time removal from active indexes and the ordered expiry/action queue. */
	private function unregisterActiveJudgementLane(note:Note):Void
	{
		if (note == null) return;
		if (note.isActiveJudgement)
		{
			var previous:Note = note.pendingJudgementPrev;
			var next:Note = note.pendingJudgementNext;
			if (activeJudgementActionHead == note) activeJudgementActionHead = next;
			if (previous != null) previous.pendingJudgementNext = next;
			else if (activeJudgementHead == note) activeJudgementHead = next;
			if (next != null) next.pendingJudgementPrev = previous;
			else if (activeJudgementTail == note) activeJudgementTail = previous;
			note.pendingJudgementPrev = null;
			note.pendingJudgementNext = null;
			note.isActiveJudgement = false;
			note.judgementActionProcessed = false;
		}

		var activeSlot:Int = note.activeJudgementArraySlot;
		if (activeSlot >= 0 && activeSlot < activeJudgementNotes.length && activeJudgementNotes[activeSlot] == note)
		{
			var lastSlot:Int = activeJudgementNotes.length - 1;
			var movedNote:Note = activeJudgementNotes[lastSlot];
			activeJudgementNotes.pop();
			if (activeSlot < activeJudgementNotes.length)
			{
				activeJudgementNotes[activeSlot] = movedNote;
				movedNote.activeJudgementArraySlot = activeSlot;
			}
		}
		else if (activeSlot >= 0)
		{
			var found:Int = activeJudgementNotes.indexOf(note);
			if (found >= 0)
			{
				var movedNote:Note = activeJudgementNotes[activeJudgementNotes.length - 1];
				activeJudgementNotes.pop();
				if (found < activeJudgementNotes.length)
				{
					activeJudgementNotes[found] = movedNote;
					movedNote.activeJudgementArraySlot = found;
				}
			}
		}
		note.activeJudgementArraySlot = -1;

		if (note.judgementLaneIndex >= 0)
			removeJudgementLaneEntry(note, note.judgementLaneIndex, note.judgementLaneSlot, activeJudgementNotesByLane, false);
		if (note.sustainJudgementLaneIndex >= 0)
			removeJudgementLaneEntry(note, note.sustainJudgementLaneIndex, note.sustainJudgementLaneSlot, activeJudgementSustainsByLane, true);
		note.judgementLaneIndex = note.judgementLaneSlot = -1;
		note.sustainJudgementLaneIndex = note.sustainJudgementLaneSlot = -1;
	}

	/** Move a note from the pending list into the active ordered queue. */
	private function linkActiveJudgementNote(note:Note):Void
	{
		if (note == null || note.isActiveJudgement) return;
		note.isActiveJudgement = true;
		note.judgementActionProcessed = false;
		note.pendingJudgementPrev = activeJudgementTail;
		note.pendingJudgementNext = null;
		if (activeJudgementTail == null) activeJudgementHead = note;
		else activeJudgementTail.pendingJudgementNext = note;
		activeJudgementTail = note;
		if (activeJudgementActionHead == null) activeJudgementActionHead = note;
		note.activeJudgementArraySlot = activeJudgementNotes.length;
		activeJudgementNotes.push(note);
		registerActiveJudgementLane(note);
	}

	/** Append notes in timestamp order. Normal chart spawning is already sorted (O(1));
	 * the backward insertion path handles an onSpawnNote script that retimes a note. */
	private function enqueuePendingJudgementNote(note:Note):Void
	{
		if (note == null || note.isPendingJudgement) return;
		note.isPendingJudgement = true;
		note.pendingJudgementPrev = null;
		note.pendingJudgementNext = null;

		var early:Float = note.earlyHitMult;
		if (!Math.isNaN(early) && early > maxJudgementEarlyHitMult)
			maxJudgementEarlyHitMult = early;

		if (pendingJudgementTail == null)
		{
			pendingJudgementHead = pendingJudgementTail = note;
			return;
		}
		if (pendingJudgementTail.strumTime <= note.strumTime)
		{
			note.pendingJudgementPrev = pendingJudgementTail;
			pendingJudgementTail.pendingJudgementNext = note;
			pendingJudgementTail = note;
			return;
		}

		var cursor:Note = pendingJudgementTail;
		while (cursor != null && cursor.strumTime > note.strumTime)
			cursor = cursor.pendingJudgementPrev;
		if (cursor == null)
		{
			note.pendingJudgementNext = pendingJudgementHead;
			pendingJudgementHead.pendingJudgementPrev = note;
			pendingJudgementHead = note;
		}
		else
		{
			note.pendingJudgementPrev = cursor;
			note.pendingJudgementNext = cursor.pendingJudgementNext;
			if (cursor.pendingJudgementNext != null)
				cursor.pendingJudgementNext.pendingJudgementPrev = note;
			else
				pendingJudgementTail = note;
			cursor.pendingJudgementNext = note;
		}
	}

	private function unlinkPendingJudgementNote(note:Note):Void
	{
		if (note == null || !note.isPendingJudgement) return;
		if (note.pendingJudgementPrev != null)
			note.pendingJudgementPrev.pendingJudgementNext = note.pendingJudgementNext;
		else if (pendingJudgementHead == note)
			pendingJudgementHead = note.pendingJudgementNext;
		if (note.pendingJudgementNext != null)
			note.pendingJudgementNext.pendingJudgementPrev = note.pendingJudgementPrev;
		else if (pendingJudgementTail == note)
			pendingJudgementTail = note.pendingJudgementPrev;
		note.pendingJudgementPrev = null;
		note.pendingJudgementNext = null;
		note.isPendingJudgement = false;
	}

	/** Rebuild once when the option is enabled mid-song; normal queue maintenance is incremental. */
	private function syncFastNoteLogicMode():Void
	{
		if (ClientPrefs.data.fastNoteLogicQueue && ClientPrefs.data.fastNoteSpawning)
		{
			if (fastNoteLogicActive) return;
			fastNoteLogicActive = true;
			pendingJudgementHead = pendingJudgementTail = null;
			activeJudgementHead = activeJudgementTail = activeJudgementActionHead = null;
			activeJudgementNotes = [];
			activeJudgementNotesByLane = [[], [], [], []];
			activeJudgementSustainsByLane = [[], [], [], []];
			maxJudgementEarlyHitMult = 1;

			// Existing logical members are already in chart-spawn order in the normal path.
			// enqueuePendingJudgementNote has an O(1) append fast path and handles rare retimed notes.
			if (notes != null && notes.members != null)
				for (note in notes.members)
					if (note != null && note.exists && note.alive) enqueuePendingJudgementNote(note);
		}
		else if (fastNoteLogicActive)
		{
			var pendingNote:Note = pendingJudgementHead;
			while (pendingNote != null)
			{
				var nextPending:Note = pendingNote.pendingJudgementNext;
				pendingNote.pendingJudgementPrev = null;
				pendingNote.pendingJudgementNext = null;
				pendingNote.isPendingJudgement = false;
				pendingNote = nextPending;
			}
			pendingJudgementHead = pendingJudgementTail = null;

			var activeNote:Note = activeJudgementHead;
			while (activeNote != null)
			{
				var nextActive:Note = activeNote.pendingJudgementNext;
				activeNote.pendingJudgementPrev = activeNote.pendingJudgementNext = null;
				activeNote.isActiveJudgement = false;
				activeNote.judgementActionProcessed = false;
				activeNote.activeJudgementArraySlot = -1;
				activeNote.judgementLaneIndex = activeNote.judgementLaneSlot = -1;
				activeNote.sustainJudgementLaneIndex = activeNote.sustainJudgementLaneSlot = -1;
				activeNote = nextActive;
			}
			activeJudgementHead = activeJudgementTail = activeJudgementActionHead = null;
			activeJudgementNotes = [];
			for (laneNotes in activeJudgementNotesByLane) laneNotes.resize(0);
			for (laneNotes in activeJudgementSustainsByLane) laneNotes.resize(0);
			maxJudgementEarlyHitMult = 1;
			fastNoteLogicActive = false;
		}
	}

	/**
	 * Event-driven judgement: activate only notes entering the hit window, process each
	 * opponent/BOTPLAY event once when its strum time is crossed, and expire notes from
	 * the ordered head. The old implementation scanned and compacted every active note
	 * every frame, which made work proportional to NPS * judgement-window duration * FPS.
	 */
	private function updateFastNoteJudgement(songPosition:Float):Void
	{
		var activationLead:Float = Conductor.safeZoneOffset * maxJudgementEarlyHitMult;
		while (pendingJudgementHead != null && pendingJudgementHead.strumTime - songPosition <= activationLead)
		{
			var note:Note = pendingJudgementHead;
			unlinkPendingJudgementNote(note);
			if (note.exists && note.alive) linkActiveJudgementNote(note);
		}
		if (pendingJudgementHead == null) maxJudgementEarlyHitMult = 1;

		// Process one-time timestamp events. Manual player taps are refreshed on key-down;
		// held sustains are refreshed only in their lane's sustain list.
		while (activeJudgementActionHead != null)
		{
			var note:Note = activeJudgementActionHead;
			var actionReady:Bool = note.mustPress && cpuControlled
				? note.strumTime < songPosition // earlyHitMult can be zero on sustain segments.
				: note.strumTime <= songPosition;
			if (!actionReady) break;
			activeJudgementActionHead = note.pendingJudgementNext;
			note.judgementActionProcessed = true;
			if (!note.exists || !note.alive) continue;

			note.updateGameplayState();
			if (note.mustPress)
			{
				if (cpuControlled && !note.blockHit && note.canBeHit && (note.isSustainNote || note.strumTime <= songPosition))
					goodNoteHit(note);
			}
			else if (note.wasGoodHit && !note.hitByOpponent && !note.ignoreNote)
				opponentNoteHit(note);
		}

		// Expiration is also ordered by strumTime, so only notes whose kill boundary has
		// actually passed are visited. Invalidation unlinks the note from every index in O(1).
		while (activeJudgementHead != null && songPosition - activeJudgementHead.strumTime > noteKillOffset)
		{
			var note:Note = activeJudgementHead;
			if (note.exists && note.alive)
			{
				note.updateGameplayState();
				if (note.mustPress && !cpuControlled && !note.ignoreNote && !endingSong && (note.tooLate || !note.wasGoodHit))
					noteMiss(note);
				if (note.exists && note.alive)
				{
					note.active = false;
					note.visible = false;
					invalidateNote(note);
				}
				else if (note.isActiveJudgement)
					invalidateNote(note);
			}
			else
				invalidateNote(note);
		}
	}

	/** Transform only the render-budget group (normally <=512 sprites), independently
	 * of the potentially enormous logical note collection. */
	private function updateRenderedNotePositions(songPosition:Float, noteSpeed:Float):Void
	{
		if (grpRenderedNotes == null || notes == null) return;
		if (ClientPrefs.data.fastNoteTransformCache) cacheNoteStrumTransforms();
		var useCache:Bool = ClientPrefs.data.fastNoteTransformCache;
		var useRenderProcessor:Bool = ClientPrefs.data.noteRenderProcessingEnabled;
		var members:Array<Note> = useRenderProcessor ? grpRenderedNotes.members : notes.members;
		var cullInterval:Int = ClientPrefs.data.noteCullingUpdateInterval;
		if (cullInterval < 1) cullInterval = 1;
		noteCullFrameCounter++;
		var updateCull:Bool = noteCullFrameCounter % cullInterval == 0;
		var i:Int = 0;
		while (i < members.length)
		{
			var note:Note = members[i];
			if (note != null && note.exists && note.alive)
			{
				// In processor mode, Note.update() skips the logical group, so judgement
				// flags are updated here. Legacy mode retains its original Note.update path.
				if (useRenderProcessor) note.updateGameplayState();
				var strumGroup:FlxTypedGroup<StrumNote> = note.mustPress ? playerStrums : opponentStrums;
				if (note.noteData < 0 || note.noteData >= strumGroup.members.length)
				{
					i++;
					continue;
				}
				var strum:StrumNote = strumGroup.members[note.noteData];
				if (strum == null)
				{
					i++;
					continue;
				}
				if (useCache)
				{
					var cacheIndex:Int = note.noteData + (note.mustPress ? 0 : 4);
					if (cacheIndex >= 0 && cacheIndex < 8 && cachedStrumRefs[cacheIndex] != null)
					{
						strum = cachedStrumRefs[cacheIndex];
						note.followStrumNoteWithCache(cachedStrumX[cacheIndex], cachedStrumY[cacheIndex],
							cachedStrumAngle[cacheIndex], cachedStrumAlpha[cacheIndex], cachedStrumDirection[cacheIndex],
							cachedStrumDownScroll[cacheIndex], cachedStrumCos[cacheIndex], cachedStrumSin[cacheIndex],
							songPosition, noteSpeed);
					}
					else note.followStrumNote(strum, 0, noteSpeed);
				}
				else note.followStrumNote(strum, 0, noteSpeed);

				var sideEnabled:Bool = note.mustPress ? ClientPrefs.data.renderPlayerNotes : ClientPrefs.data.renderOpponentNotes;
				if (!ClientPrefs.data.showNotes || !sideEnabled)
				{
					note.active = false;
					note.visible = false;
				}
				else if (ClientPrefs.data.noteViewportCulling && updateCull)
				{
					var margin:Float = ClientPrefs.data.noteViewportCullMargin;
					if (note.visible && ClientPrefs.data.noteCullingHysteresis) margin += Math.max(16, margin * 0.5);
					var insideViewport:Bool = note.x + note.width >= -margin
						&& note.x <= FlxG.width + margin
						&& note.y + note.height >= -margin
						&& note.y <= FlxG.height + margin;
					note.active = insideViewport;
					note.visible = insideViewport;
				}
				else if (!ClientPrefs.data.noteViewportCulling)
				{
					note.active = true;
					note.visible = true;
				}

				if (note.active && ClientPrefs.data.sustainNoteClipping && note.isSustainNote && strum.sustainReduce)
					note.clipToStrumNote(strum);
			}
			i++;
		}
	}


	function makeEvent(event:Array<Dynamic>, i:Int)
	{
		var subEvent:EventNote = {
			strumTime: event[0] + ClientPrefs.data.noteOffset,
			event: event[1][i][0],
			value1: event[1][i][1],
			value2: event[1][i][2]
		};
		eventNotes.push(subEvent);
		eventPushed(subEvent);
		callOnScripts('onEventPushed', [subEvent.event, subEvent.value1 != null ? subEvent.value1 : '', subEvent.value2 != null ? subEvent.value2 : '', subEvent.strumTime]);
	}

	public var skipArrowStartTween:Bool = false; //for lua
	private function generateStaticArrows(player:Int):Void
	{
		var strumLineX:Float = ClientPrefs.data.middleScroll ? STRUM_X_MIDDLESCROLL : STRUM_X;
		var strumLineY:Float = ClientPrefs.data.downScroll ? (FlxG.height - 150) : 50;
		for (i in 0...4)
		{
			// FlxG.log.add(i);
			var targetAlpha:Float = 1;
			if (player < 1)
			{
				if(!ClientPrefs.data.opponentStrums) targetAlpha = 0;
				else if(ClientPrefs.data.middleScroll) targetAlpha = 0.35;
			}

			var babyArrow:StrumNote = new StrumNote(strumLineX, strumLineY, i, player);
			babyArrow.downScroll = ClientPrefs.data.downScroll;
			if (!isStoryMode && !skipArrowStartTween)
			{
				//babyArrow.y -= 10;
				babyArrow.alpha = 0;
				FlxTween.tween(babyArrow, {/*y: babyArrow.y + 10,*/ alpha: targetAlpha}, 1, {ease: FlxEase.circOut, startDelay: 0.5 + (0.2 * i)});
			}
			else
				babyArrow.alpha = targetAlpha;

			if (player == 1)
				playerStrums.add(babyArrow);
			else
			{
				if(ClientPrefs.data.middleScroll)
				{
					babyArrow.x += 310;
					if(i > 1) { //Up and Right
						babyArrow.x += FlxG.width / 2 + 25;
					}
				}
				opponentStrums.add(babyArrow);
			}

			strumLineNotes.add(babyArrow);
			babyArrow.postAddedToGroup();
		}
	}

	override function openSubState(SubState:FlxSubState)
	{
		stagesFunc(function(stage:BaseStage) stage.openSubState(SubState));
		if (paused)
		{
			if (FlxG.sound.music != null)
			{
				FlxG.sound.music.pause();
				vocals.pause();
				opponentVocals.pause();
			}
			FlxTimer.globalManager.forEach(function(tmr:FlxTimer) if(!tmr.finished) tmr.active = false);
			FlxTween.globalManager.forEach(function(twn:FlxTween) if(!twn.finished) twn.active = false);
		}

		super.openSubState(SubState);
	}

	override function closeSubState()
	{
		super.closeSubState();
		
		stagesFunc(function(stage:BaseStage) stage.closeSubState());
		if (paused)
		{
			if (FlxG.sound.music != null && !startingSong)
			{
				resyncVocals();
			}
			FlxTimer.globalManager.forEach(function(tmr:FlxTimer) if(!tmr.finished) tmr.active = true);
			FlxTween.globalManager.forEach(function(twn:FlxTween) if(!twn.finished) twn.active = true);

			paused = false;
			callOnScripts('onResume');
			resetRPC(startTimer != null && startTimer.finished);
		}
	}

	override public function onFocus():Void
	{
		if (health > 0 && !paused) resetRPC(Conductor.songPosition > 0.0);
		super.onFocus();
	}

	override public function onFocusLost():Void
	{
		#if DISCORD_ALLOWED
		if (health > 0 && !paused && autoUpdateRPC) DiscordClient.changePresence(detailsPausedText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		#end

		super.onFocusLost();
	}

	// Updating Discord Rich Presence.
	public var autoUpdateRPC:Bool = true; //performance setting for custom RPC things
	function resetRPC(?showTime:Bool = false)
	{
		#if DISCORD_ALLOWED
		if(!autoUpdateRPC) return;

		if (showTime)
			DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter(), true, songLength - Conductor.songPosition - ClientPrefs.data.noteOffset);
		else
			DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		#end
	}

	function resyncVocals():Void
	{
		if(finishTimer != null) return;

		vocals.pause();
		opponentVocals.pause();

		FlxG.sound.music.play();
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		Conductor.songPosition = FlxG.sound.music.time;
		if (Conductor.songPosition <= vocals.length)
		{
			vocals.time = Conductor.songPosition;
			#if FLX_PITCH vocals.pitch = playbackRate; #end
		}

		if (Conductor.songPosition <= opponentVocals.length)
		{
			opponentVocals.time = Conductor.songPosition;
			#if FLX_PITCH opponentVocals.pitch = playbackRate; #end
		}
		vocals.play();
		opponentVocals.play();
	}

	public var paused:Bool = false;
	public var canReset:Bool = true;
	var startedCountdown:Bool = false;
	var canPause:Bool = true;
	var freezeCamera:Bool = false;
	var allowDebugKeys:Bool = true;

	override public function draw():Void
	{
		// Reset once per state draw. Note.draw() enforces the actual number of
		// budget-managed note sprites that reach Flixel's renderer this frame.
		renderedNoteDrawCount = 0;
		super.draw();
		#if desktop
		if (renderActive) captureRenderFrame();
		#end
	}

	/** Rebuild render membership only when a live rendering option changes. This makes
	 * the Options toggles take effect immediately without scanning all notes every frame. */
	private function syncNoteRenderOptionsIfChanged():Void
	{
		if (notes == null || grpRenderedNotes == null) return;
		var useProcessor:Bool = ClientPrefs.data.noteRenderProcessingEnabled;
		var showNotesNow:Bool = ClientPrefs.data.showNotes;
		var renderPlayerNow:Bool = ClientPrefs.data.renderPlayerNotes;
		var renderOpponentNow:Bool = ClientPrefs.data.renderOpponentNotes;
		var renderLimitNow:Int = ClientPrefs.data.renderedNotesLimit;
		var overlapNow:Float = ClientPrefs.data.overlapRemovalWindowMs;
		var poolRetentionNow:Bool = ClientPrefs.data.notePoolEnabled;
		var poolReuseNow:Bool = ClientPrefs.data.noteObjectPooling;
		var poolPerLaneNow:Int = ClientPrefs.data.maxPooledNotesPerLane;
		var poolTotalNow:Int = ClientPrefs.data.maxPooledNotesTotal;
		var renderSettingsChanged:Bool = lastNoteAnimationSetting != ClientPrefs.data.noteRenderingAnimations
			|| lastNoteRGBSetting != ClientPrefs.data.noteRenderingRGBShaders
			|| lastNoteAntialiasSetting != ClientPrefs.data.noteRenderingAntialiasing
			|| lastGlobalAntialiasSetting != ClientPrefs.data.antialiasing;
		if (renderSettingsChanged)
		{
			lastNoteAnimationSetting = ClientPrefs.data.noteRenderingAnimations;
			lastNoteRGBSetting = ClientPrefs.data.noteRenderingRGBShaders;
			lastNoteAntialiasSetting = ClientPrefs.data.noteRenderingAntialiasing;
		lastGlobalAntialiasSetting = ClientPrefs.data.antialiasing;
			Note.invalidateRenderSettings();
		}
		if (poolRetentionNow != lastNotePoolRetentionSetting || poolReuseNow != lastNoteObjectPoolingSetting
			|| poolPerLaneNow != lastNotePoolPerLaneLimit || poolTotalNow != lastNotePoolTotalLimit)
		{
			lastNotePoolRetentionSetting = poolRetentionNow;
			lastNoteObjectPoolingSetting = poolReuseNow;
			lastNotePoolPerLaneLimit = poolPerLaneNow;
			lastNotePoolTotalLimit = poolTotalNow;
			if (!poolRetentionNow || !poolReuseNow) notes.clearPools();
			else notes.trimPools();
		}
		if (useProcessor == lastRenderProcessorSetting && showNotesNow == lastShowNotesSetting
			&& renderPlayerNow == lastRenderPlayerSetting && renderOpponentNow == lastRenderOpponentSetting
			&& renderLimitNow == lastRenderedNoteLimit && overlapNow == lastOverlapWindowSetting) return;

		lastRenderProcessorSetting = useProcessor;
		lastShowNotesSetting = showNotesNow;
		lastRenderPlayerSetting = renderPlayerNow;
		lastRenderOpponentSetting = renderOpponentNow;
		lastRenderedNoteLimit = renderLimitNow;
		lastOverlapWindowSetting = overlapNow;

		var logicalNotes:Array<Note> = notes.members.copy();
		var oldRendered:Array<Note> = grpRenderedNotes.members.copy();
		for (oldNote in oldRendered)
			if (oldNote != null) grpRenderedNotes.remove(oldNote, true);
		resetRenderedNoteBudget();
		suspendRenderBudgetPromotion = true;
		notes.active = !useProcessor;
		notes.visible = !useProcessor;
		grpRenderedNotes.active = useProcessor;
		grpRenderedNotes.visible = useProcessor;

		for (note in logicalNotes)
		{
			if (note == null || !note.exists || !note.alive) continue;
			if (useProcessor)
				registerRenderedNote(note);
			else
			{
				note.renderBudgetManaged = false;
				note.renderBudgetVisible = false;
				note.renderBudgetPending = false;
				note.renderBudgetSuppressed = false;
				note.renderBudgetPrev = note.renderBudgetNext = null;
				var sideVisible:Bool = showNotesNow && (note.mustPress ? renderPlayerNow : renderOpponentNow);
				if (sideVisible) note.ensureVisuals();
				note.active = true; // Keep legacy Note.update() judgement active even when art is hidden.
				note.visible = sideVisible;
			}
		}
		suspendRenderBudgetPromotion = false;
	}

	override public function update(elapsed:Float)
	{
		syncNoteRenderOptionsIfChanged();
		if(!inCutscene && !paused && !freezeCamera) {
			FlxG.camera.followLerp = 2.4 * cameraSpeed * playbackRate;
			if(!startingSong && !endingSong && boyfriend.getAnimationName().startsWith('idle')) {
				boyfriendIdleTime += elapsed;
				if(boyfriendIdleTime >= 0.15) { // Kind of a mercy thing for making the achievement easier to get as it's apparently frustrating to some playerss
					boyfriendIdled = true;
				}
			} else {
				boyfriendIdleTime = 0;
			}
		}
		else FlxG.camera.followLerp = 0;
		callOnScripts('onUpdate', [elapsed]);

		super.update(elapsed);
		#if cpp
		if (ClientPrefs.data.disableGCLag)
		{
			gcTimer += elapsed;
			if (gcTimer >= 5)
			{
				cpp.vm.Gc.run(true);
				gcTimer = 0;
			}
		}
		#end

		if (!ClientPrefs.data.disableScriptVariableSync) {
			setOnScripts('curDecStep', curDecStep);
			setOnScripts('curDecBeat', curDecBeat);
			setOnScripts('cameraX', camFollow.x);
			setOnScripts('cameraY', camFollow.y);
			setOnScripts('botPlay', cpuControlled);
		}

		if(botplayTxt != null && botplayTxt.visible) {
			botplaySine += 180 * elapsed;
			botplayTxt.alpha = 1 - Math.sin((Math.PI * botplaySine) / 180);
		}

		if (controls.PAUSE && startedCountdown && canPause)
		{
			var ret:Dynamic = callOnScripts('onPause', null, true);
			if(ret != LuaUtils.Function_Stop) {
				openPauseMenu();
			}
		}

		if(!endingSong && !inCutscene && allowDebugKeys)
		{
			if (controls.justPressed('debug_1'))
				openChartEditor();
			else if (controls.justPressed('debug_2'))
				openCharacterEditor();
		}

		if (healthBar.bounds.max != null && health > healthBar.bounds.max)
			health = healthBar.bounds.max;

		updateIconsScale(elapsed);
		updateIconsPosition();

		if (startedCountdown && !paused)
			Conductor.songPosition += FlxG.elapsed * 1000 * playbackRate;

		if (startingSong)
		{
			if (startedCountdown && Conductor.songPosition >= 0)
				startSong();
			else if(!startedCountdown)
				Conductor.songPosition = -Conductor.crochet * 5;
		}
		else if (!paused && updateTime)
		{
			var curTime:Float = Math.max(0, Conductor.songPosition - ClientPrefs.data.noteOffset);
			songPercent = (curTime / songLength);

			var songCalc:Float = (songLength - curTime);
			if(ClientPrefs.data.timeBarType == 'Time Elapsed') songCalc = curTime;

			var secondsTotal:Int = Math.floor(songCalc / 1000);
			if(secondsTotal < 0) secondsTotal = 0;

			if(ClientPrefs.data.timeBarType != 'Song Name')
				timeTxt.text = FlxStringUtil.formatTime(secondsTotal, false);
		}

		if (camZooming)
		{
			FlxG.camera.zoom = FlxMath.lerp(defaultCamZoom, FlxG.camera.zoom, Math.exp(-elapsed * 3.125 * camZoomingDecay * playbackRate));
			camHUD.zoom = FlxMath.lerp(1, camHUD.zoom, Math.exp(-elapsed * 3.125 * camZoomingDecay * playbackRate));
		}

		#if debug
		FlxG.watch.addQuick("secShit", curSection);
		FlxG.watch.addQuick("beatShit", curBeat);
		FlxG.watch.addQuick("stepShit", curStep);
		#end

		// RESET = Quick Game Over Screen
		if (!ClientPrefs.data.noReset && controls.RESET && canReset && !inCutscene && startedCountdown && !endingSong)
		{
			health = 0;
			trace("RESET = True");
		}
		doDeathCheck();

		#if sys
		if (jsonStreamReader != null && !jsonStreamComplete
			&& pendingChunkedNoteCount() < ClientPrefs.data.noteGenerationQueueTarget)
			generateNextJsonNoteChunk(ClientPrefs.data.noteGenerationRowsPerFrame);
		#end
		if (ClientPrefs.data.chunkedNoteGeneration && !chunkedNotesComplete
			&& pendingChunkedNoteCount() < ClientPrefs.data.noteGenerationQueueTarget)
			generateNextChartNoteChunk(ClientPrefs.data.noteGenerationRowsPerFrame);

		var fastNoteSpawning:Bool = ClientPrefs.data.fastNoteSpawning;
		var spawnAhead:Float = Math.max(0, ClientPrefs.data.noteSpawnAheadMs) * playbackRate;
		if (songSpeed < 1)
		{
			spawnAhead /= songSpeed;
		}
		var budgetMode:String = ClientPrefs.data.noteSpawnBudgetMode;
		if (budgetMode != 'Count' && budgetMode != 'Time' && budgetMode != 'Hybrid') budgetMode = 'Hybrid';
		var useCountBudget:Bool = budgetMode == 'Count' || budgetMode == 'Hybrid';
		var useTimeBudget:Bool = budgetMode == 'Time' || budgetMode == 'Hybrid';
		var maxSpawnCount:Int = ClientPrefs.data.maxNoteSpawnsPerFrame;
		var maxSpawnMs:Float = ClientPrefs.data.maxNoteSpawnTimeMs;
		var maxActiveObjects:Int = ClientPrefs.data.maxActiveNoteObjects;
		var spawnStartedAt:Float = haxe.Timer.stamp();
		var spawnedThisFrame:Int = 0;
		var dispatchSpawnCallbacks:Bool = !ClientPrefs.data.disableNoteSpawnEvents && hasNoteScriptsLoaded();
		var unspawnedRoot:CastNote = null;
		var deferredTail:PendingSustainSpawn = pendingSustainSpawns.length > 0 ? pendingSustainSpawns[0] : null;

		while (true)
		{
			if (useCountBudget && maxSpawnCount > 0 && spawnedThisFrame >= maxSpawnCount) break;
			if (useTimeBudget && maxSpawnMs > 0 && (haxe.Timer.stamp() - spawnStartedAt) * 1000 >= maxSpawnMs) break;
			if (maxActiveObjects > 0 && notes != null && notes.length >= maxActiveObjects) break;

			if (fastNoteSpawning)
				unspawnedRoot = unspawnNoteIndex < unspawnNotes.length ? unspawnNotes[unspawnNoteIndex] : null;
			else
				unspawnedRoot = unspawnNotes.length > 0 ? unspawnNotes[0] : null;
			deferredTail = pendingSustainSpawns.length > 0 ? pendingSustainSpawns[0] : null;
			if (unspawnedRoot == null && deferredTail == null) break;

			// Merge both streams by strum time. A single lead window preserves chronological
			// spawn order for judgement and NPS queues while still keeping tails deferred.
			var spawnTail:Bool = deferredTail != null && (unspawnedRoot == null
				|| deferredTail.nextTime < unspawnedRoot.strumTime
				|| (deferredTail.nextTime == unspawnedRoot.strumTime && deferredTail.nextSortOrder < unspawnedRoot.sortOrder));
			var nextTime:Float = spawnTail ? deferredTail.nextTime : unspawnedRoot.strumTime;
			if (nextTime - Conductor.songPosition >= spawnAhead) break;

			var castNote:CastNote;
			if (spawnTail)
			{
				var state:PendingSustainSpawn = popPendingSustain();
				// The scratch CastNote is consumed immediately by spawnCastNote; it is never queued.
				castNote = makeDeferredSustainCastNote(state);
				if (state.remaining > 0) pushPendingSustain(state);
			}
			else
			{
				castNote = unspawnedRoot;
				if (fastNoteSpawning)
				{
					unspawnNotes[unspawnNoteIndex] = null;
					unspawnNoteIndex++;
				}
				else unspawnNotes.splice(0, 1);
			}

			var dunceNote:Note = notes.spawnCastNote(castNote, !fastNoteSpawning);
			dunceNote.spawned = true;
			dunceNote.visible = castNote.skipOnSpawn == true ? false : ClientPrefs.data.showNotes;
			if (spawnTail == false && castNote.tailCount != null && castNote.tailCount > 0)
				addDeferredSustainChain(castNote);

			if (castNote.skipOnSpawn != true)
			{
				if (dispatchSpawnCallbacks)
				{
					var noteIndex:Int = fastNoteSpawning ? notes.members.length - 1 : getNoteGroupIndex(dunceNote);
					callOnLuas('onSpawnNote', [noteIndex, dunceNote.noteData, dunceNote.noteType, dunceNote.isSustainNote, dunceNote.strumTime]);
					callOnHScript('onSpawnNote', [dunceNote]);
				}
				registerNpsNote(dunceNote);
				registerNoteIndexes(dunceNote);
				registerRenderedNote(dunceNote);
			}
			spawnedThisFrame++;
		}


		if (startedCountdown && !startingSong)
			updateNpsStats(Conductor.songPosition);
		refreshGameplayInfo();

		// Synchronize the optional scheduler after this frame's note spawns.
		syncFastNoteLogicMode();

		if (generatedMusic)
		{
			var frameSongPosition:Float = Conductor.songPosition;
			if (startedCountdown && fastNoteLogicActive && !inCutscene)
				updateFastNoteJudgement(frameSongPosition);

			if(!inCutscene)
			{
				if(!cpuControlled)
					keysCheck();
				else
					playerDance();

				if(notes.length > 0)
				{
					if(startedCountdown)
					{
						var frameNoteSpeed:Float = songSpeed / playbackRate;
						if (fastNoteLogicActive)
						{
							updateRenderedNotePositions(frameSongPosition, frameNoteSpeed);
						}
						else
						{
						var useTransformCache:Bool = ClientPrefs.data.fastNoteTransformCache;
						if (useTransformCache) cacheNoteStrumTransforms();
						var logicalNoteIndex:Int = notes.members.length - 1;
						while (logicalNoteIndex >= 0 && logicalNoteIndex < notes.members.length)
						{
							var daNote:Note = notes.members[logicalNoteIndex];
						if (daNote == null || !daNote.exists || !daNote.alive)
						{
							logicalNoteIndex--;
							continue;
						}

						// Notes outside the render group still need their timing flags. Viewport-culled
						// notes are inactive too, so this path keeps their judgement state current.
						if (daNote.renderBudgetManaged && !daNote.active) daNote.updateGameplayState();
						var strumGroup:FlxTypedGroup<StrumNote> = daNote.mustPress ? playerStrums : opponentStrums;
						var strum:StrumNote = strumGroup.members[daNote.noteData];

						if (daNote.renderBudgetVisible && ClientPrefs.data.showNotes)
						{
							if (useTransformCache)
							{
								var cacheIndex:Int = daNote.noteData + (daNote.mustPress ? 0 : 4);
								if (cacheIndex >= 0 && cacheIndex < 8 && cachedStrumRefs[cacheIndex] != null)
								{
									strum = cachedStrumRefs[cacheIndex];
									daNote.followStrumNoteWithCache(cachedStrumX[cacheIndex], cachedStrumY[cacheIndex],
										cachedStrumAngle[cacheIndex], cachedStrumAlpha[cacheIndex], cachedStrumDirection[cacheIndex],
										cachedStrumDownScroll[cacheIndex], cachedStrumCos[cacheIndex], cachedStrumSin[cacheIndex],
										frameSongPosition, frameNoteSpeed);
								}
								else daNote.followStrumNote(strum, 0, frameNoteSpeed);
							}
							else daNote.followStrumNote(strum, 0, frameNoteSpeed);

							if (ClientPrefs.data.noteViewportCulling)
							{
								var margin:Float = ClientPrefs.data.noteViewportCullMargin;
								var insideViewport:Bool = daNote.x + daNote.width >= -margin
									&& daNote.x <= FlxG.width + margin
									&& daNote.y + daNote.height >= -margin
									&& daNote.y <= FlxG.height + margin;
								daNote.active = insideViewport;
								daNote.visible = insideViewport;
							}
							else
							{
								daNote.active = true;
								daNote.visible = true;
							}
						}
						else
						{
							daNote.active = false;
							daNote.visible = false;
						}

						if (daNote.mustPress)
						{
							if (cpuControlled && !daNote.blockHit && daNote.canBeHit && (daNote.isSustainNote || daNote.strumTime <= frameSongPosition))
								goodNoteHit(daNote);
						}
						else if (daNote.wasGoodHit && !daNote.hitByOpponent && !daNote.ignoreNote)
							opponentNoteHit(daNote);

						if (daNote.renderBudgetVisible && daNote.active && ClientPrefs.data.showNotes
							&& ClientPrefs.data.sustainNoteClipping && daNote.isSustainNote && strum.sustainReduce)
							daNote.clipToStrumNote(strum);

						if (frameSongPosition - daNote.strumTime > noteKillOffset)
						{
							if (daNote.mustPress && !cpuControlled && !daNote.ignoreNote && !endingSong && (daNote.tooLate || !daNote.wasGoodHit))
								noteMiss(daNote);
							daNote.active = daNote.visible = false;
							invalidateNote(daNote);
						}

						// Reverse traversal has already processed the final member before swap-pop.
						logicalNoteIndex--;
					}

						}
					}
					else
					{
						notes.forEachAlive(function(daNote:Note)
						{
							daNote.canBeHit = false;
							daNote.wasGoodHit = false;
						});
					}
				}
			}
			checkEventNote();
		}

		#if debug
		if(!endingSong && !startingSong) {
			if (FlxG.keys.justPressed.ONE) {
				KillNotes();
				FlxG.sound.music.onComplete();
			}
			if(FlxG.keys.justPressed.TWO) { //Go 10 seconds into the future :O
				setSongTime(Conductor.songPosition + 10000);
				clearNotesBefore(Conductor.songPosition);
			}
		}
		#end

		callOnScripts('onUpdatePost', [elapsed]);
	}

	// Health icon updaters
	public dynamic function updateIconsScale(elapsed:Float)
	{
		var mult:Float = FlxMath.lerp(1, iconP1.scale.x, Math.exp(-elapsed * 9 * playbackRate));
		iconP1.scale.set(mult, mult);
		iconP1.updateHitbox();

		var mult:Float = FlxMath.lerp(1, iconP2.scale.x, Math.exp(-elapsed * 9 * playbackRate));
		iconP2.scale.set(mult, mult);
		iconP2.updateHitbox();
	}

	public dynamic function updateIconsPosition()
	{
		var iconOffset:Int = 26;
		iconP1.x = healthBar.barCenter + (150 * iconP1.scale.x - 150) / 2 - iconOffset;
		iconP2.x = healthBar.barCenter - (150 * iconP2.scale.x) / 2 - iconOffset * 2;
	}

	var iconsAnimations:Bool = true;
	function set_health(value:Float):Float // You can alter how icon animations work here
	{
		if(!iconsAnimations || healthBar == null || !healthBar.enabled || healthBar.valueFunction == null)
		{
			health = value;
			return health;
		}

		// update health bar
		health = value;
		var newPercent:Null<Float> = FlxMath.remapToRange(FlxMath.bound(healthBar.valueFunction(), healthBar.bounds.min, healthBar.bounds.max), healthBar.bounds.min, healthBar.bounds.max, 0, 100);
		healthBar.percent = (newPercent != null ? newPercent : 0);

		iconP1.animation.curAnim.curFrame = (healthBar.percent < 20) ? 1 : 0; //If health is under 20%, change player icon to frame 1 (losing icon), otherwise, frame 0 (normal)
		iconP2.animation.curAnim.curFrame = (healthBar.percent > 80) ? 1 : 0; //If health is over 80%, change opponent icon to frame 1 (losing icon), otherwise, frame 0 (normal)
		return health;
	}

	function openPauseMenu()
	{
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		persistentDraw = true;
		paused = true;

		if(FlxG.sound.music != null) {
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}
		if(!cpuControlled)
		{
			for (note in playerStrums)
				if(note.animation.curAnim != null && note.animation.curAnim.name != 'static')
				{
					note.playAnim('static');
					note.resetAnim = 0;
				}
		}
		openSubState(new PauseSubState());

		#if DISCORD_ALLOWED
		if(autoUpdateRPC) DiscordClient.changePresence(detailsPausedText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		#end
	}

	function openChartEditor()
	{
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		paused = true;
		if(FlxG.sound.music != null)
			FlxG.sound.music.stop();
		chartingMode = true;

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Chart Editor", null, null, true);
		DiscordClient.resetClientID();
		#end

		MusicBeatState.switchState(new ChartingState());
	}

	function openCharacterEditor()
	{
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		paused = true;
		if(FlxG.sound.music != null)
			FlxG.sound.music.stop();
		#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end
		MusicBeatState.switchState(new CharacterEditorState(SONG.player2));
	}

	public var isDead:Bool = false; //Don't mess with this on Lua!!!
	function doDeathCheck(?skipHealthCheck:Bool = false) {
		if (((skipHealthCheck && instakillOnMiss) || health <= 0) && !practiceMode && !isDead)
		{
			var ret:Dynamic = callOnScripts('onGameOver', null, true);
			if(ret != LuaUtils.Function_Stop) {
				FlxG.animationTimeScale = 1;
				boyfriend.stunned = true;
				deathCounter++;

				paused = true;

				vocals.stop();
				opponentVocals.stop();
				FlxG.sound.music.stop();

				persistentUpdate = false;
				persistentDraw = false;
				FlxTimer.globalManager.clear();
				FlxTween.globalManager.clear();
				#if LUA_ALLOWED
				modchartTimers.clear();
				modchartTweens.clear();
				#end

				openSubState(new GameOverSubstate());

				// MusicBeatState.switchState(new GameOverState(boyfriend.getScreenPosition().x, boyfriend.getScreenPosition().y));

				#if DISCORD_ALLOWED
				// Game Over doesn't get his its variable because it's only used here
				if(autoUpdateRPC) DiscordClient.changePresence("Game Over - " + detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
				#end
				isDead = true;
				return true;
			}
		}
		return false;
	}

	public function checkEventNote() {
		while(eventNotes.length > 0) {
			var leStrumTime:Float = eventNotes[0].strumTime;
			if(Conductor.songPosition < leStrumTime) {
				return;
			}

			var value1:String = '';
			if(eventNotes[0].value1 != null)
				value1 = eventNotes[0].value1;

			var value2:String = '';
			if(eventNotes[0].value2 != null)
				value2 = eventNotes[0].value2;

			triggerEvent(eventNotes[0].event, value1, value2, leStrumTime);
			eventNotes.shift();
		}
	}

	public function triggerEvent(eventName:String, value1:String, value2:String, strumTime:Float) {
		var flValue1:Null<Float> = Std.parseFloat(value1);
		var flValue2:Null<Float> = Std.parseFloat(value2);
		if(Math.isNaN(flValue1)) flValue1 = null;
		if(Math.isNaN(flValue2)) flValue2 = null;

		switch(eventName) {
			case 'Hey!':
				var value:Int = 2;
				switch(value1.toLowerCase().trim()) {
					case 'bf' | 'boyfriend' | '0':
						value = 0;
					case 'gf' | 'girlfriend' | '1':
						value = 1;
				}

				if(flValue2 == null || flValue2 <= 0) flValue2 = 0.6;

				if(value != 0) {
					if(dad.curCharacter.startsWith('gf')) { //Tutorial GF is actually Dad! The GF is an imposter!! ding ding ding ding ding ding ding, dindinding, end my suffering
						dad.playAnim('cheer', true);
						dad.specialAnim = true;
						dad.heyTimer = flValue2;
					} else if (gf != null) {
						gf.playAnim('cheer', true);
						gf.specialAnim = true;
						gf.heyTimer = flValue2;
					}
				}
				if(value != 1) {
					boyfriend.playAnim('hey', true);
					boyfriend.specialAnim = true;
					boyfriend.heyTimer = flValue2;
				}

			case 'Set GF Speed':
				if(flValue1 == null || flValue1 < 1) flValue1 = 1;
				gfSpeed = Math.round(flValue1);

			case 'Add Camera Zoom':
				if(ClientPrefs.data.camZooms && FlxG.camera.zoom < 1.35) {
					if(flValue1 == null) flValue1 = 0.015;
					if(flValue2 == null) flValue2 = 0.03;

					FlxG.camera.zoom += flValue1;
					camHUD.zoom += flValue2;
				}

			case 'Play Animation':
				//trace('Anim to play: ' + value1);
				var char:Character = dad;
				switch(value2.toLowerCase().trim()) {
					case 'bf' | 'boyfriend':
						char = boyfriend;
					case 'gf' | 'girlfriend':
						char = gf;
					default:
						if(flValue2 == null) flValue2 = 0;
						switch(Math.round(flValue2)) {
							case 1: char = boyfriend;
							case 2: char = gf;
						}
				}

				if (char != null)
				{
					char.playAnim(value1, true);
					char.specialAnim = true;
				}

			case 'Camera Follow Pos':
				if(camFollow != null)
				{
					isCameraOnForcedPos = false;
					if(flValue1 != null || flValue2 != null)
					{
						isCameraOnForcedPos = true;
						if(flValue1 == null) flValue1 = 0;
						if(flValue2 == null) flValue2 = 0;
						camFollow.x = flValue1;
						camFollow.y = flValue2;
					}
				}

			case 'Alt Idle Animation':
				var char:Character = dad;
				switch(value1.toLowerCase().trim()) {
					case 'gf' | 'girlfriend':
						char = gf;
					case 'boyfriend' | 'bf':
						char = boyfriend;
					default:
						var val:Int = Std.parseInt(value1);
						if(Math.isNaN(val)) val = 0;

						switch(val) {
							case 1: char = boyfriend;
							case 2: char = gf;
						}
				}

				if (char != null)
				{
					char.idleSuffix = value2;
					char.recalculateDanceIdle();
				}

			case 'Screen Shake':
				var valuesArray:Array<String> = [value1, value2];
				var targetsArray:Array<FlxCamera> = [camGame, camHUD];
				for (i in 0...targetsArray.length) {
					var split:Array<String> = valuesArray[i].split(',');
					var duration:Float = 0;
					var intensity:Float = 0;
					if(split[0] != null) duration = Std.parseFloat(split[0].trim());
					if(split[1] != null) intensity = Std.parseFloat(split[1].trim());
					if(Math.isNaN(duration)) duration = 0;
					if(Math.isNaN(intensity)) intensity = 0;

					if(duration > 0 && intensity != 0) {
						targetsArray[i].shake(intensity, duration);
					}
				}


			case 'Change Character':
				var charType:Int = 0;
				switch(value1.toLowerCase().trim()) {
					case 'gf' | 'girlfriend':
						charType = 2;
					case 'dad' | 'opponent':
						charType = 1;
					default:
						charType = Std.parseInt(value1);
						if(Math.isNaN(charType)) charType = 0;
				}

				switch(charType) {
					case 0:
						if(boyfriend.curCharacter != value2) {
							if(!boyfriendMap.exists(value2)) {
								addCharacterToList(value2, charType);
							}

							var lastAlpha:Float = boyfriend.alpha;
							boyfriend.alpha = 0.00001;
							boyfriend = boyfriendMap.get(value2);
							boyfriend.alpha = lastAlpha;
							iconP1.changeIcon(boyfriend.healthIcon);
						}
						setOnScripts('boyfriendName', boyfriend.curCharacter);

					case 1:
						if(dad.curCharacter != value2) {
							if(!dadMap.exists(value2)) {
								addCharacterToList(value2, charType);
							}

							var wasGf:Bool = dad.curCharacter.startsWith('gf-') || dad.curCharacter == 'gf';
							var lastAlpha:Float = dad.alpha;
							dad.alpha = 0.00001;
							dad = dadMap.get(value2);
							if(!dad.curCharacter.startsWith('gf-') && dad.curCharacter != 'gf') {
								if(wasGf && gf != null) {
									gf.visible = true;
								}
							} else if(gf != null) {
								gf.visible = false;
							}
							dad.alpha = lastAlpha;
							iconP2.changeIcon(dad.healthIcon);
						}
						setOnScripts('dadName', dad.curCharacter);

					case 2:
						if(gf != null)
						{
							if(gf.curCharacter != value2)
							{
								if(!gfMap.exists(value2)) {
									addCharacterToList(value2, charType);
								}

								var lastAlpha:Float = gf.alpha;
								gf.alpha = 0.00001;
								gf = gfMap.get(value2);
								gf.alpha = lastAlpha;
							}
							setOnScripts('gfName', gf.curCharacter);
						}
				}
				reloadHealthBarColors();

			case 'Change Scroll Speed':
				if (songSpeedType != "constant")
				{
					if(flValue1 == null) flValue1 = 1;
					if(flValue2 == null) flValue2 = 0;

					var newValue:Float = Song.clampScrollSpeed(SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed') * flValue1);
					if(flValue2 <= 0)
						songSpeed = newValue;
					else
						songSpeedTween = FlxTween.tween(this, {songSpeed: newValue}, flValue2 / playbackRate, {ease: FlxEase.linear, onComplete:
							function (twn:FlxTween)
							{
								songSpeedTween = null;
							}
						});
				}

			case 'Set Property':
				try
				{
					var split:Array<String> = value1.split('.');
					if(split.length > 1) {
						LuaUtils.setVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1], value2);
					} else {
						LuaUtils.setVarInArray(this, value1, value2);
					}
				}
				catch(e:Dynamic)
				{
					var len:Int = e.message.indexOf('\n') + 1;
					if(len <= 0) len = e.message.length;
					#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
					addTextToDebug('ERROR ("Set Property" Event) - ' + e.message.substr(0, len), FlxColor.RED);
					#else
					FlxG.log.warn('ERROR ("Set Property" Event) - ' + e.message.substr(0, len));
					#end
				}

			case 'Play Sound':
				if(flValue2 == null) flValue2 = 1;
				FlxG.sound.play(Paths.sound(value1), flValue2);
		}

		stagesFunc(function(stage:BaseStage) stage.eventCalled(eventName, value1, value2, flValue1, flValue2, strumTime));
		callOnScripts('onEvent', [eventName, value1, value2, strumTime]);
	}

	function moveCameraSection(?sec:Null<Int>):Void {
		if(sec == null) sec = curSection;
		if(sec < 0) sec = 0;

		if(SONG.notes[sec] == null) return;

		if (gf != null && SONG.notes[sec].gfSection)
		{
			camFollow.setPosition(gf.getMidpoint().x, gf.getMidpoint().y);
			camFollow.x += gf.cameraPosition[0] + girlfriendCameraOffset[0];
			camFollow.y += gf.cameraPosition[1] + girlfriendCameraOffset[1];
			tweenCamIn();
			callOnScripts('onMoveCamera', ['gf']);
			return;
		}

		var isDad:Bool = (SONG.notes[sec].mustHitSection != true);
		moveCamera(isDad);
		callOnScripts('onMoveCamera', [isDad ? 'dad' : 'boyfriend']);
	}

	var cameraTwn:FlxTween;
	public function moveCamera(isDad:Bool)
	{
		if(isDad)
		{
			camFollow.setPosition(dad.getMidpoint().x + 150, dad.getMidpoint().y - 100);
			camFollow.x += dad.cameraPosition[0] + opponentCameraOffset[0];
			camFollow.y += dad.cameraPosition[1] + opponentCameraOffset[1];
			tweenCamIn();
		}
		else
		{
			camFollow.setPosition(boyfriend.getMidpoint().x - 100, boyfriend.getMidpoint().y - 100);
			camFollow.x -= boyfriend.cameraPosition[0] - boyfriendCameraOffset[0];
			camFollow.y += boyfriend.cameraPosition[1] + boyfriendCameraOffset[1];

			if (songName == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1)
			{
				cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
					function (twn:FlxTween)
					{
						cameraTwn = null;
					}
				});
			}
		}
	}

	public function tweenCamIn() {
		if (songName == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1.3) {
			cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1.3}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
				function (twn:FlxTween) {
					cameraTwn = null;
				}
			});
		}
	}

	public function finishSong(?ignoreNoteOffset:Bool = false):Void
	{
		updateTime = false;
		FlxG.sound.music.volume = 0;

		vocals.volume = 0;
		vocals.pause();
		opponentVocals.volume = 0;
		opponentVocals.pause();

		if(ClientPrefs.data.noteOffset <= 0 || ignoreNoteOffset) {
			endCallback();
		} else {
			finishTimer = new FlxTimer().start(ClientPrefs.data.noteOffset / 1000, function(tmr:FlxTimer) {
				endCallback();
			});
		}
	}


	public var transitioning = false;
	public function endSong()
	{
		//Should kill you if you tried to cheat
		if(!startingSong) {
			notes.forEach(function(daNote:Note) {
				if(daNote.strumTime < songLength - Conductor.safeZoneOffset) {
					health -= 0.05 * healthLoss;
				}
			});
			var unspawnIndex:Int = ClientPrefs.data.fastNoteSpawning ? unspawnNoteIndex : 0;
			while (unspawnIndex < unspawnNotes.length) {
				var daNote:CastNote = unspawnNotes[unspawnIndex];
				if(daNote != null && daNote.strumTime < songLength - Conductor.safeZoneOffset) {
					health -= 0.05 * healthLoss;
				}
				unspawnIndex++;
			}

			if(doDeathCheck()) {
				return false;
			}
		}

		timeBar.visible = false;
		timeTxt.visible = false;
		canPause = false;
		endingSong = true;
		#if desktop
		stopGameRenderer();
		#end
		camZooming = false;
		inCutscene = false;
		updateTime = false;

		deathCounter = 0;
		seenCutscene = false;

		#if ACHIEVEMENTS_ALLOWED
		var weekNoMiss:String = WeekData.getWeekFileName() + '_nomiss';
		checkForAchievement([weekNoMiss, 'ur_bad', 'ur_good', 'hype', 'two_keys', 'toastie', 'debugger']);
		#end

		var ret:Dynamic = callOnScripts('onEndSong', null, true);
		if(ret != LuaUtils.Function_Stop && !transitioning)
		{
			#if !switch
			var percent:Float = ratingPercent;
			if(Math.isNaN(percent)) percent = 0;
			Highscore.saveScore(SONG.song, songScore, storyDifficulty, percent);
			#end
			playbackRate = 1;

			if (chartingMode)
			{
				openChartEditor();
				return false;
			}

			if (isStoryMode)
			{
				campaignScore += songScore;
				campaignMisses += songMisses;

				storyPlaylist.remove(storyPlaylist[0]);

				if (storyPlaylist.length <= 0)
				{
					Mods.loadTopMod();
					FlxG.sound.playMusic(Paths.music('freakyMenu'));
					#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end

					MusicBeatState.switchState(new StoryMenuState());

					// if ()
					if(!ClientPrefs.getGameplaySetting('practice') && !ClientPrefs.getGameplaySetting('botplay')) {
						StoryMenuState.weekCompleted.set(WeekData.weeksList[storyWeek], true);
						Highscore.saveWeekScore(WeekData.getWeekFileName(), campaignScore, storyDifficulty);

						FlxG.save.data.weekCompleted = StoryMenuState.weekCompleted;
						FlxG.save.flush();
					}
					changedDifficulty = false;
				}
				else
				{
					var difficulty:String = Difficulty.getFilePath();

					trace('LOADING NEXT SONG');
					trace(Paths.formatToSongPath(PlayState.storyPlaylist[0]) + difficulty);

					FlxTransitionableState.skipNextTransIn = true;
					FlxTransitionableState.skipNextTransOut = true;
					prevCamFollow = camFollow;

					PlayState.SONG = Song.loadFromJson(PlayState.storyPlaylist[0] + difficulty, PlayState.storyPlaylist[0], ClientPrefs.data.jsonStreamingEnabled);
					FlxG.sound.music.stop();

					LoadingState.loadAndSwitchState(new PlayState());
				}
			}
			else
			{
				trace('WENT BACK TO FREEPLAY??');
				Mods.loadTopMod();
				#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end

				MusicBeatState.switchState(new FreeplayState());
				FlxG.sound.playMusic(Paths.music('freakyMenu'));
				changedDifficulty = false;
			}
			transitioning = true;
		}
		return true;
	}

	public function KillNotes() {
		suspendRenderBudgetPromotion = true;
		while(notes.length > 0) {
			var daNote:Note = notes.members[0];
			daNote.active = false;
			daNote.visible = false;
			invalidateNote(daNote);
		}
		unspawnNotes = [];
		unspawnNoteIndex = 0;
		pendingSustainSpawns = [];
		if (notes != null) notes.resetCastChains();
		for (laneNotes in notesByLane) laneNotes.resize(0);
		for (laneNotes in activeJudgementNotesByLane) laneNotes.resize(0);
		for (laneNotes in activeJudgementSustainsByLane) laneNotes.resize(0);
		pendingJudgementHead = pendingJudgementTail = null;
		activeJudgementHead = activeJudgementTail = activeJudgementActionHead = null;
		activeJudgementNotes = [];
		maxJudgementEarlyHitMult = 1;
		eventNotes = [];
		suspendRenderBudgetPromotion = false;
		resetRenderedNoteBudget();
		resetNpsTracking();
	}

	public var totalPlayed:Int = 0;
	public var totalNotesHit:Float = 0.0;

	public var showCombo:Bool = ClientPrefs.data.showComboPopup;
	public var showComboNum:Bool = ClientPrefs.data.showNumPopup;
	public var showRating:Bool = ClientPrefs.data.showRatingPopup;

	// Stores Ratings and Combo Sprites in a group
	public var comboGroup:FlxSpriteGroup;
	// Stores HUD Objects in a Group
	public var uiGroup:FlxSpriteGroup;
	// Stores Note Objects in a Group
	public var noteGroup:FlxTypedGroup<FlxBasic>;

	private function cachePopUpScore()
	{
		var uiPrefix:String = '';
		var uiSuffix:String = '';
		if (stageUI != "normal")
		{
			uiPrefix = '${stageUI}UI/';
			if (PlayState.isPixelStage) uiSuffix = '-pixel';
		}

		if (showRating)
			for (rating in ratingsData)
				Paths.image(uiPrefix + rating.image + uiSuffix);
		if (showCombo)
			Paths.image(uiPrefix + 'combo' + uiSuffix);
		if (showComboNum)
			for (i in 0...10)
				Paths.image(uiPrefix + 'num' + i + uiSuffix);
	}

	private function popUpScore(note:Note = null):Void
	{
		showCombo = ClientPrefs.data.showComboPopup;
		showComboNum = ClientPrefs.data.showNumPopup;
		showRating = ClientPrefs.data.showRatingPopup;
		var noteDiff:Float = Math.abs(note.strumTime - Conductor.songPosition + ClientPrefs.data.ratingOffset);
		vocals.volume = 1;

		// Judgement, score, accuracy, and rating state are always calculated.
		var daRating:Rating = Conductor.judgeNote(ratingsData, noteDiff / playbackRate);
		totalNotesHit += daRating.ratingMod;
		note.ratingMod = daRating.ratingMod;
		if(!note.ratingDisabled) daRating.hits++;
		note.rating = daRating.name;

		if(daRating.noteSplash && !note.noteSplashData.disabled)
			spawnNoteSplashOnNote(note);

		if(!practiceMode && !cpuControlled) {
			songScore += daRating.score;
			if(!note.ratingDisabled)
			{
				songHits++;
				totalPlayed++;
				RecalculateRating(false);
			}
		}

		// Do not allocate sprites, load popup graphics, or create tweens when all are hidden.
		if (ClientPrefs.data.disablePopUpScore || (!showRating && !showCombo && !showComboNum)) return;

		if (!ClientPrefs.data.comboStacking && comboGroup.members.length > 0) {
			for (spr in comboGroup) {
				spr.destroy();
				comboGroup.remove(spr);
			}
		}

		var placement:Float = FlxG.width * 0.35;
		var uiPrefix:String = '';
		var uiSuffix:String = '';
		var antialias:Bool = ClientPrefs.data.antialiasing;
		if (stageUI != 'normal')
		{
			uiPrefix = '${stageUI}UI/';
			if (PlayState.isPixelStage) uiSuffix = '-pixel';
			antialias = !isPixelStage;
		}

		var rating:FlxSprite = null;
		if (showRating)
		{
			rating = new FlxSprite().loadGraphic(Paths.image(uiPrefix + daRating.image + uiSuffix));
			rating.screenCenter();
			rating.x = placement - 40 + ClientPrefs.data.comboOffset[0];
			rating.y -= 60 + ClientPrefs.data.comboOffset[1];
			rating.acceleration.y = 550 * playbackRate * playbackRate;
			rating.velocity.y -= FlxG.random.int(140, 175) * playbackRate;
			rating.velocity.x -= FlxG.random.int(0, 10) * playbackRate;
			rating.visible = !ClientPrefs.data.hideHud;
			rating.antialiasing = antialias;
			if (!PlayState.isPixelStage) rating.setGraphicSize(Std.int(rating.width * 0.7));
			else rating.setGraphicSize(Std.int(rating.width * daPixelZoom * 0.85));
			rating.updateHitbox();
			comboGroup.add(rating);
		}

		var comboSpr:FlxSprite = null;
		if (showCombo)
		{
			comboSpr = new FlxSprite().loadGraphic(Paths.image(uiPrefix + 'combo' + uiSuffix));
			comboSpr.screenCenter();
			comboSpr.x = placement + ClientPrefs.data.comboOffset[0];
			comboSpr.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
			comboSpr.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
			comboSpr.visible = !ClientPrefs.data.hideHud;
			comboSpr.y -= ClientPrefs.data.comboOffset[1];
			comboSpr.antialiasing = antialias;
			comboSpr.y += 60;
			comboSpr.velocity.x += FlxG.random.int(1, 10) * playbackRate;
			if (!PlayState.isPixelStage) comboSpr.setGraphicSize(Std.int(comboSpr.width * 0.7));
			else comboSpr.setGraphicSize(Std.int(comboSpr.width * daPixelZoom * 0.85));
			comboSpr.updateHitbox();
			comboGroup.add(comboSpr);
		}

		var rightmostNumberX:Float = placement - 90 + ClientPrefs.data.comboOffset[2];
		if (showComboNum)
		{
			var separatedScore:Array<Int> = [];
			if(combo >= 1000) separatedScore.push(Math.floor(combo / 1000) % 10);
			separatedScore.push(Math.floor(combo / 100) % 10);
			separatedScore.push(Math.floor(combo / 10) % 10);
			separatedScore.push(combo % 10);

			var digitIndex:Int = 0;
			for (digit in separatedScore)
			{
				var numScore:FlxSprite = new FlxSprite().loadGraphic(Paths.image(uiPrefix + 'num' + digit + uiSuffix));
				numScore.screenCenter();
				numScore.x = placement + (43 * digitIndex) - 90 + ClientPrefs.data.comboOffset[2];
				numScore.y += 80 - ClientPrefs.data.comboOffset[3];
				if (!PlayState.isPixelStage) numScore.setGraphicSize(Std.int(numScore.width * 0.5));
				else numScore.setGraphicSize(Std.int(numScore.width * daPixelZoom));
				numScore.updateHitbox();
				numScore.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
				numScore.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
				numScore.velocity.x = FlxG.random.float(-5, 5) * playbackRate;
				numScore.visible = !ClientPrefs.data.hideHud;
				numScore.antialiasing = antialias;
				comboGroup.add(numScore);
				FlxTween.tween(numScore, {alpha: 0}, 0.2 / playbackRate, {
					onComplete: function(tween:FlxTween) numScore.destroy(),
					startDelay: Conductor.crochet * 0.002 / playbackRate
				});
				rightmostNumberX = numScore.x;
				digitIndex++;
			}
		}

		if (comboSpr != null)
			comboSpr.x = (showComboNum ? rightmostNumberX : placement) + 50;

		if (rating != null)
			FlxTween.tween(rating, {alpha: 0}, 0.2 / playbackRate, {
				onComplete: function(tween:FlxTween) rating.destroy(),
				startDelay: Conductor.crochet * 0.001 / playbackRate
			});

		if (comboSpr != null)
			FlxTween.tween(comboSpr, {alpha: 0}, 0.2 / playbackRate, {
				onComplete: function(tween:FlxTween) comboSpr.destroy(),
				startDelay: Conductor.crochet * 0.002 / playbackRate
			});
	}

	public var strumsBlocked:Array<Bool> = [];
	private function onKeyPress(event:KeyboardEvent):Void
	{

		var eventKey:FlxKey = event.keyCode;
		var key:Int = getKeyFromEvent(keysArray, eventKey);

		if (!controls.controllerMode)
		{
			#if debug
			//Prevents crash specifically on debug without needing to try catch shit
			@:privateAccess if (!FlxG.keys._keyListMap.exists(eventKey)) return;
			#end

			if(FlxG.keys.checkStatus(eventKey, JUST_PRESSED)) keyPressed(key);
		}
	}

	private function keyPressed(key:Int)
	{
		if(cpuControlled || paused || inCutscene || key < 0 || key >= playerStrums.length || !generatedMusic || endingSong || boyfriend.stunned) return;

		var ret:Dynamic = callOnScripts('onKeyPressPre', [key]);
		if(ret == LuaUtils.Function_Stop) return;

		// more accurate hit time for the ratings?
		var lastTime:Float = Conductor.songPosition;
		if(Conductor.songPosition >= 0) Conductor.songPosition = FlxG.sound.music.time;

		// Obtain the best two notes for this lane. The optimized path avoids a temporary
		// filtered array and a full sort on every key press.
		var funnyNote:Note = null;
		var doubleNote:Note = null;
		var inputCandidates:Array<Note> = ClientPrefs.data.fastNoteInputIndex && key >= 0 && key < notesByLane.length
			? (fastNoteLogicActive ? activeJudgementNotesByLane[key] : notesByLane[key])
			: (fastNoteLogicActive ? activeJudgementNotes : notes.members);
		if (ClientPrefs.data.optimizedNoteInput)
		{
			for (candidate in inputCandidates)
			{
				if (candidate == null || !candidate.exists || !candidate.alive || candidate.noteData != key || candidate.isSustainNote) continue;
				candidate.updateGameplayState();
				if (candidate.noteData < 0 || candidate.noteData >= strumsBlocked.length) continue;
				if (strumsBlocked[candidate.noteData] || !candidate.canBeHit || !candidate.mustPress || candidate.tooLate || candidate.wasGoodHit || candidate.blockHit) continue;

				if (funnyNote == null || sortHitNotes(candidate, funnyNote) < 0)
				{
					doubleNote = funnyNote;
					funnyNote = candidate;
				}
				else if (doubleNote == null || sortHitNotes(candidate, doubleNote) < 0)
					doubleNote = candidate;
			}
		}
		else
		{
			var plrInputNotes:Array<Note> = inputCandidates.filter(function(n:Note):Bool {
				if (n == null || !n.exists || !n.alive || n.noteData < 0 || n.noteData >= strumsBlocked.length) return false;
				n.updateGameplayState();
				var canHit:Bool = !strumsBlocked[n.noteData] && n.canBeHit && n.mustPress && !n.tooLate && !n.wasGoodHit && !n.blockHit;
				return canHit && !n.isSustainNote && n.noteData == key;
			});
			plrInputNotes.sort(sortHitNotes);
			if (plrInputNotes.length > 0) funnyNote = plrInputNotes[0];
			if (plrInputNotes.length > 1) doubleNote = plrInputNotes[1];
		}

		var shouldMiss:Bool = !ClientPrefs.data.ghostTapping;
		if (funnyNote != null)
		{
			if (doubleNote != null && doubleNote.noteData == funnyNote.noteData)
			{
				// If the note has a 0ms distance (is on top of the current note), kill it.
				if (Math.abs(doubleNote.strumTime - funnyNote.strumTime) < 1.0)
					invalidateNote(doubleNote);
				else if (doubleNote.strumTime < funnyNote.strumTime)
					funnyNote = doubleNote;
			}
			goodNoteHit(funnyNote);
		}
		else if(shouldMiss)
		{
			callOnScripts('onGhostTap', [key]);
			noteMissPress(key);
		}

		// Needed for the  "Just the Two of Us" achievement.
		//									- Shadow Mario
		if(!keysPressed.contains(key)) keysPressed.push(key);

		//more accurate hit time for the ratings? part 2 (Now that the calculations are done, go back to the time it was before for not causing a note stutter)
		Conductor.songPosition = lastTime;

		var spr:StrumNote = playerStrums.members[key];
		if(strumsBlocked[key] != true && spr != null && spr.animation.curAnim.name != 'confirm')
		{
			spr.playAnim('pressed');
			spr.resetAnim = 0;
		}
		callOnScripts('onKeyPress', [key]);
	}

	public static function sortHitNotes(a:Note, b:Note):Int
	{
		if (a.lowPriority && !b.lowPriority)
			return 1;
		else if (!a.lowPriority && b.lowPriority)
			return -1;

		return FlxSort.byValues(FlxSort.ASCENDING, a.strumTime, b.strumTime);
	}

	private function onKeyRelease(event:KeyboardEvent):Void
	{
		var eventKey:FlxKey = event.keyCode;
		var key:Int = getKeyFromEvent(keysArray, eventKey);
		if(!controls.controllerMode && key > -1) keyReleased(key);
	}

	private function keyReleased(key:Int)
	{
		if(cpuControlled || !startedCountdown || paused || key < 0 || key >= playerStrums.length) return;

		var ret:Dynamic = callOnScripts('onKeyReleasePre', [key]);
		if(ret == LuaUtils.Function_Stop) return;

		var spr:StrumNote = playerStrums.members[key];
		if(spr != null)
		{
			spr.playAnim('static');
			spr.resetAnim = 0;
		}
		callOnScripts('onKeyRelease', [key]);
	}

	public static function getKeyFromEvent(arr:Array<String>, key:FlxKey):Int
	{
		if(key != NONE)
		{
			for (i in 0...arr.length)
			{
				var note:Array<FlxKey> = Controls.instance.keyboardBinds[arr[i]];
				for (noteKey in note)
					if(key == noteKey)
						return i;
			}
		}
		return -1;
	}

	// Shared sustain judgement keeps both the legacy and indexed paths identical.
	private inline function tryHitHeldSustain(note:Note, holdArray:Array<Bool>):Void
	{
		if (note == null || !note.exists || !note.alive || note.noteData < 0 || note.noteData >= strumsBlocked.length) return;
		note.updateGameplayState();
		var canHit:Bool = (!strumsBlocked[note.noteData] && note.canBeHit
			&& note.mustPress && !note.tooLate && !note.wasGoodHit && !note.blockHit);
		if (guitarHeroSustains)
			canHit = canHit && note.parent != null && note.parent.wasGoodHit;
		if (canHit && note.isSustainNote && holdArray[note.noteData])
			goodNoteHit(note);
	}

	// Hold notes
	private function keysCheck():Void
	{
		// HOLDING
		var holdArray:Array<Bool> = [];
		var pressArray:Array<Bool> = [];
		var releaseArray:Array<Bool> = [];
		var anyKeyHeld:Bool = false;
		for (key in keysArray)
		{
			var isHeld:Bool = controls.pressed(key);
			holdArray.push(isHeld);
			if (isHeld) anyKeyHeld = true;
			if(controls.controllerMode)
			{
				pressArray.push(controls.justPressed(key));
				releaseArray.push(controls.justReleased(key));
			}
		}

		// TO DO: Find a better way to handle controller inputs, this should work for now
		if(controls.controllerMode && pressArray.contains(true))
			for (i in 0...pressArray.length)
				if(pressArray[i] && strumsBlocked[i] != true)
					keyPressed(i);

		if (startedCountdown && !inCutscene && !boyfriend.stunned && generatedMusic)
		{
			if (notes.length > 0 && anyKeyHeld)
			{
				if (fastNoteLogicActive && ClientPrefs.data.fastNoteInputIndex)
				{
					// Only visit lanes with a held key, and only notes inside their judgement window.
					for (lane in 0...activeJudgementNotesByLane.length)
					{
						if (!holdArray[lane] || strumsBlocked[lane]) continue;
						var laneCandidates:Array<Note> = activeJudgementSustainsByLane[lane];
						for (note in laneCandidates) tryHitHeldSustain(note, holdArray);
					}
				}
				else
				{
					var holdCandidates:Array<Note> = fastNoteLogicActive ? activeJudgementNotes : notes.members;
					for (note in holdCandidates) tryHitHeldSustain(note, holdArray);
				}
			}

			if (!holdArray.contains(true) || endingSong)
				playerDance();

			#if ACHIEVEMENTS_ALLOWED
			else checkForAchievement(['oversinging']);
			#end
		}

		// TO DO: Find a better way to handle controller inputs, this should work for now
		if((controls.controllerMode || strumsBlocked.contains(true)) && releaseArray.contains(true))
			for (i in 0...releaseArray.length)
				if(releaseArray[i] || strumsBlocked[i] == true)
					keyReleased(i);
	}

	function noteMiss(daNote:Note):Void { //You didn't hit the key and let it go offscreen, also used by Hurt Notes
		// Duplicate cleanup only needs to inspect the same lane. The lane index is also
		// swap-removed, so processing backward avoids skipping a swapped-in candidate.
		if (ClientPrefs.data.fastNoteInputIndex && daNote.mustPress && daNote.noteData >= 0 && daNote.noteData < notesByLane.length)
		{
			var laneNotes:Array<Note> = fastNoteLogicActive
				? activeJudgementNotesByLane[daNote.noteData] : notesByLane[daNote.noteData];
			var i:Int = laneNotes.length - 1;
			while (i >= 0 && i < laneNotes.length)
			{
				var candidate:Note = laneNotes[i];
				if (candidate != null && daNote != candidate && daNote.noteData == candidate.noteData
					&& daNote.isSustainNote == candidate.isSustainNote && Math.abs(daNote.strumTime - candidate.strumTime) < 1)
				{
					invalidateNote(candidate);
					i--;
				}
				else i--;
			}
		}
		else
		{
			// Reverse traversal remains safe with both ordered removal and swap-pop.
			var duplicateCandidates:Array<Note> = fastNoteLogicActive ? activeJudgementNotes : notes.members;
			var i:Int = duplicateCandidates.length - 1;
			while (i >= 0 && i < duplicateCandidates.length)
			{
				var candidate:Note = duplicateCandidates[i];
				if (candidate != null && daNote != candidate && candidate.mustPress
					&& daNote.noteData == candidate.noteData && daNote.isSustainNote == candidate.isSustainNote
					&& Math.abs(daNote.strumTime - candidate.strumTime) < 1)
					invalidateNote(candidate);
				i--;
			}
		}

		noteMissCommon(daNote.noteData, daNote);
		if (!ClientPrefs.data.disableNoteMissEvents) {
			var result:Dynamic = callOnLuas('noteMiss', [getNoteGroupIndex(daNote), daNote.noteData, daNote.noteType, daNote.isSustainNote]);
			if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) callOnHScript('noteMiss', [daNote]);
		}
	}

	function noteMissPress(direction:Int = 1):Void //You pressed a key when there was no notes to press for this key
	{
		if(ClientPrefs.data.ghostTapping) return; //fuck it

		noteMissCommon(direction);
		FlxG.sound.play(Paths.soundRandom('missnote', 1, 3), FlxG.random.float(0.1, 0.2));
		if (!ClientPrefs.data.disableNoteMissEvents) callOnScripts('noteMissPress', [direction]);
	}

	function noteMissCommon(direction:Int, note:Note = null)
	{
		// score and data
		var subtract:Float = 0.05;
		if(note != null) subtract = note.missHealth;

		// GUITAR HERO SUSTAIN CHECK LOL!!!!
		if (note != null && guitarHeroSustains && note.parent == null) {
			var expectedTails:Int = note.expectedTailCount > 0 ? note.expectedTailCount : note.getTailCount();
			if(expectedTails > 0) {
				note.sustainChainBroken = true;
				note.alpha = 0.35;
				for(childNote in note.tail) {
					childNote.alpha = note.alpha;
					childNote.missed = true;
					childNote.canBeHit = false;
					childNote.ignoreNote = true;
					childNote.tooLate = true;
				}
				note.missed = true;
				note.canBeHit = false;

				//subtract += 0.385; // you take more damage if playing with this gameplay changer enabled.
				// i mean its fair :p -Crow
				subtract *= expectedTails + 1;
				// i think it would be fair if damage multiplied based on how long the sustain is -Tahir
			}

			if (note.missed)
				return;
		}
		if (note != null && guitarHeroSustains && note.parent != null && note.isSustainNote) {
			if (note.missed)
				return;

			var parentNote:Note = note.parent;
			if (parentNote.wasGoodHit && (parentNote.expectedTailCount > 0 || parentNote.getTailCount() > 0)) {
				parentNote.sustainChainBroken = true;
				for (child in parentNote.tail) if (child != note) {
					child.missed = true;
					child.canBeHit = false;
					child.ignoreNote = true;
					child.tooLate = true;
				}
			}
		}

		if(instakillOnMiss)
		{
			vocals.volume = 0;
			opponentVocals.volume = 0;
			doDeathCheck(true);
		}

		var lastCombo:Int = combo;
		combo = 0;

		health -= subtract * healthLoss;
		if(!practiceMode) songScore -= 10;
		if(!endingSong) songMisses++;
		totalPlayed++;
		RecalculateRating(true);

		// play character anims
		var char:Character = boyfriend;
		if((note != null && note.gfNote) || (SONG.notes[curSection] != null && SONG.notes[curSection].gfSection)) char = gf;

		if(char != null && (note == null || !note.noMissAnimation) && char.hasMissAnimations)
		{
			var suffix:String = '';
			if(note != null) suffix = note.animSuffix;

			var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, direction)))] + 'miss' + suffix;
			char.playAnim(animToPlay, true);

			if(char != gf && lastCombo > 5 && gf != null && gf.animOffsets.exists('sad'))
			{
				gf.playAnim('sad');
				gf.specialAnim = true;
			}
		}
		vocals.volume = 0;
	}

	function opponentNoteHit(note:Note):Void
	{
		if (!ClientPrefs.data.disableNoteHitEvents) {
			var result:Dynamic = callOnLuas('opponentNoteHitPre', [getNoteGroupIndex(note), Math.abs(note.noteData), note.noteType, note.isSustainNote]);
			if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) callOnHScript('opponentNoteHitPre', [note]);
		}

		if (songName != 'tutorial')
			camZooming = true;

		if(note.noteType == 'Hey!' && dad.animOffsets.exists('hey')) {
			dad.playAnim('hey', true);
			dad.specialAnim = true;
			dad.heyTimer = 0.6;
		} else if(!note.noAnimation) {
			var altAnim:String = note.animSuffix;

			if (SONG.notes[curSection] != null)
				if (SONG.notes[curSection].altAnim && !SONG.notes[curSection].gfSection)
					altAnim = '-alt';

			var char:Character = dad;
			var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, note.noteData)))] + altAnim;
			if(note.gfNote) char = gf;

			if(char != null)
			{
				char.playAnim(animToPlay, true);
				char.holdTimer = 0;
			}
		}

		if(opponentVocals.length <= 0) vocals.volume = 1;
		strumPlayAnim(true, Std.int(Math.abs(note.noteData)), Conductor.stepCrochet * 1.25 / 1000 / playbackRate);
		note.hitByOpponent = true;
		
		if (!ClientPrefs.data.disableNoteHitEvents) {
			var result:Dynamic = callOnLuas('opponentNoteHit', [getNoteGroupIndex(note), Math.abs(note.noteData), note.noteType, note.isSustainNote]);
			if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) callOnHScript('opponentNoteHit', [note]);
		}

		if (!note.isSustainNote) invalidateNote(note);
	}

	public function goodNoteHit(note:Note):Void
	{
		if(note.wasGoodHit) return;
		if(cpuControlled && note.ignoreNote) return;

		var isSus:Bool = note.isSustainNote; //GET OUT OF MY HEAD, GET OUT OF MY HEAD, GET OUT OF MY HEAD
		var leData:Int = Math.round(Math.abs(note.noteData));
		var leType:String = note.noteType;

		if (!ClientPrefs.data.disableNoteHitEvents) {
			var result:Dynamic = callOnLuas('goodNoteHitPre', [getNoteGroupIndex(note), leData, leType, isSus]);
			if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) callOnHScript('goodNoteHitPre', [note]);
		}

		note.wasGoodHit = true;

		if (ClientPrefs.data.hitsoundVolume > 0 && !note.hitsoundDisabled)
			FlxG.sound.play(Paths.sound(note.hitsound), ClientPrefs.data.hitsoundVolume);

		if(note.hitCausesMiss) {
			if(!note.noMissAnimation) {
				switch(note.noteType) {
					case 'Hurt Note': //Hurt note
						if(boyfriend.animOffsets.exists('hurt')) {
							boyfriend.playAnim('hurt', true);
							boyfriend.specialAnim = true;
						}
				}
			}

			noteMiss(note);
			if(!note.noteSplashData.disabled && !note.isSustainNote) spawnNoteSplashOnNote(note);
			if(!note.isSustainNote) invalidateNote(note);
			return;
		}

		if(!note.noAnimation) {
			var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, note.noteData)))];

			var char:Character = boyfriend;
			var animCheck:String = 'hey';
			if(note.gfNote)
			{
				char = gf;
				animCheck = 'cheer';
			}

			if(char != null)
			{
				char.playAnim(animToPlay + note.animSuffix, true);
				char.holdTimer = 0;

				if(note.noteType == 'Hey!') {
					if(char.animOffsets.exists(animCheck)) {
						char.playAnim(animCheck, true);
						char.specialAnim = true;
						char.heyTimer = 0.6;
					}
				}
			}
		}

		if(!cpuControlled)
		{
			var spr = playerStrums.members[note.noteData];
			if(spr != null) spr.playAnim('confirm', true);
		}
		else strumPlayAnim(false, Std.int(Math.abs(note.noteData)), Conductor.stepCrochet * 1.25 / 1000 / playbackRate);
		vocals.volume = 1;

		if (!note.isSustainNote)
		{
			combo++;
			if(combo > 9999) combo = 9999;
			popUpScore(note);
		}
		var gainHealth:Bool = true; // prevent health gain, *if* sustains are treated as a singular note
		if (guitarHeroSustains && note.isSustainNote) gainHealth = false;
		if (gainHealth) health += note.hitHealth * healthGain;

		if (!ClientPrefs.data.disableNoteHitEvents) {
			var result:Dynamic = callOnLuas('goodNoteHit', [getNoteGroupIndex(note), leData, leType, isSus]);
			if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) callOnHScript('goodNoteHit', [note]);
		}

		if(!note.isSustainNote) invalidateNote(note);
	}

	public function invalidateNote(note:Note):Void {
		var freedRenderSlot:Bool = note.renderBudgetVisible;
		var wasBudgetHidden:Bool = note.renderBudgetManaged && !note.renderBudgetVisible;
		if (note.renderBudgetPending) unlinkPendingRenderedNote(note);
		if (wasBudgetHidden && hiddenNoteCount > 0) hiddenNoteCount--;
		note.renderBudgetVisible = false;
		note.renderBudgetPending = false;
		note.renderBudgetManaged = false;
		note.renderBudgetPrev = null;
		note.renderBudgetNext = null;
		if (freedRenderSlot && renderedNoteCount > 0) renderedNoteCount--;
		note.active = false;
		note.visible = false;
		if (grpRenderedNotes != null) grpRenderedNotes.remove(note, true);
		unregisterNoteIndexes(note);
		var pooled:Bool = notes != null && notes.releaseToPool(note);
		if (!pooled)
		{
			note.kill();
			note.destroy();
		}
		if (freedRenderSlot && !suspendRenderBudgetPromotion) promoteNextRenderedNote();
	}

	public function spawnNoteSplashOnNote(note:Note) {
		if(note != null) {
			var strum:StrumNote = playerStrums.members[note.noteData];
			if(strum != null)
				spawnNoteSplash(strum.x, strum.y, note.noteData, note);
		}
	}

	public function spawnNoteSplash(x:Float, y:Float, data:Int, ?note:Note = null) {
		if (ClientPrefs.data.disableNoteSplashes) return;
		var splash:NoteSplash = grpNoteSplashes.recycle(NoteSplash);
		splash.setupNoteSplash(x, y, data, note);
		grpNoteSplashes.add(splash);
	}

	override function destroy() {
		chunkedChartSections = null;
		#if sys
		if (jsonStreamReader != null) jsonStreamReader.close();
		jsonStreamReader = null;
		// Do not delete the sidecar here. FlxG.resetState() reuses SONG and the
		// next PlayState must be able to reopen the same chart from byte zero.
		jsonStreamSidecarPath = null;
		#end
		streamLoadedNoteTypes = [];
		pendingJudgementHead = pendingJudgementTail = null;
		activeJudgementHead = activeJudgementTail = activeJudgementActionHead = null;
		activeJudgementNotes = [];
		notesByLane = [[], [], [], []];
		activeJudgementNotesByLane = [[], [], [], []];
		activeJudgementSustainsByLane = [[], [], [], []];
		fastNoteLogicActive = false;
		#if desktop
		stopGameRenderer();
		#end
		grpRenderedNotes = null;
		useRollingNoteGeneration = false;

		#if LUA_ALLOWED
		for (lua in luaArray)
		{
			lua.call('onDestroy', []);
			lua.stop();
		}
		luaArray = [];
		FunkinLua.customFunctions.clear();
		#end

		#if HSCRIPT_ALLOWED
		for (script in hscriptArray)
			if(script != null)
			{
				script.call('onDestroy');
				script.destroy();
			}

		while (hscriptArray.length > 0)
			hscriptArray.pop();
		#end

		FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_UP, onKeyRelease);
		FlxG.animationTimeScale = 1;
		#if FLX_PITCH FlxG.sound.music.pitch = 1; #end
		Note.globalRgbShaders = [];
		backend.NoteTypesConfig.clearNoteTypesData();
		instance = null;
		super.destroy();
	}

	var lastStepHit:Int = -1;
	override function stepHit()
	{
		if (SONG.needsVoices && FlxG.sound.music.time >= -ClientPrefs.data.noteOffset)
		{
			var timeSub:Float = Conductor.songPosition - Conductor.offset;
			var syncTime:Float = 20 * playbackRate;
			if (Math.abs(FlxG.sound.music.time - timeSub) > syncTime ||
			(vocals.length > 0 && Math.abs(vocals.time - timeSub) > syncTime) ||
			(opponentVocals.length > 0 && Math.abs(opponentVocals.time - timeSub) > syncTime))
			{
				resyncVocals();
			}
		}

		super.stepHit();

		if(curStep == lastStepHit) {
			return;
		}

		lastStepHit = curStep;
		setOnScripts('curStep', curStep);
		callOnScripts('onStepHit');
	}

	var lastBeatHit:Int = -1;

	override function beatHit()
	{
		if(lastBeatHit >= curBeat) {
			//trace('BEAT HIT: ' + curBeat + ', LAST HIT: ' + lastBeatHit);
			return;
		}

		if (generatedMusic && ClientPrefs.data.noteSorting)
		{
			var sortGroup:FlxTypedGroup<Note> = ClientPrefs.data.noteRenderProcessingEnabled ? grpRenderedNotes : notes;
			if (sortGroup != null) sortGroup.sort(FlxSort.byY, ClientPrefs.data.downScroll ? FlxSort.ASCENDING : FlxSort.DESCENDING);
		}

		iconP1.scale.set(1.2, 1.2);
		iconP2.scale.set(1.2, 1.2);

		iconP1.updateHitbox();
		iconP2.updateHitbox();

		characterBopper(curBeat);

		super.beatHit();
		lastBeatHit = curBeat;

		setOnScripts('curBeat', curBeat);
		callOnScripts('onBeatHit');
	}

	public function characterBopper(beat:Int):Void
	{
		if (gf != null && beat % Math.round(gfSpeed * gf.danceEveryNumBeats) == 0 && !gf.getAnimationName().startsWith('sing') && !gf.stunned)
			gf.dance();
		if (boyfriend != null && beat % boyfriend.danceEveryNumBeats == 0 && !boyfriend.getAnimationName().startsWith('sing') && !boyfriend.stunned)
			boyfriend.dance();
		if (dad != null && beat % dad.danceEveryNumBeats == 0 && !dad.getAnimationName().startsWith('sing') && !dad.stunned)
			dad.dance();
	}

	public function playerDance():Void
	{
		var anim:String = boyfriend.getAnimationName();
		if(boyfriend.holdTimer > Conductor.stepCrochet * (0.0011 #if FLX_PITCH / FlxG.sound.music.pitch #end) * boyfriend.singDuration && anim.startsWith('sing') && !anim.endsWith('miss'))
			boyfriend.dance();
	}

	override function sectionHit()
	{
		if (SONG.notes[curSection] != null)
		{
			if (generatedMusic && !endingSong && !isCameraOnForcedPos)
				moveCameraSection();

			if (camZooming && FlxG.camera.zoom < 1.35 && ClientPrefs.data.camZooms)
			{
				FlxG.camera.zoom += 0.015 * camZoomingMult;
				camHUD.zoom += 0.03 * camZoomingMult;
			}

			if (SONG.notes[curSection].changeBPM)
			{
				Conductor.bpm = SONG.notes[curSection].bpm;
				setOnScripts('curBpm', Conductor.bpm);
				setOnScripts('crochet', Conductor.crochet);
				setOnScripts('stepCrochet', Conductor.stepCrochet);
			}
			setOnScripts('mustHitSection', SONG.notes[curSection].mustHitSection);
			setOnScripts('altAnim', SONG.notes[curSection].altAnim);
			setOnScripts('gfSection', SONG.notes[curSection].gfSection);
		}
		super.sectionHit();

		setOnScripts('curSection', curSection);
		callOnScripts('onSectionHit');
	}

	#if LUA_ALLOWED
	public function startLuasNamed(luaFile:String)
	{
		if(ClientPrefs.data.disableLuaScripts) return false;
		#if MODS_ALLOWED
		var luaToLoad:String = Paths.modFolders(luaFile);
		if(!FileSystem.exists(luaToLoad))
			luaToLoad = Paths.getSharedPath(luaFile);

		if(FileSystem.exists(luaToLoad))
		#elseif sys
		var luaToLoad:String = Paths.getSharedPath(luaFile);
		if(OpenFlAssets.exists(luaToLoad))
		#end
		{
			for (script in luaArray)
				if(script.scriptName == luaToLoad) return false;

			new FunkinLua(luaToLoad);
			return true;
		}
		return false;
	}
	#end

	#if HSCRIPT_ALLOWED
	public function startHScriptsNamed(scriptFile:String)
	{
		if(ClientPrefs.data.disableHScriptScripts) return false;
		#if MODS_ALLOWED
		var scriptToLoad:String = Paths.modFolders(scriptFile);
		if(!FileSystem.exists(scriptToLoad))
			scriptToLoad = Paths.getSharedPath(scriptFile);
		#else
		var scriptToLoad:String = Paths.getSharedPath(scriptFile);
		#end

		if(FileSystem.exists(scriptToLoad))
		{
			if (SScript.global.exists(scriptToLoad)) return false;

			initHScript(scriptToLoad);
			return true;
		}
		return false;
	}

	public function initHScript(file:String)
	{
		if(ClientPrefs.data.disableHScriptScripts) return;
		try
		{
			var newScript:HScript = new HScript(null, file);
			if(newScript.parsingException != null)
			{
				addTextToDebug('ERROR ON LOADING: ${newScript.parsingException.message}', FlxColor.RED);
				newScript.destroy();
				return;
			}

			hscriptArray.push(newScript);
			if(newScript.exists('onCreate'))
			{
				var callValue = newScript.call('onCreate');
				if(!callValue.succeeded)
				{
					for (e in callValue.exceptions)
					{
						if (e != null)
						{
							var len:Int = e.message.indexOf('\n') + 1;
							if(len <= 0) len = e.message.length;
								addTextToDebug('ERROR ($file: onCreate) - ${e.message.substr(0, len)}', FlxColor.RED);
						}
					}

					newScript.destroy();
					hscriptArray.remove(newScript);
					trace('failed to initialize tea interp!!! ($file)');
				}
				else trace('initialized tea interp successfully: $file');
			}

		}
		catch(e)
		{
			var len:Int = e.message.indexOf('\n') + 1;
			if(len <= 0) len = e.message.length;
			addTextToDebug('ERROR - ' + e.message.substr(0, len), FlxColor.RED);
			var newScript:HScript = cast (SScript.global.get(file), HScript);
			if(newScript != null)
			{
				newScript.destroy();
				hscriptArray.remove(newScript);
			}
		}
	}
	#end

	private function isLegacyScriptBlocked(scriptPath:String, funcToCall:String):Bool
	{
		if (ClientPrefs.data.disableLuaHScriptCalls) return true;
		var normalized:String = scriptPath == null ? '' : scriptPath.replace('\\', '/').toLowerCase();
		var isStageScript:Bool = normalized.contains('/stages/') || normalized.startsWith('stages/');
		var isEventScript:Bool = normalized.contains('/custom_events/') || normalized.startsWith('custom_events/');
		if (ClientPrefs.data.disableLuaHScriptStageCalls && isStageScript) return true;
		var isEventCallback:Bool = funcToCall == 'eventEarlyTrigger' || funcToCall == 'onEventPushed' || funcToCall == 'onEvent';
		if (ClientPrefs.data.disableLuaHScriptEventCalls && (isEventScript || isEventCallback)) return true;
		return false;
	}

	private function shouldSkipScriptCallback(funcToCall:String):Bool {
		if (ClientPrefs.data.disableLuaHScriptCalls) return true;
		switch(funcToCall) {
			case 'onUpdate' | 'onUpdatePost':
				return ClientPrefs.data.disableScriptUpdateEvents;
			case 'goodNoteHitPre' | 'goodNoteHit' | 'opponentNoteHitPre' | 'opponentNoteHit':
				return ClientPrefs.data.disableNoteHitEvents;
			case 'noteMiss' | 'noteMissPress':
				return ClientPrefs.data.disableNoteMissEvents;
			case 'onSpawnNote':
				return ClientPrefs.data.disableNoteSpawnEvents;
			case 'eventEarlyTrigger' | 'onEventPushed' | 'onEvent':
				return ClientPrefs.data.disableChartEventCallbacks;
			case 'onCountdownTick' | 'onStepHit' | 'onBeatHit' | 'onSectionHit':
				return ClientPrefs.data.disableBeatStepCallbacks;
			case 'onKeyPressPre' | 'onKeyPress' | 'onKeyReleasePre' | 'onKeyRelease' | 'onGhostTap':
				return ClientPrefs.data.disableInputCallbacks;
			case 'onCreatePost' | 'onStartCountdown' | 'onCountdownStarted' | 'onSongStart' | 'onPause' | 'onResume' | 'onGameOver' | 'onEndSong':
				return ClientPrefs.data.disableLifecycleCallbacks;
			case 'onMoveCamera':
				return ClientPrefs.data.disableCameraCallbacks;
			case 'onNextDialogue' | 'onSkipDialogue':
				return ClientPrefs.data.disableDialogueCallbacks;
			case 'preUpdateScore' | 'onUpdateScore' | 'onRecalculateRating':
				return ClientPrefs.data.disableScoreCallbacks;
			case 'onCustomSubstateCreate' | 'onCustomSubstateCreatePost' | 'onCustomSubstateUpdate' | 'onCustomSubstateUpdatePost' | 'onCustomSubstateDestroy':
				return ClientPrefs.data.disableCustomSubstateCallbacks;
		}
		return false;
	}

	public function callOnScripts(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = LuaUtils.Function_Continue;
		if(shouldSkipScriptCallback(funcToCall)) return returnVal;
		if(args == null) args = [];
		if(exclusions == null) exclusions = [];
		if(excludeValues == null) excludeValues = [LuaUtils.Function_Continue];

		var result:Dynamic = callOnLuas(funcToCall, args, ignoreStops, exclusions, excludeValues);
		if(result == null || excludeValues.contains(result)) result = callOnHScript(funcToCall, args, ignoreStops, exclusions, excludeValues);
		return result;
	}

	public function callOnLuas(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = LuaUtils.Function_Continue;
		if(ClientPrefs.data.disableLuaScripts || shouldSkipScriptCallback(funcToCall)) return returnVal;
		#if LUA_ALLOWED
		if(args == null) args = [];
		if(exclusions == null) exclusions = [];
		if(excludeValues == null) excludeValues = [LuaUtils.Function_Continue];

		var arr:Array<FunkinLua> = [];
		for (script in luaArray)
		{
			if (isLegacyScriptBlocked(script.scriptName, funcToCall)) continue;
			if(script.closed)
			{
				arr.push(script);
				continue;
			}

			if(exclusions.contains(script.scriptName))
				continue;

			var myValue:Dynamic = script.call(funcToCall, args);
			if((myValue == LuaUtils.Function_StopLua || myValue == LuaUtils.Function_StopAll) && !excludeValues.contains(myValue) && !ignoreStops)
			{
				returnVal = myValue;
				break;
			}

			if(myValue != null && !excludeValues.contains(myValue))
				returnVal = myValue;

			if(script.closed) arr.push(script);
		}

		if(arr.length > 0)
			for (script in arr)
				luaArray.remove(script);
		#end
		return returnVal;
	}

	public function callOnHScript(funcToCall:String, args:Array<Dynamic> = null, ?ignoreStops:Bool = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = LuaUtils.Function_Continue;
		if(ClientPrefs.data.disableHScriptScripts || shouldSkipScriptCallback(funcToCall)) return returnVal;

		#if HSCRIPT_ALLOWED
		if(exclusions == null) exclusions = new Array();
		if(excludeValues == null) excludeValues = new Array();
		excludeValues.push(LuaUtils.Function_Continue);

		var len:Int = hscriptArray.length;
		if (len < 1)
			return returnVal;
		for(i in 0...len) {
			var script:HScript = hscriptArray[i];
			if (script != null && isLegacyScriptBlocked(script.origin, funcToCall)) continue;
			if(script == null || !script.exists(funcToCall) || exclusions.contains(script.origin))
				continue;

			var myValue:Dynamic = null;
			try {
				var callValue = script.call(funcToCall, args);
				if(!callValue.succeeded)
				{
					var e = callValue.exceptions[0];
					if(e != null)
					{
						var len:Int = e.message.indexOf('\n') + 1;
						if(len <= 0) len = e.message.length;
						addTextToDebug('ERROR (${callValue.calledFunction}) - ' + e.message.substr(0, len), FlxColor.RED);
					}
				}
				else
				{
					myValue = callValue.returnValue;
					if((myValue == LuaUtils.Function_StopHScript || myValue == LuaUtils.Function_StopAll) && !excludeValues.contains(myValue) && !ignoreStops)
					{
						returnVal = myValue;
						break;
					}

					if(myValue != null && !excludeValues.contains(myValue))
						returnVal = myValue;
				}
			}
		}
		#end

		return returnVal;
	}

	public function setOnScripts(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		if(exclusions == null) exclusions = [];
		setOnLuas(variable, arg, exclusions);
		setOnHScript(variable, arg, exclusions);
	}

	public function setOnLuas(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		if(ClientPrefs.data.disableLuaScripts) return;
		#if LUA_ALLOWED
		if(exclusions == null) exclusions = [];
		for (script in luaArray) {
			if(exclusions.contains(script.scriptName))
				continue;

			script.set(variable, arg);
		}
		#end
	}

	public function setOnHScript(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		if(ClientPrefs.data.disableHScriptScripts) return;
		#if HSCRIPT_ALLOWED
		if(exclusions == null) exclusions = [];
		for (script in hscriptArray) {
			if(exclusions.contains(script.origin))
				continue;

			if(!instancesExclude.contains(variable))
				instancesExclude.push(variable);
			script.set(variable, arg);
		}
		#end
	}

	function strumPlayAnim(isDad:Bool, id:Int, time:Float) {
		var spr:StrumNote = null;
		if(isDad) {
			spr = opponentStrums.members[id];
		} else {
			spr = playerStrums.members[id];
		}

		if(spr != null) {
			spr.playAnim('confirm', true);
			spr.resetAnim = time;
		}
	}

	public var ratingName:String = '?';
	public var ratingPercent:Float;
	public var ratingFC:String;
	public function RecalculateRating(badHit:Bool = false) {
		setOnScripts('score', songScore);
		setOnScripts('misses', songMisses);
		setOnScripts('hits', songHits);
		setOnScripts('combo', combo);

		var ret:Dynamic = callOnScripts('onRecalculateRating', null, true);
		if(ret != LuaUtils.Function_Stop)
		{
			ratingName = '?';
			if(totalPlayed != 0) //Prevent divide by 0
			{
				// Rating Percent
				ratingPercent = Math.min(1, Math.max(0, totalNotesHit / totalPlayed));
				//trace((totalNotesHit / totalPlayed) + ', Total: ' + totalPlayed + ', notes hit: ' + totalNotesHit);

				// Rating Name
				ratingName = ratingStuff[ratingStuff.length-1][0]; //Uses last string
				if(ratingPercent < 1)
					for (i in 0...ratingStuff.length-1)
						if(ratingPercent < ratingStuff[i][1])
						{
							ratingName = ratingStuff[i][0];
							break;
						}
			}
			fullComboFunction();
		}
		updateScore(badHit); // score will only update after rating is calculated, if it's a badHit, it shouldn't bounce
		setOnScripts('rating', ratingPercent);
		setOnScripts('ratingName', ratingName);
		setOnScripts('ratingFC', ratingFC);
	}

	#if ACHIEVEMENTS_ALLOWED
	private function checkForAchievement(achievesToCheck:Array<String> = null)
	{
		if(chartingMode) return;

		var usedPractice:Bool = (ClientPrefs.getGameplaySetting('practice') || ClientPrefs.getGameplaySetting('botplay'));
		if(cpuControlled) return;

		for (name in achievesToCheck) {
			if(!Achievements.exists(name)) continue;

			var unlock:Bool = false;
			if (name != WeekData.getWeekFileName() + '_nomiss') // common achievements
			{
				switch(name)
				{
					case 'ur_bad':
						unlock = (ratingPercent < 0.2 && !practiceMode);

					case 'ur_good':
						unlock = (ratingPercent >= 1 && !usedPractice);

					case 'oversinging':
						unlock = (boyfriend.holdTimer >= 10 && !usedPractice);

					case 'hype':
						unlock = (!boyfriendIdled && !usedPractice);

					case 'two_keys':
						unlock = (!usedPractice && keysPressed.length <= 2);

					case 'toastie':
						unlock = (!ClientPrefs.data.cacheOnGPU && !ClientPrefs.data.shaders && ClientPrefs.data.lowQuality && !ClientPrefs.data.antialiasing);

					case 'debugger':
						unlock = (songName == 'test' && !usedPractice);
				}
			}
			else // any FC achievements, name should be "weekFileName_nomiss", e.g: "week3_nomiss";
			{
				if(isStoryMode && campaignMisses + songMisses < 1 && Difficulty.getString().toUpperCase() == 'HARD'
					&& storyPlaylist.length <= 1 && !changedDifficulty && !usedPractice)
					unlock = true;
			}

			if(unlock) Achievements.unlock(name);
		}
	}
	#end

	#if (!flash && sys)
	public var runtimeShaders:Map<String, Array<String>> = new Map<String, Array<String>>();
	public function createRuntimeShader(name:String):FlxRuntimeShader
	{
		if(!ClientPrefs.data.shaders) return new FlxRuntimeShader();

		#if (!flash && MODS_ALLOWED && sys)
		if(!runtimeShaders.exists(name) && !initLuaShader(name))
		{
			FlxG.log.warn('Shader $name is missing!');
			return new FlxRuntimeShader();
		}

		var arr:Array<String> = runtimeShaders.get(name);
		return new FlxRuntimeShader(arr[0], arr[1]);
		#else
		FlxG.log.warn("Platform unsupported for Runtime Shaders!");
		return null;
		#end
	}

	public function initLuaShader(name:String, ?glslVersion:Int = 120)
	{
		if(!ClientPrefs.data.shaders) return false;

		#if (MODS_ALLOWED && !flash && sys)
		if(runtimeShaders.exists(name))
		{
			FlxG.log.warn('Shader $name was already initialized!');
			return true;
		}

		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'shaders/'))
		{
			var frag:String = folder + name + '.frag';
			var vert:String = folder + name + '.vert';
			var found:Bool = false;
			if(FileSystem.exists(frag))
			{
				frag = File.getContent(frag);
				found = true;
			}
			else frag = null;

			if(FileSystem.exists(vert))
			{
				vert = File.getContent(vert);
				found = true;
			}
			else vert = null;

			if(found)
			{
				runtimeShaders.set(name, [frag, vert]);
				//trace('Found shader $name!');
				return true;
			}
		}
			#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
			addTextToDebug('Missing shader $name .frag AND .vert files!', FlxColor.RED);
			#else
			FlxG.log.warn('Missing shader $name .frag AND .vert files!');
			#end
		#else
		FlxG.log.warn('This platform doesn\'t support Runtime Shaders!');
		#end
		return false;
	}
	#end
}
