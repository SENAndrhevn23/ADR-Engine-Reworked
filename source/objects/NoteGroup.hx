package objects;

import flixel.group.FlxGroup.FlxTypedGroup;
import objects.Note.CastNote;
import objects.Note.CastNoteFlags;

/**
 * Logical note collection inspired by H-Slice's NoteGroup.
 * Pending chart records remain compact CastNotes; full Note sprites are created only
 * when their spawn window is reached. Plain tap notes are pooled by lane. Sustains and
 * custom note types are deliberately not pooled yet because parent/tail and mod state
 * can retain references to them.
 */
class NoteGroup extends FlxTypedGroup<Note>
{
	// Keep a larger per-lane reuse pool for high-throughput charts. The pool is
	// bounded so long songs cannot retain an unbounded number of FlxSprite objects.
	private var tapPools:Map<Int, Array<Note>> = new Map<Int, Array<Note>>();
	private var pooledNoteCount:Int = 0;
	private inline function getLanePool(lane:Int, create:Bool):Array<Note>
	{
		var lanePool:Array<Note> = tapPools.get(lane);
		if (lanePool == null && create)
		{
			lanePool = [];
			tapPools.set(lane, lanePool);
		}
		return lanePool;
	}
	private var chainParents:Map<Int, Note> = new Map<Int, Note>();
	private var chainPrevious:Map<Int, Note> = new Map<Int, Note>();
	public var createdNotes:Int = 0;
	public var reusedNotes:Int = 0;

	public function new()
	{
		super();
	}

