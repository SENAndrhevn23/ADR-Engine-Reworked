package objects;

import backend.animation.PsychAnimationController;
import backend.NoteTypesConfig;

import shaders.RGBPalette;
import shaders.RGBPalette.RGBShaderReference;

import objects.StrumNote;

import flixel.math.FlxRect;
import flixel.graphics.frames.FlxAtlasFrames;

using StringTools;

typedef EventNote = {
	strumTime:Float,
	event:String,
	value1:String,
	value2:String
}

typedef NoteSplashData = {
	disabled:Bool,
	texture:String,
	useGlobalShader:Bool, //breaks r/g/b/a but makes it copy default colors for your custom note
	useRGBShader:Bool,
	antialiasing:Bool,
	r:FlxColor,
	g:FlxColor,
	b:FlxColor,
	a:Float
}

/** Compact chart record. Flags are packed into noteData to avoid allocating a FlxSprite
 * for every future chart note. Bit layout intentionally mirrors H-Slice's CastNote. */
typedef CastNote = {
	var strumTime:Float;
	var noteData:Int;
	var sortOrder:Int;
	var chainId:Int;
	@:optional var hasSustain:Bool;
	@:optional var skipOnSpawn:Bool;
	@:optional var chainEnd:Bool;
	@:optional var tailCount:Int;
	@:optional var expectedTailCount:Int;
	@:optional var stepCrochet:Float;
	@:optional var sustainLength:Float;
	@:optional var noteType:String;
	@:optional var density:Float;
	@:optional var holdLength:Null<Float>;
	@:optional var cmpSpam:Array<Dynamic>;
	@:optional var isSustainEnds:Bool;
	// compactFlags=false stores lane and flags in separate fields for compatibility/debugging.
	// Missing compactFlags is treated as true so old CastNote records remain readable.
	@:optional var compactFlags:Bool;
	@:optional var mustPress:Bool;
	@:optional var isSustainNote:Bool;
	@:optional var gfNote:Bool;
	@:optional var altAnim:Bool;
	@:optional var noAnimation:Bool;
	@:optional var blockHit:Bool;
	@:optional var ignoreNote:Bool;
}

/** Decoded bitfield view for CastNote.noteData. */
typedef CastNoteFlags = {
	var lane:Int;
	var mustPress:Bool;
	var isSustainNote:Bool;
	var isSustainEnds:Bool;
	var gfNote:Bool;
	var altAnim:Bool;
	var noAnimation:Bool;
	var blockHit:Bool;
	var ignoreNote:Bool;
}

/**
 * The note object used as a data structure to spawn and manage notes during gameplay.
 * 
 * If you want to make a custom note type, you should search for: "function set_noteType"
**/
class Note extends FlxSprite
{
	// Script data is allocated only when a script actually accesses it. Most chart
	// notes never need a per-note Map, so this removes one heap allocation per note.
	private var _extraData:Map<String, Dynamic> = null;
	public var extraData(get, set):Map<String, Dynamic>;
	private function get_extraData():Map<String, Dynamic>
	{
		if (_extraData == null) _extraData = new Map<String, Dynamic>();
		return _extraData;
	}
	private function set_extraData(value:Map<String, Dynamic>):Map<String, Dynamic>
	{
		_extraData = value;
		return value;
	}
	public function hasExtraData():Bool
	{
		if (_extraData == null) return false;
		for (_ in _extraData.keys()) return true;
		return false;
	}

	// Sustain-tail arrays are allocated only for notes that actually own tail pieces.
	// The public getter preserves the old Note.tail API for scripts and gameplay code.
	private var _tail:Array<Note> = null;
	public var tail(get, set):Array<Note>;
	private function get_tail():Array<Note>
	{
		if (_tail == null) _tail = [];
		return _tail;
	}
	private function set_tail(value:Array<Note>):Array<Note>
	{
		_tail = value;
		return value;
	}
	public inline function addTailNote(note:Note):Void
	{
		if (_tail == null) _tail = [];
		_tail.push(note);
	}
	public inline function getTailCount():Int return _tail == null ? 0 : _tail.length;
	public inline function clearTail():Void
	{
		if (_tail != null) _tail.resize(0);
	}

	public var strumTime:Float = 0;
	public var noteData:Int = 0;
	public var strum:StrumNote = null;

	public var mustPress:Bool = false;
	public var canBeHit:Bool = false;
	public var tooLate:Bool = false;

	public var wasGoodHit:Bool = false;
	public var missed:Bool = false;

	public var ignoreNote:Bool = false;
	public var hitByOpponent:Bool = false;
	public var noteWasHit:Bool = false;
	public var prevNote:Note;
	public var nextNote:Note;

	public var spawned:Bool = false;
	public var poolEligible:Bool = false;

	// PlayState render-budget bookkeeping. Hidden notes remain alive and judgeable.
	public var renderBudgetManaged:Bool = false;
	public var renderBudgetVisible:Bool = false;
	public var renderBudgetPending:Bool = false;
	public var renderBudgetSuppressed:Bool = false;
	public var renderBudgetPrev:Note = null;
	public var renderBudgetNext:Note = null; // Intrusive doubly-linked FIFO; enables O(1) unlink on expiry.
	// PlayState-owned indexes. -1 means that the note is not currently indexed.
	public var playStateGroupIndex:Int = -1;
	public var inputLaneIndex:Int = -1;
	public var inputLaneSlot:Int = -1;
	// Intrusive queue links used by PlayState's optional time-window judgement scheduler.
	public var pendingJudgementPrev:Note = null;
	public var pendingJudgementNext:Note = null;
	public var isPendingJudgement:Bool = false;
	// After activation, the same intrusive links are reused for the active expiry queue.
	// Notes are unlinked in O(1) when hit/removed, so pooled objects are never left in a queue.
	public var isActiveJudgement:Bool = false;
	public var judgementActionProcessed:Bool = false;
	public var activeJudgementArraySlot:Int = -1;
	public var judgementLaneIndex:Int = -1;
	public var judgementLaneSlot:Int = -1;
	public var sustainJudgementLaneIndex:Int = -1;
	public var sustainJudgementLaneSlot:Int = -1;

