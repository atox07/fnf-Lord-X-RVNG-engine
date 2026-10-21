package;

import flixel.FlxG;
import haxe.Json;
import flixel.util.FlxTimer;
import flixel.util.FlxSave;
import flixel.addons.transition.FlxTransitionableState;

class StartupState extends MusicBeatState
{
	var vidSprite:VideoSprite = null;
	var leaving:Bool = false;
	var restartMode:Bool = false;

	override public function create():Void
	{
		FlxTransitionableState.skipNextTransIn = true;
		FlxTransitionableState.skipNextTransOut = true;
		FlxG.mouse.visible = false;

		restartMode = isCrashPending();

		super.create();

		// Piccolo ritardo: il video va creato quando lo state è già attivo,
		// altrimenti si sente l'audio ma non si vede l'immagine
		new FlxTimer().start(0.1, function(tmr:FlxTimer)
		{
			if (!leaving)
				startIntro();
		});
	}

	// stesso save scritto da the-strongest-enemy/crash.lua
	function openSecretSave():FlxSave
	{
		var save:FlxSave = new FlxSave();
		save.bind('conscienceSecret', 'conscienceSecret');
		return save;
	}

	function isCrashPending():Bool
	{
		return openSecretSave().data.crashPending == true;
	}

	function clearCrashFlag():Void
	{
		var save = openSecretSave();
		save.data.crashPending = false;
		save.flush();
	}

	function startIntro():Void
	{
		#if VIDEOS_ALLOWED
		var fileName:String = Paths.video(restartMode ? 'introrestart' : 'HaxeFlixelIntro');

		#if sys
		var found:Bool = FileSystem.exists(fileName);
		#else
		var found:Bool = OpenFlAssets.exists(fileName);
		#end

		if (!found)
		{
			FlxG.log.error('Video not found: ' + fileName);
			onIntroEnd();
			return;
		}

		// canSkip = false: lo skip lo gestiamo noi con ENTER in update()
		vidSprite = new VideoSprite(fileName, false, false, false);
		vidSprite.finishCallback = onIntroEnd;
		vidSprite.onSkip = restartMode ? function() {} : onIntroEnd;
		insert(0, vidSprite);
		vidSprite.videoSprite.play();
		#else
		FlxG.log.warn('Platform not supported!');
		onIntroEnd();
		#end
	}

	function onIntroEnd():Void
	{
		if (restartMode)
			goToConscience();
		else
			goToTitle();
	}

	function goToTitle():Void
	{
		if (leaving)
			return;
		leaving = true;
		FlxG.switchState(TitleState.new);
	}

	function goToConscience():Void
	{
		if (leaving)
			return;
		leaving = true;

		clearCrashFlag();

		try
		{
			// Quello che TitleState.create() fa e che serve al resto del gioco (Freeplay incluso)
			Highscore.load();
			TitleState.titleJSON = Json.parse(Paths.getTextFromFile('images/gfDanceTitle.json'));
			if (FlxG.save.data.weekCompleted != null)
				StoryMenuState.weekCompleted = FlxG.save.data.weekCompleted;

			// Come fa FreeplayState: PlayState si aspetta che le settimane siano caricate,
			// che storyWeek punti alla settimana giusta e che la cartella mod sia impostata.
			var song:String = 'conscience';
			WeekData.reloadWeekFiles(false);

			var weekIndex:Int = -1;
			for (i in 0...WeekData.weeksList.length)
			{
				var leWeek:WeekData = WeekData.weeksLoaded.get(WeekData.weeksList[i]);
				if (leWeek == null)
					continue;
				for (sg in leWeek.songs)
				{
					if (Paths.formatToSongPath(sg[0]) == song)
					{
						weekIndex = i;
						WeekData.setDirectoryFromWeek(leWeek);
						break;
					}
				}
				if (weekIndex > -1)
					break;
			}
			if (weekIndex < 0)
				throw 'conscience non trovata in nessun weeks/*.json';

			PlayState.storyWeek = weekIndex;

			// difficoltà: stessa logica di FreeplayState.setupDifficulties()
			CoolUtil.difficulties = CoolUtil.defaultDifficulties.copy();
			var diffStr:String = WeekData.getCurrentWeek().difficulties;
			if (diffStr != null)
				diffStr = diffStr.trim();
			if (diffStr != null && diffStr.length > 0)
			{
				var diffs:Array<String> = diffStr.split(',');
				var k:Int = diffs.length - 1;
				while (k > 0)
				{
					if (diffs[k] != null)
					{
						diffs[k] = diffs[k].trim();
						if (diffs[k].length < 1)
							diffs.remove(diffs[k]);
					}
					--k;
				}
				if (diffs.length > 0 && diffs[0].length > 0)
					CoolUtil.difficulties = diffs;
			}
			var defIndex:Int = CoolUtil.difficulties.indexOf(CoolUtil.defaultDifficulty);
			var diff:Int = defIndex > -1 ? defIndex : 0;
			PlayState.storyDifficulty = diff;
			CoolUtil.currentDifficulty = CoolUtil.difficultyString();

			var chart:String = Highscore.formatSong(song, diff);
			trace('[Startup] conscience chart=' + chart + ' week=' + weekIndex + ' mod="' + Mods.currentModDirectory + '"');

			PlayState.SONG = Song.loadFromJson(chart, song);
			PlayState.isStoryMode = PlayState.wasOriginallyFreeplay = ClientPrefs.alwaysTriggerCutscene;

			if (FlxG.sound.music != null)
				FlxG.sound.music.stop();

			LoadingState.loadAndSwitchState(PlayState.new);
		}
		catch (e:Dynamic)
		{
			trace('Errore caricando conscience: ' + e);
			FlxG.switchState(TitleState.new);
		}
	}

	override function update(elapsed:Float)
	{
		// introrestart NON è skippabile
		if (!restartMode && FlxG.keys.justPressed.ENTER)
			goToTitle();

		super.update(elapsed);
	}
}
