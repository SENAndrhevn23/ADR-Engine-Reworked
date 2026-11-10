package options;

import backend.ClientPrefs;
import objects.Note;

class OptimizationsSubState extends BaseOptionsMenu
{
	private var presetOption:Option = null;
	private var applyingPreset:Bool = false;

	override public function addOption(option:Option):Option
	{
		var result:Option = super.addOption(option);
		if (presetOption != null && option != presetOption)
		{
			var previousChange:Void->Void = option.onChange;
			option.onChange = function():Void
			{
				if (previousChange != null) previousChange();
				markPresetCustom();
			};
		}
		return result;
	}

	private function markPresetCustom():Void
	{
		if (applyingPreset || presetOption == null) return;
		presetOption.setValue('Custom');
		presetOption.curOption = presetOption.options.indexOf('Custom');
	}

	private function applyPerformancePreset(name:String):Void
	{
		// Choosing Custom is a no-op: it is a marker for manually adjusted options.
		if (name == 'Custom') return;
		applyingPreset = true;
		var data = ClientPrefs.data;
		var isDefault:Bool = name == 'Default';
		var isMaximum:Bool = name == 'Maximum Performance';

		// Presets touch processing/storage settings only. They intentionally do not alter
		// Show Notes, player/opponent visibility, animation quality, shaders, antialiasing,
		// overlap suppression, or the rendered-note limit. Visual accuracy stays user-owned.
		data.noteRenderProcessingEnabled = !isDefault;
		data.compactCastNoteStorageEnabled = !isDefault;
		data.noteObjectPooling = !isDefault;
		data.notePoolEnabled = !isDefault;
		data.maxPooledNotesPerLane = isDefault ? 0 : (isMaximum ? 2048 : 512);
		data.maxPooledNotesTotal = isDefault ? 0 : (isMaximum ? 16384 : 4096);
		data.lazyNoteGraphics = !isDefault;
		data.noteAnimationResourceCaching = !isDefault;
		data.fastNoteSpawning = !isDefault;
		data.deferredSustainSpawning = !isDefault;
		data.chunkedNoteGeneration = !isDefault;
		data.releaseProcessedChartData = !isDefault;
		data.fastNoteLogicQueue = !isDefault;
		data.optimizedNoteInput = !isDefault;
		data.fastNoteTransformCache = !isDefault;
		data.noteViewportCulling = !isDefault;
		data.noteCullingUpdateInterval = 1;
		data.noteCullingHysteresis = !isDefault;
		data.noteViewportCullMargin = isMaximum ? 160 : 128;
		data.fastNoteGroupRemoval = !isDefault;
		data.fastNoteInputIndex = !isDefault;
		data.reuseSustainClipRects = !isDefault;
		data.maxActiveNoteObjects = 0;
		data.noteSpawnAheadMs = 1500;
		data.noteGenerationRowsPerFrame = isDefault ? 2048 : (isMaximum ? 16384 : 4096);
		data.noteGenerationQueueTarget = isDefault ? 25000 : (isMaximum ? 100000 : 50000);
		data.maxNoteSpawnsPerFrame = isDefault ? 0 : (isMaximum ? 16384 : 4096);
		data.maxNoteSpawnTimeMs = isDefault ? 0 : (isMaximum ? 4 : 2);
		data.noteSpawnBudgetMode = isDefault ? 'Count' : (isMaximum ? 'Hybrid' : 'Count');

		if (!data.noteAnimationResourceCaching) Note.clearNoteAnimationCache();
		applyingPreset = false;
	}