	// Deferred sustain descriptors know the full hold length before every tail sprite exists.
	public var expectedTailCount:Int = 0;
	public var sustainChainBroken:Bool = false;
	public var parent:Note;
	public var blockHit:Bool = false; // only works for player

	public var sustainLength:Float = 0;
	public var holdLength:Null<Float> = null;	// Optional alias used by compact chart records.
	public var density:Float = 0;
	public var cmpSpam:Array<Dynamic> = null;
	public var isSustainEnds:Bool = false;
	public var isSustainNote:Bool = false;
	public var noteType(default, set):String = null;

	public var eventName:String = '';
	public var eventLength:Int = 0;
	public var eventVal1:String = '';
	public var eventVal2:String = '';

	public var rgbShader:RGBShaderReference;
	// Tracks whether the performance setting, rather than gameplay/mod code, paused this note.
	private var _pausedByRenderSetting:Bool = false;
	private var _appliedRenderSettingsRevision:Int = -1;
	// Plain gameplay-only notes defer atlas/animation/shader setup until admitted to
	// the rendered-note budget. This keeps hidden notes substantially lighter.
	public var visualsInitialized:Bool = false;
	private var psychAnimationDeferred:Bool = false;
	public static var globalRgbShaders:Array<RGBPalette> = [];
	public var inEditor:Bool = false;

	public var animSuffix:String = '';
	public var gfNote:Bool = false;
	public var earlyHitMult:Float = 1;
	public var lateHitMult:Float = 1;
	public var lowPriority:Bool = false;

	public static var SUSTAIN_SIZE:Int = 44;
	public static var swagWidth:Float = 160 * 0.7;
	public static var colArray:Array<String> = ['purple', 'blue', 'green', 'red'];
	public static var defaultNoteSkin(default, never):String = 'noteSkins/NOTE_assets';
	public static inline var CAST_LANE_MASK:Int = 0xFF;
	public static inline var CAST_MUST_PRESS:Int = 1 << 8;
	public static inline var CAST_SUSTAIN:Int = 1 << 9;
	public static inline var CAST_SUSTAIN_END:Int = 1 << 10;
	public static inline var CAST_GF_NOTE:Int = 1 << 11;
	public static inline var CAST_ALT_ANIM:Int = 1 << 12;
	public static inline var CAST_NO_ANIMATION:Int = 1 << 13;
	public static inline var CAST_BLOCK_HIT:Int = 1 << 14;
	public static inline var CAST_IGNORE_NOTE:Int = 1 << 15;
	private static var noteAtlasCache:Map<String, FlxAtlasFrames> = new Map<String, FlxAtlasFrames>();
	private static var renderSettingsRevision:Int = 0;

	/** Map lane indices 0..255 onto the four stock directional animation names.
	 * Custom skins still supply their own atlas frames; this mapping only chooses prefixes. */
	public static inline function getLaneColorName(lane:Int):String
	{
		var index:Int = lane % colArray.length;
		if (index < 0) index += colArray.length;
		return colArray[index];
	}

	public static function encodeCastNoteData(lane:Int, mustPress:Bool, isSustainNote:Bool, isSustainEnds:Bool,
		gfNote:Bool, altAnim:Bool, noAnimation:Bool, blockHit:Bool, ignoreNote:Bool):Int
	{
		var packed:Int = lane & CAST_LANE_MASK;
		if (mustPress) packed |= CAST_MUST_PRESS;
		if (isSustainNote) packed |= CAST_SUSTAIN;
		if (isSustainEnds) packed |= CAST_SUSTAIN_END;
		if (gfNote) packed |= CAST_GF_NOTE;
		if (altAnim) packed |= CAST_ALT_ANIM;
		if (noAnimation) packed |= CAST_NO_ANIMATION;
		if (blockHit) packed |= CAST_BLOCK_HIT;
		if (ignoreNote) packed |= CAST_IGNORE_NOTE;
		return packed;
	}

	public static inline function decodeCastNoteData(packed:Int):CastNoteFlags
	{
		return {
			lane: packed & CAST_LANE_MASK,
			mustPress: (packed & CAST_MUST_PRESS) != 0,
			isSustainNote: (packed & CAST_SUSTAIN) != 0,
			isSustainEnds: (packed & CAST_SUSTAIN_END) != 0,
			gfNote: (packed & CAST_GF_NOTE) != 0,
			altAnim: (packed & CAST_ALT_ANIM) != 0,
			noAnimation: (packed & CAST_NO_ANIMATION) != 0,
			blockHit: (packed & CAST_BLOCK_HIT) != 0,
			ignoreNote: (packed & CAST_IGNORE_NOTE) != 0
		};
	}

	/** Read flags from either the compact bitfield or the expanded compatibility layout.
	 * Older records without compactFlags are interpreted as packed bitfields. */
	public static inline function decodeCastNoteFlags(record:CastNote):CastNoteFlags
	{
		if (record == null) return decodeCastNoteData(0);
		if (record.compactFlags == false)
		{
			return {
				lane: record.noteData & CAST_LANE_MASK,
				mustPress: record.mustPress == true,
				isSustainNote: record.isSustainNote == true,
				isSustainEnds: record.isSustainEnds == true || record.chainEnd == true,
				gfNote: record.gfNote == true,
				altAnim: record.altAnim == true,
				noAnimation: record.noAnimation == true,
				blockHit: record.blockHit == true,
				ignoreNote: record.ignoreNote == true
			};
		}
		return decodeCastNoteData(record.noteData);
	}

