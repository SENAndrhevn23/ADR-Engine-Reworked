package backend;

import haxe.Json;
import lime.utils.Assets;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

import backend.Section;

typedef SwagSong =
{
	var song:String;
	var notes:Array<SwagSection>;
	var events:Array<Dynamic>;
	var bpm:Float;
	var needsVoices:Bool;
	var speed:Float;

	var player1:String;
	var player2:String;
	var gfVersion:String;
	var stage:String;

	@:optional var gameOverChar:String;
	@:optional var gameOverSound:String;
	@:optional var gameOverLoop:String;
	@:optional var gameOverEnd:String;
	
	@:optional var disableNoteRGB:Bool;

	@:optional var arrowSkin:String;
	@:optional var splashSkin:String;
	@:optional var __chartStreamPath:String;
	@:optional var __chartSourcePath:String;
}

class Song
{
	/** Maximum supported chart scroll speed multiplier. */
	public static inline var MAX_SCROLL_SPEED:Float = 100.0;
	/** Maximum supported song/section/metronome BPM. */
	public static inline var MAX_BPM:Float = 999999999.0;

	public static function clampScrollSpeed(value:Float):Float
	{
		if (Math.isNaN(value)) return 1.0;
		if (value < 0.1) return 0.1;
		if (value > MAX_SCROLL_SPEED) return MAX_SCROLL_SPEED;
		return value;
	}

	public static function clampBpm(value:Float):Float
	{
		if (Math.isNaN(value) || value < 1.0) return 1.0;
		if (value > MAX_BPM) return MAX_BPM;
		return value;
	}
	public var song:String;
	public var notes:Array<SwagSection>;
	public var events:Array<Dynamic>;
	public var bpm:Float;
	public var needsVoices:Bool = true;
	public var arrowSkin:String;
	public var splashSkin:String;
	public var gameOverChar:String;
	public var gameOverSound:String;
	public var gameOverLoop:String;
	public var gameOverEnd:String;
	public var disableNoteRGB:Bool = false;
	public var speed:Float = 1;
	public var stage:String;
	public var player1:String = 'bf';
	public var player2:String = 'dad';
	public var gfVersion:String = 'gf';

	private static function isMissingString(value:Dynamic):Bool
	{
		return value == null || (Std.isOfType(value, String) && StringTools.trim(Std.string(value)).length == 0);
	}

	private static function canonicalChartKey(value:String):String
	{
		if (value == null) return '';
		var key = StringTools.trim(value).toLowerCase();
		if (StringTools.endsWith(key, '.json')) key = key.substr(0, key.length - 5);
		return new EReg('[^a-z0-9]', 'g').replace(key, '');
	}

