package states.editors;

import flash.geom.Rectangle;
import haxe.Json;
import haxe.Int64;
import haxe.format.JsonParser;
import haxe.io.Bytes;
import haxe.io.Path;

import flixel.FlxObject;
import flixel.addons.display.FlxGridOverlay;
import flixel.addons.ui.FlxUI;
import flixel.addons.ui.FlxUICheckBox;
import flixel.addons.ui.FlxUIInputText;
import flixel.addons.ui.FlxUIDropDownMenu;
import flixel.addons.ui.FlxUINumericStepper;
import flixel.addons.ui.FlxUISlider;
import flixel.addons.ui.FlxUITabMenu;
import flixel.group.FlxGroup;
import flixel.ui.FlxButton;

import flixel.util.FlxSort;
import lime.media.AudioBuffer;
import lime.utils.Assets;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.media.Sound;
import openfl.net.FileReference;
import openfl.utils.Assets as OpenFlAssets;

import backend.Song;
import backend.Section;
import backend.PackedNoteBuffer;
import backend.StageData;
#if sys
import backend.SplitChartSaveJob;
import lime.ui.FileDialog;
import lime.ui.FileDialogType;
#end

import objects.Note;
import objects.StrumNote;
import objects.NoteSplash;
import objects.HealthIcon;
import objects.AttachedSprite;
import objects.Character;
import substates.Prompt;

#if sys
import flash.media.Sound;
#end

@:access(flixel.sound.FlxSound._sound)
@:access(openfl.media.Sound.__buffer)

class ChartingState extends MusicBeatState
{
	public static var noteTypeList:Array<String> = [
		'',
		'Alt Animation',
		'Hey!',
		'Hurt Note',
		'GF Sing',
		'No Animation'
	];
	public var ignoreWarnings = false;
	var curNoteTypes:Array<String> = [];
	var undos = [];
	var redos = [];
	var eventStuff:Array<Dynamic> = [
		['', "Nothing. Yep, that's right."],
		['Dadbattle Spotlight', "Used in Dad Battle,\nValue 1: 0/1 = ON/OFF,\n2 = Target Dad\n3 = Target BF"],
		['Hey!', "Plays the \"Hey!\" animation from Bopeebo,\nValue 1: BF = Only Boyfriend, GF = Only Girlfriend,\nSomething else = Both.\nValue 2: Custom animation duration,\nleave it blank for 0.6s"],
		['Set GF Speed', "Sets GF head bopping speed,\nValue 1: 1 = Normal speed,\n2 = 1/2 speed, 4 = 1/4 speed etc.\nUsed on Fresh during the beatbox parts.\n\nWarning: Value must be integer!"],
		['Philly Glow', "Exclusive to Week 3\nValue 1: 0/1/2 = OFF/ON/Reset Gradient\n \nNo, i won't add it to other weeks."],
		['Kill Henchmen', "For Mom's songs, don't use this please, i love them :("],
		['Add Camera Zoom', "Used on MILF on that one \"hard\" part\nValue 1: Camera zoom add (Default: 0.015)\nValue 2: UI zoom add (Default: 0.03)\nLeave the values blank if you want to use Default."],
		['BG Freaks Expression', "Should be used only in \"school\" Stage!"],
		['Trigger BG Ghouls', "Should be used only in \"schoolEvil\" Stage!"],
		['Play Animation', "Plays an animation on a Character,\nonce the animation is completed,\nthe animation changes to Idle\n\nValue 1: Animation to play.\nValue 2: Character (Dad, BF, GF)"],
		['Camera Follow Pos', "Value 1: X\nValue 2: Y\n\nThe camera won't change the follow point\nafter using this, for getting it back\nto normal, leave both values blank."],
		['Alt Idle Animation', "Sets a specified suffix after the idle animation name.\nYou can use this to trigger 'idle-alt' if you set\nValue 2 to -alt\n\nValue 1: Character to set (Dad, BF or GF)\nValue 2: New suffix (Leave it blank to disable)"],
		['Screen Shake', "Value 1: Camera shake\nValue 2: HUD shake\n\nEvery value works as the following example: \"1, 0.05\".\nThe first number (1) is the duration.\nThe second number (0.05) is the intensity."],
		['Change Character', "Value 1: Character to change (Dad, BF, GF)\nValue 2: New character's name"],
		['Change Scroll Speed', "Value 1: Scroll Speed Multiplier (1 is default, maximum effective scroll speed is 100)\nValue 2: Time it takes to change fully in seconds."],
		['Set Property', "Value 1: Variable name\nValue 2: New value"],
		['Play Sound', "Value 1: Sound file name\nValue 2: Volume (Default: 1), ranges from 0 to 1"]
	];

	var _file:FileReference;
	var UI_box:FlxUITabMenu;

	public static var goToPlayState:Bool = false;
	public static var curSec:Int = 0;
	public static var lastSection:Int = 0;
	private static var lastSong:String = '';

	var bpmTxt:FlxText;

	var camPos:FlxObject;
	var strumLine:FlxSprite;
	var quant:AttachedSprite;
	var strumLineNotes:FlxTypedGroup<StrumNote>;
	var curSong:String = 'Test';
	var amountSteps:Int = 0;
	var bullshitUI:FlxGroup;

	var highlight:FlxSprite;

	public static var GRID_SIZE:Int = 40;
	var CAM_OFFSET:Int = 360;

	var dummyArrow:FlxSprite;

	var curRenderedSustains:FlxTypedGroup<FlxSprite>;
	var curRenderedNotes:FlxTypedGroup<Note>;
	var curRenderedNoteType:FlxTypedGroup<FlxText>;

	var nextRenderedSustains:FlxTypedGroup<FlxSprite>;
	var nextRenderedNotes:FlxTypedGroup<Note>;

	// Performance & Caching System
	var renderDensity:Int = 1024;
	var removeOverlapThreshold:Int = 2;
	var overlapPixelStepper:FlxUINumericStepper;
	var noteDensityStepper:FlxUINumericStepper;
	var noteAlphaStepper:FlxUINumericStepper;
	var renderLimitStepper:FlxUINumericStepper;
	var showNotesCheckbox:FlxUICheckBox;
	var showEventsCheckbox:FlxUICheckBox;
	public var noteAlpha:Float = 1.0;
	public var showNotes:Bool = true;
	public var showEvents:Bool = true;
	public var noteDensity:Int = 1;
	private var noteRenderDirty:Bool = true;
	private static inline var MAX_RENDERED_NOTES:Int = 8192;
	private static inline var NOTE_RENDER_PADDING:Float = 260;
	// Target two hundred million chart rows per second. Actual throughput is
	// still bounded by the 5 ms per-frame work budget and available CPU/memory.
	private static inline var NOTE_SPAM_RATE_PER_SECOND:Float = 200000000.0;
	// Up to 10M rows may be processed in one frame when rate debt accumulates;
	// the time budget below normally stops the loop much earlier.
	private static inline var MAX_SPAM_BATCH_PER_FRAME:Int = 10000000;
	// Spam requests and individual sections use the configured 64-bit ceiling;
	// the complete chart has its own separate total-count safety ceiling below.
	private static var MAX_SPAM_REQUEST_COUNT:Int64 = Int64.parseString("5000000000");
	private static var MAX_SECTION_NOTE_COUNT:Int64 = Int64.parseString("5000000000");
	private static inline var MAX_SPAM_REQUEST_FLOAT:Float = 5000000000.0;
	private static inline var SPAM_FRAME_BUDGET_MS:Float = 5.0;
	private static inline var SPAM_MAX_CATCHUP_SECONDS:Float = 0.05;
	// Commit notes in compact batches instead of calling appendEncoded once per row.
	// The wall-clock budget is checked between batches to keep editor frames responsive.
	private static inline var SPAM_GENERATED_BATCH_MIN:Int = 4096;
	private static inline var SPAM_GENERATED_BATCH_MID:Int = 16384;
	private static inline var SPAM_GENERATED_BATCH_MAX:Int = 65536;
	// Reserve in bounded chunks: a million-row request reserves its outer array
	// once, while multi-billion requests do not reserve all memory immediately.
	private static inline var SPAM_RESERVE_CHUNK_SIZE:Int = 1000000;
	// Legacy editor commands that require Array<Dynamic> rows must not expand
	// an enormous packed section all at once. This is not a chart/spam limit.
	private static inline var MAX_LEGACY_EXPANSION_ROWS:Int = 2000000;
	private var pendingSpamRateAccumulator:Float = 0;
	private var lastSpamProcessTimestamp:Float = 0;
	// Haxe/C++ Int is signed 32-bit. Keep note counts and spam jobs in range.
	private static var MAX_CHART_NOTE_COUNT:Int64 = Int64.parseString("5000000000");
	private static inline var MAX_SPAM_MULTIPLIER:Float = 5000000000.0;

	// The HUD sums section array lengths, not individual note rows. Cache the
	// section-count pass so chart edits are the only reason it is repeated.
	private var cachedTotalNoteCount:Int64 = Int64.ofInt(0);
	private var noteCountCacheValid:Bool = false;
	// Spam-generated notes stay in typed column buffers instead of allocating
	// one Array<Dynamic> for every row. Legacy chart rows remain untouched.
	private var packedSpamSections:Map<Int, PackedNoteBuffer> = new Map<Int, PackedNoteBuffer>();

	// Large note-spam jobs are generated incrementally to avoid freezing the editor.
	private var pendingSpamCount:Int64 = Int64.ofInt(0);
	private var pendingSpamSection:Int = -1;
	private var pendingSpamTime:Float = 0;
	private var pendingSpamData:Int = 0;
	private var pendingSpamSpacing:Float = 0;
	private var pendingSpamSideOffset:Int = 0;
	private var pendingSpamType:Int = 0;
	// HaxeFlixel normally stops updating when the window loses focus if
	// FlxG.autoPause is true. Temporarily override that only while a spam job
	// is active, so the editor keeps generating while another app is focused.
	private var spamBackgroundModeActive:Bool = false;
	private var spamPreviousAutoPause:Bool = true;
	private var lastChartUpdateMs:Float = 0;
	private var lastChartDrawMs:Float = 0;
	private var lastChartGridMs:Float = 0;
	private var lastEventIndexMs:Float = 0;
	private var lastWaveformMs:Float = 0;
	private var lastSpamBatchMs:Float = 0;
	private var lastSpamBatchRows:Int = 0;
	// Live throughput diagnostics. This reports actual generated rows/sec,
	// separately from the Spam Count (rows requested for one click).
	private var spamRateWindowStart:Float = 0;
	private var spamRateWindowRows:Int = 0;
	private var spamJobStartTimestamp:Float = 0;
	private var spamJobGeneratedRows:Int64 = Int64.ofInt(0);
	private var currentMeasuredSpamRate:Int = 0;
	private var lastMeasuredSpamRate:Int = 0;
	private var hudRefreshTimer:Float = 0;
	private var lastEditorHudText:String = '';
	private var playedSound:Array<Bool> = [false, false, false, false];

	#if sys
	private var splitChartSaveJob:SplitChartSaveJob = null;
	private var splitSaveDialog:FileDialog = null;
	private var splitSavePromptOpen:Bool = false;
	private var splitSavePreviousUiActive:Bool = true;
	private var splitSaveMusicWasPlaying:Bool = false;
	private var splitSaveCancelRequested:Bool = false;
	#end

	// The BPM map is ordered by songTime. Keep a cursor while playback moves
	// forward instead of scanning every BPM change on every editor frame.
	private var cachedBpmMap:Array<BPMChangeEvent> = null;
	private var cachedBpmMapIndex:Int = -1;
	private var cachedBpmMapTime:Float = -1.0e30;

	// AudioBuffer.data.toBytes() copies the entire decoded audio buffer. Reuse
	// that copy while the same audio buffer is active.
	private var waveformBufferCache:AudioBuffer = null;
	private var waveformBytesCache:Bytes = null;

	private var sectionDensityCache:Map<Int, Map<Int, Array<Array<Dynamic>>>> = new Map();
	private var sectionDensityCacheDirty:Map<Int, Bool> = new Map();
	private var cachedSectionStarts:Array<Float> = [];
	private var sectionCacheDirty:Bool = true;

	// Event markers are indexed once by section so updateGrid never scans the
	// complete event list twice just to find markers for the visible sections.
	private var eventSectionCache:Map<Int, Array<Dynamic>> = new Map();
	private var eventSectionCacheValid:Bool = false;

	// Note Spamming Controls
	var check_stackActive:FlxUICheckBox;
	var stepperStackNum:FlxUINumericStepper;
	var stepperStackOffset:FlxUINumericStepper;
	var stepperStackSideOffset:FlxUINumericStepper;
	var stepperShrinkAmount:FlxUINumericStepper;

	var gridBG:FlxSprite;
	var nextGridBG:FlxSprite;

	var daquantspot = 0;
	var curEventSelected:Int = 0;
	var curUndoIndex = 0;
	var curRedoIndex = 0;
	var _song:SwagSong;

	var curSelectedNote:Array<Dynamic> = null;
	var playbackSpeed:Float = 1;

	var vocals:FlxSound = null;
	var opponentVocals:FlxSound = null;

	var leftIcon:HealthIcon;
	var rightIcon:HealthIcon;

	var value1InputText:FlxUIInputText;
	var value2InputText:FlxUIInputText;
	var currentSongName:String;

	var zoomTxt:FlxText;

	var zoomList:Array<Float> = [0.25, 0.5, 1, 2, 3, 4, 6, 8, 12, 16, 24];
	var curZoom:Int = 2;

	private var blockPressWhileTypingOn:Array<FlxUIInputText> = [];
	private var blockPressWhileTypingOnStepper:Array<FlxUINumericStepper> = [];
	private var blockPressWhileScrolling:Array<FlxUIDropDownMenu> = [];

	var waveformSprite:FlxSprite;
	var gridLayer:FlxTypedGroup<FlxSprite>;

	public static var quantization:Int = 16;
	public static var curQuant = 3;

	public var quantizations:Array<Int> = [4, 8, 12, 16, 20, 24, 32, 48, 64, 96, 192];

	var text:String = "";
	public static var vortex:Bool = false;
	public var mouseQuant:Bool = false;

	override function create()
	{
		if (PlayState.SONG != null)
			_song = PlayState.SONG;
		else
		{
			Difficulty.resetList();
			_song = {
				song: 'Test',
				notes: [],
				events: [],
				bpm: 150.0,
				needsVoices: true,
				player1: 'bf',
				player2: 'dad',
				gfVersion: 'gf',
				speed: 1,
				stage: 'stage'
			};
			addSection();
			PlayState.SONG = _song;
		}
		_song.bpm = Song.clampBpm(_song.bpm);
		_song.speed = Song.clampScrollSpeed(_song.speed);
		for (section in _song.notes)
			if (section != null && section.changeBPM) section.bpm = Song.clampBpm(section.bpm);

		#if DISCORD_ALLOWED
		updatePresenceCounter();
		#end

		vortex = FlxG.save.data.chart_vortex;
		ignoreWarnings = FlxG.save.data.ignoreWarnings;
		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.scrollFactor.set();
		bg.color = 0xFF222222;
		add(bg);

		gridLayer = new FlxTypedGroup<FlxSprite>();
		add(gridLayer);

		waveformSprite = new FlxSprite(GRID_SIZE, 0).makeGraphic(1, 1, 0x00FFFFFF);
		add(waveformSprite);

		var eventIcon:FlxSprite = new FlxSprite(-GRID_SIZE - 5, -90).loadGraphic(Paths.image('eventArrow'));
		eventIcon.antialiasing = ClientPrefs.data.antialiasing;
		leftIcon = new HealthIcon('bf');
		rightIcon = new HealthIcon('dad');
		eventIcon.scrollFactor.set(1, 1);
		leftIcon.scrollFactor.set(1, 1);
		rightIcon.scrollFactor.set(1, 1);

		eventIcon.setGraphicSize(30, 30);
		leftIcon.setGraphicSize(0, 45);
		rightIcon.setGraphicSize(0, 45);

		add(eventIcon);
		add(leftIcon);
		add(rightIcon);

		leftIcon.setPosition(GRID_SIZE + 10, -100);
		rightIcon.setPosition(GRID_SIZE * 5.2, -100);

		curRenderedSustains = new FlxTypedGroup<FlxSprite>();
		curRenderedNotes = new FlxTypedGroup<Note>();
		curRenderedNoteType = new FlxTypedGroup<FlxText>();

		nextRenderedSustains = new FlxTypedGroup<FlxSprite>();
		nextRenderedNotes = new FlxTypedGroup<Note>();

		FlxG.mouse.visible = true;

		updateJsonData();
		currentSongName = Paths.formatToSongPath(_song.song);
		loadSong();
		reloadGridLayer();
		Conductor.bpm = _song.bpm;
		Conductor.mapBPMChanges(_song);
		if (curSec >= _song.notes.length) curSec = _song.notes.length - 1;

		bpmTxt = new FlxText(1000, 50, 0, "", 16);
		bpmTxt.scrollFactor.set();
		add(bpmTxt);

		strumLine = new FlxSprite(0, 50).makeGraphic(Std.int(GRID_SIZE * 9), 4);
		add(strumLine);

		quant = new AttachedSprite('chart_quant', 'chart_quant');
		quant.animation.addByPrefix('q', 'chart_quant', 0, false);
		quant.animation.play('q', true, false, 0);
		quant.sprTracker = strumLine;
		quant.xAdd = -32;
		quant.yAdd = 8;
		add(quant);

		strumLineNotes = new FlxTypedGroup<StrumNote>();
		for (i in 0...8) {
			var note:StrumNote = new StrumNote(GRID_SIZE * (i + 1), strumLine.y, i % 4, 0);
			note.setGraphicSize(GRID_SIZE, GRID_SIZE);
			note.updateHitbox();
			note.playAnim('static', true);
			strumLineNotes.add(note);
			note.scrollFactor.set(1, 1);
		}
		add(strumLineNotes);

		camPos = new FlxObject(0, 0, 1, 1);
		camPos.setPosition(strumLine.x + CAM_OFFSET, strumLine.y);

		dummyArrow = new FlxSprite().makeGraphic(GRID_SIZE, GRID_SIZE);
		dummyArrow.antialiasing = ClientPrefs.data.antialiasing;
		add(dummyArrow);

		var tabs = [
			{name: "Song", label: 'Song'},
			{name: "Section", label: 'Section'},
			{name: "Note", label: 'Note'},
			{name: "Events", label: 'Events'},
			{name: "Charting", label: 'Charting'},
			{name: "Density", label: 'Density'},
			{name: "Note Spamming", label: 'Note Spamming'},
			{name: "Data", label: 'Data'},
		];

		UI_box = new FlxUITabMenu(null, tabs, true);
		UI_box.resize(300, 400);
		UI_box.x = 640 + GRID_SIZE / 2;
		UI_box.y = 25;
		UI_box.scrollFactor.set();

		text =
		"W/S or Mouse Wheel - Change Conductor's strum time
		\nA/D - Go to the previous/next section
		\nLeft/Right - Change Snap
		\nUp/Down - Change Conductor's Strum Time with Snapping" +
		#if FLX_PITCH
		"\nLeft Bracket / Right Bracket - Change Song Playback Rate (SHIFT to go Faster)
		\nALT + Left Bracket / Right Bracket - Reset Song Playback Rate" +
		#end
		"\nHold Shift to move 4x faster
		\nHold Control and click on an arrow to select it
		\nZ/X - Zoom in/out
		\n
		\nEsc - Test your chart inside Chart Editor
		\nEnter - Play your chart
		\nQ/E - Decrease/Increase Note Sustain Length
		\nSpace - Stop/Resume song";

		var tipTextArray:Array<String> = text.split('\n');
		for (i in 0...tipTextArray.length) {
			var tipText:FlxText = new FlxText(UI_box.x, UI_box.y + UI_box.height + 8, 0, tipTextArray[i], 16);
			tipText.y += i * 12;
			tipText.setFormat(Paths.font("vcr.ttf"), 14, FlxColor.WHITE, LEFT);
			tipText.scrollFactor.set();
			add(tipText);
		}
		add(UI_box);

		addSongUI();
		addSectionUI();
		addNoteUI();
		addEventsUI();
		addChartingUI();
		addDensityUI();
		addNoteStackingUI();
		addDataUI();
		updateHeads();
		updateWaveform();

		add(curRenderedSustains);
		add(curRenderedNotes);
		add(curRenderedNoteType);
		add(nextRenderedSustains);
		add(nextRenderedNotes);

		if (lastSong != currentSongName) {
			changeSection();
		}
		lastSong = currentSongName;

		zoomTxt = new FlxText(10, 10, 0, "Zoom: 1 / 1", 16);
		zoomTxt.scrollFactor.set();
		add(zoomTxt);

		updateGrid();
		super.create();
	}

	var check_mute_inst:FlxUICheckBox = null;
	var check_mute_vocals:FlxUICheckBox = null;
	var check_mute_vocals_opponent:FlxUICheckBox = null;
	var check_vortex:FlxUICheckBox = null;
	var check_warnings:FlxUICheckBox = null;
	var playSoundBf:FlxUICheckBox = null;
	var playSoundDad:FlxUICheckBox = null;
	var UI_songTitle:FlxUIInputText;
	var stageDropDown:FlxUIDropDownMenu;
	#if FLX_PITCH
	var sliderRate:FlxUISlider;
	#end