	/** Store flags using the selected representation. Records carry their own format bit,
	 * so toggling this option cannot invalidate CastNotes already waiting in a queue. */
	public static function writeCastNoteFlags(record:CastNote, lane:Int, mustPress:Bool, isSustainNote:Bool,
		isSustainEnds:Bool, gfNote:Bool, altAnim:Bool, noAnimation:Bool, blockHit:Bool, ignoreNote:Bool):Void
	{
		if (ClientPrefs.data.compactCastNoteStorageEnabled)
		{
			record.noteData = encodeCastNoteData(lane, mustPress, isSustainNote, isSustainEnds, gfNote, altAnim, noAnimation, blockHit, ignoreNote);
			record.compactFlags = true;
			record.mustPress = false;
			record.isSustainNote = false;
			record.gfNote = false;
			record.altAnim = false;
			record.noAnimation = false;
			record.blockHit = false;
			record.ignoreNote = false;
			record.isSustainEnds = isSustainEnds;
		}
		else
		{
			record.noteData = lane & CAST_LANE_MASK;
			record.compactFlags = false;
			record.mustPress = mustPress;
			record.isSustainNote = isSustainNote;
			record.isSustainEnds = isSustainEnds;
			record.gfNote = gfNote;
			record.altAnim = altAnim;
			record.noAnimation = noAnimation;
			record.blockHit = blockHit;
			record.ignoreNote = ignoreNote;
		}
	}

	public static function clearNoteAnimationCache():Void
	{
		noteAtlasCache.clear();
	}

	private static function getCachedNoteAtlas(skin:String):FlxAtlasFrames
	{
		if (!ClientPrefs.data.noteAnimationResourceCaching) return Paths.getSparrowAtlas(skin);
		var cached:FlxAtlasFrames = noteAtlasCache.get(skin);
		if (cached != null) return cached;
		cached = Paths.getSparrowAtlas(skin);
		if (cached != null) noteAtlasCache.set(skin, cached);
		return cached;
	}

	// Splash metadata is rarely read for ordinary notes. Keep it lazy while retaining
	// the public property used by existing scripts and note-type configuration.
	private var _noteSplashData:NoteSplashData = null;
	public var noteSplashData(get, set):NoteSplashData;
	private function get_noteSplashData():NoteSplashData
	{
		if (_noteSplashData == null)
		{
			_noteSplashData = {
				disabled: false,
				texture: PlayState.SONG != null ? PlayState.SONG.splashSkin : 'noteSplashes',
				antialiasing: ClientPrefs.data.antialiasing && ClientPrefs.data.noteRenderingAntialiasing && !PlayState.isPixelStage,
				useGlobalShader: false,
				useRGBShader: ClientPrefs.data.noteRenderingRGBShaders && ((PlayState.SONG != null) ? !(PlayState.SONG.disableNoteRGB == true) : true),
				r: -1, g: -1, b: -1, a: ClientPrefs.data.splashAlpha
			};
		}
		return _noteSplashData;
	}
	private function set_noteSplashData(value:NoteSplashData):NoteSplashData
	{
		_noteSplashData = value;
		return value;
	}

	public var offsetX:Float = 0;
	public var offsetY:Float = 0;
	public var offsetAngle:Float = 0;
	public var multAlpha:Float = 1;
	public var multSpeed(default, set):Float = 1;

	public var copyX:Bool = true;
	public var copyY:Bool = true;
	public var copyAngle:Bool = true;
	public var copyAlpha:Bool = true;

	public var hitHealth:Float = 0.023;
	public var missHealth:Float = 0.0475;
	public var rating:String = 'unknown';
	public var ratingMod:Float = 0; //9 = unknown, 0.25 = shit, 0.5 = bad, 0.75 = good, 1 = sick
	public var ratingDisabled:Bool = false;

	public var texture(default, set):String = null;

	public var noAnimation:Bool = false;
	public var noMissAnimation:Bool = false;
	public var hitCausesMiss:Bool = false;
	public var distance:Float = 2000; //plan on doing scroll directions soon -bb

	public var hitsoundDisabled:Bool = false;
	public var hitsoundChartEditor:Bool = true;
	public var hitsound:String = 'hitsound';

	private function set_multSpeed(value:Float):Float {
		resizeByRatio(value / multSpeed);
		multSpeed = value;
		//trace('fuck cock');
		return value;
	}

	public function resizeByRatio(ratio:Float) //haha funny twitter shit
	{
		if(isSustainNote && animation.curAnim != null && !animation.curAnim.name.endsWith('end'))
		{
			scale.y *= ratio;
			updateHitbox();
		}
	}

	private function set_texture(value:String):String {
		if(texture != value)
		{
			reloadNote(value);
			visualsInitialized = true;
		}

		texture = value;
		return value;
	}

	public function defaultRGB()
	{
		if (rgbShader == null || noteData < 0) return;
		var colors:Array<Array<FlxColor>> = PlayState.isPixelStage ? ClientPrefs.data.arrowRGBPixel : ClientPrefs.data.arrowRGB;
		if (colors == null || colors.length == 0) return;
		var colorLane:Int = noteData % colors.length;
		var arr:Array<FlxColor> = colors[colorLane];
		if (arr != null && arr.length >= 3)
		{
			rgbShader.r = arr[0];
			rgbShader.g = arr[1];
			rgbShader.b = arr[2];
		}
	}