	private static function onLoadJson(songJson:Dynamic):Void // Normalize common chart metadata variants.
	{
		if (songJson == null) throw 'Invalid chart JSON: the song object is missing';

		if (songJson.bpm == null) songJson.bpm = 100.0;
		if (songJson.speed == null) songJson.speed = 1.0;
		songJson.bpm = clampBpm(Std.parseFloat(Std.string(songJson.bpm)));
		songJson.speed = clampScrollSpeed(Std.parseFloat(Std.string(songJson.speed)));

		// Psych Engine versions and community chart tools have used several spellings.
		// Accept all common aliases, including the frequent "gf-verison" typo.
		var gf:Dynamic = Reflect.field(songJson, 'gfVersion');
		if (isMissingString(gf))
		{
			for (field in Reflect.fields(songJson))
			{
				var key = canonicalChartKey(field);
				if (key == 'gfversion' || key == 'gfverison')
				{
					var candidate:Dynamic = Reflect.field(songJson, field);
					if (!isMissingString(candidate))
					{
						gf = candidate;
						break;
					}
				}
			}
		}
		if (isMissingString(gf)) gf = Reflect.field(songJson, 'player3');
		if (isMissingString(gf)) gf = 'gf';
		Reflect.setField(songJson, 'gfVersion', Std.string(gf));
		if (Reflect.hasField(songJson, 'player3')) Reflect.setField(songJson, 'player3', null);

		if (songJson.notes == null || !Std.isOfType(songJson.notes, Array)) songJson.notes = [];
		// songJson is Dynamic, so give its validated notes collection an iterable type.
		var chartSections:Array<Dynamic> = cast songJson.notes;
		if (songJson.events == null || !Std.isOfType(songJson.events, Array))
		{
			songJson.events = [];
			// Convert legacy event notes safely. Malformed rows are ignored, not fatal.
			for (section in chartSections)
			{
				if (section == null) continue;
				var sectionRows:Dynamic = Reflect.field(section, 'sectionNotes');
				if (sectionRows == null || !Std.isOfType(sectionRows, Array)) continue;
				var notes:Array<Dynamic> = cast sectionRows;
				var i:Int = 0;
				while (i < notes.length)
				{
					var note:Dynamic = notes[i];
					if (note != null && Std.isOfType(note, Array) && note.length >= 2 && note[1] != null && Std.parseFloat(Std.string(note[1])) < 0)
					{
						var eventName:Dynamic = note.length > 2 ? note[2] : '';
						var value1:Dynamic = note.length > 3 ? note[3] : '';
						var value2:Dynamic = note.length > 4 ? note[4] : '';
						songJson.events.push([note[0], [[eventName, value1, value2]]]);
						notes.remove(note);
					}
					else i++;
				}
			}
		}

		for (section in chartSections)
		{
			if (section == null || !Reflect.hasField(section, 'changeBPM') || !section.changeBPM) continue;
			var sectionBpm:Float = section.bpm == null ? songJson.bpm : Std.parseFloat(Std.string(section.bpm));
			section.bpm = clampBpm(sectionBpm);
		}
		if (songJson.player1 == null) songJson.player1 = 'bf';
		if (songJson.player2 == null) songJson.player2 = 'dad';
		if (songJson.needsVoices == null) songJson.needsVoices = true;
	}

	public function new(song, notes, bpm)
	{
		this.song = song;
		this.notes = notes;
		this.bpm = bpm;
	}

	#if sys
	private static function addUniquePath(paths:Array<String>, path:String):Void
	{
		if (path != null && path.length > 0 && !paths.contains(path)) paths.push(path);
	}

	private static function chartDataRoots():Array<String>
	{
		var roots:Array<String> = [];
		#if MODS_ALLOWED
		if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			addUniquePath(roots, Paths.mods(Mods.currentModDirectory + '/data'));
		for (mod in Mods.getGlobalMods()) addUniquePath(roots, Paths.mods(mod + '/data'));
		for (mod in Mods.getModDirectories()) addUniquePath(roots, Paths.mods(mod + '/data'));
		addUniquePath(roots, Paths.mods('data'));
		#end
		addUniquePath(roots, Paths.getSharedPath('data'));
		addUniquePath(roots, 'assets/data');
		return roots;
	}

	private static function chartPathBasename(path:String):String
	{
		var slash = path.lastIndexOf('/');
		return slash >= 0 ? path.substr(slash + 1) : path;
	}

	private static function resolveCaseInsensitiveDirectory(root:String, requestedFolder:String):String
	{
		if (requestedFolder == null || StringTools.trim(requestedFolder).length == 0) return root;
		if (!FileSystem.exists(root) || !FileSystem.isDirectory(root)) return null;

		var direct = haxe.io.Path.join([root, requestedFolder]);
		if (FileSystem.exists(direct) && FileSystem.isDirectory(direct)) return direct;

		var wanted = canonicalChartKey(requestedFolder);
		if (wanted.length == 0) return null;
		var matches:Array<String> = [];
		try
		{
			for (entry in FileSystem.readDirectory(root))
			{
				var candidate = haxe.io.Path.join([root, entry]);
				if (FileSystem.isDirectory(candidate) && canonicalChartKey(entry) == wanted)
					matches.push(candidate);
			}
		}
		catch (e:Dynamic) return null;
		if (matches.length == 0) return null;
		matches.sort(function(a:String, b:String):Int
		{
			var aName = chartPathBasename(a);
			var bName = chartPathBasename(b);
			var aExact = aName.toLowerCase() == requestedFolder.toLowerCase();
			var bExact = bName.toLowerCase() == requestedFolder.toLowerCase();
			if (aExact != bExact) return aExact ? -1 : 1;
			return a.toLowerCase() < b.toLowerCase() ? -1 : (a.toLowerCase() > b.toLowerCase() ? 1 : 0);
		});
		return matches[0];
	}