	function addSongUI():Void
	{
		UI_songTitle = new FlxUIInputText(10, 10, 70, _song.song, 8);
		blockPressWhileTypingOn.push(UI_songTitle);

		var check_voices = new FlxUICheckBox(10, 25, null, null, "Has voice track", 100);
		check_voices.checked = _song.needsVoices;
		check_voices.callback = function() {
			_song.needsVoices = check_voices.checked;
		};

		var saveButton:FlxButton = new FlxButton(110, 8, "Save", function() {
			saveLevel();
		});

		var reloadSong:FlxButton = new FlxButton(saveButton.x + 90, saveButton.y, "Reload Audio", function() {
			currentSongName = Paths.formatToSongPath(UI_songTitle.text);
			updateJsonData();
			loadSong();
			updateWaveform();
		});

		var reloadSongJson:FlxButton = new FlxButton(reloadSong.x, saveButton.y + 30, "Reload JSON", function() {
			openSubState(new Prompt('This action will clear current progress.\n\nProceed?', 0, function() {
				loadJson(_song.song.toLowerCase());
			}, null, ignoreWarnings));
		});

		var loadAutosaveBtn:FlxButton = new FlxButton(reloadSongJson.x, reloadSongJson.y + 30, 'Load Autosave', function() {
			PlayState.SONG = Song.parseJSONshit(FlxG.save.data.autosave);
			MusicBeatState.resetState();
		});

		var loadEventJson:FlxButton = new FlxButton(loadAutosaveBtn.x, loadAutosaveBtn.y + 30, 'Load Events', function() {
			var songName:String = Paths.formatToSongPath(_song.song);
			if (Song.chartExists('events', songName))
			{
				clearEvents();
				var events:SwagSong = Song.loadFromJson('events', songName);
				_song.events = events.events;
				invalidateEventRenderCache();
				changeSection(curSec);
			}
		});

		var saveEvents:FlxButton = new FlxButton(110, reloadSongJson.y, 'Save Events', function() {
			saveEvents();
		});

		var clear_events:FlxButton = new FlxButton(320, 310, 'Clear events', function() {
			openSubState(new Prompt('This action will clear current progress.\n\nProceed?', 0, clearEvents, null, ignoreWarnings));
		});
		clear_events.color = FlxColor.RED;
		clear_events.label.color = FlxColor.WHITE;

		var clear_notes:FlxButton = new FlxButton(320, clear_events.y + 30, 'Clear notes', function() {
			openSubState(new Prompt('This action will clear current progress.\n\nProceed?', 0, function() {
				pendingSpamCount = 0;
				pendingSpamSection = -1;
				pendingSpamRateAccumulator = 0;
				lastSpamProcessTimestamp = 0;
				endSpamBackgroundMode();
				packedSpamSections = new Map<Int, PackedNoteBuffer>();
				for (sec in 0..._song.notes.length) {
					_song.notes[sec].sectionNotes = [];
				}
				invalidateRenderCache();
				updateGrid();
			}, null, ignoreWarnings));
		});
		clear_notes.color = FlxColor.RED;
		clear_notes.label.color = FlxColor.WHITE;

		var stepperBPM:FlxUINumericStepper = new FlxUINumericStepper(10, 70, 1, 1, 1, Song.MAX_BPM, 3);
		stepperBPM.value = Conductor.bpm;
		stepperBPM.name = 'song_bpm';
		blockPressWhileTypingOnStepper.push(stepperBPM);

		var stepperSpeed:FlxUINumericStepper = new FlxUINumericStepper(10, stepperBPM.y + 35, 0.1, 1, 0.1, Song.MAX_SCROLL_SPEED, 2);
		stepperSpeed.value = _song.speed;
		stepperSpeed.name = 'song_speed';
		blockPressWhileTypingOnStepper.push(stepperSpeed);

		#if MODS_ALLOWED
		var directories:Array<String> = [Paths.mods('characters/'), Paths.mods(Mods.currentModDirectory + '/characters/'), Paths.getSharedPath('characters/')];
		for (mod in Mods.getGlobalMods())
			directories.push(Paths.mods(mod + '/characters/'));
		#else
		var directories:Array<String> = [Paths.getSharedPath('characters/')];
		#end

		var tempArray:Array<String> = [];
		var characters:Array<String> = Mods.mergeAllTextsNamed('data/characterList.txt', Paths.getSharedPath());
		for (character in characters) {
			if (character.trim().length > 0)
				tempArray.push(character);
		}

		#if MODS_ALLOWED
		for (i in 0...directories.length) {
			var directory:String = directories[i];
			if (FileSystem.exists(directory)) {
				for (file in FileSystem.readDirectory(directory)) {
					var path = haxe.io.Path.join([directory, file]);
					if (!FileSystem.isDirectory(path) && file.endsWith('.json')) {
						var charToCheck:String = file.substr(0, file.length - 5);
						if (charToCheck.trim().length > 0 && !charToCheck.endsWith('-dead') && !tempArray.contains(charToCheck)) {
							tempArray.push(charToCheck);
							characters.push(charToCheck);
						}
					}
				}
			}
		}
		#end
		tempArray = [];

		var player1DropDown = new FlxUIDropDownMenu(10, stepperSpeed.y + 45, FlxUIDropDownMenu.makeStrIdLabelArray(characters, true), function(character:String) {
			_song.player1 = characters[Std.parseInt(character)];
			updateJsonData();
			updateHeads();
		});
		player1DropDown.selectedLabel = _song.player1;
		blockPressWhileScrolling.push(player1DropDown);

		var gfVersionDropDown = new FlxUIDropDownMenu(player1DropDown.x, player1DropDown.y + 40, FlxUIDropDownMenu.makeStrIdLabelArray(characters, true), function(character:String) {
			_song.gfVersion = characters[Std.parseInt(character)];
			updateJsonData();
			updateHeads();
		});
		gfVersionDropDown.selectedLabel = _song.gfVersion;
		blockPressWhileScrolling.push(gfVersionDropDown);

		var player2DropDown = new FlxUIDropDownMenu(player1DropDown.x, gfVersionDropDown.y + 40, FlxUIDropDownMenu.makeStrIdLabelArray(characters, true), function(character:String) {
			_song.player2 = characters[Std.parseInt(character)];
			updateJsonData();
			updateHeads();
		});
		player2DropDown.selectedLabel = _song.player2;
		blockPressWhileScrolling.push(player2DropDown);

		#if MODS_ALLOWED
		var directories:Array<String> = [Paths.mods('stages/'), Paths.mods(Mods.currentModDirectory + '/stages/'), Paths.getSharedPath('stages/')];
		for (mod in Mods.getGlobalMods())
			directories.push(Paths.mods(mod + '/stages/'));
		#else
		var directories:Array<String> = [Paths.getSharedPath('stages/')];
		#end

		var stageFile:Array<String> = Mods.mergeAllTextsNamed('data/stageList.txt', Paths.getSharedPath());
		var stages:Array<String> = [];
		for (stage in stageFile) {
			if (stage.trim().length > 0) {
				stages.push(stage);
			}
			tempArray.push(stage);
		}
		#if MODS_ALLOWED
		for (i in 0...directories.length) {
			var directory:String = directories[i];
			if (FileSystem.exists(directory)) {
				for (file in FileSystem.readDirectory(directory)) {
					var path = haxe.io.Path.join([directory, file]);
					if (!FileSystem.isDirectory(path) && file.endsWith('.json')) {
						var stageToCheck:String = file.substr(0, file.length - 5);
						if (stageToCheck.trim().length > 0 && !tempArray.contains(stageToCheck)) {
							tempArray.push(stageToCheck);
							stages.push(stageToCheck);
						}
					}
				}
			}
		}
		#end

		if (stages.length < 1) stages.push('stage');

		stageDropDown = new FlxUIDropDownMenu(player1DropDown.x + 140, player1DropDown.y, FlxUIDropDownMenu.makeStrIdLabelArray(stages, true), function(character:String) {
			_song.stage = stages[Std.parseInt(character)];
		});
		stageDropDown.selectedLabel = _song.stage;
		blockPressWhileScrolling.push(stageDropDown);

		var tab_group_song = new FlxUI(null, UI_box);
		tab_group_song.name = "Song";
		tab_group_song.add(UI_songTitle);
		tab_group_song.add(check_voices);
		tab_group_song.add(clear_events);
		tab_group_song.add(clear_notes);
		tab_group_song.add(saveButton);
		tab_group_song.add(saveEvents);
		tab_group_song.add(reloadSong);
		tab_group_song.add(reloadSongJson);
		tab_group_song.add(loadAutosaveBtn);
		tab_group_song.add(loadEventJson);
		tab_group_song.add(stepperBPM);
		tab_group_song.add(stepperSpeed);
		tab_group_song.add(new FlxText(stepperBPM.x, stepperBPM.y - 15, 0, 'Song BPM:'));
		tab_group_song.add(new FlxText(stepperBPM.x + 100, stepperBPM.y - 15, 0, 'Song Offset:'));
		tab_group_song.add(new FlxText(stepperSpeed.x, stepperSpeed.y - 15, 0, 'Song Speed:'));
		tab_group_song.add(new FlxText(player2DropDown.x, player2DropDown.y - 15, 0, 'Opponent:'));
		tab_group_song.add(new FlxText(gfVersionDropDown.x, gfVersionDropDown.y - 15, 0, 'Girlfriend:'));
		tab_group_song.add(new FlxText(player1DropDown.x, player1DropDown.y - 15, 0, 'Boyfriend:'));
		tab_group_song.add(new FlxText(stageDropDown.x, stageDropDown.y - 15, 0, 'Stage:'));
		tab_group_song.add(player2DropDown);
		tab_group_song.add(gfVersionDropDown);
		tab_group_song.add(player1DropDown);
		tab_group_song.add(stageDropDown);

		UI_box.addGroup(tab_group_song);
		initPsychCamera().follow(camPos, LOCKON, 999);
	}

	var stepperBeats:FlxUINumericStepper;
	var check_mustHitSection:FlxUICheckBox;
	var check_gfSection:FlxUICheckBox;
	var check_changeBPM:FlxUICheckBox;
	var stepperSectionBPM:FlxUINumericStepper;
	var check_altAnim:FlxUICheckBox;

	var sectionToCopy:Int = 0;
	var notesCopied:Array<Dynamic>;

	function addSectionUI():Void
	{
		var tab_group_section = new FlxUI(null, UI_box);
		tab_group_section.name = 'Section';

		check_mustHitSection = new FlxUICheckBox(10, 15, null, null, "Must hit section", 100);
		check_mustHitSection.name = 'check_mustHit';
		check_mustHitSection.checked = _song.notes[curSec].mustHitSection;

		check_gfSection = new FlxUICheckBox(10, check_mustHitSection.y + 22, null, null, "GF section", 100);
		check_gfSection.name = 'check_gf';
		check_gfSection.checked = _song.notes[curSec].gfSection;

		check_altAnim = new FlxUICheckBox(check_gfSection.x + 120, check_gfSection.y, null, null, "Alt Animation", 100);
		check_altAnim.checked = _song.notes[curSec].altAnim;

		stepperBeats = new FlxUINumericStepper(10, 100, 1, 4, 1, 7, 2);
		stepperBeats.value = getSectionBeats();
		stepperBeats.name = 'section_beats';
		blockPressWhileTypingOnStepper.push(stepperBeats);
		check_altAnim.name = 'check_altAnim';

		check_changeBPM = new FlxUICheckBox(10, stepperBeats.y + 30, null, null, 'Change BPM', 100);
		check_changeBPM.checked = _song.notes[curSec].changeBPM;
		check_changeBPM.name = 'check_changeBPM';

		stepperSectionBPM = new FlxUINumericStepper(10, check_changeBPM.y + 20, 1, Conductor.bpm, 1, Song.MAX_BPM, 1);
		if (check_changeBPM.checked) {
			stepperSectionBPM.value = _song.notes[curSec].bpm;
		} else {
			stepperSectionBPM.value = Conductor.bpm;
		}
		stepperSectionBPM.name = 'section_bpm';
		blockPressWhileTypingOnStepper.push(stepperSectionBPM);

		var check_eventsSec:FlxUICheckBox = null;
		var check_notesSec:FlxUICheckBox = null;
		var copyButton:FlxButton = new FlxButton(10, 190, "Copy Section", function() {
			if (!materializePackedSpamSection(curSec)) return;
			notesCopied = [];
			sectionToCopy = curSec;
			for (i in 0..._song.notes[curSec].sectionNotes.length) {
				var note:Array<Dynamic> = _song.notes[curSec].sectionNotes[i];
				notesCopied.push(note);
			}

			var startThing:Float = sectionStartTime();
			var endThing:Float = sectionStartTime(1);
			for (event in _song.events) {
				var strumTime:Float = event[0];
				if (endThing > event[0] && event[0] >= startThing) {
					var copiedEventArray:Array<Dynamic> = [];
					for (i in 0...event[1].length) {
						var eventToPush:Array<Dynamic> = event[1][i];
						copiedEventArray.push([eventToPush[0], eventToPush[1], eventToPush[2]]);
					}
					notesCopied.push([strumTime, -1, copiedEventArray]);
				}
			}
		});

		var pasteButton:FlxButton = new FlxButton(copyButton.x + 100, copyButton.y, "Paste Section", function() {
			if (!materializePackedSpamSection(curSec)) return;
			if (notesCopied == null || notesCopied.length < 1) return;

			var addToTime:Float = Conductor.stepCrochet * (getSectionBeats() * 4 * (curSec - sectionToCopy));

			for (note in notesCopied) {
				var copiedNote:Array<Dynamic> = [];
				var newStrumTime:Float = note[0] + addToTime;
				if (note[1] < 0) {
					if (check_eventsSec.checked) {
						var copiedEventArray:Array<Dynamic> = [];
						for (i in 0...note[2].length) {
							var eventToPush:Array<Dynamic> = note[2][i];
							copiedEventArray.push([eventToPush[0], eventToPush[1], eventToPush[2]]);
						}
						_song.events.push([newStrumTime, copiedEventArray]);
					}
				} else {
					if (check_notesSec.checked) {
						if (note[4] != null)
							copiedNote = [newStrumTime, note[1], note[2], note[3], note[4]];
						else
							copiedNote = [newStrumTime, note[1], note[2], note[3]];

						appendNoteToSection(curSec, copiedNote);
					}
				}
			}
			if (check_eventsSec.checked) invalidateEventRenderCache();
			invalidateRenderCache(curSec);
			updateGrid();
		});

		var clearSectionButton:FlxButton = new FlxButton(pasteButton.x + 100, pasteButton.y, "Clear", function() {
			if (check_notesSec.checked) {
				if (pendingSpamSection == curSec) {
					pendingSpamCount = 0;
					pendingSpamSection = -1;
					pendingSpamRateAccumulator = 0;
					lastSpamProcessTimestamp = 0;
					endSpamBackgroundMode();
					FlxG.log.add('Background spam for the cleared section was cancelled.');
				}
				packedSpamSections.remove(curSec);
				_song.notes[curSec].sectionNotes = [];
			}

			if (check_eventsSec.checked) {
				var startThing:Float = sectionStartTime();
				var endThing:Float = sectionStartTime(1);
				var writeIndex:Int = 0;
				var originalLength:Int = _song.events.length;
				for (readIndex in 0...originalLength) {
					var event:Array<Dynamic> = _song.events[readIndex];
					var removeEvent:Bool = event != null && event.length > 0 && event[0] != null && endThing > event[0] && event[0] >= startThing;
					if (!removeEvent) {
						_song.events[writeIndex] = event;
						writeIndex++;
					}
				}
				while (_song.events.length > writeIndex) _song.events.pop();
				if (writeIndex != originalLength) invalidateEventRenderCache();
			}
			invalidateRenderCache(curSec);
			updateGrid();
			updateNoteUI();
		});
		clearSectionButton.color = FlxColor.RED;
		clearSectionButton.label.color = FlxColor.WHITE;
		
		check_notesSec = new FlxUICheckBox(10, clearSectionButton.y + 25, null, null, "Notes", 100);
		check_notesSec.checked = true;
		check_eventsSec = new FlxUICheckBox(check_notesSec.x + 100, check_notesSec.y, null, null, "Events", 100);
		check_eventsSec.checked = true;

		var swapSection:FlxButton = new FlxButton(10, check_notesSec.y + 40, "Swap section", function() {
			var packed:PackedNoteBuffer = getPackedSpamSection(curSec);
			if (packed != null) packed.swapSides();
			for (i in 0..._song.notes[curSec].sectionNotes.length) {
				var note:Array<Dynamic> = _song.notes[curSec].sectionNotes[i];
				note[1] = (note[1] + 4) % 8;
				_song.notes[curSec].sectionNotes[i] = note;
			}
			invalidateRenderCache(curSec);
			updateGrid();
		});

		var stepperCopy:FlxUINumericStepper = null;
		var copyLastButton:FlxButton = new FlxButton(10, swapSection.y + 30, "Copy last section", function() {
			var value:Int = Std.int(stepperCopy.value);
			if (value == 0) return;

			var daSec = FlxMath.maxInt(curSec, value);
			if (!materializePackedSpamSection(daSec - value) || !materializePackedSpamSection(daSec)) return;

			for (note in _song.notes[daSec - value].sectionNotes) {
				var strum = note[0] + Conductor.stepCrochet * (getSectionBeats(daSec) * 4 * value);
				var copiedNote:Array<Dynamic> = [strum, note[1], note[2], note[3]];
				if (!appendNoteToSection(daSec, copiedNote)) break;
			}

			var startThing:Float = sectionStartTime(-value);
			var endThing:Float = sectionStartTime(-value + 1);
			for (event in _song.events) {
				var strumTime:Float = event[0];
				if (endThing > event[0] && event[0] >= startThing) {
					strumTime += Conductor.stepCrochet * (getSectionBeats(daSec) * 4 * value);
					var copiedEventArray:Array<Dynamic> = [];
					for (i in 0...event[1].length) {
						var eventToPush:Array<Dynamic> = event[1][i];
						copiedEventArray.push([eventToPush[0], eventToPush[1], eventToPush[2]]);
					}
					_song.events.push([strumTime, copiedEventArray]);
				}
			}
			invalidateEventRenderCache();
			invalidateRenderCache(daSec);
			updateGrid();
		});
		copyLastButton.setGraphicSize(80, 30);
		copyLastButton.updateHitbox();
		
		stepperCopy = new FlxUINumericStepper(copyLastButton.x + 100, copyLastButton.y, 1, 1, -999, 999, 0);
		blockPressWhileTypingOnStepper.push(stepperCopy);

		var duetButton:FlxButton = new FlxButton(10, copyLastButton.y + 45, "Duet Notes", function() {
			if (!materializePackedSpamSection(curSec)) return;
			var duetNotes:Array<Array<Dynamic>> = [];
			for (note in _song.notes[curSec].sectionNotes) {
				var boob = note[1];
				if (boob > 3) boob -= 4;
				else boob += 4;

				var copiedNote:Array<Dynamic> = [note[0], boob, note[2], note[3]];
				duetNotes.push(copiedNote);
			}

			for (i in duetNotes) {
				if (!appendNoteToSection(curSec, i)) break;
			}
			invalidateRenderCache(curSec);
			updateGrid();
		});
		var mirrorButton:FlxButton = new FlxButton(duetButton.x + 100, duetButton.y, "Mirror Notes", function() {
			var packed:PackedNoteBuffer = getPackedSpamSection(curSec);
			if (packed != null) packed.mirrorLanes();
			for (note in _song.notes[curSec].sectionNotes) {
				var boob = note[1] % 4;
				boob = 3 - boob;
				if (note[1] > 3) boob += 4;
				note[1] = boob;
			}
			invalidateRenderCache(curSec);
			updateGrid();
		});

		tab_group_section.add(new FlxText(stepperBeats.x, stepperBeats.y - 15, 0, 'Beats per Section:'));
		tab_group_section.add(stepperBeats);
		tab_group_section.add(stepperSectionBPM);
		tab_group_section.add(check_mustHitSection);
		tab_group_section.add(check_gfSection);
		tab_group_section.add(check_altAnim);
		tab_group_section.add(check_changeBPM);
		tab_group_section.add(copyButton);
		tab_group_section.add(pasteButton);
		tab_group_section.add(clearSectionButton);
		tab_group_section.add(check_notesSec);
		tab_group_section.add(check_eventsSec);
		tab_group_section.add(swapSection);
		tab_group_section.add(stepperCopy);
		tab_group_section.add(copyLastButton);
		tab_group_section.add(duetButton);
		tab_group_section.add(mirrorButton);

		UI_box.addGroup(tab_group_section);
	}

	var stepperSusLength:FlxUINumericStepper;
	var strumTimeInputText:FlxUIInputText;
	var noteTypeDropDown:FlxUIDropDownMenu;
	var currentType:Int = 0;

	function addNoteUI():Void
	{
		var tab_group_note = new FlxUI(null, UI_box);
		tab_group_note.name = 'Note';

		stepperSusLength = new FlxUINumericStepper(10, 25, Conductor.stepCrochet / 2, 0, 0, Conductor.stepCrochet * 64);
		stepperSusLength.value = 0;
		stepperSusLength.name = 'note_susLength';
		blockPressWhileTypingOnStepper.push(stepperSusLength);

		strumTimeInputText = new FlxUIInputText(10, 65, 180, "0");
		tab_group_note.add(strumTimeInputText);
		blockPressWhileTypingOn.push(strumTimeInputText);

		var key:Int = 0;
		while (key < noteTypeList.length) {
			curNoteTypes.push(noteTypeList[key]);
			key++;
		}

		#if sys
		var foldersToCheck:Array<String> = Mods.directoriesWithFile(Paths.getSharedPath(), 'custom_notetypes/');
		for (folder in foldersToCheck)
			for (file in FileSystem.readDirectory(folder)) {
				var fileName:String = file.toLowerCase().trim();
				var wordLen:Int = 4;
				if ((#if LUA_ALLOWED fileName.endsWith('.lua') || #end
					#if HSCRIPT_ALLOWED (fileName.endsWith('.hx') && (wordLen = 3) == 3) || #end
					fileName.endsWith('.txt')) && fileName != 'readme.txt') {
					var fileToCheck:String = file.substr(0, file.length - wordLen);
					if (!curNoteTypes.contains(fileToCheck)) {
						curNoteTypes.push(fileToCheck);
						key++;
					}
				}
			}
		#end

		var displayNameList:Array<String> = curNoteTypes.copy();
		for (i in 1...displayNameList.length) {
			displayNameList[i] = i + '. ' + displayNameList[i];
		}

		noteTypeDropDown = new FlxUIDropDownMenu(10, 105, FlxUIDropDownMenu.makeStrIdLabelArray(displayNameList, true), function(character:String) {
			currentType = Std.parseInt(character);
			if (curSelectedNote != null && curSelectedNote[1] > -1) {
				curSelectedNote[3] = curNoteTypes[currentType];
				updateGrid();
			}
		});
		blockPressWhileScrolling.push(noteTypeDropDown);

		tab_group_note.add(new FlxText(10, 10, 0, 'Sustain length:'));
		tab_group_note.add(new FlxText(10, 50, 0, 'Strum time (in miliseconds):'));
		tab_group_note.add(new FlxText(10, 90, 0, 'Note type:'));
		tab_group_note.add(stepperSusLength);
		tab_group_note.add(strumTimeInputText);
		tab_group_note.add(noteTypeDropDown);

		UI_box.addGroup(tab_group_note);
	}