	private function set_noteType(value:String):String {
		if (rgbShader != null) defaultRGB();
		// A late custom-note assignment may need graphics even if this note was
		// originally deferred as a plain gameplay-only tap.
		if (value != null && value.length > 0 && !visualsInitialized) ensureVisuals();

		if(noteData > -1 && noteType != value) {
			switch(value) {
				case 'Hurt Note':
					ignoreNote = mustPress;
					var splashData:NoteSplashData = noteSplashData;
					splashData.texture = PlayState.SONG != null ? PlayState.SONG.splashSkin : 'noteSplashes';
					//reloadNote('HURTNOTE_assets');
					//this used to change the note texture to HURTNOTE_assets.png,
					//but i've changed it to something more optimized with the implementation of RGBPalette:

					// note colors
					if (rgbShader != null)
					{
						rgbShader.r = 0xFF101010;
						rgbShader.g = 0xFFFF0000;
						rgbShader.b = 0xFF990022;
					}

					// splash data and colors
					splashData.r = 0xFFFF0000;
					splashData.g = 0xFF101010;
					splashData.texture = 'noteSplashes/noteSplashes-electric';

					// gameplay data
					lowPriority = true;
					missHealth = isSustainNote ? 0.25 : 0.1;
					hitCausesMiss = true;
					hitsound = 'cancelMenu';
					hitsoundChartEditor = false;
				case 'Alt Animation':
					animSuffix = '-alt';
				case 'No Animation':
					noAnimation = true;
					noMissAnimation = true;
				case 'GF Sing':
					gfNote = true;
			}
			if (value != null && value.length > 1) NoteTypesConfig.applyNoteTypeData(this, value);
			if (hitsound != 'hitsound' && ClientPrefs.data.hitsoundVolume > 0) Paths.sound(hitsound); //precache new sound for being idiot-proof
			noteType = value;
		}
		return value;
	}

	/** Convert this live Note to a compact chart record. Optional script-owned data is
	 * copied so the record does not share a mutable array with the sprite. */
	public function toCastNote(sortOrder:Int = 0, chainId:Int = 0):CastNote
	{
		var copiedSpam:Array<Dynamic> = cmpSpam == null ? null : cmpSpam.copy();
		var record:CastNote = {
			strumTime: strumTime,
			noteData: 0,
			sortOrder: sortOrder,
			chainId: chainId,
			hasSustain: sustainLength > 0 || getTailCount() > 0,
			skipOnSpawn: false,
			chainEnd: isSustainEnds,
			tailCount: getTailCount(),
			expectedTailCount: expectedTailCount,
			stepCrochet: Conductor.stepCrochet,
			sustainLength: sustainLength,
			holdLength: holdLength == null ? sustainLength : holdLength,
			noteType: noteType,
			density: density,
			cmpSpam: copiedSpam,
			isSustainEnds: isSustainEnds
		};
		writeCastNoteFlags(record, noteData, mustPress, isSustainNote, isSustainEnds, gfNote,
			animSuffix == '-alt', noAnimation, blockHit, ignoreNote);
		return record;
	}

	/** Apply the gameplay flags encoded in a CastNote record. */
	public function applyCastNoteFlags(packed:Int):Void
	{
		var flags:CastNoteFlags = decodeCastNoteData(packed);
		noteData = flags.lane;
		mustPress = flags.mustPress;
		isSustainNote = flags.isSustainNote;
		isSustainEnds = flags.isSustainEnds;
		gfNote = flags.gfNote;
		animSuffix = flags.altAnim ? '-alt' : '';
		noAnimation = flags.noAnimation;
		noMissAnimation = flags.noAnimation;
		blockHit = flags.blockHit;
		ignoreNote = flags.ignoreNote;
	}

	public function new(strumTime:Float, noteData:Int, ?prevNote:Note, ?sustainNote:Bool = false, ?inEditor:Bool = false, ?createdFrom:Dynamic = null, ?deferVisuals:Bool = false)
	{
		super();

		if (deferVisuals) psychAnimationDeferred = true;
		else animation = new PsychAnimationController(this);

		antialiasing = ClientPrefs.data.antialiasing && ClientPrefs.data.noteRenderingAntialiasing && !PlayState.isPixelStage;
		if(createdFrom == null) createdFrom = PlayState.instance;

		if (prevNote == null)
			prevNote = this;

		this.prevNote = prevNote;
		isSustainNote = sustainNote;
		this.inEditor = inEditor;
		this.moves = false;

		x += (ClientPrefs.data.middleScroll ? PlayState.STRUM_X_MIDDLESCROLL : PlayState.STRUM_X) + 50;
		// MAKE SURE ITS DEFINITELY OFF SCREEN?
		y -= 2000;
		this.strumTime = strumTime;
		if(!inEditor) this.strumTime += ClientPrefs.data.noteOffset;

		this.noteData = noteData;

		if(noteData > -1) {
			x += swagWidth * (noteData);
			if (!deferVisuals) ensureVisuals();
		}

		// trace(prevNote);

		if(prevNote != null)
			prevNote.nextNote = this;

		if (isSustainNote && prevNote != null)
		{
			alpha = 0.6;
			multAlpha = 0.6;
			hitsoundDisabled = true;
			if(ClientPrefs.data.downScroll) flipY = true;

			offsetX += width / 2;
			copyAngle = false;

			// Sustain notes must always have their own animation controller, even if a
			// caller accidentally requested deferred visuals for this note.
			if (animation == null || psychAnimationDeferred) ensureVisuals();
			if (animation != null && noteData >= 0)
				animation.play(getLaneColorName(noteData) + 'holdend');

			updateHitbox();

			offsetX -= width / 2;

			if (PlayState.isPixelStage)
				offsetX += 30;

			// A deferred sustain chain can outlive the previous segment's sprite. Keep
			// prevNote linked for gameplay state, but only extend its visual if the old
			// FlxSprite still owns valid transform objects. Destroyed sprites have null
			// scale/animation members and must never be touched here.
			if (prevNote != this && prevNote.isSustainNote && prevNote.exists && prevNote.scale != null)
			{
				if (prevNote.animation == null || prevNote.psychAnimationDeferred || !prevNote.visualsInitialized)
					prevNote.ensureVisuals();

				if (prevNote.animation != null && prevNote.scale != null && prevNote.exists)
				{
					if (prevNote.noteData >= 0)
						prevNote.animation.play(getLaneColorName(prevNote.noteData) + 'hold');

					prevNote.scale.y *= Conductor.stepCrochet / 100 * 1.05;
					if(createdFrom != null && createdFrom.songSpeed != null) prevNote.scale.y *= createdFrom.songSpeed;

					if(PlayState.isPixelStage && height > 0) {
						prevNote.scale.y *= 1.19;
						prevNote.scale.y *= (6 / height); //Auto adjust note size
					}
					prevNote.updateHitbox();
				}
				// If the previous segment has already been destroyed, its gameplay flags
				// remain available through prevNote, but there is no sprite left to extend.
			}

			if(PlayState.isPixelStage)
			{
				scale.y *= PlayState.daPixelZoom;
				updateHitbox();
			}
			earlyHitMult = 0;
		}
		else if(!isSustainNote)
		{
			centerOffsets();
			centerOrigin();
		}
		x += offsetX;
	}