	public function spawnCastNote(castNote:CastNote, prepend:Bool = false):Note
	{
		if (castNote == null) return null;
		var flags:CastNoteFlags = Note.decodeCastNoteFlags(castNote);
		var lane:Int = flags.lane;
		var mustPress:Bool = flags.mustPress;
		var sustain:Bool = flags.isSustainNote;
		var gfNote:Bool = flags.gfNote;
		var parent:Note = sustain ? chainParents.get(castNote.chainId) : null;
		// Keep the previous object reference even if its sprite has expired: its
		// wasGoodHit/missed flags still carry sustain gameplay state. Note.new() now
		// checks the sprite members before trying to extend its visual.
		var previous:Note = sustain ? chainPrevious.get(castNote.chainId) : null;
		var note:Note = null;

		// Only plain tap notes with no sustain chain or custom type are pooled in this
		// first port. This avoids reusing an object still referenced by a sustain tail.
		var plainTap:Bool = !sustain && !flags.isSustainEnds && (castNote.hasSustain != true) && (castNote.noteType == null || castNote.noteType.length == 0);
		var poolStorageEnabled:Bool = ClientPrefs.data.notePoolEnabled;
		// Mod scripts may retain Note references or attach dynamic state. Keep the legacy
		// allocation path when scripts are loaded so object identity/state stays compatible.
		var scriptsNeedFullNoteVisuals:Bool = PlayState.instance != null && PlayState.instance.hasNoteScriptsLoaded();
		var poolReuseEnabled:Bool = ClientPrefs.data.noteObjectPooling && poolStorageEnabled && !scriptsNeedFullNoteVisuals;
		if (!poolStorageEnabled && pooledNoteCount > 0) clearPools();
		var poolable:Bool = plainTap;
		var deferVisuals:Bool = plainTap && ClientPrefs.data.lazyNoteGraphics && !scriptsNeedFullNoteVisuals;
		if (poolable && poolReuseEnabled && lane >= 0 && lane <= Note.CAST_LANE_MASK)
		{
			// Discard stale entries defensively. A destroyed FlxSprite releases its internal
			// FlxPoints (offset/origin/scale/scrollFactor), so calling recycleBasicTap() on it
			// would crash at offset.set(). This can happen if another cleanup path destroyed
			// an object after it was returned to the pool.
			var lanePool:Array<Note> = getLanePool(lane, false);
			if (lanePool == null) lanePool = [];
			while (lanePool.length > 0 && note == null)
			{
				var candidate:Note = lanePool.pop();
				if (candidate != null) pooledNoteCount--;
				if (candidate != null && candidate.canRecycleBasicTap())
					note = candidate;
				else if (candidate != null)
					candidate.destroy();
			}
			if (note != null)
			{
				note.recycleNote(castNote);
				reusedNotes++;
			}
		}

		if (note == null)
		{
			note = new Note(castNote.strumTime - ClientPrefs.data.noteOffset, lane, previous, sustain, false, null, deferVisuals);
			createdNotes++;
			if (sustain && previous != null && previous.isSustainNote)
			{
				if (!PlayState.isPixelStage)
				{
					previous.scale.y *= Note.SUSTAIN_SIZE / previous.frameHeight;
					previous.scale.y /= PlayState.instance.playbackRate;
				}
				else previous.scale.y /= PlayState.instance.playbackRate;
				previous.updateHitbox();
			}
			note.mustPress = mustPress;
			note.gfNote = gfNote;
			note.blockHit = flags.blockHit;
			note.ignoreNote = flags.ignoreNote;
			note.animSuffix = flags.altAnim ? '-alt' : '';
			if (flags.noAnimation) note.noAnimation = note.noMissAnimation = true;
			note.isSustainEnds = flags.isSustainEnds || castNote.chainEnd == true || castNote.isSustainEnds == true;
			note.sustainLength = castNote.sustainLength == null ? 0 : castNote.sustainLength;
			note.noteType = castNote.noteType;
			if (mustPress) note.x += FlxG.width / 2;
			else if (ClientPrefs.data.middleScroll)
			{
				note.x += 310;
				if (lane > 1) note.x += FlxG.width / 2 + 25;
			}
			if (sustain && parent != null)
			{
				note.parent = parent;
				note.correctionOffset = parent.height / 2;
				if (ClientPrefs.data.downScroll) note.correctionOffset = 0;
			}
			note.scrollFactor.set();
		}

		// Pooled notes are plain taps only; custom-note setter side effects are never pooled.
		// Apply optional compact metadata for both newly allocated and recycled notes.
		note.sustainLength = castNote.sustainLength != null ? castNote.sustainLength : (castNote.holdLength == null ? note.sustainLength : castNote.holdLength);
		note.holdLength = castNote.holdLength == null ? note.sustainLength : castNote.holdLength;
		note.density = castNote.density == null ? 0 : castNote.density;
		note.cmpSpam = castNote.cmpSpam == null ? null : castNote.cmpSpam.copy();
		note.isSustainEnds = flags.isSustainEnds || castNote.chainEnd == true || castNote.isSustainEnds == true;
		note.poolEligible = poolable;
		if (poolable)
		{
			note.blockHit = flags.blockHit;
			note.ignoreNote = flags.ignoreNote;
			note.animSuffix = flags.altAnim ? '-alt' : '';
			if (flags.noAnimation) note.noAnimation = note.noMissAnimation = true;
			note.isSustainEnds = flags.isSustainEnds || castNote.chainEnd == true || castNote.isSustainEnds == true;
		}

		if (!sustain && castNote.hasSustain == true)
		{
			if (castNote.expectedTailCount != null)
				note.expectedTailCount = castNote.expectedTailCount;
			else if (castNote.tailCount != null)
				note.expectedTailCount = castNote.tailCount;
			else
				note.expectedTailCount = note.getTailCount();
			note.sustainChainBroken = false;
			chainParents.set(castNote.chainId, note);
			chainPrevious.set(castNote.chainId, note);
		}
		else if (sustain)
		{
			if (parent != null)
			{
				parent.addTailNote(note);
				// A late-spawned tail inherits a Guitar Hero sustain break even if the
				// parent has already left the active group.
				if (parent.sustainChainBroken)
				{
					note.missed = true;
					note.canBeHit = false;
					note.ignoreNote = true;
					note.tooLate = true;
				}
			}
			chainPrevious.set(castNote.chainId, note);
			if (castNote.chainEnd == true)
			{
				chainParents.remove(castNote.chainId);
				chainPrevious.remove(castNote.chainId);
			}
		}

		note.exists = note.alive = true;
		if (castNote.skipOnSpawn == true && !sustain && castNote.hasSustain == true)
		{
			// Retain only the logical parent needed by future sustain pieces; it is already hit
			// and must not appear, be judged again, or enter the active note collection.
			note.wasGoodHit = true;
			note.ignoreNote = true;
			note.active = note.visible = false;
		}
		else
		{
			note.active = note.visible = true;
			if (prepend) members.unshift(note); else members.push(note);
			@:privateAccess length++;
		}
		return note;
	}