	function addNoteStackingUI():Void
	{
		var tab_group_stacking = new FlxUI(null, UI_box);
		tab_group_stacking.name = 'Note Spamming';

		check_stackActive = new FlxUICheckBox(10, 10, null, null, "Enable EZ Spam Mode", 100);
		check_stackActive.name = 'check_stackActive';

		stepperStackNum = new FlxUINumericStepper(10, 30, 1, 1, 0, MAX_SPAM_REQUEST_FLOAT, 4);
		stepperStackNum.name = 'stack_count';
		blockPressWhileTypingOnStepper.push(stepperStackNum);

		var doubleSpamNum:FlxButton = new FlxButton(stepperStackNum.x, stepperStackNum.y + 20, 'x2 Amount', function() {
			stepperStackNum.value = Math.min(MAX_SPAM_REQUEST_FLOAT, stepperStackNum.value * 2);
		});
		doubleSpamNum.setGraphicSize(Std.int(doubleSpamNum.width), Std.int(doubleSpamNum.height));
		doubleSpamNum.color = FlxColor.GREEN;
		doubleSpamNum.label.color = FlxColor.WHITE;

		var halfSpamNum:FlxButton = new FlxButton(doubleSpamNum.x + doubleSpamNum.width + 20, doubleSpamNum.y, 'x0.5 Amount', function() {
			stepperStackNum.value /= 2;
		});
		halfSpamNum.setGraphicSize(Std.int(halfSpamNum.width), Std.int(halfSpamNum.height));
		halfSpamNum.color = FlxColor.RED;
		halfSpamNum.label.color = FlxColor.WHITE;

		stepperStackOffset = new FlxUINumericStepper(10, 80, 1, 1, 0, MAX_SPAM_MULTIPLIER, 0);
		stepperStackOffset.name = 'stack_offset';
		blockPressWhileTypingOnStepper.push(stepperStackOffset);

		var doubleSpamMult:FlxButton = new FlxButton(stepperStackOffset.x, stepperStackOffset.y + 20, 'x2 SM', function() {
			stepperStackOffset.value = clampSpamMultiplier(stepperStackOffset.value * 2);
		});
		doubleSpamMult.color = FlxColor.GREEN;
		doubleSpamMult.label.color = FlxColor.WHITE;

		var halfSpamMult:FlxButton = new FlxButton(doubleSpamMult.x + doubleSpamMult.width + 20, doubleSpamMult.y, 'x0.5 SM', function() {
			stepperStackOffset.value = clampSpamMultiplier(stepperStackOffset.value / 2);
		});
		halfSpamMult.setGraphicSize(Std.int(halfSpamMult.width), Std.int(halfSpamMult.height));
		halfSpamMult.color = FlxColor.RED;
		halfSpamMult.label.color = FlxColor.WHITE;

		var cancelBackgroundSpamButton:FlxButton = new FlxButton(270, 10, 'Cancel Background Spam', function() {
			cancelPendingNoteSpam();
		});
		cancelBackgroundSpamButton.color = FlxColor.RED;
		cancelBackgroundSpamButton.label.color = FlxColor.WHITE;

		stepperStackSideOffset = new FlxUINumericStepper(10, 140, 1, 0, -9999, 9999);
		stepperStackSideOffset.name = 'stack_sideways';
		blockPressWhileTypingOnStepper.push(stepperStackSideOffset);

		stepperShrinkAmount = new FlxUINumericStepper(10, stepperStackSideOffset.y + 30, 1, 1, 0, 8192, 4);
		stepperShrinkAmount.name = 'shrinker_amount';
		blockPressWhileTypingOnStepper.push(stepperShrinkAmount);

		var doubleShrinker:FlxButton = new FlxButton(stepperShrinkAmount.x, stepperShrinkAmount.y + 20, 'x2 SH', function() {
			stepperShrinkAmount.value *= 2;
		});
		doubleShrinker.color = FlxColor.GREEN;
		doubleShrinker.label.color = FlxColor.WHITE;

		var halfShrinker:FlxButton = new FlxButton(doubleShrinker.x + doubleShrinker.width + 20, doubleShrinker.y, 'x0.5 SH', function() {
			stepperShrinkAmount.value /= 2;
		});
		halfShrinker.setGraphicSize(Std.int(halfShrinker.width), Std.int(halfShrinker.height));
		halfShrinker.color = FlxColor.RED;
		halfShrinker.label.color = FlxColor.WHITE;

		var shrinkNotesButton:FlxButton = new FlxButton(10, doubleShrinker.y + 30, "Stretch Notes", function() {
			var minimumTime:Float = sectionStartTime();
			for (i in 0..._song.notes[curSec].sectionNotes.length) {
				var note:Array<Dynamic> = _song.notes[curSec].sectionNotes[i];
				if (note[2] > 0) note[2] *= stepperShrinkAmount.value;
				var originalStartTime:Float = note[0] - sectionStartTime();
				var stretchedStartTime:Float = originalStartTime * stepperShrinkAmount.value;
				var newStartTime:Float = sectionStartTime() + stretchedStartTime;
				note[0] = Math.max(newStartTime, minimumTime);
				_song.notes[curSec].sectionNotes[i] = note;
			}
			var packed:PackedNoteBuffer = getPackedSpamSection(curSec);
			if (packed != null) packed.stretchFrom(minimumTime, sectionStartTime(), stepperShrinkAmount.value);
			invalidateRenderCache(curSec);
			updateGrid();
		});

		var stepperShiftSteps:FlxUINumericStepper = new FlxUINumericStepper(10, shrinkNotesButton.y + 30, 1, 1, -8192, 8192, 4);
		stepperShiftSteps.name = 'shifter_amount';
		blockPressWhileTypingOnStepper.push(stepperShiftSteps);

		var shiftNotesButton:FlxButton = new FlxButton(10, stepperShiftSteps.y + 20, "Shift Notes", function() {
			var shiftDelta:Float = (stepperShiftSteps.value) * (15000 / Conductor.bpm);
			for (i in 0..._song.notes[curSec].sectionNotes.length) {
				_song.notes[curSec].sectionNotes[i][0] += shiftDelta;
			}
			var packed:PackedNoteBuffer = getPackedSpamSection(curSec);
			if (packed != null) packed.shiftTimes(shiftDelta);
			invalidateRenderCache(curSec);
			updateGrid();
		});

		var stepperDuplicateAmount:FlxUINumericStepper = new FlxUINumericStepper(10, shiftNotesButton.y + 30, 1, 1, 0, 32, 4);
		stepperDuplicateAmount.name = 'duplicater_amount';
		blockPressWhileTypingOnStepper.push(stepperDuplicateAmount);

		var dupeNotesButton:FlxButton = new FlxButton(10, stepperDuplicateAmount.y + 20, "Duplicate Notes", function() {
			if (!materializePackedSpamSection(curSec)) return;
			var copiedNotes:Array<Dynamic> = [];
			for (i in 0..._song.notes[curSec].sectionNotes.length) {
				var note:Array<Dynamic> = _song.notes[curSec].sectionNotes[i];
				copiedNotes.push(note);
			}
			var duplicateFull:Bool = false;
			for (_i in 1...Std.int(stepperDuplicateAmount.value) + 1) {
				for (i in 0...copiedNotes.length) {
					final copiedNote:Array<Dynamic> = [copiedNotes[i][0], copiedNotes[i][1], copiedNotes[i][2], copiedNotes[i][3]];
					copiedNote[0] += (stepperShiftSteps.value * _i) * (15000 / Conductor.bpm);
					if (!appendNoteToSection(curSec, copiedNote)) { duplicateFull = true; break; }
				}
				if (duplicateFull) break;
			}
			invalidateRenderCache(curSec);
			updateGrid();
		});

		tab_group_stacking.add(check_stackActive);
		tab_group_stacking.add(stepperStackNum);
		tab_group_stacking.add(stepperStackOffset);
		tab_group_stacking.add(stepperStackSideOffset);
		tab_group_stacking.add(stepperShrinkAmount);
		tab_group_stacking.add(stepperShiftSteps);
		tab_group_stacking.add(stepperDuplicateAmount);
		tab_group_stacking.add(doubleSpamNum);
		tab_group_stacking.add(halfSpamNum);
		tab_group_stacking.add(doubleSpamMult);
		tab_group_stacking.add(halfSpamMult);
		tab_group_stacking.add(cancelBackgroundSpamButton);
		tab_group_stacking.add(doubleShrinker);
		tab_group_stacking.add(halfShrinker);
		tab_group_stacking.add(shrinkNotesButton);
		tab_group_stacking.add(shiftNotesButton);
		tab_group_stacking.add(dupeNotesButton);

		tab_group_stacking.add(new FlxText(100, 30, 0, "Spam Count (32-bit maximum per click / section)"));
		tab_group_stacking.add(new FlxText(100, 80, 0, "Spam Multiplier (32-bit)"));
		tab_group_stacking.add(new FlxText(100, 140, 0, "Spam Scroll Amount"));
		tab_group_stacking.add(new FlxText(100, stepperShrinkAmount.y, 0, "Stretch Amount"));
		tab_group_stacking.add(new FlxText(100, stepperShiftSteps.y, 0, "Steps to Shift By"));
		tab_group_stacking.add(new FlxText(100, stepperDuplicateAmount.y, 0, "Amount of Duplicates"));

		UI_box.addGroup(tab_group_stacking);
	}

	function addDensityUI():Void
	{
		var tab_group_density = new FlxUI(null, UI_box);
		tab_group_density.name = 'Density';

		noteDensityStepper = new FlxUINumericStepper(10, 20, 16, noteDensity, 1, 32768, 0);
		noteDensityStepper.name = 'note_density';
		blockPressWhileTypingOnStepper.push(noteDensityStepper);

		noteAlphaStepper = new FlxUINumericStepper(10, 110, 0.1, noteAlpha, 0, 1, 1);
		noteAlphaStepper.name = 'note_alpha';
		blockPressWhileTypingOnStepper.push(noteAlphaStepper);

		showNotesCheckbox = new FlxUICheckBox(10, 150, null, null, "Show Notes", 100);
		showNotesCheckbox.checked = showNotes;
		showNotesCheckbox.callback = function() {
			showNotes = showNotesCheckbox.checked;
			noteRenderDirty = true;
			updateGrid();
		};

		// Events are separate chart objects; hiding note sprites must not leave
		// thousands of event-marker sprites being created in the background.
		showEventsCheckbox = new FlxUICheckBox(10, 172, null, null, "Show Events", 100);
		showEventsCheckbox.checked = showEvents;
		showEventsCheckbox.callback = function() {
			showEvents = showEventsCheckbox.checked;
			updateGrid();
		};

		renderLimitStepper = new FlxUINumericStepper(10, 222, 128, renderDensity, 128, MAX_RENDERED_NOTES, 0);
		renderLimitStepper.name = 'render_limit';
		blockPressWhileTypingOnStepper.push(renderLimitStepper);

		var resetDensityButton:FlxButton = new FlxButton(10, 55, 'Reset Cache', function() {
			invalidateRenderCache();
			updateGrid();
		});

		overlapPixelStepper = new FlxUINumericStepper(10, 282, 1, removeOverlapThreshold, 1, 20, 0);
		overlapPixelStepper.name = 'overlap_pixels';
		blockPressWhileTypingOnStepper.push(overlapPixelStepper);

		var removeOverlapButton:FlxButton = new FlxButton(10, 312, 'Remove Overlapped', function() {
			removeOverlapThreshold = Std.int(overlapPixelStepper.value);
			removeOverlappedNotes();
		});

		var refreshCounterButton:FlxButton = new FlxButton(160, 312, 'Refresh Counter', function() {
			updatePresenceCounter();
		});

		tab_group_density.add(new FlxText(10, 5, 0, 'Note Density Bucket (ms):'));
		tab_group_density.add(new FlxText(10, 80, 0, 'Larger buckets mean fewer scans.'));
		tab_group_density.add(noteDensityStepper);
		tab_group_density.add(resetDensityButton);
		tab_group_density.add(new FlxText(10, 95, 0, 'Note Transparency (0.0 - 1.0):'));
		tab_group_density.add(noteAlphaStepper);
		tab_group_density.add(showNotesCheckbox);
		tab_group_density.add(showEventsCheckbox);
		tab_group_density.add(new FlxText(10, 202, 0, 'Maximum rendered note heads:'));
		tab_group_density.add(renderLimitStepper);
		tab_group_density.add(new FlxText(10, 265, 0, 'Overlap Threshold (pixels):'));
		tab_group_density.add(overlapPixelStepper);
		tab_group_density.add(removeOverlapButton);
		tab_group_density.add(refreshCounterButton);

		UI_box.addGroup(tab_group_density);
	}

	function removeOverlappedNotes():Void
	{
		// Sorting/deduplicating is a legacy whole-array operation. Refuse to
		// expand very large compact buffers rather than risking an editor OOM.
		if (!materializeAllPackedSpamSections()) return;
		var removed:Int = 0;
		var thresholdMs:Float = (removeOverlapThreshold / GRID_SIZE) * Conductor.stepCrochet;

		for (section in _song.notes) {
			if (section == null || section.sectionNotes == null) continue;
			section.sectionNotes.sort(function(a, b) {
				if (a[0] < b[0]) return -1;
				if (a[0] > b[0]) return 1;
				if (a[1] < b[1]) return -1;
				if (a[1] > b[1]) return 1;
				return 0;
			});

			var i:Int = 0;
			while (i < section.sectionNotes.length - 1) {
				var noteA = section.sectionNotes[i];
				var noteB = section.sectionNotes[i + 1];
				if (noteA[1] == noteB[1] && Math.abs(noteA[0] - noteB[0]) < thresholdMs) {
					section.sectionNotes.splice(i + 1, 1);
					removed++;
				} else {
					i++;
				}
			}
		}

		if (removed > 0) {
			invalidateRenderCache();
			updateGrid();
			updatePresenceCounter();
		}
	}

	function updatePresenceCounter():Void
	{
		#if DISCORD_ALLOWED
		var count:Int64 = getNoteAmount();
		DiscordClient.changePresence("Chart Editor", '${StringTools.replace(_song.song, "-", " ")} (${formatCountWithCommas64(count)} Notes)');
		#end
	}

	private function getPackedSpamSection(sectionIndex:Int, create:Bool = false):PackedNoteBuffer
	{
		var packed:PackedNoteBuffer = packedSpamSections.get(sectionIndex);
		if (packed == null && create)
		{
			packed = new PackedNoteBuffer();
			packedSpamSections.set(sectionIndex, packed);
		}
		return packed;
	}

	private function getSectionNoteCount(sectionIndex:Int):Int64
	{
		if (_song == null || _song.notes == null || sectionIndex < 0 || sectionIndex >= _song.notes.length || _song.notes[sectionIndex] == null)
			return Int64.ofInt(0);
		var count:Int64 = Int64.ofInt(_song.notes[sectionIndex].sectionNotes == null ? 0 : _song.notes[sectionIndex].sectionNotes.length);
		var packed:PackedNoteBuffer = getPackedSpamSection(sectionIndex);
		if (packed != null) count += packed.length64;
		return count;
	}

	/**
	 * Convert one compact section back to legacy row arrays for an explicit
	 * legacy operation. Large expansions are refused to avoid recreating the
	 * per-row allocation spike that compact storage is designed to prevent.
	 */
	private function materializePackedSpamSection(sectionIndex:Int):Bool
	{
		var packed:PackedNoteBuffer = getPackedSpamSection(sectionIndex);
		if (packed == null || packed.length64 == Int64.ofInt(0)) return true;
		if (_song == null || _song.notes == null || sectionIndex < 0 || sectionIndex >= _song.notes.length || _song.notes[sectionIndex] == null) return false;
		var rows:Array<Dynamic> = _song.notes[sectionIndex].sectionNotes;
		var existingRows:Int = rows == null ? 0 : rows.length;
		var combinedRows:Int64 = Int64.ofInt(existingRows) + packed.length64;
		if (getNoteAmount() > Int64.ofInt(MAX_LEGACY_EXPANSION_ROWS) || combinedRows > Int64.ofInt(MAX_LEGACY_EXPANSION_ROWS))
		{
			FlxG.log.add('This legacy operation was cancelled: expanding packed rows in a chart above 2,000,000 notes could exhaust memory. The compact notes remain intact.');
			return false;
		}
		if (rows == null)
		{
			rows = [];
			_song.notes[sectionIndex].sectionNotes = rows;
		}
		#if cpp
		if (!reserveSpamSectionCapacity(rows, existingRows + Int64.toInt(packed.length64)))
		{
			FlxG.log.add('Could not expand compact note storage for this operation. The compact notes were kept intact.');
			return false;
		}
		#end
		packed.appendRowsTo(rows);
		packedSpamSections.remove(sectionIndex);
		return true;
	}

	private function materializeAllPackedSpamSections():Bool
	{
		if (_song == null || _song.notes == null) return false;
		var sectionIndices:Array<Int> = [];
		for (sectionIndex in packedSpamSections.keys()) sectionIndices.push(sectionIndex);
		for (sectionIndex in sectionIndices)
			if (!materializePackedSpamSection(sectionIndex)) return false;
		return true;
	}

	/** A detached legacy song snapshot. Only allowed for small charts. */
	private function buildSerializableSong():Dynamic
	{
		if (_song == null) return null;
		if (getNoteAmount() > Int64.ofInt(MAX_LEGACY_EXPANSION_ROWS)) return null;
		var snapshot:Dynamic = Reflect.copy(_song);
		var sections:Array<Dynamic> = [];
		if (_song.notes != null)
		{
			for (sectionIndex in 0..._song.notes.length)
			{
				var section:Dynamic = _song.notes[sectionIndex];
				if (section == null)
				{
					sections.push(null);
					continue;
				}
				var sectionCopy:Dynamic = Reflect.copy(section);
				var rows:Array<Dynamic> = section.sectionNotes == null ? [] : cast section.sectionNotes.copy();
				var packed:PackedNoteBuffer = getPackedSpamSection(sectionIndex);
				if (packed != null) packed.appendRowsTo(rows);
				Reflect.setField(sectionCopy, 'sectionNotes', rows);
				sections.push(sectionCopy);
			}
		}
		Reflect.setField(snapshot, 'notes', sections);
		return snapshot;
	}

	function getNoteAmount():Int64
	{
		if (noteCountCacheValid) return cachedTotalNoteCount;
		var count:Int64 = Int64.ofInt(0);
		if (_song != null && _song.notes != null) {
			for (sectionIndex in 0..._song.notes.length) {
				var sec = _song.notes[sectionIndex];
				if (sec != null && sec.sectionNotes != null) count += Int64.ofInt(sec.sectionNotes.length);
				var packed:PackedNoteBuffer = getPackedSpamSection(sectionIndex);
				if (packed != null) count += packed.length64;
			}
		}
		cachedTotalNoteCount = count;
		noteCountCacheValid = true;
		return cachedTotalNoteCount;
	}

	private function getGcMemoryLabel():String
	{
		#if cpp
		// MEM_INFO_CURRENT includes uncollected garbage, which helps distinguish
		// live chart storage from temporary allocation pressure during spam jobs.
		var currentBytes:Int = cpp.vm.Gc.memInfo(cpp.vm.Gc.MEM_INFO_CURRENT);
		if (currentBytes < 0) return ">=2,048 MB";
		return formatCountWithCommas(Std.int(currentBytes / 1048576)) + " MB";
		#else
		return "Unavailable";
		#end
	}

	private function getPackedSpamRowCount():Int64
	{
		var count:Int64 = Int64.ofInt(0);
		for (sectionIndex in packedSpamSections.keys())
		{
			var packed:PackedNoteBuffer = packedSpamSections.get(sectionIndex);
			if (packed != null) count += packed.length64;
		}
		return count;
	}

	private function getPackedStorageEstimate():String
	{
		// Estimate allocated segmented payload capacity, not just live rows.
		// Base storage is 20 bytes per row (Float64 time, Int32 lane, Float64
		// sustain); optional type columns add 4 bytes per row only in segments
		// that actually contain typed notes. Haxe container overhead is excluded.
		var bytes:Float = 0;
		for (sectionIndex in packedSpamSections.keys())
		{
			var packed:PackedNoteBuffer = packedSpamSections.get(sectionIndex);
			if (packed != null) bytes += packed.getEstimatedAllocatedBytes();
		}
		return Std.string(FlxMath.roundDecimal(bytes / 1048576.0, 1)) + ' MB';
	}

	private function getPackedSegmentCount():Int
	{
		var count:Int = 0;
		for (sectionIndex in packedSpamSections.keys())
		{
			var packed:PackedNoteBuffer = packedSpamSections.get(sectionIndex);
			if (packed != null) count += packed.getAllocatedChunkCount();
		}
		return count;
	}

	private function formatCountWithCommas(value:Int):String
	{
		var raw:String = Std.string(value);
		var start:Int = raw.charAt(0) == '-' ? 1 : 0;
		var formatted:String = start == 1 ? '-' : '';
		for (i in start...raw.length) {
			if (i > start && (raw.length - i) % 3 == 0) formatted += ',';
			formatted += raw.charAt(i);
		}
		return formatted;
	}

	private function formatCountWithCommas64(value:Int64):String
	{
		var raw:String = Int64.toStr(value);
		var start:Int = raw.charAt(0) == '-' ? 1 : 0;
		var formatted:String = start == 1 ? '-' : '';
		for (i in start...raw.length)
		{
			if (i > start && (raw.length - i) % 3 == 0) formatted += ',';
			formatted += raw.charAt(i);
		}
		return formatted;
	}

	private function clampSpamMultiplier(value:Float):Float
	{
		if (Math.isNaN(value)) return 1;
		if (value <= 0) return 0;
		if (value >= MAX_SPAM_MULTIPLIER) return MAX_SPAM_MULTIPLIER;
		return Math.floor(value);
	}

	var eventDropDown:FlxUIDropDownMenu;
	var descText:FlxText;
	var selectedEventText:FlxText;

	function addEventsUI():Void
	{
		var tab_group_event = new FlxUI(null, UI_box);
		tab_group_event.name = 'Events';

		#if LUA_ALLOWED
		var eventPushedMap:Map<String, Bool> = new Map<String, Bool>();
		var directories:Array<String> = [];

		#if MODS_ALLOWED
		directories.push(Paths.mods('custom_events/'));
		directories.push(Paths.mods(Mods.currentModDirectory + '/custom_events/'));
		for (mod in Mods.getGlobalMods())
			directories.push(Paths.mods(mod + '/custom_events/'));
		#end

		for (i in 0...directories.length) {
			var directory:String = directories[i];
			if (FileSystem.exists(directory)) {
				for (file in FileSystem.readDirectory(directory)) {
					var path = haxe.io.Path.join([directory, file]);
					if (!FileSystem.isDirectory(path) && file != 'readme.txt' && file.endsWith('.txt')) {
						var fileToCheck:String = file.substr(0, file.length - 4);
						if (!eventPushedMap.exists(fileToCheck)) {
							eventPushedMap.set(fileToCheck, true);
							eventStuff.push([fileToCheck, File.getContent(path)]);
						}
					}
				}
			}
		}
		eventPushedMap.clear();
		eventPushedMap = null;
		#end

		descText = new FlxText(20, 200, 0, eventStuff[0][0]);

		var leEvents:Array<String> = [];
		for (i in 0...eventStuff.length) {
			leEvents.push(eventStuff[i][0]);
		}

		var text:FlxText = new FlxText(20, 30, 0, "Event:");
		tab_group_event.add(text);
		eventDropDown = new FlxUIDropDownMenu(20, 50, FlxUIDropDownMenu.makeStrIdLabelArray(leEvents, true), function(pressed:String) {
			var selectedEvent:Int = Std.parseInt(pressed);
			descText.text = eventStuff[selectedEvent][1];
			if (curSelectedNote != null && eventStuff != null) {
				if (curSelectedNote != null && curSelectedNote[2] == null) {
					curSelectedNote[1][curEventSelected][0] = eventStuff[selectedEvent][0];
				}
				updateGrid();
			}
		});
		blockPressWhileScrolling.push(eventDropDown);

		var text:FlxText = new FlxText(20, 90, 0, "Value 1:");
		tab_group_event.add(text);
		value1InputText = new FlxUIInputText(20, 110, 100, "");
		blockPressWhileTypingOn.push(value1InputText);

		var text:FlxText = new FlxText(20, 130, 0, "Value 2:");
		tab_group_event.add(text);
		value2InputText = new FlxUIInputText(20, 150, 100, "");
		blockPressWhileTypingOn.push(value2InputText);

		var removeButton:FlxButton = new FlxButton(eventDropDown.x + eventDropDown.width + 10, eventDropDown.y, '-', function() {
			if (curSelectedNote != null && curSelectedNote[2] == null) {
				if (curSelectedNote[1].length < 2) {
					_song.events.remove(curSelectedNote);
					invalidateEventRenderCache();
					curSelectedNote = null;
				} else {
					curSelectedNote[1].remove(curSelectedNote[1][curEventSelected]);
				}

				var eventsGroup:Array<Dynamic>;
				--curEventSelected;
				if (curEventSelected < 0) curEventSelected = 0;
				else if (curSelectedNote != null && curEventSelected >= (eventsGroup = curSelectedNote[1]).length) curEventSelected = eventsGroup.length - 1;

				changeEventSelected();
				updateGrid();
			}
		});
		removeButton.setGraphicSize(Std.int(removeButton.height), Std.int(removeButton.height));
		removeButton.updateHitbox();
		removeButton.color = FlxColor.RED;
		removeButton.label.color = FlxColor.WHITE;
		removeButton.label.size = 12;
		setAllLabelsOffset(removeButton, -30, 0);
		tab_group_event.add(removeButton);

		var addButton:FlxButton = new FlxButton(removeButton.x + removeButton.width + 10, removeButton.y, '+', function() {
			if (curSelectedNote != null && curSelectedNote[2] == null) {
				var eventsGroup:Array<Dynamic> = curSelectedNote[1];
				eventsGroup.push(['', '', '']);
				changeEventSelected(1);
				updateGrid();
			}
		});
		addButton.setGraphicSize(Std.int(removeButton.width), Std.int(removeButton.height));
		addButton.updateHitbox();
		addButton.color = FlxColor.GREEN;
		addButton.label.color = FlxColor.WHITE;
		addButton.label.size = 12;
		setAllLabelsOffset(addButton, -30, 0);
		tab_group_event.add(addButton);

		var moveLeftButton:FlxButton = new FlxButton(addButton.x + addButton.width + 20, addButton.y, '<', function() {
			changeEventSelected(-1);
		});
		moveLeftButton.setGraphicSize(Std.int(addButton.width), Std.int(addButton.height));
		moveLeftButton.updateHitbox();
		moveLeftButton.label.size = 12;
		setAllLabelsOffset(moveLeftButton, -30, 0);
		tab_group_event.add(moveLeftButton);

		var moveRightButton:FlxButton = new FlxButton(moveLeftButton.x + moveLeftButton.width + 10, moveLeftButton.y, '>', function() {
			changeEventSelected(1);
		});
		moveRightButton.setGraphicSize(Std.int(moveLeftButton.width), Std.int(moveLeftButton.height));
		moveRightButton.updateHitbox();
		moveRightButton.label.size = 12;
		setAllLabelsOffset(moveRightButton, -30, 0);
		tab_group_event.add(moveRightButton);

		selectedEventText = new FlxText(addButton.x - 100, addButton.y + addButton.height + 6, (moveRightButton.x - addButton.x) + 186, 'Selected Event: None');
		selectedEventText.alignment = CENTER;
		tab_group_event.add(selectedEventText);

		tab_group_event.add(descText);
		tab_group_event.add(value1InputText);
		tab_group_event.add(value2InputText);
		tab_group_event.add(eventDropDown);

		UI_box.addGroup(tab_group_event);
	}