	/** Mark the shared render policy dirty after an Options setting changes. */
	public static function invalidateRenderSettings():Void
	{
		renderSettingsRevision++;
	}

	/** Apply user-selected sprite rendering policies only when their shared revision changes. */
	private function syncNoteRenderSettings():Void
	{
		if (_appliedRenderSettingsRevision == renderSettingsRevision) return;
		_appliedRenderSettingsRevision = renderSettingsRevision;
		if (animation != null)
		{
			if (!ClientPrefs.data.noteRenderingAnimations)
			{
				if (!_pausedByRenderSetting) animation.pause();
				_pausedByRenderSetting = true;
			}
			else if (_pausedByRenderSetting)
			{
				animation.resume();
				_pausedByRenderSetting = false;
			}
		}

		if (visualsInitialized && noteData >= 0)
		{
			var useRGB:Bool = ClientPrefs.data.noteRenderingRGBShaders
				&& (PlayState.SONG == null || PlayState.SONG.disableNoteRGB != true);
			if (useRGB && rgbShader == null)
				rgbShader = new RGBShaderReference(this, initializeGlobalRGBShader(noteData));
			if (rgbShader != null) rgbShader.enabled = useRGB;
			antialiasing = ClientPrefs.data.antialiasing && ClientPrefs.data.noteRenderingAntialiasing && !PlayState.isPixelStage;
		}
	}

	/** Initialize the atlas, animations and per-sprite RGB shader only when this note
	 * is actually admitted to the render group (or a custom note type requires it). */
	public function ensureVisuals():Void
	{
		if (noteData < 0) return;
		if (animation == null || psychAnimationDeferred)
		{
			animation = new PsychAnimationController(this);
			psychAnimationDeferred = false;
		}
		if (!visualsInitialized) texture = '';
		// Avoid allocating per-note RGB shader references when the user disables them.
		if (ClientPrefs.data.noteRenderingRGBShaders)
		{
			if (rgbShader == null)
				rgbShader = new RGBShaderReference(this, initializeGlobalRGBShader(noteData));
			if (rgbShader != null)
				rgbShader.enabled = PlayState.SONG == null || !PlayState.SONG.disableNoteRGB;
		}
		else if (rgbShader != null) rgbShader.enabled = false;
		antialiasing = ClientPrefs.data.antialiasing && ClientPrefs.data.noteRenderingAntialiasing && !PlayState.isPixelStage;
		if (!isSustainNote && noteData >= 0)
			animation.play(getLaneColorName(noteData) + 'Scroll');
		visualsInitialized = true;
		_appliedRenderSettingsRevision = -1;
		syncNoteRenderSettings();
	}

	/**
	 * A FlxSprite.destroy() call releases its pooled FlxPoint members and sets them to null.
	 * A note with any of these missing is not safe to put back into NoteGroup's object pool.
	 * Lazy-visual notes intentionally have no animation until ensureVisuals(), so animation
	 * is only required after visuals have been initialized.
	 */
	public function canRecycleBasicTap():Bool
	{
		return offset != null && origin != null && scale != null && scrollFactor != null
			&& (!visualsInitialized || animation != null);
	}