	public function new()
	{
		title = 'Optimizations';
		rpcTitle = 'Optimization Settings Menu';

		// Original ADR Engine controls, mapped to the reworked engine's current runtime.
		addOption(new Option('Show Rating Pop-Up',
			'Shows the rating sprite after a successful hit.', 'showRatingPopup', 'bool'));
		addOption(new Option('Show Combo Number Pop-Up',
			'Shows the individual combo digits after a successful hit.', 'showNumPopup', 'bool'));
		addOption(new Option('Show Combo Pop-Up',
			'Shows the combo label after a successful hit.', 'showComboPopup', 'bool'));
		addOption(new Option('Disable Score Pop-Up',
			'Skips creating rating/combo popup sprites after scoring. Hit judgement, accuracy, score and health calculations are preserved.',
			'disablePopUpScore', 'bool'));
		addOption(new Option('Manual Garbage Collection',
			'On C++ builds, requests a garbage-collection pass every five seconds. This can reduce unpredictable automatic collection timing, but may cause a short periodic pause.',
			'disableGCLag', 'bool'));
		addOption(new Option('Disable onUpdate Callbacks',
			'Skips onUpdate/onUpdatePost script callbacks. Game updates and note judgement continue.',
			'disableScriptUpdateEvents', 'bool'));
		addOption(new Option('Disable onStepHit Callbacks',
			'Skips beat/step-related script callbacks. Engine beat and step timing continue.',
			'disableBeatStepCallbacks', 'bool'));
		addOption(new Option('Disable Lua/HScript Calls',
			'Skips Lua and HScript callbacks for gameplay. Script-driven mod features will not run.',
			'disableLuaHScriptCalls', 'bool'));
		addOption(new Option('Disable Lua/HScript Calls On Stages',
			'Skips callbacks for scripts loaded from stage script paths. Other Lua/HScript callbacks remain enabled.',
			'disableLuaHScriptStageCalls', 'bool'));
		addOption(new Option('Disable Lua/HScript Calls On Events',
			'Skips callbacks for event scripts and chart-event callback names. Built-in event handling continues.',
			'disableLuaHScriptEventCalls', 'bool'));
		addOption(new Option('Note Culling',
			'Skips Flixel updates/drawing for rendered notes outside the viewport plus a margin. Notes remain available for judgement.',
			'noteViewportCulling', 'bool'));
		var oldLimit:Option = new Option('Max Notes Shown',
			'Maximum number of note sprites admitted to the render group. 0 means unlimited. Remaining chart notes still receive gameplay judgement.',
			'renderedNotesLimit', 'int');
		oldLimit.minValue = 0;
		oldLimit.maxValue = 100000;
		oldLimit.changeValue = 1024;
		oldLimit.scrollSpeed = 2048;
		oldLimit.displayFormat = '%v (0 = Unlimited)';
		addOption(oldLimit);
		var betterRecycling:Option = new Option('Better Recycling',
			'Enables bounded reuse and retention of eligible plain tap-note sprites. Sustain chains and custom note types use the normal compatibility path.',
			'noteObjectPooling', 'bool');
		betterRecycling.onChange = function():Void
		{
			ClientPrefs.data.notePoolEnabled = ClientPrefs.data.noteObjectPooling;
		};
		addOption(betterRecycling);

		// Presets only modify note processing settings. Individual edits switch the selector to Custom.
		presetOption = new Option('Performance Preset',
			'Choose Default, Optimized, or Maximum Performance note-processing settings. All note visuals, gameplay judgement, custom note types and sustain behavior remain enabled. Manual changes to individual optimization settings select Custom.',
			'notePerformancePreset', 'string', ['Default', 'Optimized', 'Maximum Performance', 'Custom']);
		presetOption.onChange = function():Void applyPerformancePreset(Std.string(presetOption.getValue()));
		addOption(presetOption);

		addOption(new Option('Note Rendering Processing',
			'Uses a separate render group so Flixel only traverses notes admitted to the rendering pipeline. Disable to restore the legacy all-note Flixel group. This does not cap or hide notes when Rendered Notes Limit is 0.',
			'noteRenderProcessingEnabled', 'bool'));

		// Visibility controls requested at the top of this menu.
		addOption(new Option('Show Notes',
			'Shows or hides note art. Hidden notes still receive hit-window and gameplay checks; their sprite animation/update work is skipped.',
			'showNotes', 'bool'));

		// Per-side and per-sprite rendering controls. They never remove logical notes.
		addOption(new Option('Render Player Notes',
			'Draws the player-side note sprites. Disabling this hides their art only; input, hit windows, misses, scoring and BOTPLAY remain active.',
			'renderPlayerNotes', 'bool'));
		addOption(new Option('Render Opponent Notes',
			'Draws the opponent-side note sprites. Disabling this hides their art only; opponent timing and hit processing remain active.',
			'renderOpponentNotes', 'bool'));
		addOption(new Option('Animate Note Graphics',
			'Pauses note sprite animations to reduce per-sprite animation work. Notes remain visible on a static frame; gameplay and sustain timing are unchanged.',
			'noteRenderingAnimations', 'bool'));
		addOption(new Option('Note RGB Shader Effects',
			'Uses per-note RGB palette shaders for lane colors and RGB note effects. Disable to avoid creating/using these note shaders; custom note colors and Hurt Note tinting may look different.',
			'noteRenderingRGBShaders', 'bool'));
		addOption(new Option('Note Antialiasing',
			'Allows antialiasing on non-pixel note sprites when the global antialiasing preference is enabled. Disable for sharper edges and slightly less filtering work.',
			'noteRenderingAntialiasing', 'bool'));


		var overlapWindow:Option = new Option('Remove Overlapped Notes (ms)',
			'Optional visual suppression of duplicate tap-note heads in the same side, lane and note type. No notes are hidden by default (0 ms); enabling this explicitly suppresses duplicate visuals but never changes chart data, scoring or judgement.',
			'overlapRemovalWindowMs', 'float');
		overlapWindow.minValue = 0;
		overlapWindow.maxValue = 5;
		overlapWindow.changeValue = 0.01;
		overlapWindow.scrollSpeed = 0.05;
		overlapWindow.decimals = 2;
		overlapWindow.displayFormat = '%v ms (0 = Off)';
		addOption(overlapWindow);

		addOption(new Option('JSON Streaming (Configurable Rows/Frame)',
			'For filesystem charts, scans JSON with a bounded input buffer and writes note rows to a temporary disk-backed sidecar. PlayState converts a configurable number of raw rows per update into compact CastNote records. Requires extra free disk space. Embedded assets use normal loading. SONG.notes[].sectionNotes is empty in this mode, so scripts or editors that inspect raw chart rows may not be compatible.',
			'jsonStreamingEnabled', 'bool'));
		addOption(new Option('Chunk Note Generation (Configurable Rows/Frame)',
			'For charts loaded normally, creates compact CastNote records in configurable batches per update and replenishes the unspawned queue as it drains. Enabled by default for high-density charts. JSON Streaming performs file-backed loading and does not require this option.',
			'chunkedNoteGeneration', 'bool'));
		addOption(new Option('Release Processed Chart Data',
			'When chunked generation is enabled, clears sectionNotes after their rows have been converted into compact pending chart records. Scripts that inspect processed SONG.notes[].sectionNotes will no longer see those rows.',
			'releaseProcessedChartData', 'bool'));

		// Note processing. Defaults preserve the original gameplay behavior.
		addOption(new Option('Enable Note Object Recycling',
			'Reuses eligible plain tap Note instances retained by the pool. Requires Enable Note Pool Retention. Disabling recycling clears retained objects and returns removed notes to normal destruction. Sustain chains, custom note types and Lua/HScript-mod charts use fresh objects for compatibility.',
			'noteObjectPooling', 'bool'));
		addOption(new Option('Enable Note Pool Retention',
			'Retains eligible removed plain tap notes in the bounded Note pool for reuse. Requires Enable Note Object Recycling. Disable to destroy removed notes and clear retained objects.',
			'notePoolEnabled', 'bool'));
		addOption(new Option('Compact CastNote Flag Storage',
			'Packs lane and gameplay booleans into a 16-bit flag layout inside CastNote.noteData. The expanded compatibility layout remains available when disabled. Lane indices 0 through 255 are preserved in both layouts; changing this setting does not invalidate queued records.',
			'compactCastNoteStorageEnabled', 'bool'));
		addOption(new Option('Lazy Note Graphics',
			'Defers note atlas, animation and per-note RGB shader initialization for ordinary tap notes until they enter the rendered-note budget. Hidden gameplay notes remain judgeable but avoid most visual setup. Sustain/custom notes initialize immediately; this automatically falls back to eager setup when Lua/HScript mods are loaded.',
			'lazyNoteGraphics', 'bool'));
		var animationCache:Option = new Option('Cache Note Animation Atlases',
			'Reuses resolved Sparrow atlas frame objects by skin name. Custom skins use separate cache entries. Disabling this clears the Note atlas lookup cache and returns to direct Paths lookups.',
			'noteAnimationResourceCaching', 'bool');
		animationCache.onChange = function():Void { if (!ClientPrefs.data.noteAnimationResourceCaching) Note.clearNoteAnimationCache(); };
		addOption(animationCache);
		addOption(new Option('Fast Note Spawning',
			'Uses a cursor-based spawn queue and appends directly to the private logical-note array, avoiding a full null-slot search per spawn. Recommended for dense charts and enabled by default. It does not dispatch FlxTypedGroup memberAdded signals; mods that directly modify notes.members or unspawnNotes may be incompatible.',
			'fastNoteSpawning', 'bool'));
		addOption(new Option('Deferred Sustain Spawning',
			'Keeps one compact descriptor per sustain chain and creates each sustain segment only when it enters the spawn-ahead window. This avoids expanding long holds into thousands of pending CastNote objects during chart generation. Disable only for compatibility testing.',
			'deferredSustainSpawning', 'bool'));
		var ahead:Option = new Option('Note Spawn Ahead (ms)',
			'How many milliseconds before a note is due that it becomes a live Note object. Lower values reduce the number of live Note objects and memory, but notes appear closer to the receptors. Higher values give more visual travel time but use more memory.',
			'noteSpawnAheadMs', 'float');
		ahead.minValue = 100;
		ahead.maxValue = 5000;
		ahead.changeValue = 100;
		ahead.scrollSpeed = 500;
		ahead.decimals = 0;
		ahead.displayFormat = '%v ms';
		addOption(ahead);
		var spawnBudget:Option = new Option('Max Note Spawns Per Frame',
			'Hard count limit for Note objects created in one update. Used by Count and Hybrid modes. The 4,096 default targets dense charts; 0 disables the count limit. If the limit is too low, notes may spawn late.',
			'maxNoteSpawnsPerFrame', 'int');
		spawnBudget.minValue = 0;
		spawnBudget.maxValue = 65536;
		spawnBudget.changeValue = 512;
		spawnBudget.scrollSpeed = 4096;
		spawnBudget.displayFormat = '%v (0 = Unlimited)';
		addOption(spawnBudget);
		addOption(new Option('Spawn Budget Mode',
			'Count limits objects per update; Time limits note-spawn CPU time; Hybrid obeys both limits. Count is the high-throughput default. Use Hybrid or Time to prioritize a strict frame-time budget.',
			'noteSpawnBudgetMode', 'string', ['Hybrid', 'Count', 'Time']));
		var spawnTimeBudget:Option = new Option('Spawn CPU Budget (ms)',
			'Maximum CPU time spent creating notes in one update. Used by Time and Hybrid modes. 0 disables the time limit. Very low values can cause late spawning on dense charts.',
			'maxNoteSpawnTimeMs', 'float');
		spawnTimeBudget.minValue = 0;
		spawnTimeBudget.maxValue = 12;
		spawnTimeBudget.changeValue = 0.25;
		spawnTimeBudget.scrollSpeed = 1;
		spawnTimeBudget.decimals = 2;
		spawnTimeBudget.displayFormat = '%v ms (0 = Unlimited)';
		addOption(spawnTimeBudget);
		var activeLimit:Option = new Option('Max Active Note Objects',
			'Optional ceiling for live logical Note objects, following H-Slice limitNotes. When the ceiling is reached, new notes remain in the pending queue until older notes are judged/removed. 0 disables the ceiling; a low value can make notes spawn late.',
			'maxActiveNoteObjects', 'int');
		activeLimit.minValue = 0;
		activeLimit.maxValue = 1000000;
		activeLimit.changeValue = 1024;
		activeLimit.scrollSpeed = 8192;
		activeLimit.displayFormat = '%v (0 = Unlimited)';
		addOption(activeLimit);
		var rowsBudget:Option = new Option('Chart Rows Per Frame',
			'Raw chart rows converted into compact pending records per update. Higher values load huge charts faster but can create larger frame-time spikes. Sustain tails are not expanded here when Deferred Sustain Spawning is enabled.',
			'noteGenerationRowsPerFrame', 'int');
		rowsBudget.minValue = 64;
		rowsBudget.maxValue = 16384;
		rowsBudget.changeValue = 256;
		rowsBudget.scrollSpeed = 1024;
		addOption(rowsBudget);
		var queueTarget:Option = new Option('Pending Chart Queue Target',
			'When the number of unspawned chart heads falls below this value, another chart-generation batch is read. Lower values reduce pending-memory use; higher values keep more data ready ahead of time.',
			'noteGenerationQueueTarget', 'int');
		queueTarget.minValue = 1024;
		queueTarget.maxValue = 250000;
		queueTarget.changeValue = 4096;
		queueTarget.scrollSpeed = 16384;
		queueTarget.displayFormat = '%v notes';
		addOption(queueTarget);
		var poolLimit:Option = new Option('Pooled Tap Notes Per Lane',
			'Maximum recycled tap-note sprites retained for each lane. Higher values reduce allocations during bursts but retain more memory. 0 disables pooling retention.',
			'maxPooledNotesPerLane', 'int');
		poolLimit.minValue = 0;
		poolLimit.maxValue = 32768;
		poolLimit.changeValue = 512;
		poolLimit.scrollSpeed = 2048;
		poolLimit.displayFormat = '%v';
		addOption(poolLimit);
		var poolTotal:Option = new Option('Maximum Total Pooled Notes',
			'Global limit across every lane. This prevents the per-lane pool limits from retaining too many sprites on high-lane-count charts. 0 disables pool retention.',
			'maxPooledNotesTotal', 'int');
		poolTotal.minValue = 0;
		poolTotal.maxValue = 131072;
		poolTotal.changeValue = 256;
		poolTotal.scrollSpeed = 8192;
		poolTotal.displayFormat = '%v (0 = Off)';
		addOption(poolTotal);
		addOption(new Option('Active-Window Note Logic',
			'Uses a timestamp-ordered queue to keep future notes out of per-frame judgement scans. Notes are processed from their early-hit window through normal miss/expiry time; notes inside that window are still checked every frame. Normal hit windows, BOTPLAY, opponent hits, misses and scoring remain active. Requires Fast Note Spawning. Enabled by default. Experimental: mods that directly insert/remove notes.members or retime notes after spawn may be incompatible.',
			'fastNoteLogicQueue', 'bool'));
		addOption(new Option('Optimized Note Input',
			'Finds the best two matching notes in one pass instead of allocating and sorting a temporary array on every key press. Gameplay selection rules are preserved.',
			'optimizedNoteInput', 'bool'));
		addOption(new Option('Cached Note Lane Transforms',
			'Calculates each receptor lane transform once per frame and reuses its direction math for every note. This reduces repeated sine/cosine work without hiding notes or changing hit windows.',
			'fastNoteTransformCache', 'bool'));
		addOption(new Option('Disable Note Splashes',
			'Stops creating note splash effects when notes are hit.',
			'disableNoteSplashes', 'bool'));
		addOption(new Option('Sustain Note Clipping',
			'Keeps hold notes clipped against the receptors. Disable it to skip per-frame clipping work; hold notes may draw through the receptors.',
			'sustainNoteClipping', 'bool'));
		addOption(new Option('Reuse Sustain Clip Rectangles',
			"Reuses each sustain note's FlxRect clipping object instead of allocating a new rectangle on each clipping update. Disable only for compatibility testing with custom code that expects clip-rect replacement.",
			'reuseSustainClipRects', 'bool'));
		addOption(new Option('Beat Note Sorting',
			'Sorts active notes by screen position every beat so overlapping notes render in the expected order. Disable to skip that sort; overlap draw order may change.',
			'noteSorting', 'bool'));

		addOption(new Option('Fast Logical Note Removal',
			'Removes expired notes from the private logical-note array with a constant-time swap-pop instead of searching and shifting the whole array. It changes notes.members order and bypasses FlxTypedGroup memberRemoved signals; turn it off for mods that depend on either behavior.',
			'fastNoteGroupRemoval', 'bool'));
		addOption(new Option('Fast Lane Input Index',
			'Keeps notes indexed by lane for key presses and sustain checks. With Active-Window Note Logic enabled, it searches only notes inside the judgement window, not future spawned notes. Core hit windows and scoring remain enabled. Mods that change noteData after spawn or insert notes directly into notes.members should turn this off.',
			'fastNoteInputIndex', 'bool'));
		var cullMargin:Option = new Option('Viewport Cull Margin',
			'Extra pixels around the screen before a note is deactivated for rendering. Increase this for unusual camera movement or large custom note graphics.',
			'noteViewportCullMargin', 'int');
		cullMargin.minValue = 0;
		cullMargin.maxValue = 1024;
		cullMargin.changeValue = 32;
		cullMargin.scrollSpeed = 128;
		cullMargin.displayFormat = '%v px';
		addOption(cullMargin);
		var cullInterval:Option = new Option('Note Culling Update Interval',
			'Recalculates viewport visibility every N frames. 1 is the most accurate and recommended value. Higher values reduce bounds checks slightly but can delay a note appearing by a few frames; increase Cull Margin if needed.',
			'noteCullingUpdateInterval', 'int');
		cullInterval.minValue = 1;
		cullInterval.maxValue = 4;
		cullInterval.changeValue = 1;
		cullInterval.scrollSpeed = 1;
		cullInterval.displayFormat = 'Every %v frame(s)';
		addOption(cullInterval);
		addOption(new Option('Note Culling Hysteresis',
			'Uses a slightly larger exit margin for currently visible notes, preventing rapid on/off flicker as a note crosses the viewport boundary.',
			'noteCullingHysteresis', 'bool'));

		// Script execution. Core note judgement, scoring, built-in events and stage logic remain active.
		addOption(new Option('Disable Lua Scripts',
			'Prevents Lua scripts from loading and receiving callbacks for this PlayState. Lua-based mod features will not run.',
			'disableLuaScripts', 'bool'));
		addOption(new Option('Disable HScript Scripts',
			'Prevents HScript (.hx) scripts from loading and receiving callbacks for this PlayState. HScript-based mod features will not run.',
			'disableHScriptScripts', 'bool'));
		addOption(new Option('Disable Script Update Callbacks',
			'Skips onUpdate and onUpdatePost in Lua and HScript. Other script callbacks remain available.',
			'disableScriptUpdateEvents', 'bool'));
		addOption(new Option('Disable Note Hit Events',
			'Skips goodNoteHitPre, goodNoteHit, opponentNoteHitPre and opponentNoteHit script callbacks. Note hits, animations, scoring and health still work.',
			'disableNoteHitEvents', 'bool'));
		addOption(new Option('Disable Note Miss Events',
			'Skips noteMiss and noteMissPress script callbacks. Miss judgement, health loss and score changes still work.',
			'disableNoteMissEvents', 'bool'));
		addOption(new Option('Disable Note Spawn Events',
			'Skips onSpawnNote callbacks. Notes still spawn normally; scripts will not receive each note-spawn notification.',
			'disableNoteSpawnEvents', 'bool'));
		addOption(new Option('Disable Chart Event Callbacks',
			'Skips eventEarlyTrigger, onEventPushed and onEvent script callbacks. Built-in chart events and stage event handlers still run.',
			'disableChartEventCallbacks', 'bool'));
		addOption(new Option('Disable Beat/Step Callbacks',
			'Skips onCountdownTick, onStepHit, onBeatHit and onSectionHit script callbacks. The engine beat/step timing and character dances remain active.',
			'disableBeatStepCallbacks', 'bool'));
		addOption(new Option('Disable Input Callbacks',
			'Skips onKeyPress, onKeyPressPre, onKeyRelease, onKeyReleasePre and onGhostTap script callbacks. Keyboard input and note judgement remain active.',
			'disableInputCallbacks', 'bool'));
		addOption(new Option('Disable Lifecycle Callbacks',
			'Skips script callbacks for countdown/song start, pause/resume, game over, song end and PlayState post-creation. Engine state transitions still work.',
			'disableLifecycleCallbacks', 'bool'));
		addOption(new Option('Disable Camera Callbacks',
			'Skips onMoveCamera callbacks. Built-in camera movement and section logic remain active.',
			'disableCameraCallbacks', 'bool'));
		addOption(new Option('Disable Dialogue Callbacks',
			'Skips onNextDialogue and onSkipDialogue callbacks. Dialogue itself remains available.',
			'disableDialogueCallbacks', 'bool'));
		addOption(new Option('Disable Score Callbacks',
			'Skips preUpdateScore, onUpdateScore and onRecalculateRating callbacks. Built-in score and accuracy calculations remain active.',
			'disableScoreCallbacks', 'bool'));
		addOption(new Option('Disable Custom Substate Callbacks',
			'Skips script callbacks when custom substates are created, updated or destroyed. Custom substates still run.',
			'disableCustomSubstateCallbacks', 'bool'));
		addOption(new Option('Disable Per-Frame Script Variable Sync',
			'Stops updating curDecStep, curDecBeat, cameraX, cameraY and botPlay in scripts every frame. Scripts reading these values may behave differently.',
			'disableScriptVariableSync', 'bool'));

		super();
	}
}