	private static function resolveCaseInsensitiveJson(directory:String, requestedName:String):String
	{
		if (directory == null || !FileSystem.exists(directory) || !FileSystem.isDirectory(directory)) return null;
		var requested = requestedName == null ? '' : StringTools.trim(requestedName);
		var slash = requested.lastIndexOf('/');
		if (slash >= 0) requested = requested.substr(slash + 1);
		if (StringTools.endsWith(requested.toLowerCase(), '.json')) requested = requested.substr(0, requested.length - 5);
		var wanted = canonicalChartKey(requested);
		if (wanted.length == 0) return null;

		var matches:Array<String> = [];
		try
		{
			for (entry in FileSystem.readDirectory(directory))
			{
				if (!StringTools.endsWith(entry.toLowerCase(), '.json')) continue;
				var full = haxe.io.Path.join([directory, entry]);
				if (FileSystem.isDirectory(full)) continue;
				var basename = entry.substr(0, entry.length - 5);
				if (canonicalChartKey(basename) == wanted) matches.push(full);
			}
		}
		catch (e:Dynamic) return null;
		if (matches.length == 0) return null;
		matches.sort(function(a:String, b:String):Int
		{
			var aName = chartPathBasename(a);
			var bName = chartPathBasename(b);
			var aBase = aName.substr(0, aName.length - 5);
			var bBase = bName.substr(0, bName.length - 5);
			var aExact = aBase.toLowerCase() == requested.toLowerCase();
			var bExact = bBase.toLowerCase() == requested.toLowerCase();
			if (aExact != bExact) return aExact ? -1 : 1;
			return a.toLowerCase() < b.toLowerCase() ? -1 : (a.toLowerCase() > b.toLowerCase() ? 1 : 0);
		});
		return matches[0];
	}

	private static function resolveChartDiskPath(jsonInput:String, folder:String):String
	{
		var roots = chartDataRoots();
		for (root in roots)
		{
			var directory = resolveCaseInsensitiveDirectory(root, folder);
			var file = resolveCaseInsensitiveJson(directory, jsonInput);
			if (file != null) return file;
			// Also support flat data directories where charts sit directly in data/.
			if (folder != null && folder.length > 0)
			{
				file = resolveCaseInsensitiveJson(root, jsonInput);
				if (file != null) return file;
			}
		}
		return null;
	}
	#end

	/** True when a chart/event JSON exists, including case and separator variants. */
	public static function chartExists(jsonInput:String, ?folder:String):Bool
	{
		#if sys
		if (resolveChartDiskPath(jsonInput, folder) != null) return true;
		#end
		var formattedFolder = folder == null ? '' : Paths.formatToSongPath(folder);
		var formattedSong = Paths.formatToSongPath(jsonInput);
		var key = formattedFolder.length > 0 ? formattedFolder + '/' + formattedSong : formattedSong;
		return Assets.exists(Paths.json(key));
	}