	/** Reinitialize a pooled, plain tap note. Sustain/custom notes are never pooled by NoteGroup. */
	public function recycleBasicTap(castNote:CastNote):Void
	{
		if (castNote == null) throw "Cannot recycle a Note without CastNote data";
		if (!canRecycleBasicTap())
			throw "Attempted to recycle a destroyed or incomplete Note sprite";

		var flags:CastNoteFlags = decodeCastNoteFlags(castNote);
		var lane:Int = flags.lane;
		var laneChanged:Bool = noteData != lane;
		var previousTexture:String = texture;

		// Clear all transient gameplay, chain, script and render state before applying the new row.
		strumTime = castNote.strumTime;
		noteData = lane;
		mustPress = flags.mustPress;
		wasGoodHit = false;
		canBeHit = false;
		tooLate = false;
		missed = false;
		hitByOpponent = false;
		noteWasHit = false;
		ignoreNote = flags.ignoreNote;
		blockHit = flags.blockHit;
		noAnimation = flags.noAnimation;
		noMissAnimation = flags.noAnimation;
		hitCausesMiss = false;
		lowPriority = false;
		gfNote = flags.gfNote;
		animSuffix = flags.altAnim ? '-alt' : '';
		isSustainNote = flags.isSustainNote;
		isSustainEnds = flags.isSustainEnds || castNote.chainEnd == true || castNote.isSustainEnds == true;
		sustainLength = castNote.sustainLength == null ? 0 : castNote.sustainLength;
		holdLength = castNote.holdLength == null ? sustainLength : castNote.holdLength;
		density = castNote.density == null ? 0 : castNote.density;
		cmpSpam = castNote.cmpSpam == null ? null : castNote.cmpSpam.copy();
		parent = null;
		expectedTailCount = castNote.expectedTailCount == null ? 0 : castNote.expectedTailCount;
		sustainChainBroken = false;
		prevNote = this;
		nextNote = null;
		clearTail();
		strum = null;
		eventName = '';
		eventLength = 0;
		eventVal1 = '';
		eventVal2 = '';
		distance = 2000;
		correctionOffset = 0;
		missHealth = 0.0475;
		hitHealth = 0.023;
		earlyHitMult = lateHitMult = 1;
		rating = 'unknown';
		ratingMod = 0;
		ratingDisabled = false;
		hitsoundDisabled = false;
		hitsound = 'hitsound';
		hitsoundChartEditor = true;
		if (_extraData != null) _extraData.clear();
		if (_noteSplashData != null)
		{
			_noteSplashData.disabled = false;
			_noteSplashData.texture = PlayState.SONG != null ? PlayState.SONG.splashSkin : 'noteSplashes';
			_noteSplashData.useGlobalShader = false;
			_noteSplashData.useRGBShader = PlayState.SONG == null || !PlayState.SONG.disableNoteRGB;
			_noteSplashData.antialiasing = ClientPrefs.data.antialiasing && ClientPrefs.data.noteRenderingAntialiasing && !PlayState.isPixelStage;
			_noteSplashData.r = _noteSplashData.g = _noteSplashData.b = -1;
			_noteSplashData.a = ClientPrefs.data.splashAlpha;
		}

		// A pooled note is only eligible when it has no custom note type/skin. Still restore
		// the chart's current default skin if a script changed its texture in the meantime.
		noteType = null;
		var expectedSkin:String = PlayState.SONG != null ? PlayState.SONG.arrowSkin : defaultNoteSkin;
		if (expectedSkin == null || expectedSkin.length == 0) expectedSkin = defaultNoteSkin;
		if (laneChanged && visualsInitialized) reloadNote();
		else if (previousTexture != null && previousTexture.length > 0 && previousTexture != expectedSkin && visualsInitialized) reloadNote(expectedSkin);

		// Reset visual state only after note gameplay properties have been restored.
		x = (ClientPrefs.data.middleScroll ? PlayState.STRUM_X_MIDDLESCROLL : PlayState.STRUM_X) + 50 + swagWidth * lane;
		y = -2000;
		if (mustPress) x += FlxG.width / 2;
		else if (ClientPrefs.data.middleScroll)
		{
			x += 310;
			if (lane > 1) x += FlxG.width / 2 + 25;
		}
		alpha = multAlpha = 1;
		angle = 0;
		angularVelocity = angularAcceleration = angularDrag = 0;
		if (velocity != null) velocity.set();
		if (acceleration != null) acceleration.set();
		if (drag != null) drag.set();
		color = FlxColor.WHITE;
		flipX = false;
		flipY = ClientPrefs.data.downScroll && isSustainNote;
		if (scale != null) scale.set(PlayState.isPixelStage ? PlayState.daPixelZoom : 0.7, PlayState.isPixelStage ? PlayState.daPixelZoom : 0.7);
		offset.set();
		scrollFactor.set();
		multSpeed = 1;
		active = visible = exists = alive = true;
		moves = false;
		spawned = false;
		poolEligible = true;
		offsetX = offsetY = offsetAngle = 0;
		copyX = copyY = copyAngle = copyAlpha = true;
		clipRect = null;
		renderBudgetManaged = renderBudgetVisible = renderBudgetPending = renderBudgetSuppressed = false;
		renderBudgetPrev = renderBudgetNext = null;
		playStateGroupIndex = inputLaneIndex = inputLaneSlot = -1;
		pendingJudgementPrev = pendingJudgementNext = null;
		isPendingJudgement = false;
		isActiveJudgement = false;
		judgementActionProcessed = false;
		activeJudgementArraySlot = -1;
		judgementLaneIndex = judgementLaneSlot = -1;
		sustainJudgementLaneIndex = sustainJudgementLaneSlot = -1;

		if (rgbShader != null)
		{
			var palette:Array<Array<FlxColor>> = PlayState.isPixelStage ? ClientPrefs.data.arrowRGBPixel : ClientPrefs.data.arrowRGB;
			var colorLane:Int = palette == null || palette.length == 0 ? -1 : lane % palette.length;
			var colors:Array<FlxColor> = colorLane >= 0 ? palette[colorLane] : null;
			if (colors != null && colors.length >= 3)
			{
				rgbShader.r = colors[0];
				rgbShader.g = colors[1];
				rgbShader.b = colors[2];
			}
		}
		if (visualsInitialized && animation != null)
			animation.play(getLaneColorName(lane) + (isSustainNote ? 'holdend' : 'Scroll'), true);
		// A pooled sprite may have been inactive while global options changed. Force one
		// synchronization after every recycle so animation pause/RGB/AA never leak.
		_appliedRenderSettingsRevision = -1;
		centerOffsets();
		centerOrigin();
		updateHitbox();
		syncNoteRenderSettings();
	}