	function changeEventSelected(change:Int = 0)
	{
		if (curSelectedNote != null && curSelectedNote[2] == null) {
			curEventSelected += change;
			if (curEventSelected < 0) curEventSelected = Std.int(curSelectedNote[1].length) - 1;
			else if (curEventSelected >= curSelectedNote[1].length) curEventSelected = 0;
			selectedEventText.text = 'Selected Event: ' + (curEventSelected + 1) + ' / ' + curSelectedNote[1].length;
		} else {
			curEventSelected = 0;
			selectedEventText.text = 'Selected Event: None';
		}
		updateNoteUI();
	}

	function setAllLabelsOffset(button:FlxButton, x:Float, y:Float)
	{
		for (point in button.labelOffsets) {
			point.set(x, y);
		}
	}

	var metronome:FlxUICheckBox;
	var mouseScrollingQuant:FlxUICheckBox;
	var metronomeStepper:FlxUINumericStepper;
	var metronomeOffsetStepper:FlxUINumericStepper;
	var disableAutoScrolling:FlxUICheckBox;
	var instVolume:FlxUINumericStepper;
	var voicesVolume:FlxUINumericStepper;
	var voicesOppVolume:FlxUINumericStepper;

	function addChartingUI() {
		var tab_group_chart = new FlxUI(null, UI_box);
		tab_group_chart.name = 'Charting';

		#if desktop
		if (FlxG.save.data.chart_waveformInst == null) FlxG.save.data.chart_waveformInst = false;
		if (FlxG.save.data.chart_waveformVoices == null) FlxG.save.data.chart_waveformVoices = false;
		if (FlxG.save.data.chart_waveformOppVoices == null) FlxG.save.data.chart_waveformOppVoices = false;

		var waveformUseInstrumental:FlxUICheckBox = null;
		var waveformUseVoices:FlxUICheckBox = null;
		var waveformUseOppVoices:FlxUICheckBox = null;

		waveformUseInstrumental = new FlxUICheckBox(10, 90, null, null, "Waveform\n(Instrumental)", 85);
		waveformUseInstrumental.checked = FlxG.save.data.chart_waveformInst;
		waveformUseInstrumental.callback = function() {
			waveformUseVoices.checked = false;
			waveformUseOppVoices.checked = false;
			FlxG.save.data.chart_waveformVoices = false;
			FlxG.save.data.chart_waveformOppVoices = false;
			FlxG.save.data.chart_waveformInst = waveformUseInstrumental.checked;
			updateWaveform();
		};

		waveformUseVoices = new FlxUICheckBox(waveformUseInstrumental.x + 100, waveformUseInstrumental.y, null, null, "Waveform\n(Main Vocals)", 85);
		waveformUseVoices.checked = FlxG.save.data.chart_waveformVoices && !waveformUseInstrumental.checked;
		waveformUseVoices.callback = function() {
			waveformUseInstrumental.checked = false;
			waveformUseOppVoices.checked = false;
			FlxG.save.data.chart_waveformInst = false;
			FlxG.save.data.chart_waveformOppVoices = false;
			FlxG.save.data.chart_waveformVoices = waveformUseVoices.checked;
			updateWaveform();
		};

		waveformUseOppVoices = new FlxUICheckBox(waveformUseInstrumental.x + 200, waveformUseInstrumental.y, null, null, "Waveform\n(Opp. Vocals)", 85);
		waveformUseOppVoices.checked = FlxG.save.data.chart_waveformOppVoices && !waveformUseVoices.checked;
		waveformUseOppVoices.callback = function() {
			waveformUseInstrumental.checked = false;
			waveformUseVoices.checked = false;
			FlxG.save.data.chart_waveformInst = false;
			FlxG.save.data.chart_waveformVoices = false;
			FlxG.save.data.chart_waveformOppVoices = waveformUseOppVoices.checked;
			updateWaveform();
		};
		#end

		check_mute_inst = new FlxUICheckBox(10, 280, null, null, "Mute Instrumental (in editor)", 100);
		check_mute_inst.checked = false;
		check_mute_inst.callback = function() {
			var vol:Float = instVolume.value;
			if (check_mute_inst.checked) vol = 0;
			FlxG.sound.music.volume = vol;
		};
		mouseScrollingQuant = new FlxUICheckBox(10, 190, null, null, "Mouse Scrolling Quantization", 100);
		if (FlxG.save.data.mouseScrollingQuant == null) FlxG.save.data.mouseScrollingQuant = false;
		mouseScrollingQuant.checked = FlxG.save.data.mouseScrollingQuant;

		mouseScrollingQuant.callback = function() {
			FlxG.save.data.mouseScrollingQuant = mouseScrollingQuant.checked;
			mouseQuant = FlxG.save.data.mouseScrollingQuant;
		};

		check_vortex = new FlxUICheckBox(10, 160, null, null, "Vortex Editor (BETA)", 100);
		if (FlxG.save.data.chart_vortex == null) FlxG.save.data.chart_vortex = false;
		check_vortex.checked = FlxG.save.data.chart_vortex;

		check_vortex.callback = function() {
			FlxG.save.data.chart_vortex = check_vortex.checked;
			vortex = FlxG.save.data.chart_vortex;
			reloadGridLayer();
		};

		check_warnings = new FlxUICheckBox(10, 120, null, null, "Ignore Progress Warnings", 100);
		if (FlxG.save.data.ignoreWarnings == null) FlxG.save.data.ignoreWarnings = false;
		check_warnings.checked = FlxG.save.data.ignoreWarnings;

		check_warnings.callback = function() {
			FlxG.save.data.ignoreWarnings = check_warnings.checked;
			ignoreWarnings = FlxG.save.data.ignoreWarnings;
		};

		check_mute_vocals = new FlxUICheckBox(check_mute_inst.x, check_mute_inst.y + 30, null, null, "Mute Main Vocals (in editor)", 100);
		check_mute_vocals.checked = false;
		check_mute_vocals.callback = function() {
			var vol:Float = voicesVolume.value;
			if (check_mute_vocals.checked) vol = 0;
			if (vocals != null) vocals.volume = vol;
		};
		check_mute_vocals_opponent = new FlxUICheckBox(check_mute_vocals.x + 120, check_mute_vocals.y, null, null, "Mute Opp. Vocals (in editor)", 100);
		check_mute_vocals_opponent.checked = false;
		check_mute_vocals_opponent.callback = function() {
			var vol:Float = voicesOppVolume.value;
			if (check_mute_vocals_opponent.checked) vol = 0;
			if (opponentVocals != null) opponentVocals.volume = vol;
		};

		playSoundBf = new FlxUICheckBox(check_mute_inst.x, check_mute_vocals.y + 30, null, null, 'Play Sound (Boyfriend notes)', 100, function() {
			FlxG.save.data.chart_playSoundBf = playSoundBf.checked;
		});
		if (FlxG.save.data.chart_playSoundBf == null) FlxG.save.data.chart_playSoundBf = false;
		playSoundBf.checked = FlxG.save.data.chart_playSoundBf;

		playSoundDad = new FlxUICheckBox(check_mute_inst.x + 120, playSoundBf.y, null, null, 'Play Sound (Opponent notes)', 100, function() {
			FlxG.save.data.chart_playSoundDad = playSoundDad.checked;
		});
		if (FlxG.save.data.chart_playSoundDad == null) FlxG.save.data.chart_playSoundDad = false;
		playSoundDad.checked = FlxG.save.data.chart_playSoundDad;

		metronome = new FlxUICheckBox(10, 15, null, null, "Metronome Enabled", 100, function() {
			FlxG.save.data.chart_metronome = metronome.checked;
		});
		if (FlxG.save.data.chart_metronome == null) FlxG.save.data.chart_metronome = false;
		metronome.checked = FlxG.save.data.chart_metronome;

		metronomeStepper = new FlxUINumericStepper(15, 55, 5, _song.bpm, 1, Song.MAX_BPM, 1);
		metronomeOffsetStepper = new FlxUINumericStepper(metronomeStepper.x + 100, metronomeStepper.y, 25, 0, 0, 1000, 1);
		blockPressWhileTypingOnStepper.push(metronomeStepper);
		blockPressWhileTypingOnStepper.push(metronomeOffsetStepper);

		disableAutoScrolling = new FlxUICheckBox(metronome.x + 120, metronome.y, null, null, "Disable Autoscroll (Not Recommended)", 120, function() {
			FlxG.save.data.chart_noAutoScroll = disableAutoScrolling.checked;
		});
		if (FlxG.save.data.chart_noAutoScroll == null) FlxG.save.data.chart_noAutoScroll = false;
		disableAutoScrolling.checked = FlxG.save.data.chart_noAutoScroll;

		instVolume = new FlxUINumericStepper(metronomeStepper.x, 250, 0.1, 1, 0, 1, 1);
		instVolume.value = FlxG.sound.music.volume;
		instVolume.name = 'inst_volume';
		blockPressWhileTypingOnStepper.push(instVolume);

		voicesVolume = new FlxUINumericStepper(instVolume.x + 100, instVolume.y, 0.1, 1, 0, 1, 1);
		voicesVolume.value = vocals.volume;
		voicesVolume.name = 'voices_volume';
		blockPressWhileTypingOnStepper.push(voicesVolume);

		voicesOppVolume = new FlxUINumericStepper(instVolume.x + 200, instVolume.y, 0.1, 1, 0, 1, 1);
		voicesOppVolume.value = vocals.volume;
		voicesOppVolume.name = 'voices_opp_volume';
		blockPressWhileTypingOnStepper.push(voicesOppVolume);

		#if FLX_PITCH
		sliderRate = new FlxUISlider(this, 'playbackSpeed', 120, 120, 0.5, 3, 150, null, 5, FlxColor.WHITE, FlxColor.BLACK);
		sliderRate.nameLabel.text = 'Playback Rate';
		tab_group_chart.add(sliderRate);
		#end

		tab_group_chart.add(new FlxText(metronomeStepper.x, metronomeStepper.y - 15, 0, 'BPM:'));
		tab_group_chart.add(new FlxText(metronomeOffsetStepper.x, metronomeOffsetStepper.y - 15, 0, 'Offset (ms):'));
		tab_group_chart.add(new FlxText(instVolume.x, instVolume.y - 15, 0, 'Inst Volume'));
		tab_group_chart.add(new FlxText(voicesVolume.x, voicesVolume.y - 15, 0, 'Main Vocals'));
		tab_group_chart.add(new FlxText(voicesOppVolume.x, voicesOppVolume.y - 15, 0, 'Opp. Vocals'));
		tab_group_chart.add(metronome);
		tab_group_chart.add(disableAutoScrolling);
		tab_group_chart.add(metronomeStepper);
		tab_group_chart.add(metronomeOffsetStepper);
		#if desktop
		tab_group_chart.add(waveformUseInstrumental);
		tab_group_chart.add(waveformUseVoices);
		tab_group_chart.add(waveformUseOppVoices);
		#end
		tab_group_chart.add(instVolume);
		tab_group_chart.add(voicesVolume);
		tab_group_chart.add(voicesOppVolume);
		tab_group_chart.add(check_mute_inst);
		tab_group_chart.add(check_mute_vocals);
		tab_group_chart.add(check_mute_vocals_opponent);
		tab_group_chart.add(check_vortex);
		tab_group_chart.add(mouseScrollingQuant);
		tab_group_chart.add(check_warnings);
		tab_group_chart.add(playSoundBf);
		tab_group_chart.add(playSoundDad);
		UI_box.addGroup(tab_group_chart);
	}

	var gameOverCharacterInputText:FlxUIInputText;
	var gameOverSoundInputText:FlxUIInputText;
	var gameOverLoopInputText:FlxUIInputText;
	var gameOverEndInputText:FlxUIInputText;
	var noteSkinInputText:FlxUIInputText;
	var noteSplashesInputText:FlxUIInputText;

	function addDataUI()
	{
		var tab_group_data = new FlxUI(null, UI_box);
		tab_group_data.name = 'Data';

		gameOverCharacterInputText = new FlxUIInputText(10, 25, 150, _song.gameOverChar != null ? _song.gameOverChar : '', 8);
		blockPressWhileTypingOn.push(gameOverCharacterInputText);
		
		gameOverSoundInputText = new FlxUIInputText(10, gameOverCharacterInputText.y + 35, 150, _song.gameOverSound != null ? _song.gameOverSound : '', 8);
		blockPressWhileTypingOn.push(gameOverSoundInputText);
		
		gameOverLoopInputText = new FlxUIInputText(10, gameOverSoundInputText.y + 35, 150, _song.gameOverLoop != null ? _song.gameOverLoop : '', 8);
		blockPressWhileTypingOn.push(gameOverLoopInputText);
		
		gameOverEndInputText = new FlxUIInputText(10, gameOverLoopInputText.y + 35, 150, _song.gameOverEnd != null ? _song.gameOverEnd : '', 8);
		blockPressWhileTypingOn.push(gameOverEndInputText);

		var check_disableNoteRGB:FlxUICheckBox = new FlxUICheckBox(10, 170, null, null, "Disable Note RGB", 100);
		check_disableNoteRGB.checked = (_song.disableNoteRGB == true);
		check_disableNoteRGB.callback = function() {
			_song.disableNoteRGB = check_disableNoteRGB.checked;
			updateGrid();
		};

		noteSkinInputText = new FlxUIInputText(10, 280, 150, _song.arrowSkin != null ? _song.arrowSkin : '', 8);
		blockPressWhileTypingOn.push(noteSkinInputText);

		noteSplashesInputText = new FlxUIInputText(noteSkinInputText.x, noteSkinInputText.y + 35, 150, _song.splashSkin != null ? _song.splashSkin : '', 8);
		blockPressWhileTypingOn.push(noteSplashesInputText);

		var reloadNotesButton:FlxButton = new FlxButton(noteSplashesInputText.x + 5, noteSplashesInputText.y + 20, 'Change Notes', function() {
			_song.arrowSkin = noteSkinInputText.text;
			updateGrid();
		});

		tab_group_data.add(gameOverCharacterInputText);
		tab_group_data.add(gameOverSoundInputText);
		tab_group_data.add(gameOverLoopInputText);
		tab_group_data.add(gameOverEndInputText);
		tab_group_data.add(check_disableNoteRGB);
		tab_group_data.add(reloadNotesButton);
		tab_group_data.add(noteSkinInputText);
		tab_group_data.add(noteSplashesInputText);

		tab_group_data.add(new FlxText(gameOverCharacterInputText.x, gameOverCharacterInputText.y - 15, 0, 'Game Over Character Name:'));
		tab_group_data.add(new FlxText(gameOverSoundInputText.x, gameOverSoundInputText.y - 15, 0, 'Game Over Death Sound (sounds/):'));
		tab_group_data.add(new FlxText(gameOverLoopInputText.x, gameOverLoopInputText.y - 15, 0, 'Game Over Loop Music (music/):'));
		tab_group_data.add(new FlxText(gameOverEndInputText.x, gameOverEndInputText.y - 15, 0, 'Game Over Retry Music (music/):'));
		tab_group_data.add(new FlxText(noteSkinInputText.x, noteSkinInputText.y - 15, 0, 'Note Texture:'));
		tab_group_data.add(new FlxText(noteSplashesInputText.x, noteSplashesInputText.y - 15, 0, 'Note Splashes Texture:'));
		UI_box.addGroup(tab_group_data);
	}

	function loadSong():Void
	{
		if (FlxG.sound.music != null) FlxG.sound.music.stop();

		if (vocals != null) {
			vocals.stop();
			vocals.destroy();
		}
		if (opponentVocals != null) {
			opponentVocals.stop();
			opponentVocals.destroy();
		}

		vocals = new FlxSound();
		opponentVocals = new FlxSound();
		try {
			var playerVocals = Paths.voices(currentSongName, (characterData.vocalsP1 == null || characterData.vocalsP1.length < 1) ? 'Player' : characterData.vocalsP1);
			vocals.loadEmbedded(playerVocals != null ? playerVocals : Paths.voices(currentSongName));
		}
		vocals.autoDestroy = false;
		FlxG.sound.list.add(vocals);

		opponentVocals = new FlxSound();
		try {
			var oppVocals = Paths.voices(currentSongName, (characterData.vocalsP2 == null || characterData.vocalsP2.length < 1) ? 'Opponent' : characterData.vocalsP2);
			if (oppVocals != null) opponentVocals.loadEmbedded(oppVocals);
		}
		opponentVocals.autoDestroy = false;
		FlxG.sound.list.add(opponentVocals);

		generateSong();
		FlxG.sound.music.pause();
		Conductor.songPosition = sectionStartTime();
		FlxG.sound.music.time = Conductor.songPosition;

		var curTime:Float = 0;
		if (_song.notes.length <= 1) {
			while (curTime < FlxG.sound.music.length) {
				addSection();
				curTime += (60 / _song.bpm) * 4000;
			}
		}
	}

	var playtesting:Bool = false;
	var playtestingTime:Float = 0;
	var playtestingOnComplete:Void->Void = null;

	override function closeSubState()
	{
		if (playtesting) {
			FlxG.sound.music.pause();
			FlxG.sound.music.time = playtestingTime;
			FlxG.sound.music.onComplete = playtestingOnComplete;
			if (instVolume != null) FlxG.sound.music.volume = instVolume.value;
			if (check_mute_inst != null && check_mute_inst.checked) FlxG.sound.music.volume = 0;

			if (vocals != null) {
				vocals.pause();
				vocals.time = playtestingTime;
				if (voicesVolume != null) vocals.volume = voicesVolume.value;
				if (check_mute_vocals != null && check_mute_vocals.checked) vocals.volume = 0;
			}

			if (opponentVocals != null) {
				opponentVocals.pause();
				opponentVocals.time = playtestingTime;
				if (voicesOppVolume != null) opponentVocals.volume = voicesOppVolume.value;
				if (check_mute_vocals_opponent != null && check_mute_vocals_opponent.checked) opponentVocals.volume = 0;
			}

			#if DISCORD_ALLOWED
			updatePresenceCounter();
			#end
		}
		super.closeSubState();
	}

	function generateSong() {
		FlxG.sound.playMusic(Paths.inst(currentSongName), 0.6);
		FlxG.sound.music.autoDestroy = false;
		if (instVolume != null) FlxG.sound.music.volume = instVolume.value;
		if (check_mute_inst != null && check_mute_inst.checked) FlxG.sound.music.volume = 0;

		FlxG.sound.music.onComplete = function() {
			FlxG.sound.music.pause();
			Conductor.songPosition = 0;
			if (vocals != null) {
				vocals.pause();
				vocals.time = 0;
			}
			if (opponentVocals != null) {
				opponentVocals.pause();
				opponentVocals.time = 0;
			}
			changeSection();
			curSec = 0;
			updateGrid();
			updateSectionUI();
			if (vocals != null) vocals.play();
			if (opponentVocals != null) opponentVocals.play();
		};
	}

	function generateUI():Void
	{
		while (bullshitUI.members.length > 0) {
			bullshitUI.remove(bullshitUI.members[0], true);
		}
		var title:FlxText = new FlxText(UI_box.x + 20, UI_box.y + 20, 0);
		bullshitUI.add(title);
	}