	public static function loadFromJson(jsonInput:String, ?folder:String, ?streamNotes:Bool = false):SwagSong
	{
		var safeInput:String = jsonInput == null ? '' : jsonInput;
		var formattedFolder:String = folder == null ? '' : Paths.formatToSongPath(folder);
		var formattedSong:String = Paths.formatToSongPath(safeInput);
		var relativeKey:String = formattedFolder.length > 0 ? formattedFolder + '/' + formattedSong : formattedSong;
		var path:String = Paths.json(relativeKey);
		var diskPath:String = null;
		var rawJson:String = null;

		#if sys
		// First keep the old exact-path lookup, then fall back to a directory scan that
		// ignores filename case, spaces, hyphens, underscores and punctuation.
		if (FileSystem.exists(path)) diskPath = path;
		if (diskPath == null) diskPath = resolveChartDiskPath(safeInput, folder);
		if ((streamNotes || (diskPath != null && ChartJsonStream.isSplitChart(diskPath))) && diskPath != null)
		{
			var streamedSong:Dynamic = ChartJsonStream.loadSong(diskPath);
			onLoadJson(streamedSong);
			if (canonicalChartKey(safeInput) != 'events') StageData.loadDirectory(streamedSong);
			return cast streamedSong;
		}
		if (diskPath != null) rawJson = File.getContent(diskPath).trim();
		#end

		if (rawJson == null)
		{
			#if sys
			if (FileSystem.exists(path)) rawJson = File.getContent(path).trim();
			else
			#end
			{
				if (!Assets.exists(path)) throw '[file_contents,$path]';
				rawJson = Assets.getText(path);
				if (rawJson != null) rawJson = StringTools.trim(rawJson);
			}
		}

		if (rawJson == null || rawJson.length == 0) throw 'Chart JSON is empty or unreadable: ' + (diskPath == null ? path : diskPath);
		// Ignore a UTF-8 BOM, which some Windows chart editors include.
		if (rawJson.length > 0 && rawJson.charCodeAt(0) == 0xFEFF) rawJson = rawJson.substr(1);
		while (rawJson.length > 0 && !rawJson.endsWith("}")) rawJson = rawJson.substr(0, rawJson.length - 1);
		if (rawJson.length == 0) throw 'Invalid chart JSON: no closing object brace in ' + (diskPath == null ? path : diskPath);

		var songJson:Dynamic = parseJSONshit(rawJson);
		if (canonicalChartKey(safeInput) != 'events') StageData.loadDirectory(songJson);
		return songJson;
	}

	#if sys
	/** Rebuild a streamed SONG after a retry when its sidecar has already reached EOF. */
	public static function reloadStreamedSong(song:SwagSong):SwagSong
	{
		if (song == null || song.__chartSourcePath == null || song.__chartSourcePath.length == 0)
			throw 'Cannot reload streamed chart: its original JSON path was not retained';
		if (!FileSystem.exists(song.__chartSourcePath))
			throw 'Cannot reload streamed chart because the source JSON no longer exists: ' + song.__chartSourcePath;

		var streamedSong:Dynamic = ChartJsonStream.loadSong(song.__chartSourcePath);
		onLoadJson(streamedSong);
		StageData.loadDirectory(streamedSong);
		return cast streamedSong;
	}
	#end

	public static function parseJSONshit(rawJson:String):SwagSong
	{
		if (rawJson == null) throw 'Cannot parse an empty chart JSON string';
		var clean:String = StringTools.trim(rawJson);
		if (clean.length > 0 && clean.charCodeAt(0) == 0xFEFF) clean = clean.substr(1);
		var root:Dynamic = Json.parse(clean);
		if (root == null) throw 'Invalid chart JSON: root value is null';
		var songJson:Dynamic = Reflect.field(root, 'song');
		// Some exporters write a song-name string plus chart fields at the root,
		// rather than wrapping the chart object inside a `song` object.
		if ((songJson == null || Std.isOfType(songJson, String) || Std.isOfType(songJson, Array))
			&& !Std.isOfType(root, Array) && Reflect.hasField(root, 'notes')) songJson = root;
		if (songJson == null) throw 'Invalid chart JSON: expected a song object or a root notes array';
		onLoadJson(songJson);
		return cast songJson;
	}
}