	/** Publicly named recycling entry point used by NoteGroup. */
	public inline function recycleNote(castNote:CastNote):Void
	{
		recycleBasicTap(castNote);
	}

	public static function initializeGlobalRGBShader(noteData:Int):RGBPalette
	{
		if (noteData < 0) return null;
		while (globalRgbShaders.length <= noteData) globalRgbShaders.push(null);
		if(globalRgbShaders[noteData] == null)
		{
			var newRGB:RGBPalette = new RGBPalette();
			globalRgbShaders[noteData] = newRGB;

			var colors:Array<Array<FlxColor>> = (!PlayState.isPixelStage) ? ClientPrefs.data.arrowRGB : ClientPrefs.data.arrowRGBPixel;
			var colorLane:Int = colors == null || colors.length == 0 ? -1 : noteData % colors.length;
			var arr:Array<FlxColor> = colorLane >= 0 ? colors[colorLane] : null;
			if (arr != null && arr.length >= 3)
			{
				newRGB.r = arr[0];
				newRGB.g = arr[1];
				newRGB.b = arr[2];
			}
		}
		return globalRgbShaders[noteData];
	}

	var _lastNoteOffX:Float = 0;
	static var _lastValidChecked:String; //optimization
	public var originalHeight:Float = 6;
	public var correctionOffset:Float = 0; //dont mess with this
	public function reloadNote(texture:String = '', postfix:String = '') {
		if(texture == null) texture = '';
		if(postfix == null) postfix = '';

		var skin:String = texture + postfix;
		if(texture.length < 1) {
			skin = PlayState.SONG != null ? PlayState.SONG.arrowSkin : null;
			if(skin == null || skin.length < 1)
				skin = defaultNoteSkin + postfix;
		}

		var animName:String = null;
		if(animation.curAnim != null) {
			animName = animation.curAnim.name;
		}

		var skinPixel:String = skin;
		var lastScaleY:Float = scale.y;
		var skinPostfix:String = getNoteSkinPostfix();
		var customSkin:String = skin + skinPostfix;
		var path:String = PlayState.isPixelStage ? 'pixelUI/' : '';
		if(customSkin == _lastValidChecked || Paths.fileExists('images/' + path + customSkin + '.png', IMAGE))
		{
			skin = customSkin;
			_lastValidChecked = customSkin;
		}
		else skinPostfix = '';

		if(PlayState.isPixelStage) {
			if(isSustainNote) {
				var graphic = Paths.image('pixelUI/' + skinPixel + 'ENDS' + skinPostfix);
				loadGraphic(graphic, true, Math.floor(graphic.width / 4), Math.floor(graphic.height / 2));
				originalHeight = graphic.height / 2;
			} else {
				var graphic = Paths.image('pixelUI/' + skinPixel + skinPostfix);
				loadGraphic(graphic, true, Math.floor(graphic.width / 4), Math.floor(graphic.height / 5));
			}
			setGraphicSize(Std.int(width * PlayState.daPixelZoom));
			loadPixelNoteAnims();
			antialiasing = false;

			if(isSustainNote) {
				offsetX += _lastNoteOffX;
				_lastNoteOffX = (width - 7) * (PlayState.daPixelZoom / 2);
				offsetX -= _lastNoteOffX;
			}
		} else {
			frames = getCachedNoteAtlas(skin);
			loadNoteAnims();
			if(!isSustainNote)
			{
				centerOffsets();
				centerOrigin();
			}
		}

		if(isSustainNote) {
			scale.y = lastScaleY;
		}
		updateHitbox();

		if(animName != null)
			animation.play(animName, true);
		antialiasing = ClientPrefs.data.antialiasing && ClientPrefs.data.noteRenderingAntialiasing && !PlayState.isPixelStage;
		_appliedRenderSettingsRevision = -1;
		syncNoteRenderSettings();
	}

	public static function getNoteSkinPostfix()
	{
		var skin:String = '';
		if(ClientPrefs.data.noteSkin != ClientPrefs.defaultData.noteSkin)
			skin = '-' + ClientPrefs.data.noteSkin.trim().toLowerCase().replace(' ', '_');
		return skin;
	}

	function loadNoteAnims() {
		var laneName:String = getLaneColorName(noteData);
		if (isSustainNote)
		{
			attemptToAddAnimationByPrefix('purpleholdend', 'pruple end hold', 24, true); // legacy skin typo compatibility
			animation.addByPrefix(laneName + 'holdend', laneName + ' hold end', 24, true);
			animation.addByPrefix(laneName + 'hold', laneName + ' hold piece', 24, true);
		}
		else animation.addByPrefix(laneName + 'Scroll', laneName + '0');

		setGraphicSize(Std.int(width * 0.7));
		updateHitbox();
	}

	function loadPixelNoteAnims() {
		var lane:Int = noteData % colArray.length;
		var laneName:String = getLaneColorName(noteData);
		if(isSustainNote)
		{
			animation.add(laneName + 'holdend', [lane + 4], 24, true);
			animation.add(laneName + 'hold', [lane], 24, true);
		} else animation.add(laneName + 'Scroll', [lane + 4], 24, true);
	}

	function attemptToAddAnimationByPrefix(name:String, prefix:String, framerate:Float = 24, doLoop:Bool = true)
	{
		var animFrames = [];
		@:privateAccess
		animation.findByPrefix(animFrames, prefix); // adds valid frames to animFrames
		if(animFrames.length < 1) return;

		animation.addByPrefix(name, prefix, framerate, doLoop);
	}