	override function getEvent(id:String, sender:Dynamic, data:Dynamic, ?params:Array<Dynamic>)
	{
		if (id == FlxUICheckBox.CLICK_EVENT) {
			var check:FlxUICheckBox = cast sender;
			var label = check.getLabel().text;
			switch (label) {
				case 'Must hit section':
					_song.notes[curSec].mustHitSection = check.checked;
					updateGrid();
					updateHeads();
				case 'GF section':
					_song.notes[curSec].gfSection = check.checked;
					updateGrid();
					updateHeads();
				case 'Change BPM':
					_song.notes[curSec].changeBPM = check.checked;
					sectionCacheDirty = true;
					invalidateEventRenderCache();
					updateGrid();
				case "Alt Animation":
					_song.notes[curSec].altAnim = check.checked;
			}
		} else if (id == FlxUINumericStepper.CHANGE_EVENT && (sender is FlxUINumericStepper)) {
			var nums:FlxUINumericStepper = cast sender;
			var wname = nums.name;
			switch (wname) {
				case 'section_beats':
					_song.notes[curSec].sectionBeats = nums.value;
					sectionCacheDirty = true;
					invalidateEventRenderCache();
					reloadGridLayer();
				case 'song_speed':
					_song.speed = Song.clampScrollSpeed(nums.value);
					nums.value = _song.speed;
				case 'song_bpm':
					_song.bpm = Song.clampBpm(nums.value);
					nums.value = _song.bpm;
					sectionCacheDirty = true;
					invalidateEventRenderCache();
					Conductor.mapBPMChanges(_song);
					Conductor.bpm = nums.value;
					stepperSusLength.stepSize = Math.ceil(Conductor.stepCrochet / 2);
					updateGrid();
				case 'note_susLength':
					if (curSelectedNote != null && curSelectedNote[2] != null) {
						curSelectedNote[2] = nums.value;
						updateGrid();
					}
				case 'section_bpm':
					_song.notes[curSec].bpm = Song.clampBpm(nums.value);
					nums.value = _song.notes[curSec].bpm;
					sectionCacheDirty = true;
					invalidateEventRenderCache();
					Conductor.mapBPMChanges(_song);
					updateGrid();
				case 'note_density':
					noteDensity = Std.int(Math.max(1, nums.value));
					invalidateRenderCache();
					noteRenderDirty = true;
					updateGrid();
				case 'note_alpha':
					noteAlpha = FlxMath.bound(nums.value, 0, 1);
					noteRenderDirty = true;
					updateGrid();
				case 'render_limit':
					renderDensity = Std.int(FlxMath.bound(nums.value, 128, MAX_RENDERED_NOTES));
					updateGrid();
				case 'inst_volume':
					FlxG.sound.music.volume = nums.value;
					if (check_mute_inst.checked) FlxG.sound.music.volume = 0;
				case 'voices_volume':
					vocals.volume = nums.value;
					if (check_mute_vocals.checked) vocals.volume = 0;
				case 'voices_opp_volume':
					opponentVocals.volume = nums.value;
					if (check_mute_vocals_opponent.checked) opponentVocals.volume = 0;
			}
		} else if (id == FlxUIInputText.CHANGE_EVENT && (sender is FlxUIInputText)) {
			if (sender == noteSplashesInputText) {
				_song.splashSkin = noteSplashesInputText.text;
			} else if (sender == noteSkinInputText) {
				_song.arrowSkin = noteSkinInputText.text;
			} else if (sender == gameOverCharacterInputText) {
				_song.gameOverChar = gameOverCharacterInputText.text;
			} else if (sender == gameOverSoundInputText) {
				_song.gameOverSound = gameOverSoundInputText.text;
			} else if (sender == gameOverLoopInputText) {
				_song.gameOverLoop = gameOverLoopInputText.text;
			} else if (sender == gameOverEndInputText) {
				_song.gameOverEnd = gameOverEndInputText.text;
			} else if (curSelectedNote != null) {
				if (sender == value1InputText) {
					if (curSelectedNote[1][curEventSelected] != null) {
						curSelectedNote[1][curEventSelected][1] = value1InputText.text;
						updateGrid();
					}
				} else if (sender == value2InputText) {
					if (curSelectedNote[1][curEventSelected] != null) {
						curSelectedNote[1][curEventSelected][2] = value2InputText.text;
						updateGrid();
					}
				} else if (sender == strumTimeInputText) {
					var value:Float = Std.parseFloat(strumTimeInputText.text);
					if (Math.isNaN(value)) value = 0;
					curSelectedNote[0] = value;
					if (curSelectedNote[2] == null) invalidateEventRenderCache();
					updateGrid();
				}
			}
		} else if (id == FlxUISlider.CHANGE_EVENT && (sender is FlxUISlider)) {
			switch (sender) {
				case 'playbackSpeed':
					playbackSpeed = #if FLX_PITCH Std.int(sliderRate.value) #else 1.0 #end;
			}
		}
	}

	var updatedSection:Bool = false;

	function sectionStartTime(add:Int = 0):Float
	{
		if (sectionCacheDirty || cachedSectionStarts.length != _song.notes.length) {
			rebuildSectionStartCache();
		}
		var target:Int = curSec + add;
		if (target < 0 || target >= cachedSectionStarts.length) return 0;
		return cachedSectionStarts[target];
	}

	function rebuildSectionStartCache():Void
	{
		cachedSectionStarts = [];
		var daBPM:Float = _song.bpm;
		var pos:Float = 0;

		for (sec in 0..._song.notes.length) {
			cachedSectionStarts[sec] = pos;
			if (_song.notes[sec] != null) {
				if (_song.notes[sec].changeBPM) daBPM = _song.notes[sec].bpm;
				pos += getSectionBeats(sec) * (1000 * 60 / daBPM);
			}
		}
		sectionCacheDirty = false;
	}

	var lastConductorPos:Float;
	var colorSine:Float = 0;

	override function update(elapsed:Float)
	{
		var chartUpdateStarted:Float = haxe.Timer.stamp();
		processPendingNoteSpam();
		#if sys
		processSplitSaveJob();
		// The exporter reads the current chart on its worker thread. Keep the
		// source data immutable until it finishes, while still updating/drawing
		// the editor and any checkpoint prompt on the main thread.
		if (splitChartSaveJob != null)
		{
			hudRefreshTimer -= elapsed;
			if (hudRefreshTimer <= 0 && bpmTxt != null)
			{
				hudRefreshTimer = 0.1;
				bpmTxt.text = 'SPLIT SAVE RUNNING IN BACKGROUND\n' + splitChartSaveJob.getProgressText()
					+ '\n\nESC: cancel save\nChart editing is paused until the export completes.';
			}
			super.update(elapsed);
			lastChartUpdateMs = (haxe.Timer.stamp() - chartUpdateStarted) * 1000;
			return;
		}
		#end
		curStep = recalculateSteps();

		if (FlxG.sound.music.time < 0) {
			FlxG.sound.music.pause();
			FlxG.sound.music.time = 0;
		} else if (FlxG.sound.music.time > FlxG.sound.music.length) {
			FlxG.sound.music.pause();
			FlxG.sound.music.time = 0;
			changeSection();
		}
		Conductor.songPosition = FlxG.sound.music.time;
		_song.song = UI_songTitle.text;

		strumLineUpdateY();
		for (i in 0...8) {
			strumLineNotes.members[i].y = strumLine.y;
		}

		FlxG.mouse.visible = true;
		camPos.y = strumLine.y;
		if (!disableAutoScrolling.checked) {
			if (Math.ceil(strumLine.y) >= gridBG.height) {
				if (_song.notes[curSec + 1] == null) {
					addSection();
				}
				changeSection(curSec + 1, false);
			} else if (strumLine.y < -10) {
				changeSection(curSec - 1, false);
			}
		}
		FlxG.watch.addQuick('daBeat', curBeat);
		FlxG.watch.addQuick('daStep', curStep);

		if (FlxG.mouse.x > gridBG.x
			&& FlxG.mouse.x < gridBG.x + gridBG.width
			&& FlxG.mouse.y > gridBG.y
			&& FlxG.mouse.y < gridBG.y + (GRID_SIZE * getSectionBeats() * 4) * zoomList[curZoom]) {
			dummyArrow.visible = true;
			dummyArrow.x = Math.floor(FlxG.mouse.x / GRID_SIZE) * GRID_SIZE;
			if (FlxG.keys.pressed.SHIFT)
				dummyArrow.y = FlxG.mouse.y;
			else {
				var gridmult = GRID_SIZE / (quantization / 16);
				dummyArrow.y = Math.floor(FlxG.mouse.y / gridmult) * gridmult;
			}
		} else {
			dummyArrow.visible = false;
		}

		if (FlxG.mouse.justPressed #if sys && splitChartSaveJob == null #end) {
			if (FlxG.mouse.overlaps(curRenderedNotes)) {
				curRenderedNotes.forEachAlive(function(note:Note) {
					if (FlxG.mouse.overlaps(note)) {
						if (FlxG.keys.pressed.CONTROL) {
							selectNote(note);
						} else if (FlxG.keys.pressed.ALT) {
							selectNote(note);
							curSelectedNote[3] = curNoteTypes[currentType];
							updateGrid();
						} else {
							deleteNote(note);
						}
					}
				});
			} else {
				if (FlxG.mouse.x > gridBG.x
					&& FlxG.mouse.x < gridBG.x + gridBG.width
					&& FlxG.mouse.y > gridBG.y
					&& FlxG.mouse.y < gridBG.y + (GRID_SIZE * getSectionBeats() * 4) * zoomList[curZoom]) {
					FlxG.log.add('added note');
					var requestedTotal:Float = 0;
					var safeMultiplier:Float = 1;
					if (check_stackActive.checked) {
						safeMultiplier = clampSpamMultiplier(stepperStackOffset.value);
						requestedTotal = Math.min(MAX_SPAM_REQUEST_FLOAT, Math.floor(Math.max(0, stepperStackNum.value) * safeMultiplier));
					}

					if (requestedTotal > 1 && pendingSpamCount <= 0) {
						// The section and request can use the full signed 32-bit range. Keep
						// the total chart ceiling as a separate safety limit.
						var currentCount:Int64 = getNoteAmount();
						var currentSectionCount:Int64 = getSectionNoteCount(curSec);
						if (currentCount >= MAX_CHART_NOTE_COUNT) {
							FlxG.log.add('Chart reached the configured note limit (5,000,000,000).');
						} else if (currentSectionCount >= MAX_SECTION_NOTE_COUNT) {
							FlxG.log.add('This section reached the configured note limit (5,000,000,000).');
						} else {
							addNote(null, null, null, false);
							var baseTime:Float = curSelectedNote[0];
							var baseData:Int = Std.int(curSelectedNote[1]);
							var spacing:Float = safeMultiplier == 0 ? 0 : (15000 / Conductor.bpm) / safeMultiplier;
							var sideOffset:Int = Std.int(Math.floor(stepperStackSideOffset.value));
							invalidateRenderCache(curSec);
							currentCount = getNoteAmount(); // Include the clicked note before calculating capacity.
							currentSectionCount = getSectionNoteCount(curSec);
							var remainingChartCapacity:Int64 = MAX_CHART_NOTE_COUNT - currentCount;
							var remainingSectionCapacity:Int64 = MAX_SECTION_NOTE_COUNT - currentSectionCount;
							var remainingCapacity:Int64 = remainingSectionCapacity < remainingChartCapacity ? remainingSectionCapacity : remainingChartCapacity;
							var requestedAdditional:Int64 = Int64.fromFloat(Math.max(0, requestedTotal - 1));
							var addCount:Int64 = requestedAdditional >= remainingCapacity ? remainingCapacity : requestedAdditional;
							if (requestedAdditional > remainingSectionCapacity)
								FlxG.log.add("Spam request capped at this section's 5,000,000,000-note capacity.");
							else if (requestedAdditional > remainingChartCapacity)
								FlxG.log.add('Spam request capped at 5,000,000,000 total chart notes.');
							if (addCount > Int64.ofInt(0))
								queueNoteSpam(addCount, curSec, baseTime, baseData, spacing, sideOffset, currentType);
							updateGrid();
							updateNoteUI();
						}
					} else {
						// A background spam job must not lock the chart editor. While it
						// runs, clicks still place ordinary notes and all other editor
						// controls remain usable. The active job keeps its original section.
						if (pendingSpamCount > 0 && check_stackActive.checked && requestedTotal > 1)
							FlxG.log.add('Background spam is already running. Your click was placed as a single note.');
						addNote();
					}
				}
			}
		}

		var blockInput:Bool = false;
		for (inputText in blockPressWhileTypingOn) {
			if (inputText.hasFocus) {
				ClientPrefs.toggleVolumeKeys(false);
				blockInput = true;
				break;
			}
		}

		if (!blockInput) {
			for (stepper in blockPressWhileTypingOnStepper) {
				@:privateAccess
				var leText:FlxUIInputText = cast (stepper.text_field, FlxUIInputText);
				if (leText.hasFocus) {
					ClientPrefs.toggleVolumeKeys(false);
					blockInput = true;
					break;
				}
			}
		}

		#if sys
		if (splitChartSaveJob != null) blockInput = true;
		#end

		if (!blockInput) {
			ClientPrefs.toggleVolumeKeys(true);
			for (dropDownMenu in blockPressWhileScrolling) {
				if (dropDownMenu.dropPanel.visible) {
					blockInput = true;
					break;
				}
			}
		}

		if (!blockInput #if sys && splitChartSaveJob == null #end) {
			if (FlxG.keys.justPressed.ESCAPE) {
				if (FlxG.sound.music != null) FlxG.sound.music.stop();
				if (vocals != null) {
					vocals.pause();
					vocals.volume = 0;
				}
				if (opponentVocals != null) {
					opponentVocals.pause();
					opponentVocals.volume = 0;
				}
				autosaveSong();
				PlayState.SONG = buildSerializableSong();
				playtesting = true;
				playtestingTime = Conductor.songPosition;
				playtestingOnComplete = FlxG.sound.music.onComplete;
				openSubState(new states.editors.EditorPlayState(playbackSpeed));
			} else if (FlxG.keys.justPressed.ENTER) {
				autosaveSong();
				FlxG.mouse.visible = false;
				PlayState.SONG = buildSerializableSong();
				FlxG.sound.music.stop();
				if (vocals != null) vocals.stop();
				if (opponentVocals != null) opponentVocals.stop();
				StageData.loadDirectory(PlayState.SONG);
				LoadingState.loadAndSwitchState(new PlayState());
			}

			if (curSelectedNote != null && curSelectedNote[1] > -1) {
				if (FlxG.keys.justPressed.E) {
					changeNoteSustain(Conductor.stepCrochet);
				}
				if (FlxG.keys.justPressed.Q) {
					changeNoteSustain(-Conductor.stepCrochet);
				}
			}

			if (FlxG.keys.justPressed.BACKSPACE) {
				autosaveSong();
				PlayState.chartingMode = false;
				MusicBeatState.switchState(new states.editors.MasterEditorMenu());
				FlxG.sound.playMusic(Paths.music('freakyMenu'));
				FlxG.mouse.visible = false;
				return;
			}

			if (FlxG.keys.justPressed.Z && FlxG.keys.pressed.CONTROL) {
				undo();
			}

			if (FlxG.keys.justPressed.Z && curZoom > 0 && !FlxG.keys.pressed.CONTROL) {
				--curZoom;
				updateZoom();
			}
			if (FlxG.keys.justPressed.X && curZoom < zoomList.length - 1) {
				curZoom++;
				updateZoom();
			}

			if (FlxG.keys.justPressed.TAB) {
				if (FlxG.keys.pressed.SHIFT) {
					UI_box.selected_tab -= 1;
					if (UI_box.selected_tab < 0) UI_box.selected_tab = 2;
				} else {
					UI_box.selected_tab += 1;
					if (UI_box.selected_tab >= 3) UI_box.selected_tab = 0;
				}
			}

			if (FlxG.keys.justPressed.SPACE) {
				if (vocals != null) vocals.play();
				if (opponentVocals != null) opponentVocals.play();
				pauseAndSetVocalsTime();
				if (!FlxG.sound.music.playing) {
					FlxG.sound.music.play();
					if (vocals != null) vocals.play();
					if (opponentVocals != null) opponentVocals.play();
				} else FlxG.sound.music.pause();
			}

			if (!FlxG.keys.pressed.ALT && FlxG.keys.justPressed.R) {
				if (FlxG.keys.pressed.SHIFT) resetSection(true);
				else resetSection();
			}

			if (FlxG.mouse.wheel != 0) {
				FlxG.sound.music.pause();
				if (!mouseQuant)
					FlxG.sound.music.time -= (FlxG.mouse.wheel * Conductor.stepCrochet * 0.8);
				else {
					var time:Float = FlxG.sound.music.time;
					var beat:Float = curDecBeat;
					var snap:Float = quantization / 4;
					var increase:Float = 1 / snap;
					if (FlxG.mouse.wheel > 0) {
						var fuck:Float = CoolUtil.quantize(beat, snap) - increase;
						FlxG.sound.music.time = Conductor.beatToSeconds(fuck);
					} else {
						var fuck:Float = CoolUtil.quantize(beat, snap) + increase;
						FlxG.sound.music.time = Conductor.beatToSeconds(fuck);
					}
				}
				pauseAndSetVocalsTime();
			}

			if (FlxG.keys.pressed.W || FlxG.keys.pressed.S) {
				FlxG.sound.music.pause();
				var holdingShift:Float = 1;
				if (FlxG.keys.pressed.CONTROL) holdingShift = 0.25;
				else if (FlxG.keys.pressed.SHIFT) holdingShift = 4;
				var daTime:Float = 700 * FlxG.elapsed * holdingShift;
				FlxG.sound.music.time += daTime * (FlxG.keys.pressed.W ? -1 : 1);
				pauseAndSetVocalsTime();
			}

			if (!vortex) {
				if (FlxG.keys.justPressed.UP || FlxG.keys.justPressed.DOWN) {
					FlxG.sound.music.pause();
					updateCurStep();
					var time:Float = FlxG.sound.music.time;
					var beat:Float = curDecBeat;
					var snap:Float = quantization / 4;
					var increase:Float = 1 / snap;
					if (FlxG.keys.pressed.UP) {
						var fuck:Float = CoolUtil.quantize(beat, snap) - increase;
						FlxG.sound.music.time = Conductor.beatToSeconds(fuck);
					} else {
						var fuck:Float = CoolUtil.quantize(beat, snap) + increase;
						FlxG.sound.music.time = Conductor.beatToSeconds(fuck);
					}
				}
			}

			var style = currentType;
			if (FlxG.keys.pressed.SHIFT) style = 3;
			var conductorTime = Conductor.songPosition;

			if (!blockInput) {
				if (FlxG.keys.justPressed.RIGHT) {
					curQuant++;
					if (curQuant > quantizations.length - 1) curQuant = 0;
					quantization = quantizations[curQuant];
				}

				if (FlxG.keys.justPressed.LEFT) {
					curQuant--;
					if (curQuant < 0) curQuant = quantizations.length - 1;
					quantization = quantizations[curQuant];
				}
				quant.animation.play('q', true, false, curQuant);
			}

			if (vortex && !blockInput) {
				var controlArray:Array<Bool> = [
					FlxG.keys.justPressed.ONE, FlxG.keys.justPressed.TWO, FlxG.keys.justPressed.THREE, FlxG.keys.justPressed.FOUR,
					FlxG.keys.justPressed.FIVE, FlxG.keys.justPressed.SIX, FlxG.keys.justPressed.SEVEN, FlxG.keys.justPressed.EIGHT
				];

				if (controlArray.contains(true)) {
					for (i in 0...controlArray.length) {
						if (controlArray[i]) doANoteThing(conductorTime, i, style);
					}
				}

				var feces:Float;
				if (FlxG.keys.justPressed.UP || FlxG.keys.justPressed.DOWN) {
					FlxG.sound.music.pause();
					updateCurStep();
					var time:Float = FlxG.sound.music.time;
					var beat:Float = curDecBeat;
					var snap:Float = quantization / 4;
					var increase:Float = 1 / snap;
					if (FlxG.keys.pressed.UP) {
						var fuck:Float = CoolUtil.quantize(beat, snap) - increase;
						feces = Conductor.beatToSeconds(fuck);
					} else {
						var fuck:Float = CoolUtil.quantize(beat, snap) + increase;
						feces = Conductor.beatToSeconds(fuck);
					}
					FlxTween.tween(FlxG.sound.music, {time: feces}, 0.1, {ease: FlxEase.circOut});
					pauseAndSetVocalsTime();

					var dastrum = 0;
					if (curSelectedNote != null) dastrum = curSelectedNote[0];

					var secStart:Float = sectionStartTime();
					var datime = (feces - secStart) - (dastrum - secStart);
					if (curSelectedNote != null) {
						var controlArray:Array<Bool> = [
							FlxG.keys.pressed.ONE, FlxG.keys.pressed.TWO, FlxG.keys.pressed.THREE, FlxG.keys.pressed.FOUR,
							FlxG.keys.pressed.FIVE, FlxG.keys.pressed.SIX, FlxG.keys.pressed.SEVEN, FlxG.keys.pressed.EIGHT
						];

						if (controlArray.contains(true)) {
							for (i in 0...controlArray.length) {
								if (controlArray[i])
									if (curSelectedNote[1] == i) curSelectedNote[2] += datime - curSelectedNote[2] - Conductor.stepCrochet;
							}
							updateGrid();
							updateNoteUI();
						}
					}
				}
			}

			var shiftThing:Int = 1;
			if (FlxG.keys.pressed.SHIFT) shiftThing = 4;

			if (FlxG.keys.justPressed.D) changeSection(curSec + shiftThing);
			if (FlxG.keys.justPressed.A) {
				if (curSec <= 0) changeSection(_song.notes.length - 1);
				else changeSection(curSec - shiftThing);
			}
		} else if (FlxG.keys.justPressed.ENTER) {
			for (i in 0...blockPressWhileTypingOn.length) {
				if (blockPressWhileTypingOn[i].hasFocus) {
					blockPressWhileTypingOn[i].hasFocus = false;
				}
			}
		}

		strumLineNotes.visible = quant.visible = vortex;

		if (FlxG.sound.music.time < 0) {
			FlxG.sound.music.pause();
			FlxG.sound.music.time = 0;
		} else if (FlxG.sound.music.time > FlxG.sound.music.length) {
			FlxG.sound.music.pause();
			FlxG.sound.music.time = 0;
			changeSection();
		}
		Conductor.songPosition = FlxG.sound.music.time;
		strumLineUpdateY();
		camPos.y = strumLine.y;
		for (i in 0...8) {
			strumLineNotes.members[i].y = strumLine.y;
			strumLineNotes.members[i].alpha = FlxG.sound.music.playing ? 1 : 0.35;
		}

		#if FLX_PITCH
		var holdingShift = FlxG.keys.pressed.SHIFT;
		var holdingLB = FlxG.keys.pressed.LBRACKET;
		var holdingRB = FlxG.keys.pressed.RBRACKET;
		var pressedLB = FlxG.keys.justPressed.LBRACKET;
		var pressedRB = FlxG.keys.justPressed.RBRACKET;

		if (!holdingShift && pressedLB || holdingShift && holdingLB) playbackSpeed -= 0.01;
		if (!holdingShift && pressedRB || holdingShift && holdingRB) playbackSpeed += 0.01;
		if (FlxG.keys.pressed.ALT && (pressedLB || pressedRB || holdingLB || holdingRB)) playbackSpeed = 1;

		if (playbackSpeed <= 0.5) playbackSpeed = 0.5;
		if (playbackSpeed >= 3) playbackSpeed = 3;

		FlxG.sound.music.pitch = playbackSpeed;
		vocals.pitch = playbackSpeed;
		opponentVocals.pitch = playbackSpeed;
		#end

		// FlxText regenerates its graphic when text changes. Updating this HUD
		// 10 times per second avoids a per-frame text-rasterization cost.
		hudRefreshTimer -= elapsed;
		if (hudRefreshTimer <= 0) {
			hudRefreshTimer = 0.1;
			var splitSaveStatus:String = 'Idle';
			#if sys
			if (splitChartSaveJob != null) splitSaveStatus = splitChartSaveJob.getProgressText();
			#end
			var hudText:String =
				Std.string(FlxMath.roundDecimal(Conductor.songPosition / 1000, 2)) + " / " + Std.string(FlxMath.roundDecimal(FlxG.sound.music.length / 1000, 2)) +
				"\nSection: " + curSec +
				"\n\nBeat: " + Std.string(curDecBeat).substring(0,4) +
				"\nStep: " + curStep +
				"\nBeat Snap: " + quantization + "th" +
				"\n\nTotal Notes: " + formatCountWithCommas64(getNoteAmount()) +
				"\nSection Notes: " + formatCountWithCommas64(getSectionNoteCount(curSec)) +
				"\nRendered Sprites: " + (curRenderedNotes.length + nextRenderedNotes.length) +
				"\nShow Notes/Events: " + showNotes + "/" + showEvents +
				"\nEditor Update: " + Std.string(FlxMath.roundDecimal(lastChartUpdateMs, 2)) + " ms" +
				"\nEditor Draw: " + Std.string(FlxMath.roundDecimal(lastChartDrawMs, 2)) + " ms" +
				"\nGrid Build: " + Std.string(FlxMath.roundDecimal(lastChartGridMs, 2)) + " ms" +
				"\nEvent Index: " + Std.string(FlxMath.roundDecimal(lastEventIndexMs, 2)) + " ms" +
				"\nWaveform: " + Std.string(FlxMath.roundDecimal(lastWaveformMs, 2)) + " ms" +
				"\nSpam Job: " + (pendingSpamCount > 0 ? "Running in editor background (Section " + pendingSpamSection + ")" : "Idle") +
				"\nUnfocused Updates: " + (spamBackgroundModeActive ? "Enabled while spam runs" : "Normal preference") +
				"\nSpam Target: " + formatCountWithCommas(Std.int(NOTE_SPAM_RATE_PER_SECOND)) + "/s" +
				"\nSpam Actual: " + (pendingSpamCount > 0 && currentMeasuredSpamRate <= 0 ? "measuring..." : formatCountWithCommas(pendingSpamCount > 0 ? currentMeasuredSpamRate : lastMeasuredSpamRate) + "/s") +
				"\nSpam Generated: " + formatCountWithCommas64(spamJobGeneratedRows) +
				"\nSpam Remaining: " + formatCountWithCommas64(pendingSpamCount) +
				"\nSpam Batch: " + formatCountWithCommas(lastSpamBatchRows) + " rows / " + Std.string(FlxMath.roundDecimal(lastSpamBatchMs, 2)) + " ms" +
				"\nPacked Spam Rows: " + formatCountWithCommas64(getPackedSpamRowCount()) +
				"\nPacked Segments: " + formatCountWithCommas(getPackedSegmentCount()) +
				"\nPacked Payload Est.: " + getPackedStorageEstimate() +
				"\nGC Current: " + getGcMemoryLabel() +
				"\nSplit Save: " + splitSaveStatus;
			if (hudText != lastEditorHudText) {
				bpmTxt.text = hudText;
				lastEditorHudText = hudText;
			}
		}

		playedSound[0] = false;
		playedSound[1] = false;
		playedSound[2] = false;
		playedSound[3] = false;
		for (note in curRenderedNotes.members) {
			if (note == null || !note.exists || !note.alive) continue;
			note.alpha = noteAlpha;
			if (curSelectedNote != null) {
				var noteDataToCheck:Int = note.noteData;
				if (noteDataToCheck > -1 && note.mustPress != _song.notes[curSec].mustHitSection) noteDataToCheck += 4;

				if (curSelectedNote[0] == note.strumTime && ((curSelectedNote[2] == null && noteDataToCheck < 0) || (curSelectedNote[2] != null && curSelectedNote[1] == noteDataToCheck))) {
					colorSine += elapsed;
					var colorVal:Float = 0.7 + Math.sin(Math.PI * colorSine) * 0.3;
					note.color = FlxColor.fromRGBFloat(colorVal, colorVal, colorVal, 0.999);
				}
			}

			if (note.strumTime <= Conductor.songPosition) {
				note.alpha = noteAlpha * 0.4;
				if (note.strumTime > lastConductorPos && FlxG.sound.music.playing && note.noteData > -1) {
					var data:Int = note.noteData % 4;
					var noteDataToCheck:Int = note.noteData;
					if (noteDataToCheck > -1 && note.mustPress != _song.notes[curSec].mustHitSection) noteDataToCheck += 4;
					strumLineNotes.members[noteDataToCheck].playAnim('confirm', true);
					strumLineNotes.members[noteDataToCheck].resetAnim = ((note.sustainLength / 1000) + 0.15) / playbackSpeed;
					if (!playedSound[data]) {
						if (note.hitsoundChartEditor && ((playSoundBf.checked && note.mustPress) || (playSoundDad.checked && !note.mustPress))) {
							var soundToPlay = note.hitsound;
							if (_song.player1 == 'gf') soundToPlay = 'GF_' + Std.string(data + 1);

							FlxG.sound.play(Paths.sound(soundToPlay)).pan = note.noteData < 4 ? -0.3 : 0.3;
							playedSound[data] = true;
						}
					}
				}
			}
		}

		if (metronome.checked && lastConductorPos != Conductor.songPosition) {
			var metroInterval:Float = 60 / metronomeStepper.value;
			var metroStep:Int = Math.floor(((Conductor.songPosition + metronomeOffsetStepper.value) / metroInterval) / 1000);
			var lastMetroStep:Int = Math.floor(((lastConductorPos + metronomeOffsetStepper.value) / metroInterval) / 1000);
			if (metroStep != lastMetroStep) {
				FlxG.sound.play(Paths.sound('Metronome_Tick'));
			}
		}
		lastConductorPos = Conductor.songPosition;
		super.update(elapsed);
		lastChartUpdateMs = (haxe.Timer.stamp() - chartUpdateStarted) * 1000;
	}

