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

	// nomi di file accettati come flag (uno scritto dal mio crash.lua, l'altro dalla tua versione)
	static final FLAG_FILES:Array<String> = ['conscience_crash.flag', 'crashpending.flag'];

	function isCrashPending():Bool
	{
		var fromFile:Bool = false;
		#if sys
		for (f in FLAG_FILES)
			if (sys.FileSystem.exists(f))
				fromFile = true;
		#end
		var fromSave:Bool = openSecretSave().data.crashPending == true;
		trace('[Startup] crash flag: file=' + fromFile + ' save=' + fromSave);
		return fromFile || fromSave;
	}

	function clearCrashFlag():Void
	{
		#if sys
		for (f in FLAG_FILES)
		{
			try
			{
				if (sys.FileSystem.exists(f))
					sys.FileSystem.deleteFile(f);
			}
			catch (e:Dynamic) {}
		}
		#end
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
			// Quello che TitleState.create() fa e che serve al Freeplay
			Highscore.load();
			TitleState.titleJSON = Json.parse(Paths.getTextFromFile('images/gfDanceTitle.json'));
			if (FlxG.save.data.weekCompleted != null)
				StoryMenuState.weekCompleted = FlxG.save.data.weekCompleted;

			// Il resto del gioco (Freeplay, PlayState) si aspetta che la musica del menu esista:
			// TitleState la avvia, ma noi lo saltiamo. Parte a volume 0.
			Paths.playMenuMusic(true, 0);

			// Passo dal Freeplay vero: lui prepara tutto quello che serve a PlayState
			// e avvia conscience da solo (vedi FreeplayState.autoStartSecret)
			FreeplayState.autoStartSecret = true;
			FlxG.switchState(FreeplayState.new);
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
