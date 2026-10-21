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

			// stessa logica di FreeplayState: difficoltà di default
			CoolUtil.difficulties = CoolUtil.defaultDifficulties.copy();
			var defIndex:Int = CoolUtil.difficulties.indexOf(CoolUtil.defaultDifficulty);
			var diff:Int = defIndex > -1 ? defIndex : 0;
			PlayState.storyDifficulty = diff;
			CoolUtil.currentDifficulty = CoolUtil.difficultyString();

			var song:String = 'conscience';
			var chart:String = Highscore.formatSong(song, diff);

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