	override function draw():Void
	{
		var chartDrawStarted:Float = haxe.Timer.stamp();
		super.draw();
		lastChartDrawMs = (haxe.Timer.stamp() - chartDrawStarted) * 1000;
	}

	function pauseAndSetVocalsTime()
	{
		if (vocals != null) {
			vocals.pause();
			vocals.time = FlxG.sound.music.time;
		}
		if (opponentVocals != null) {
			opponentVocals.pause();
			opponentVocals.time = FlxG.sound.music.time;
		}
	}

	function updateZoom() {
		var daZoom:Float = zoomList[curZoom];
		var zoomThing:String = '1 / ' + daZoom;
		if (daZoom < 1) zoomThing = Math.round(1 / daZoom) + ' / 1';
		zoomTxt.text = 'Zoom: ' + zoomThing;
		reloadGridLayer();
	}

	override function destroy()
	{
		#if sys
		if (splitChartSaveJob != null)
		{
			splitChartSaveJob.cancel();
			splitChartSaveJob = null;
		}
		#end
		endSpamBackgroundMode();
		pendingSpamCount = 0;
		pendingSpamSection = -1;
		pendingSpamRateAccumulator = 0;
		lastSpamProcessTimestamp = 0;
		spamRateWindowStart = 0;
		spamRateWindowRows = 0;
		spamJobStartTimestamp = 0;
		spamJobGeneratedRows = 0;
		currentMeasuredSpamRate = 0;
		waveformBufferCache = null;
		waveformBytesCache = null;
		Note.globalRgbShaders = [];
		backend.NoteTypesConfig.clearNoteTypesData();
		super.destroy();
	}

	var lastSecBeats:Float = 0;
	var lastSecBeatsNext:Float = 0;
	var columns:Int = 9;

	function reloadGridLayer() {
		gridLayer.clear();
		gridBG = FlxGridOverlay.create(1, 1, columns, Std.int(getSectionBeats() * 4 * zoomList[curZoom]));
		gridBG.antialiasing = false;
		gridBG.scale.set(GRID_SIZE, GRID_SIZE);
		gridBG.updateHitbox();

		#if desktop
		if (FlxG.save.data.chart_waveformInst || FlxG.save.data.chart_waveformVoices || FlxG.save.data.chart_waveformOppVoices) {
			updateWaveform();
		}
		#end

		var leHeight:Int = Std.int(gridBG.height);
		var foundNextSec:Bool = false;
		if (sectionStartTime(1) <= FlxG.sound.music.length) {
			nextGridBG = FlxGridOverlay.create(1, 1, columns, Std.int(getSectionBeats(curSec + 1) * 4 * zoomList[curZoom]));
			nextGridBG.antialiasing = false;
			nextGridBG.scale.set(GRID_SIZE, GRID_SIZE);
			nextGridBG.updateHitbox();
			leHeight = Std.int(gridBG.height + nextGridBG.height);
			foundNextSec = true;
		} else nextGridBG = new FlxSprite().makeGraphic(1, 1, FlxColor.TRANSPARENT);
		nextGridBG.y = gridBG.height;
		
		gridLayer.add(nextGridBG);
		gridLayer.add(gridBG);

		if (foundNextSec) {
			var gridBlack:FlxSprite = new FlxSprite(0, gridBG.height).makeGraphic(1, 1, FlxColor.BLACK);
			gridBlack.setGraphicSize(Std.int(GRID_SIZE * 9), Std.int(nextGridBG.height));
			gridBlack.updateHitbox();
			gridBlack.antialiasing = false;
			gridBlack.alpha = 0.4;
			gridLayer.add(gridBlack);
		}

		var gridBlackLine:FlxSprite = new FlxSprite(gridBG.x + gridBG.width - (GRID_SIZE * 4)).makeGraphic(1, 1, FlxColor.BLACK);
		gridBlackLine.setGraphicSize(2, leHeight);
		gridBlackLine.updateHitbox();
		gridBlackLine.antialiasing = false;
		gridLayer.add(gridBlackLine);

		for (i in 1...Std.int(getSectionBeats())) {
			var beatsep:FlxSprite = new FlxSprite(gridBG.x, (GRID_SIZE * (4 * zoomList[curZoom])) * i).makeGraphic(1, 1, 0x44FF0000);
			beatsep.scale.x = gridBG.width;
			beatsep.updateHitbox();
			if (vortex) gridLayer.add(beatsep);
		}

		var gridBlackLine:FlxSprite = new FlxSprite(gridBG.x + GRID_SIZE).makeGraphic(1, 1, FlxColor.BLACK);
		gridBlackLine.setGraphicSize(2, leHeight);
		gridBlackLine.updateHitbox();
		gridBlackLine.antialiasing = false;
		gridLayer.add(gridBlackLine);
		updateGrid();

		lastSecBeats = getSectionBeats();
		if (sectionStartTime(1) > FlxG.sound.music.length) lastSecBeatsNext = 0;
		else getSectionBeats(curSec + 1);
	}

	function strumLineUpdateY()
	{
		strumLine.y = getYfromStrum((Conductor.songPosition - sectionStartTime()) / zoomList[curZoom] % (Conductor.stepCrochet * 16)) / (getSectionBeats() / 4);
	}

	var waveformPrinted:Bool = true;
	var wavData:Array<Array<Array<Float>>> = [[[0], [0]], [[0], [0]]];
	var lastWaveformHeight:Int = 0;