	/** Drop retained objects immediately when the user lowers the pool limits. */
	public function trimPools():Void
	{
		if (!ClientPrefs.data.notePoolEnabled)
		{
			if (pooledNoteCount > 0) clearPools();
			return;
		}
		var perLaneLimit:Int = ClientPrefs.data.maxPooledNotesPerLane;
		var totalLimit:Int = ClientPrefs.data.maxPooledNotesTotal;
		var lanes:Array<Int> = [for (lane in tapPools.keys()) lane];
		for (lane in lanes)
		{
			var lanePool:Array<Note> = tapPools.get(lane);
			if (lanePool == null) continue;
			while (lanePool.length > 0 && (perLaneLimit <= 0 || lanePool.length > perLaneLimit || totalLimit <= 0 || pooledNoteCount > totalLimit))
			{
				var retired:Note = lanePool.pop();
				if (pooledNoteCount > 0) pooledNoteCount--;
				if (retired != null) retired.destroy();
			}
			if (lanePool.length == 0) tapPools.remove(lane);
		}
	}

	/** Called after PlayState unlinks a note from its logical/render/index groups. */
	public function releaseToPool(note:Note):Bool
	{
		if (!ClientPrefs.data.notePoolEnabled || !ClientPrefs.data.noteObjectPooling || note == null || !note.poolEligible
			|| note.isSustainNote || note.parent != null || note.getTailCount() > 0
			|| note.isPendingJudgement || note.isActiveJudgement || (note.noteType != null && note.noteType.length > 0)) return false;
		if (PlayState.instance != null && PlayState.instance.hasNoteScriptsLoaded()) return false;
		// A fresh standalone tap points prev/next to itself. Never pool a note that is
		// still linked into another note's chain.
		if (note.prevNote != null && note.prevNote != note) return false;
		if (note.nextNote != null && note.nextNote != note) return false;
		if (note.hasExtraData()) return false; // Script-attached state is not safe to reuse.
		var lane:Int = note.noteData;
		var laneLimit:Int = ClientPrefs.data.maxPooledNotesPerLane;
		var totalLimit:Int = ClientPrefs.data.maxPooledNotesTotal;
		if (laneLimit <= 0 || totalLimit <= 0 || lane < 0 || lane > Note.CAST_LANE_MASK || pooledNoteCount >= totalLimit) return false;
		var lanePool:Array<Note> = getLanePool(lane, true);
		if (lanePool.length >= laneLimit) return false;
		note.active = note.visible = false;
		note.exists = note.alive = false;
		note.clipRect = null;
		note.spawned = false;
		lanePool.push(note);
		pooledNoteCount++;
		return true;
	}

	/** Destroy and release all retained sprites. Used when pooling is disabled or the song ends. */
	public function clearPools():Void
	{
		for (lanePool in tapPools)
		{
			for (note in lanePool) if (note != null) note.destroy();
			lanePool.resize(0);
		}
		tapPools = new Map<Int, Array<Note>>();
		pooledNoteCount = 0;
	}

	public function resetCastChains():Void
	{
		chainParents.clear();
		chainPrevious.clear();
	}

	/** Drop a deferred chain when seeking past all of its remaining tail segments. */
	public inline function discardCastChain(chainId:Int):Void
	{
		chainParents.remove(chainId);
		chainPrevious.remove(chainId);
	}

	public inline function poolSize():Int return pooledNoteCount;

	override public function destroy():Void
	{
		clearPools();
		resetCastChains();
		super.destroy();
	}
}