	override function update(elapsed:Float)
	{
		// With the optional time-window scheduler enabled, PlayState updates gameplay
		// flags only for notes near their judgement/miss times. Visible sprites still
		// receive normal Flixel animation updates here.
		var fastLogic:Bool = renderBudgetManaged && PlayState.instance != null && PlayState.instance.fastNoteLogicActive;
		if (fastLogic)
		{
			if (!renderBudgetVisible || renderBudgetSuppressed) return;
			syncNoteRenderSettings();
			super.update(elapsed);
			return;
		}

		// Budget-hidden notes still need their gameplay flags in the legacy path.
		if (renderBudgetManaged && (!renderBudgetVisible || renderBudgetSuppressed))
		{
			updateGameplayState();
			return;
		}
		syncNoteRenderSettings();
		super.update(elapsed);
		updateGameplayState();
	}

	override public function draw():Void
	{
		// Final enforcement point: a note cannot bypass the configured render cap
		// merely because another code path toggled its visible flag back on.
		if (renderBudgetManaged)
		{
			var state:PlayState = PlayState.instance;
			if (state == null || !state.canDrawBudgetedNote(this)) return;
		}
		super.draw();
	}

	/**
	 * Updates only timing/judgement flags. PlayState calls this for notes hidden by
	 * the rendered-note budget, allowing their FlxSprite update and animation work
	 * to be skipped without changing hit windows or opponent timing.
	 */
	public inline function updateGameplayState():Void
	{
		if (mustPress)
		{
			canBeHit = (strumTime > Conductor.songPosition - (Conductor.safeZoneOffset * lateHitMult) &&
						strumTime < Conductor.songPosition + (Conductor.safeZoneOffset * earlyHitMult));

			if (strumTime < Conductor.songPosition - Conductor.safeZoneOffset && !wasGoodHit)
				tooLate = true;
		}
		else
		{
			canBeHit = false;

			if (strumTime < Conductor.songPosition + (Conductor.safeZoneOffset * earlyHitMult))
			{
				if((isSustainNote && prevNote.wasGoodHit) || strumTime <= Conductor.songPosition)
					wasGoodHit = true;
			}
		}

		if (tooLate && !inEditor && alpha > 0.3) alpha = 0.3;
	}

	override public function destroy()
	{
		super.destroy();
		_lastValidChecked = '';
	}

	public function followStrumNote(myStrum:StrumNote, fakeCrochet:Float, songSpeed:Float = 1)
	{
		var angleDir:Float = myStrum.direction * Math.PI / 180;
		followStrumNoteWithCache(myStrum.x, myStrum.y, myStrum.angle, myStrum.alpha,
			myStrum.direction, myStrum.downScroll, Math.cos(angleDir), Math.sin(angleDir),
			Conductor.songPosition, songSpeed);
	}

	/**
	 * Updates a note using a strum transform calculated once per lane by PlayState.
	 * Reusing directionCos/directionSin avoids two trigonometric calls per note per frame.
	 */
	public inline function followStrumNoteWithCache(strumX:Float, strumY:Float, strumAngle:Float,
		strumAlpha:Float, strumDirection:Float, downScroll:Bool, directionCos:Float,
		directionSin:Float, songPosition:Float, songSpeed:Float):Void
	{
		distance = 0.45 * (songPosition - strumTime) * songSpeed * multSpeed;
		if (!downScroll) distance *= -1;

		if (copyAngle)
			angle = strumDirection - 90 + strumAngle + offsetAngle;

		if (copyAlpha)
			alpha = strumAlpha * multAlpha;

		if (copyX)
			x = strumX + offsetX + directionCos * distance;

		if (copyY)
		{
			y = strumY + offsetY + correctionOffset + directionSin * distance;
			if (downScroll && isSustainNote)
			{
				if (PlayState.isPixelStage)
					y -= PlayState.daPixelZoom * 9.5;
				y -= (frameHeight * scale.y) - (Note.swagWidth / 2);
			}
		}
	}

	public function clipToStrumNote(myStrum:StrumNote)
	{
		var center:Float = myStrum.y + offsetY + Note.swagWidth / 2;
		if(isSustainNote && (mustPress || !ignoreNote) &&
			(!mustPress || (wasGoodHit || (prevNote.wasGoodHit && !canBeHit))))
		{
			var swagRect:FlxRect = clipRect;
			if (swagRect == null || !ClientPrefs.data.reuseSustainClipRects)
			{
				swagRect = new FlxRect(0, 0, frameWidth, frameHeight);
				// Assign once so Flixel refreshes the frame/clip state. Subsequent frames
				// mutate the same rectangle instead of re-running set_clipRect every update.
				clipRect = swagRect;
			}

			if (myStrum.downScroll)
			{
				if(y - offset.y * scale.y + height >= center)
				{
					swagRect.width = frameWidth;
					swagRect.height = (center - y) / scale.y;
					swagRect.y = frameHeight - swagRect.height;
				}
			}
			else if (y + offset.y * scale.y <= center)
			{
				swagRect.y = (center - y) / scale.y;
				swagRect.width = width / scale.x;
				swagRect.height = (height / scale.y) - swagRect.y;
			}
			// swagRect is already the live clipRect; mutating it avoids a repeated
			// frame refresh through set_clipRect on every sustain update.
		}
	}

	@:noCompletion
	override function set_clipRect(rect:FlxRect):FlxRect
	{
		clipRect = rect;

		if (frames != null)
			frame = frames.frames[animation.frameIndex];

		return rect;
	}
}