	function updateWaveform() {
		#if desktop
		var waveformStarted:Float = haxe.Timer.stamp();
		if (waveformPrinted) {
			var width:Int = Std.int(GRID_SIZE * 8);
			var height:Int = Std.int(gridBG.height);
			if (lastWaveformHeight != height && waveformSprite.pixels != null) {
				waveformSprite.pixels.dispose();
				waveformSprite.pixels.disposeImage();
				waveformSprite.makeGraphic(width, height, 0x00FFFFFF);
				lastWaveformHeight = height;
			}
			waveformSprite.pixels.fillRect(new Rectangle(0, 0, width, height), 0x00FFFFFF);
		}
		waveformPrinted = false;

		if (!FlxG.save.data.chart_waveformInst && !FlxG.save.data.chart_waveformVoices && !FlxG.save.data.chart_waveformOppVoices) {
			lastWaveformMs = (haxe.Timer.stamp() - waveformStarted) * 1000;
			return;
		}

		wavData[0][0] = [];
		wavData[0][1] = [];
		wavData[1][0] = [];
		wavData[1][1] = [];

		var steps:Int = Math.round(getSectionBeats() * 4);
		var st:Float = sectionStartTime();
		var et:Float = st + (Conductor.stepCrochet * steps);

		var sound:FlxSound = FlxG.sound.music;
		if (FlxG.save.data.chart_waveformVoices) sound = vocals;
		else if (FlxG.save.data.chart_waveformOppVoices) sound = opponentVocals;
		
		if (sound != null && sound._sound != null && sound._sound.__buffer != null) {
			var audioBuffer:AudioBuffer = sound._sound.__buffer;
			if (waveformBufferCache != audioBuffer || waveformBytesCache == null) {
				waveformBufferCache = audioBuffer;
				waveformBytesCache = audioBuffer.data.toBytes();
			}
			wavData = waveformData(audioBuffer, waveformBytesCache, st, et, 1, wavData, Std.int(gridBG.height));
		}

		var gSize:Int = Std.int(GRID_SIZE * 8);
		var hSize:Int = Std.int(gSize / 2);
		var size:Float = 1;

		var leftLength:Int = (wavData[0][0].length > wavData[0][1].length ? wavData[0][0].length : wavData[0][1].length);
		var rightLength:Int = (wavData[1][0].length > wavData[1][1].length ? wavData[1][0].length : wavData[1][1].length);
		var length:Int = leftLength > rightLength ? leftLength : rightLength;

		for (index in 0...length) {
			var lmin:Float = FlxMath.bound(((index < wavData[0][0].length && index >= 0) ? wavData[0][0][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;
			var lmax:Float = FlxMath.bound(((index < wavData[0][1].length && index >= 0) ? wavData[0][1][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;
			var rmin:Float = FlxMath.bound(((index < wavData[1][0].length && index >= 0) ? wavData[1][0][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;
			var rmax:Float = FlxMath.bound(((index < wavData[1][1].length && index >= 0) ? wavData[1][1][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;

			waveformSprite.pixels.fillRect(new Rectangle(hSize - (lmin + rmin), index * size, (lmin + rmin) + (lmax + rmax), size), FlxColor.BLUE);
		}

		waveformPrinted = true;
		lastWaveformMs = (haxe.Timer.stamp() - waveformStarted) * 1000;
		#end
	}

	function waveformData(buffer:AudioBuffer, bytes:Bytes, time:Float, endTime:Float, multiply:Float = 1, ?array:Array<Array<Array<Float>>>, ?steps:Float):Array<Array<Array<Float>>>
	{
		#if (lime_cffi && !macro)
		if (buffer == null || buffer.data == null) return [[[0], [0]], [[0], [0]]];

		var khz:Float = (buffer.sampleRate / 1000);
		var channels:Int = buffer.channels;
		var index:Int = Std.int(time * khz);
		var samples:Float = ((endTime - time) * khz);

		if (steps == null) steps = 1280;

		var samplesPerRow:Float = samples / steps;
		var samplesPerRowI:Int = Std.int(samplesPerRow);
		var gotIndex:Int = 0;

		var lmin:Float = 0;
		var lmax:Float = 0;
		var rmin:Float = 0;
		var rmax:Float = 0;

		var rows:Float = 0;
		var simpleSample:Bool = true;
		var v1:Bool = false;

		if (array == null) array = [[[0], [0]], [[0], [0]]];

		while (index < (bytes.length - 1)) {
			if (index >= 0) {
				var byte:Int = bytes.getUInt16(index * channels * 2);
				if (byte > 65535 / 2) byte -= 65535;
				var sample:Float = (byte / 65535);

				if (sample > 0) {
					if (sample > lmax) lmax = sample;
				} else if (sample < 0) {
					if (sample < lmin) lmin = sample;
				}

				if (channels >= 2) {
					byte = bytes.getUInt16((index * channels * 2) + 2);
					if (byte > 65535 / 2) byte -= 65535;
					sample = (byte / 65535);

					if (sample > 0) {
						if (sample > rmax) rmax = sample;
					} else if (sample < 0) {
						if (sample < rmin) rmin = sample;
					}
				}
			}

			v1 = samplesPerRowI > 0 ? (index % samplesPerRowI == 0) : false;
			while (simpleSample ? v1 : rows >= samplesPerRow) {
				v1 = false;
				rows -= samplesPerRow;

				gotIndex++;

				var lRMin:Float = Math.abs(lmin) * multiply;
				var lRMax:Float = lmax * multiply;
				var rRMin:Float = Math.abs(rmin) * multiply;
				var rRMax:Float = rmax * multiply;

				if (gotIndex > array[0][0].length) array[0][0].push(lRMin);
				else array[0][0][gotIndex - 1] = array[0][0][gotIndex - 1] + lRMin;

				if (gotIndex > array[0][1].length) array[0][1].push(lRMax);
				else array[0][1][gotIndex - 1] = array[0][1][gotIndex - 1] + lRMax;

				if (channels >= 2) {
					if (gotIndex > array[1][0].length) array[1][0].push(rRMin);
					else array[1][0][gotIndex - 1] = array[1][0][gotIndex - 1] + rRMin;

					if (gotIndex > array[1][1].length) array[1][1].push(rRMax);
					else array[1][1][gotIndex - 1] = array[1][1][gotIndex - 1] + rRMax;
				} else {
					if (gotIndex > array[1][0].length) array[1][0].push(lRMin);
					else array[1][0][gotIndex - 1] = array[1][0][gotIndex - 1] + lRMin;

					if (gotIndex > array[1][1].length) array[1][1].push(lRMax);
					else array[1][1][gotIndex - 1] = array[1][1][gotIndex - 1] + lRMax;
				}

				lmin = 0;
				lmax = 0;
				rmin = 0;
				rmax = 0;
			}

			index++;
			rows++;
			if (gotIndex > steps) break;
		}

		return array;
		#else
		return [[[0], [0]], [[0], [0]]];
		#end
	}

	function changeNoteSustain(value:Float):Void
	{
		if (curSelectedNote != null) {
			if (curSelectedNote[2] != null) {
				curSelectedNote[2] += Math.ceil(value);
				curSelectedNote[2] = Math.max(curSelectedNote[2], 0);
			}
		}

		updateNoteUI();
		invalidateRenderCache(curSec);
		updateGrid();
	}

	function recalculateSteps(add:Float = 0):Int
	{
		var songTime:Float = FlxG.sound.music.time;
		var bpmMap:Array<BPMChangeEvent> = Conductor.bpmChangeMap;
		var lastChange:BPMChangeEvent = {stepTime: 0, songTime: 0, bpm: 0};
		var mapLength:Int = bpmMap == null ? 0 : bpmMap.length;

		if (mapLength > 0) {
			// Re-seek after a map rebuild, backward seek, or large time jump.
			// The strict '>' preserves the original boundary behavior.
			if (cachedBpmMap != bpmMap || songTime < cachedBpmMapTime || songTime - cachedBpmMapTime > 250 || cachedBpmMapIndex >= mapLength) {
				var low:Int = 0;
				var high:Int = mapLength - 1;
				var found:Int = -1;
				while (low <= high) {
					var middle:Int = low + Std.int((high - low) / 2);
					if (songTime > bpmMap[middle].songTime) {
						found = middle;
						low = middle + 1;
					} else {
						high = middle - 1;
					}
				}
				cachedBpmMap = bpmMap;
				cachedBpmMapIndex = found;
			} else {
				// Normal playback advances through zero or a few changes only.
				while (cachedBpmMapIndex + 1 < mapLength && songTime > bpmMap[cachedBpmMapIndex + 1].songTime) {
					cachedBpmMapIndex++;
				}
			}
			if (cachedBpmMapIndex >= 0 && cachedBpmMapIndex < mapLength) {
				lastChange = bpmMap[cachedBpmMapIndex];
			}
		}
		cachedBpmMapTime = songTime;

		curStep = lastChange.stepTime + Math.floor((songTime - lastChange.songTime + add) / Conductor.stepCrochet);
		updateBeat();

		return curStep;
	}

	function resetSection(songBeginning:Bool = false):Void
	{
		updateGrid();

		FlxG.sound.music.pause();
		FlxG.sound.music.time = sectionStartTime();

		if (songBeginning) {
			FlxG.sound.music.time = 0;
			curSec = 0;
		}

		pauseAndSetVocalsTime();
		updateCurStep();

		updateGrid();
		updateSectionUI();
		updateWaveform();
	}

	function changeSection(sec:Int = 0, ?updateMusic:Bool = true):Void
	{
		var waveformChanged:Bool = false;
		if (_song.notes[sec] != null) {
			curSec = sec;
			if (updateMusic) {
				FlxG.sound.music.pause();
				FlxG.sound.music.time = sectionStartTime();
				pauseAndSetVocalsTime();
				updateCurStep();
			}

			var blah1:Float = getSectionBeats();
			var blah2:Float = getSectionBeats(curSec + 1);
			if (sectionStartTime(1) > FlxG.sound.music.length) blah2 = 0;
	
			if (blah1 != lastSecBeats || blah2 != lastSecBeatsNext) {
				reloadGridLayer();
				waveformChanged = true;
			} else {
				updateGrid();
			}
			updateSectionUI();
		} else {
			changeSection();
		}
		Conductor.songPosition = FlxG.sound.music.time;
		if (!waveformChanged) updateWaveform();
	}

	function updateSectionUI():Void
	{
		var sec = _song.notes[curSec];

		stepperBeats.value = getSectionBeats();
		check_mustHitSection.checked = sec.mustHitSection;
		check_gfSection.checked = sec.gfSection;
		check_altAnim.checked = sec.altAnim;
		check_changeBPM.checked = sec.changeBPM;
		stepperSectionBPM.value = sec.bpm;

		updateHeads();
	}

	var characterData:Dynamic = {
		iconP1: null,
		iconP2: null,
		vocalsP1: null,
		vocalsP2: null
	};

	function updateJsonData():Void
	{
		for (i in 1...3) {
			var data:CharacterFile = loadCharacterFile(Reflect.field(_song, 'player$i'));
			Reflect.setField(characterData, 'iconP$i', !characterFailed ? data.healthicon : 'face');
			Reflect.setField(characterData, 'vocalsP$i', data.vocals_file != null ? data.vocals_file : '');
		}
	}

	function updateHeads():Void
	{
		if (_song.notes[curSec].mustHitSection) {
			leftIcon.changeIcon(characterData.iconP1);
			rightIcon.changeIcon(characterData.iconP2);
			if (_song.notes[curSec].gfSection) leftIcon.changeIcon('gf');
		} else {
			leftIcon.changeIcon(characterData.iconP2);
			rightIcon.changeIcon(characterData.iconP1);
			if (_song.notes[curSec].gfSection) leftIcon.changeIcon('gf');
		}
	}

	var characterFailed:Bool = false;

	function loadCharacterFile(char:String):CharacterFile {
		characterFailed = false;
		var characterPath:String = 'characters/' + char + '.json';
		#if MODS_ALLOWED
		var path:String = Paths.modFolders(characterPath);
		if (!FileSystem.exists(path)) {
			path = Paths.getSharedPath(characterPath);
		}

		if (!FileSystem.exists(path))
		#else
		var path:String = Paths.getSharedPath(characterPath);
		if (!OpenFlAssets.exists(path))
		#end
		{
			path = Paths.getSharedPath('characters/' + Character.DEFAULT_CHARACTER + '.json');
			characterFailed = true;
		}

		#if MODS_ALLOWED
		var rawJson = File.getContent(path);
		#else
		var rawJson = OpenFlAssets.getText(path);
		#end
		return cast Json.parse(rawJson);
	}

	function updateNoteUI():Void
	{
		if (curSelectedNote != null) {
			if (curSelectedNote[2] != null) {
				stepperSusLength.value = curSelectedNote[2];
				if (curSelectedNote[3] != null) {
					currentType = curNoteTypes.indexOf(curSelectedNote[3]);
					if (currentType <= 0) {
						noteTypeDropDown.selectedLabel = '';
					} else {
						noteTypeDropDown.selectedLabel = currentType + '. ' + curSelectedNote[3];
					}
				}
			} else {
				eventDropDown.selectedLabel = curSelectedNote[1][curEventSelected][0];
				var selected:Int = Std.parseInt(eventDropDown.selectedId);
				if (selected > 0 && selected < eventStuff.length) {
					descText.text = eventStuff[selected][1];
				}
				value1InputText.text = curSelectedNote[1][curEventSelected][1];
				value2InputText.text = curSelectedNote[1][curEventSelected][2];
			}
			strumTimeInputText.text = '' + curSelectedNote[0];
		}
	}

	// Caching & Density Optimization
	private function invalidateRenderCache(?sectionIndex:Int = -1, ?invalidateNoteCount:Bool = true):Void
	{
		// A note edit invalidates the total count, but ordinary frame updates do not.
		if (invalidateNoteCount) noteCountCacheValid = false;
		if (sectionIndex < 0) {
			sectionDensityCache = new Map();
			sectionDensityCacheDirty = new Map();
			return;
		}
		sectionDensityCache.remove(sectionIndex);
		sectionDensityCacheDirty.set(sectionIndex, true);
	}

	private inline function compareNoteEntries(a:Array<Dynamic>, b:Array<Dynamic>):Int
	{
		var aTime:Float = (a != null && a.length > 0 && a[0] != null) ? a[0] : 0;
		var bTime:Float = (b != null && b.length > 0 && b[0] != null) ? b[0] : 0;
		if (aTime < bTime) return -1;
		if (aTime > bTime) return 1;
		return 0;
	}

	private function rebuildSectionDensityCache(sectionIndex:Int):Map<Int, Array<Array<Dynamic>>>
	{
		var buckets:Map<Int, Array<Array<Dynamic>>> = new Map();
		if (_song == null || _song.notes == null || _song.notes[sectionIndex] == null || _song.notes[sectionIndex].sectionNotes == null) {
			sectionDensityCache.set(sectionIndex, buckets);
			sectionDensityCacheDirty.set(sectionIndex, false);
			return buckets;
		}

		var density:Int = Std.int(Math.max(1, noteDensity));
		for (note in _song.notes[sectionIndex].sectionNotes) {
			if (note == null || note.length < 2) continue;
			var bucket:Int = Std.int(Math.floor(note[0] / density));
			if (!buckets.exists(bucket)) buckets.set(bucket, []);
			buckets.get(bucket).push(note);
		}

		for (bucket in buckets.keys()) {
			var bucketNotes = buckets.get(bucket);
			if (bucketNotes != null && bucketNotes.length > 1) {
				bucketNotes.sort(compareNoteEntries);
			}
		}

		sectionDensityCache.set(sectionIndex, buckets);
		sectionDensityCacheDirty.set(sectionIndex, false);
		return buckets;
	}

	private inline function getSectionDensityCache(sectionIndex:Int):Map<Int, Array<Array<Dynamic>>>
	{
		if (!sectionDensityCache.exists(sectionIndex) || (sectionDensityCacheDirty.exists(sectionIndex) && sectionDensityCacheDirty.get(sectionIndex))) {
			return rebuildSectionDensityCache(sectionIndex);
		}
		return sectionDensityCache.get(sectionIndex);
	}

	private function invalidateEventRenderCache():Void
	{
		eventSectionCache = new Map();
		eventSectionCacheValid = false;
	}

	private function findSectionForEventTime(eventTime:Float):Int
	{
		if (cachedSectionStarts.length == 0) return -1;
		var low:Int = 0;
		var high:Int = cachedSectionStarts.length - 1;
		var result:Int = 0;
		while (low <= high) {
			var middle:Int = low + Std.int((high - low) / 2);
			if (cachedSectionStarts[middle] <= eventTime) {
				result = middle;
				low = middle + 1;
			} else {
				high = middle - 1;
			}
		}
		return result;
	}

	private function rebuildEventRenderCache():Void
	{
		var eventIndexStarted:Float = haxe.Timer.stamp();
		eventSectionCache = new Map();
		if (_song == null || _song.events == null || _song.notes == null || _song.notes.length == 0) {
			eventSectionCacheValid = true;
			lastEventIndexMs = (haxe.Timer.stamp() - eventIndexStarted) * 1000;
			return;
		}

		if (sectionCacheDirty || cachedSectionStarts.length != _song.notes.length) {
			rebuildSectionStartCache();
		}

		for (event in _song.events) {
			if (event == null || event.length < 2 || event[0] == null || event[1] == null) continue;
			var sectionIndex:Int = findSectionForEventTime(event[0]);
			if (sectionIndex < 0) continue;
			if (!eventSectionCache.exists(sectionIndex)) eventSectionCache.set(sectionIndex, []);
			eventSectionCache.get(sectionIndex).push(event);
		}
		eventSectionCacheValid = true;
		lastEventIndexMs = (haxe.Timer.stamp() - eventIndexStarted) * 1000;
	}

	private function getEventsForSection(sectionIndex:Int):Array<Dynamic>
	{
		if (!eventSectionCacheValid) rebuildEventRenderCache();
		if (eventSectionCache.exists(sectionIndex)) return eventSectionCache.get(sectionIndex);
		return [];
	}

	private inline function isNoteRenderEnabled():Bool
	{
		return showNotes && noteAlpha > 0;
	}

	function updateGrid():Void
	{
		var gridBuildStarted:Float = haxe.Timer.stamp();
		curRenderedNotes.forEachAlive(function(spr:Note) spr.destroy());
		curRenderedNotes.clear();
		curRenderedSustains.forEachAlive(function(spr:FlxSprite) spr.destroy());
		curRenderedSustains.clear();
		curRenderedNoteType.forEachAlive(function(spr:FlxText) spr.destroy());
		curRenderedNoteType.clear();
		nextRenderedNotes.forEachAlive(function(spr:Note) spr.destroy());
		nextRenderedNotes.clear();
		nextRenderedSustains.forEachAlive(function(spr:FlxSprite) spr.destroy());
		nextRenderedSustains.clear();

		if (_song == null || _song.notes == null || _song.notes.length == 0 || curSec < 0 || curSec >= _song.notes.length || _song.notes[curSec] == null) {
			updatePresenceCounter();
			lastChartGridMs = (haxe.Timer.stamp() - gridBuildStarted) * 1000;
			return;
		}

		if (_song.notes[curSec].changeBPM && _song.notes[curSec].bpm > 0) {
			Conductor.bpm = _song.notes[curSec].bpm;
		} else {
			var daBPM:Float = _song.bpm;
			for (i in 0...curSec)
				if (_song.notes[i] != null && _song.notes[i].changeBPM) daBPM = _song.notes[i].bpm;
			Conductor.bpm = daBPM;
		}

		// A shared budget covers current/next section note heads and event markers.
		// This bounds sprite creation even when a single section contains millions of rows.
		var renderBudget:Int = Std.int(FlxMath.bound(renderDensity, 128, MAX_RENDERED_NOTES));

		if (isNoteRenderEnabled() && renderBudget > 0 && _song.notes[curSec].sectionNotes != null) {
			var beats:Float = getSectionBeats();
			for (i in _song.notes[curSec].sectionNotes) {
				if (renderBudget <= 0) break;
				if (i == null || i.length < 2 || i[0] == null || i[1] == null) continue;
				var note:Note = setupNoteData(i, false);
				note.mustPress = _song.notes[curSec].mustHitSection;
				if (i[1] > 3) note.mustPress = !note.mustPress;
				curRenderedNotes.add(note);
				renderBudget--;
				if (note.sustainLength > 0) {
					curRenderedSustains.add(setupSusNote(note, beats));
				}

				if (i.length > 3 && i[3] != null && note.noteType != null && note.noteType.length > 0) {
					var typeInt:Int = curNoteTypes.indexOf(i[3]);
					var theType:String = '' + typeInt;
					if (typeInt < 0) theType = '?';

					var daText:AttachedFlxText = new AttachedFlxText(0, 0, 100, theType, 24);
					daText.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE_FAST, FlxColor.BLACK);
					daText.xAdd = -32;
					daText.yAdd = 6;
					daText.borderSize = 1;
					curRenderedNoteType.add(daText);
					daText.sprTracker = note;
				}
			}
		}

		// Spam-generated rows are held in compact typed buffers. Materialize only
		// the small number admitted by the render budget.
		if (isNoteRenderEnabled() && renderBudget > 0) {
			var packedCurrent:PackedNoteBuffer = getPackedSpamSection(curSec);
			if (packedCurrent != null) {
				var packedLimit:Int = packedCurrent.length < renderBudget ? packedCurrent.length : renderBudget;
				var beats:Float = getSectionBeats();
				for (packedIndex in 0...packedLimit) {
					var row:Array<Dynamic> = packedCurrent.getRow(packedIndex);
					if (row == null || row.length < 2) continue;
					var packedNote:Note = setupNoteData(row, false);
					packedNote.mustPress = _song.notes[curSec].mustHitSection;
					if (row[1] > 3) packedNote.mustPress = !packedNote.mustPress;
					curRenderedNotes.add(packedNote);
					renderBudget--;
					if (packedNote.sustainLength > 0) curRenderedSustains.add(setupSusNote(packedNote, beats));
					if (renderBudget <= 0) break;
				}
			}
		}

		// Event rows are independent from note visibility. Turning Show Events off
		// skips the entire event-array traversal, not just the marker drawing.
		if (showEvents && renderBudget > 0) {
			for (i in getEventsForSection(curSec)) {
				if (renderBudget <= 0) break;
				var note:Note = setupNoteData(i, false);
				curRenderedNotes.add(note);
				var eventText:String = 'Event: ' + note.eventName + ' (' + Math.floor(note.strumTime) + ' ms)' + '\nValue 1: ' + note.eventVal1 + '\nValue 2: ' + note.eventVal2;
				if (note.eventLength > 1) eventText = note.eventLength + ' Events:\n' + note.eventName;
				var daText:AttachedFlxText = new AttachedFlxText(0, 0, 400, eventText, 12);
				daText.setFormat(Paths.font("vcr.ttf"), 12, FlxColor.WHITE, RIGHT, FlxTextBorderStyle.OUTLINE_FAST, FlxColor.BLACK);
				daText.xAdd = -410;
				daText.borderSize = 1;
				if (note.eventLength > 1) daText.yAdd += 8;
				curRenderedNoteType.add(daText);
				daText.sprTracker = note;
				renderBudget--;
			}
		}

		if (isNoteRenderEnabled() && renderBudget > 0 && curSec < _song.notes.length - 1 && _song.notes[curSec + 1] != null && _song.notes[curSec + 1].sectionNotes != null) {
			var beats:Float = getSectionBeats(1);
			for (i in _song.notes[curSec + 1].sectionNotes) {
				if (renderBudget <= 0) break;
				if (i == null || i.length < 2 || i[0] == null || i[1] == null) continue;
				var note:Note = setupNoteData(i, true);
				note.alpha = 0.6 * noteAlpha;
				nextRenderedNotes.add(note);
				renderBudget--;
				if (note.sustainLength > 0) {
					nextRenderedSustains.add(setupSusNote(note, beats));
				}
			}
		}

		if (isNoteRenderEnabled() && renderBudget > 0 && curSec < _song.notes.length - 1) {
			var packedNext:PackedNoteBuffer = getPackedSpamSection(curSec + 1);
			if (packedNext != null) {
				var packedNextLimit:Int = packedNext.length < renderBudget ? packedNext.length : renderBudget;
				for (packedIndex in 0...packedNextLimit) {
					var row:Array<Dynamic> = packedNext.getRow(packedIndex);
					if (row == null || row.length < 2) continue;
					var packedNote:Note = setupNoteData(row, true);
					packedNote.alpha = 0.6 * noteAlpha;
					nextRenderedNotes.add(packedNote);
					renderBudget--;
					if (packedNote.sustainLength > 0) nextRenderedSustains.add(setupSusNote(packedNote, getSectionBeats(1)));
					if (renderBudget <= 0) break;
				}
			}
		}

		if (showEvents && renderBudget > 0) {
			for (i in getEventsForSection(curSec + 1)) {
				if (renderBudget <= 0) break;
				var note:Note = setupNoteData(i, true);
				note.alpha = 0.6;
				nextRenderedNotes.add(note);
				renderBudget--;
			}
		}

		updatePresenceCounter();
		lastChartGridMs = (haxe.Timer.stamp() - gridBuildStarted) * 1000;
	}

	function setupNoteData(i:Array<Dynamic>, isNextSection:Bool):Note
	{
		var daNoteInfo = i[1];
		var daStrumTime = i[0];
		var daSus:Dynamic = i[2];

		var note:Note = new Note(daStrumTime, daNoteInfo % 4, null, null, true);
		if (daSus != null) {
			var noteType:String = null;
			if (i.length > 3 && i[3] != null) {
				if (Std.isOfType(i[3], String)) {
					noteType = cast i[3];
				} else {
					var noteTypeIndex:Int = Std.int(i[3]);
					if (noteTypeIndex >= 0 && noteTypeIndex < curNoteTypes.length) {
						noteType = curNoteTypes[noteTypeIndex];
						i[3] = noteType;
					}
				}
				if (noteType != null && noteType.length == 0) noteType = null;
			}
			note.sustainLength = daSus;
			note.noteType = noteType;
		} else {
			note.loadGraphic(Paths.image('eventArrow'));
			note.rgbShader.enabled = false;
			note.eventName = getEventName(i[1]);
			note.eventLength = i[1].length;
			if (i[1].length < 2) {
				note.eventVal1 = i[1][0][1];
				note.eventVal2 = i[1][0][2];
			}
			note.noteData = -1;
			daNoteInfo = -1;
		}

		note.setGraphicSize(GRID_SIZE, GRID_SIZE);
		note.updateHitbox();
		note.x = Math.floor(daNoteInfo * GRID_SIZE) + GRID_SIZE;
		if (isNextSection && _song.notes[curSec].mustHitSection != _song.notes[curSec + 1].mustHitSection) {
			if (daNoteInfo > 3) {
				note.x -= GRID_SIZE * 4;
			} else if (daSus != null) {
				note.x += GRID_SIZE * 4;
			}
		}

		var beats:Float = getSectionBeats(isNextSection ? 1 : 0);
		note.y = getYfromStrumNotes(daStrumTime - sectionStartTime(), beats);
		if (note.y < -150) note.y = -150;
		return note;
	}

	function getEventName(names:Array<Dynamic>):String
	{
		var retStr:String = '';
		var addedOne:Bool = false;
		for (i in 0...names.length) {
			if (addedOne) retStr += ', ';
			retStr += names[i][0];
			addedOne = true;
		}
		return retStr;
	}

	function setupSusNote(note:Note, beats:Float):FlxSprite {
		var height:Int = Math.floor(FlxMath.remapToRange(note.sustainLength, 0, Conductor.stepCrochet * 16, 0, GRID_SIZE * 16 * zoomList[curZoom]) + (GRID_SIZE * zoomList[curZoom]) - GRID_SIZE / 2);
		var minHeight:Int = Std.int((GRID_SIZE * zoomList[curZoom] / 2) + GRID_SIZE / 2);
		if (height < minHeight) height = minHeight;
		if (height < 1) height = 1;

		var spr:FlxSprite = new FlxSprite(note.x + (GRID_SIZE * 0.5) - 4, note.y + GRID_SIZE / 2).makeGraphic(8, height);
		return spr;
	}

	private function addSection(sectionBeats:Float = 4):Void
	{
		var sec:SwagSection = {
			sectionBeats: sectionBeats,
			bpm: _song.bpm,
			changeBPM: false,
			mustHitSection: true,
			gfSection: false,
			sectionNotes: [],
			altAnim: false
		};
		_song.notes.push(sec);
		sectionCacheDirty = true;
		invalidateEventRenderCache();
	}

	function selectNote(note:Note):Void
	{
		var noteDataToCheck:Int = note.noteData;

		if (noteDataToCheck > -1) {
			if (note.mustPress != _song.notes[curSec].mustHitSection) noteDataToCheck += 4;
			var foundNote:Bool = false;
			for (i in _song.notes[curSec].sectionNotes) {
				if (i != curSelectedNote && i.length > 2 && i[0] == note.strumTime && i[1] == noteDataToCheck) {
					curSelectedNote = i;
					foundNote = true;
					break;
				}
			}
			// Selecting one compact row should expand only that row, not millions
			// of spam-generated notes in the section.
			if (!foundNote) {
				var packed:PackedNoteBuffer = getPackedSpamSection(curSec);
				if (packed != null) {
					var packedIndex:Int = packed.find(note.strumTime, noteDataToCheck);
					if (packedIndex >= 0) {
						var selectedRow:Array<Dynamic> = packed.takeAt(packedIndex);
						if (selectedRow != null) {
							_song.notes[curSec].sectionNotes.push(selectedRow);
							curSelectedNote = selectedRow;
							if (packed.length == 0) packedSpamSections.remove(curSec);
						}
					}
				}
			}
		} else {
			for (i in _song.events) {
				if (i != curSelectedNote && i[0] == note.strumTime) {
					curSelectedNote = i;
					curEventSelected = Std.int(curSelectedNote[1].length) - 1;
					break;
				}
			}
		}
		changeEventSelected();
		updateGrid();
		updateNoteUI();
	}

	function deleteNote(note:Note):Void
	{
		var noteDataToCheck:Int = note.noteData;
		if (noteDataToCheck > -1 && note.mustPress != _song.notes[curSec].mustHitSection) noteDataToCheck += 4;

		if (note.noteData > -1) {
			var removedLegacy:Bool = false;
			for (i in _song.notes[curSec].sectionNotes) {
				if (i != null && i.length > 1 && i[0] == note.strumTime && i[1] == noteDataToCheck) {
					if (i == curSelectedNote) curSelectedNote = null;
					_song.notes[curSec].sectionNotes.remove(i);
					removedLegacy = true;
					break;
				}
			}
			if (!removedLegacy) {
				var packed:PackedNoteBuffer = getPackedSpamSection(curSec);
				if (packed != null) {
					var packedIndex:Int = packed.find(note.strumTime, noteDataToCheck);
					if (packedIndex >= 0) {
						if (curSelectedNote != null && curSelectedNote.length > 1 && curSelectedNote[0] == note.strumTime && curSelectedNote[1] == noteDataToCheck)
							curSelectedNote = null;
						packed.removeAt(packedIndex);
						if (packed.length == 0) packedSpamSections.remove(curSec);
					}
				}
			}
		} else {
			for (i in _song.events) {
				if (i[0] == note.strumTime) {
					if (i == curSelectedNote) {
						curSelectedNote = null;
						changeEventSelected();
					}
					_song.events.remove(i);
					invalidateEventRenderCache();
					break;
				}
			}
		}
		invalidateRenderCache(curSec);
		updateGrid();
	}

	public function doANoteThing(cs, d, style) {
		var delnote = false;
		if (strumLineNotes.members[d].overlaps(curRenderedNotes)) {
			curRenderedNotes.forEachAlive(function(note:Note) {
				if (note.overlapsPoint(new FlxPoint(strumLineNotes.members[d].x + 1, strumLine.y + 1)) && note.noteData == d % 4) {
					if (!delnote) deleteNote(note);
					delnote = true;
				}
			});
		}

		if (!delnote) {
			addNote(cs, d, style);
		}
	}

	function clearSong():Void
	{
		pendingSpamCount = 0;
		pendingSpamSection = -1;
		pendingSpamRateAccumulator = 0;
		lastSpamProcessTimestamp = 0;
		endSpamBackgroundMode();
		packedSpamSections = new Map<Int, PackedNoteBuffer>();
		for (daSection in 0..._song.notes.length) {
			_song.notes[daSection].sectionNotes = [];
		}
		invalidateRenderCache();
		updateGrid();
	}

	// Centralized note insertion guard: every editor operation that adds a
	// note row can use the full signed 32-bit section range. The complete chart
	// retains its separate signed 32-bit safety ceiling.
	private function appendNoteToSection(sectionIndex:Int, note:Array<Dynamic>):Bool
	{
		if (_song == null || _song.notes == null || note == null || sectionIndex < 0 || sectionIndex >= _song.notes.length) return false;
		var section = _song.notes[sectionIndex];
		if (section == null) return false;
		if (section.sectionNotes == null) section.sectionNotes = [];
		if (getSectionNoteCount(sectionIndex) >= MAX_SECTION_NOTE_COUNT) return false;
		if (getNoteAmount() >= MAX_CHART_NOTE_COUNT) return false;
		section.sectionNotes.push(note);
		if (noteCountCacheValid) cachedTotalNoteCount += Int64.ofInt(1);
		return true;
	}

	private function addNote(strum:Null<Float> = null, data:Null<Int> = null, type:Null<Int> = null, refresh:Bool = true):Void
	{
		var noteStrum = getStrumTime(dummyArrow.y * (getSectionBeats() / 4), false) + sectionStartTime();
		var noteData = Math.floor((FlxG.mouse.x - GRID_SIZE) / GRID_SIZE);
		var noteSus = 0;
		var daAlt = false;
		var daType = currentType;

		if (strum != null) noteStrum = strum;
		if (data != null) noteData = data;
		if (type != null) daType = type;

		if (noteData > -1) {
			var createdNote:Array<Dynamic> = [noteStrum, noteData, noteSus, curNoteTypes[daType]];
			if (!appendNoteToSection(curSec, createdNote)) {
				FlxG.log.add('This section or the complete chart reached its configured 64-bit-safe note limit (5,000,000,000).');
				return;
			}
			curSelectedNote = createdNote;
		} else {
			var event = eventStuff[Std.parseInt(eventDropDown.selectedId)][0];
			var text1 = value1InputText.text;
			var text2 = value2InputText.text;
			_song.events.push([noteStrum, [[event, text1, text2]]]);
			curSelectedNote = _song.events[_song.events.length - 1];
			curEventSelected = 0;
		}
		if (noteData > -1 && FlxG.keys.pressed.CONTROL) {
			appendNoteToSection(curSec, [noteStrum, (noteData + 4) % 8, noteSus, curNoteTypes[daType]]);
		}

		if (refresh) {
			changeEventSelected();
			strumTimeInputText.text = '' + curSelectedNote[0];
			invalidateRenderCache(curSec);
			updateGrid();
			updateNoteUI();
		}
	}

	#if cpp
	private function reserveSpamSectionCapacity(sectionNotes:Array<Dynamic>, requiredCapacity:Int):Bool
	{
		if (sectionNotes == null || requiredCapacity < 0) return false;
		try {
			var currentCapacity:Int = cpp.NativeArray.capacity(sectionNotes);
			if (requiredCapacity > currentCapacity) {
				// Geometric growth avoids copying an ever-larger pointer array every
				// million rows (1M -> 2M -> 4M -> 8M instead of 1M steps).
				var expandedCapacity:Int = currentCapacity;
				if (expandedCapacity < SPAM_RESERVE_CHUNK_SIZE) {
					expandedCapacity = SPAM_RESERVE_CHUNK_SIZE;
				} else if (expandedCapacity <= 1073741823) {
					expandedCapacity *= 2;
				} else {
					expandedCapacity = 2147483647;
				}
				var reserveTarget:Int = requiredCapacity > expandedCapacity ? requiredCapacity : expandedCapacity;
				if (reserveTarget > 2147483647) reserveTarget = 2147483647;
				cpp.NativeArray.reserve(sectionNotes, reserveTarget);
			}
			return cpp.NativeArray.capacity(sectionNotes) >= requiredCapacity;
		} catch (error:Dynamic) {
			FlxG.log.add('Note spam stopped: could not reserve chart-note storage ($error).');
			return false;
		}
	}
	#end

	/** Keep the HaxeFlixel update loop running while a spam job is active.
	 * This is an in-process background mode, not a separate worker thread:
	 * packed chart data is still mutated on the main thread for safety.
	 */
	private function beginSpamBackgroundMode():Void
	{
		if (spamBackgroundModeActive) return;
		spamPreviousAutoPause = FlxG.autoPause;
		spamBackgroundModeActive = true;
		FlxG.autoPause = false;
	}

	/** Restore the user's normal focus-pause preference after the job ends. */
	private function endSpamBackgroundMode():Void
	{
		if (!spamBackgroundModeActive) return;
		FlxG.autoPause = spamPreviousAutoPause;
		spamBackgroundModeActive = false;
	}

	private function queueNoteSpam(count:Int64, sectionIndex:Int, startTime:Float, startData:Int, spacing:Float, sideOffset:Int, noteType:Int):Void
	{
		if (_song == null || _song.notes == null || count <= 0 || sectionIndex < 0 || sectionIndex >= _song.notes.length || _song.notes[sectionIndex] == null) return;

		var targetSectionNotes:Array<Dynamic> = _song.notes[sectionIndex].sectionNotes;
		if (targetSectionNotes == null) {
			targetSectionNotes = [];
			_song.notes[sectionIndex].sectionNotes = targetSectionNotes;
		}
		var packedTarget:PackedNoteBuffer = getPackedSpamSection(sectionIndex, true);

		// Capacity is checked against both legacy rows and the compact generated
		// buffer. The chart-wide signed 32-bit ceiling remains a separate guard.
		var remainingSectionCapacity:Int64 = MAX_SECTION_NOTE_COUNT - getSectionNoteCount(sectionIndex);
		var remainingChartCapacity:Int64 = MAX_CHART_NOTE_COUNT - getNoteAmount();
		if (remainingSectionCapacity <= Int64.ofInt(0) || remainingChartCapacity <= Int64.ofInt(0)) return;
		var remainingCapacity:Int64 = remainingSectionCapacity < remainingChartCapacity ? remainingSectionCapacity : remainingChartCapacity;
		if (count > remainingCapacity) count = remainingCapacity;
		// Reserve the four compact typed columns once before generation starts.
		// Unlike Array<Dynamic> rows, each generated note does not allocate its
		// own heap array; the row data lives in contiguous primitive arrays.
		var initialReserveCount:Int = count > Int64.ofInt(SPAM_RESERVE_CHUNK_SIZE) ? SPAM_RESERVE_CHUNK_SIZE : Int64.toInt(count);
		if (!packedTarget.reserve(packedTarget.length64 + Int64.ofInt(initialReserveCount))) {
			FlxG.log.add('Note spam stopped: could not reserve compact note storage.');
			return;
		}

		// The regular FlxGame loop normally stops on focus loss when autoPause is
		// enabled. Disable that temporarily so this queued job continues while
		// the user switches to another application.
		beginSpamBackgroundMode();
		pendingSpamCount = count;
		pendingSpamSection = sectionIndex;
		pendingSpamTime = startTime;
		pendingSpamData = startData;
		pendingSpamSpacing = spacing;
		pendingSpamSideOffset = sideOffset;
		pendingSpamType = noteType;
		pendingSpamRateAccumulator = 0;
		lastSpamProcessTimestamp = haxe.Timer.stamp();
		spamRateWindowStart = lastSpamProcessTimestamp;
		spamRateWindowRows = 0;
		spamJobStartTimestamp = lastSpamProcessTimestamp;
		spamJobGeneratedRows = 0;
		currentMeasuredSpamRate = 0;
		lastMeasuredSpamRate = 0;
	}

	private function processPendingNoteSpam():Void
	{
		if (pendingSpamCount <= 0) {
			lastSpamBatchMs = 0;
			pendingSpamRateAccumulator = 0;
			lastSpamProcessTimestamp = 0;
			currentMeasuredSpamRate = 0;
			return;
		}
		var spamBatchStarted:Float = haxe.Timer.stamp();
		lastSpamBatchMs = 0;
		lastSpamBatchRows = 0;
		if (_song == null || _song.notes == null || pendingSpamSection < 0 || pendingSpamSection >= _song.notes.length || _song.notes[pendingSpamSection] == null) {
			pendingSpamCount = 0;
			pendingSpamSection = -1;
			pendingSpamRateAccumulator = 0;
			lastSpamProcessTimestamp = 0;
			endSpamBackgroundMode();
			spamRateWindowRows = 0;
			spamJobGeneratedRows = 0;
			currentMeasuredSpamRate = 0;
			return;
		}

		// Use wall-clock time to maintain the requested rate, but do not let a
		// slow frame create a massive catch-up batch. This was the feedback loop
		// behind editor stalls: a long frame accrued a huge batch, then that batch
		// made the next frame even longer. Keep only 50 ms of rate debt.
		var now:Float = haxe.Timer.stamp();
		var realElapsed:Float = now - lastSpamProcessTimestamp;
		lastSpamProcessTimestamp = now;
		if (Math.isNaN(realElapsed) || realElapsed < 0) realElapsed = 0;
		if (realElapsed > SPAM_MAX_CATCHUP_SECONDS) realElapsed = SPAM_MAX_CATCHUP_SECONDS;
		pendingSpamRateAccumulator += realElapsed * NOTE_SPAM_RATE_PER_SECOND;
		var maxDebt:Float = NOTE_SPAM_RATE_PER_SECOND * SPAM_MAX_CATCHUP_SECONDS;
		if (pendingSpamRateAccumulator > maxDebt) pendingSpamRateAccumulator = maxDebt;
		var availableBudget:Int = Std.int(Math.floor(pendingSpamRateAccumulator));
		if (availableBudget <= 0) return;

		var packedNotes:PackedNoteBuffer = getPackedSpamSection(pendingSpamSection, true);

		var batchLimit:Int = pendingSpamCount > Int64.ofInt(availableBudget) ? availableBudget : Int64.toInt(pendingSpamCount);
		if (batchLimit > MAX_SPAM_BATCH_PER_FRAME) batchLimit = MAX_SPAM_BATCH_PER_FRAME;
		if (batchLimit <= 0) return;

		if (!packedNotes.reserve(packedNotes.length64 + Int64.ofInt(batchLimit))) {
			// Keep every note already committed; abandon only the ungenerated tail.
			pendingSpamCount = 0;
			batchLimit = 0;
		}
		if (batchLimit <= 0) {
			finishPendingNoteSpam();
			return;
		}

		var noteTypeName:String = (pendingSpamType >= 0 && pendingSpamType < curNoteTypes.length) ? curNoteTypes[pendingSpamType] : '';
		var hasSpamNoteType:Bool = noteTypeName != null && noteTypeName.length > 0;
		var spamTypeId:Int = hasSpamNoteType ? packedNotes.internTypeValue(noteTypeName) : -1;
		// Keep frequently changed values in locals. This avoids repeated object
		// field writes in the hottest part of the million-row generation loop.
		var writeTime:Float = pendingSpamTime;
		var writeData:Int = pendingSpamData;
		var spacing:Float = pendingSpamSpacing;
		var sideOffset:Int = pendingSpamSideOffset;
		var generated:Int = 0;
		// Start conservatively, then enlarge batches only after measured throughput
		// demonstrates that the current machine can process them comfortably.
		var generatedBatchSize:Int = SPAM_GENERATED_BATCH_MIN;
		if (currentMeasuredSpamRate >= 20000000) generatedBatchSize = SPAM_GENERATED_BATCH_MID;
		if (currentMeasuredSpamRate >= 80000000) generatedBatchSize = SPAM_GENERATED_BATCH_MAX;
		// Generate directly into the packed primitive columns. This moves the
		// per-note work out of this state loop and amortizes reserve/Int64 updates
		// over each bounded batch. Timer checks remain between batches.
		var appendFailed:Bool = false;
		while (generated < batchLimit) {
			var requestedBatch:Int = batchLimit - generated;
			if (requestedBatch > generatedBatchSize) requestedBatch = generatedBatchSize;
			var appended:Int = packedNotes.appendGeneratedBatch(requestedBatch, writeTime, writeData,
				spacing, sideOffset, 0, spamTypeId);
			if (appended <= 0) {
				appendFailed = true;
				break;
			}
			generated += appended;
			writeTime = packedNotes.getLastWrittenTime();
			writeData = packedNotes.getLastWrittenLane();
			if (appended < requestedBatch) {
				appendFailed = true;
				break;
			}
			if ((haxe.Timer.stamp() - spamBatchStarted) * 1000 >= SPAM_FRAME_BUDGET_MS) break;
		}
		pendingSpamTime = writeTime;
		pendingSpamData = writeData;
		if (generated <= 0) {
			if (appendFailed) {
				FlxG.log.error('Note spam stopped because compact storage could not append another row. Existing generated notes were preserved.');
				pendingSpamCount = 0;
				finishPendingNoteSpam();
			}
			return;
		}
		if (appendFailed) {
			FlxG.log.error('Note spam stopped because compact storage could not append another row. Existing generated notes were preserved.');
			pendingSpamCount = 0;
		}
		pendingSpamRateAccumulator -= generated;
		if (pendingSpamRateAccumulator < 0) pendingSpamRateAccumulator = 0;
		pendingSpamCount -= Int64.ofInt(generated);
		spamRateWindowRows += generated;
		spamJobGeneratedRows += generated;

		// Keep the HUD count accurate without rescanning the complete chart.
		if (noteCountCacheValid) cachedTotalNoteCount += Int64.ofInt(generated);

		var finishedAt:Float = haxe.Timer.stamp();
		lastSpamBatchRows = generated;
		lastSpamBatchMs = (finishedAt - spamBatchStarted) * 1000;
		var sampleElapsed:Float = finishedAt - spamRateWindowStart;
		if (sampleElapsed >= 0.25) {
			currentMeasuredSpamRate = Std.int(Math.floor(spamRateWindowRows / sampleElapsed));
			spamRateWindowRows = 0;
			spamRateWindowStart = finishedAt;
		}

		if (pendingSpamCount <= 0) finishPendingNoteSpam();
	}

	/** Cancel the active background job but keep notes already generated. */
	private function cancelPendingNoteSpam():Void
	{
		if (pendingSpamCount <= 0 || pendingSpamSection < 0) {
			endSpamBackgroundMode();
			return;
		}
		pendingSpamCount = 0;
		finishPendingNoteSpam();
		FlxG.log.add('Background note spam cancelled. Generated notes were kept.');
	}

	private function finishPendingNoteSpam():Void
	{
		if (pendingSpamSection < 0) {
			endSpamBackgroundMode();
			return;
		}
		var completedSection:Int = pendingSpamSection;
		pendingSpamSection = -1;
		endSpamBackgroundMode();
		invalidateRenderCache(completedSection, false);
		pendingSpamRateAccumulator = 0;
		lastSpamProcessTimestamp = 0;
		var finishedAt:Float = haxe.Timer.stamp();
		var totalJobElapsed:Float = finishedAt - spamJobStartTimestamp;
		if (totalJobElapsed > 0)
			lastMeasuredSpamRate = Std.int(Math.floor(Std.parseFloat(Int64.toStr(spamJobGeneratedRows)) / totalJobElapsed));
		currentMeasuredSpamRate = 0;
		spamRateWindowRows = 0;
		// One bounded render refresh after all rows have been appended.
		updateGrid();
		changeEventSelected();
		if (curSelectedNote != null) strumTimeInputText.text = '' + curSelectedNote[0];
		updateNoteUI();
	}

	function redo() {}

	function undo()
	{
		undos.pop();
	}

	function getStrumTime(yPos:Float, doZoomCalc:Bool = true):Float
	{
		var leZoom:Float = zoomList[curZoom];
		if (!doZoomCalc) leZoom = 1;
		return FlxMath.remapToRange(yPos, gridBG.y, gridBG.y + gridBG.height * leZoom, 0, 16 * Conductor.stepCrochet);
	}

	function getYfromStrum(strumTime:Float, doZoomCalc:Bool = true):Float
	{
		var leZoom:Float = zoomList[curZoom];
		if (!doZoomCalc) leZoom = 1;
		return FlxMath.remapToRange(strumTime, 0, 16 * Conductor.stepCrochet, gridBG.y, gridBG.y + gridBG.height * leZoom);
	}
	
	function getYfromStrumNotes(strumTime:Float, beats:Float):Float
	{
		var value:Float = strumTime / (beats * 4 * Conductor.stepCrochet);
		return GRID_SIZE * beats * 4 * zoomList[curZoom] * value + gridBG.y;
	}

	function getNotes():Array<Dynamic>
	{
		var noteData:Array<Dynamic> = [];
		for (sectionIndex in 0..._song.notes.length) {
			var section = _song.notes[sectionIndex];
			var rows:Array<Dynamic> = section == null || section.sectionNotes == null ? [] : cast section.sectionNotes.copy();
			var packed:PackedNoteBuffer = getPackedSpamSection(sectionIndex);
			if (packed != null) packed.appendRowsTo(rows);
			noteData.push(rows);
		}
		return noteData;
	}

	var missingText:FlxText;
	var missingTextTimer:FlxTimer;

	function loadJson(song:String):Void
	{
		try {
			if (Difficulty.getString() != Difficulty.getDefault()) {
				if (Difficulty.getString() == null) {
					PlayState.SONG = Song.loadFromJson(song.toLowerCase(), song.toLowerCase());
				} else {
					PlayState.SONG = Song.loadFromJson(song.toLowerCase() + "-" + Difficulty.getString(), song.toLowerCase());
				}
			}
			else PlayState.SONG = Song.loadFromJson(song.toLowerCase(), song.toLowerCase());
			MusicBeatState.resetState();
		} catch(e) {
			trace('ERROR! $e');
			var errorStr:String = e.toString();
			if (errorStr.startsWith('[file_contents,assets/data/')) errorStr = 'Missing file: ' + errorStr.substring(27, errorStr.length-1);
			
			if (missingText == null) {
				missingText = new FlxText(50, 0, FlxG.width - 100, '', 24);
				missingText.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				missingText.scrollFactor.set();
				add(missingText);
			}
			else missingTextTimer.cancel();

			missingText.text = 'ERROR WHILE LOADING CHART:\n$errorStr';
			missingText.screenCenter(Y);

			missingTextTimer = new FlxTimer().start(5, function(tmr:FlxTimer) {
				remove(missingText);
				missingText.destroy();
			});
			FlxG.sound.play(Paths.sound('cancelMenu'));
		}
	}

	function autosaveSong():Void
	{
		// Autosave uses the legacy JSON object model. Expanding millions of compact
		// rows here would recreate the memory spike that compact storage avoids.
		// Keep the editor responsive; explicit Save Level still exports all rows.
		if (getNoteAmount() > Int64.ofInt(2000000))
		{
			FlxG.log.add('Autosave skipped for charts above 2,000,000 notes to avoid a large temporary memory spike. Use Save Level to export the complete chart.');
			return;
		}
		FlxG.save.data.autosave = haxe.Json.stringify({
			"song": buildSerializableSong()
		});
		FlxG.save.flush();
	}

	function clearEvents() {
		_song.events = [];
		invalidateEventRenderCache();
		updateGrid();
	}

	private function saveLevel()
	{
		#if sys
		if (splitChartSaveJob != null)
		{
			FlxG.log.add('A split chart save is already running.');
			return;
		}
		if (pendingSpamCount > 0)
		{
			FlxG.log.add('Wait for background note generation to finish before starting a chart save.');
			return;
		}
		if (_song.events != null && _song.events.length > 1) _song.events.sort(sortByTime);
		openSubState(new Prompt(
			'Hey! Save before a part reaches the 32-bit byte limit (2.1 GB).\n\nA single JSON part should not exceed 2.1 GB. Each split part pauses at 1 GB, 1.5 GB, 2 GB and the final 2.1 GB warning.\n\nBinary uses a small JSON manifest plus .bin parts.',
			0,
			function() chooseSplitSavePath(true),
			function() chooseSplitSavePath(false),
			false,
			'Save As Binary and split',
			'Save as JSON and split',
			'Continue editing',
			function() {}
		));
		#else
		if (_song.events != null && _song.events.length > 1) _song.events.sort(sortByTime);
		var json = { "song": buildSerializableSong() };
		var data:String = haxe.Json.stringify(json, "\t");
		if (data != null && data.length > 0)
		{
			_file = new FileReference();
			_file.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data.trim(), Paths.formatToSongPath(_song.song) + '.json');
		}
		#end
	}

	#if sys
	private function chooseSplitSavePath(binary:Bool):Void
	{
		if (splitChartSaveJob != null) return;
		splitSaveDialog = new FileDialog();
		var extension:String = binary ? '.bin' : '.json';
		var suggestedName:String = Paths.formatToSongPath(_song.song) + extension;
		var suggestedPath:String = Path.join([Sys.getCwd(), suggestedName]);
		splitSaveDialog.onSelect.add(function(selectedPath:String)
		{
			splitSaveDialog = null;
			try
			{
				if (selectedPath == null || selectedPath.length == 0) throw 'No output filename was selected';
				splitChartSaveJob = new SplitChartSaveJob(_song, packedSpamSections, selectedPath, binary);
				splitSavePreviousUiActive = UI_box == null ? true : UI_box.active;
				splitSaveMusicWasPlaying = FlxG.sound.music != null && FlxG.sound.music.playing;
				splitSaveCancelRequested = false;
				if (FlxG.sound.music != null) FlxG.sound.music.pause();
				if (vocals != null) vocals.pause();
				if (opponentVocals != null) opponentVocals.pause();
				if (UI_box != null) UI_box.active = false;
				splitChartSaveJob.startBackground();
				FlxG.log.notice('Split chart save started in the background: ' + splitChartSaveJob.getProgressText() + '. Press ESC to cancel.');
			}
			catch (error:Dynamic)
			{
				if (splitChartSaveJob != null)
				{
					try splitChartSaveJob.cancel() catch (cleanupError:Dynamic) {}
					if (!splitChartSaveJob.backgroundRunning) splitChartSaveJob = null;
				}
				if (UI_box != null) UI_box.active = splitSavePreviousUiActive;
				if (splitSaveMusicWasPlaying && FlxG.sound.music != null) FlxG.sound.music.play();
				FlxG.log.error('Unable to start split chart save: ' + Std.string(error));
			}
		});
		splitSaveDialog.onCancel.add(function() { splitSaveDialog = null; });
		if (!splitSaveDialog.browse(FileDialogType.SAVE, binary ? '*.bin' : '*.json', suggestedPath,
			binary ? 'Save H-Slice Binary Parts' : 'Save Split JSON Parts'))
		{
			splitSaveDialog = null;
			FlxG.log.error('This platform does not support a native multi-file save dialog.');
		}
	}

	private function restoreSplitSaveUi():Void
	{
		splitChartSaveJob = null;
		splitSavePromptOpen = false;
		splitSaveCancelRequested = false;
		if (UI_box != null) UI_box.active = splitSavePreviousUiActive;
		if (splitSaveMusicWasPlaying && FlxG.sound.music != null) FlxG.sound.music.play();
	}

	private function processSplitSaveJob():Void
	{
		var job:SplitChartSaveJob = splitChartSaveJob;
		if (job == null) return;

		if (FlxG.keys.justPressed.ESCAPE && !splitSavePromptOpen && !splitSaveCancelRequested && !job.complete)
		{
			splitSaveCancelRequested = true;
			job.cancel();
		}

		if (splitSaveCancelRequested)
		{
			if (job.backgroundRunning) return;
			restoreSplitSaveUi();
			FlxG.log.add('Split chart save cancelled. Incomplete output parts were removed.');
			return;
		}

		if (job.error != null)
		{
			// Let the worker leave its batch before deleting any temporary files.
			if (job.backgroundRunning) return;
			var message:String = job.error;
			job.cancel();
			restoreSplitSaveUi();
			FlxG.log.error('Chart split save failed: ' + message);
			return;
		}

		if (job.paused && job.checkpointLabel != null && !splitSavePromptOpen)
		{
			splitSavePromptOpen = true;
			var label:String = job.checkpointLabel;
			openSubState(new Prompt(
				'Hey! This part is at ' + label + '.\n\nSave this part now and continue in the next file, or continue to the next size limit?\n\nNo part will exceed the 2.1 GB hard byte limit.',
				0,
				function() { job.respondToCheckpoint(true); splitSavePromptOpen = false; },
				function() { job.respondToCheckpoint(false); splitSavePromptOpen = false; },
				false,
				'Save Part',
				'Continue to next limit'
			));
		}

		if (job.complete && !job.backgroundRunning)
		{
			var completedText:String = job.getProgressText();
			var outputFiles:Array<String> = job.getOutputFiles();
			restoreSplitSaveUi();
			FlxG.log.notice('Chart split save completed: ' + completedText + '. Files: ' + outputFiles.join(' | ') + '. Keep every numbered part together.');
		}
	}
	#end

	function sortByTime(Obj1:Array<Dynamic>, Obj2:Array<Dynamic>):Int
	{
		return FlxSort.byValues(FlxSort.ASCENDING, Obj1[0], Obj2[0]);
	}

	private function saveEvents()
	{
		if (_song.events != null && _song.events.length > 1) _song.events.sort(sortByTime);
		var eventsSong:Dynamic = {
			events: _song.events
		};
		var json = {
			"song": eventsSong
		}

		var data:String = haxe.Json.stringify(json, "\t");

		if ((data != null) && (data.length > 0)) {
			_file = new FileReference();
			_file.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data.trim(), "events.json");
		}
	}

	function onSaveComplete(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.notice("Successfully saved LEVEL DATA.");
	}

	function onSaveCancel(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
	}

	function onSaveError(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.error("Problem saving Level data");
	}

	function getSectionBeats(?section:Null<Int> = null)
	{
		if (section == null) section = curSec;
		var val:Null<Float> = null;
		if (_song.notes[section] != null) val = _song.notes[section].sectionBeats;
		return val != null ? val : 4;
	}
}

class AttachedFlxText extends FlxText
{
	public var sprTracker:FlxSprite;
	public var xAdd:Float = 0;
	public var yAdd:Float = 0;

	public function new(X:Float = 0, Y:Float = 0, FieldWidth:Float = 0, ?Text:String, Size:Int = 8, EmbeddedFont:Bool = true) {
		super(X, Y, FieldWidth, Text, Size, EmbeddedFont);
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (sprTracker != null) {
			setPosition(sprTracker.x + xAdd, sprTracker.y + yAdd);
			angle = sprTracker.angle;
			alpha = sprTracker.alpha;
		}
	}
}
