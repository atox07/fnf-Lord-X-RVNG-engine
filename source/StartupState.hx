package;

import flixel.FlxG;
import flixel.util.FlxTimer;
import flixel.addons.transition.FlxTransitionableState;

class StartupState extends MusicBeatState
{
	var vidSprite:VideoSprite = null;
	var leaving:Bool = false;

	override public function create():Void
	{
		FlxTransitionableState.skipNextTransIn = true;
		FlxTransitionableState.skipNextTransOut = true;
		FlxG.mouse.visible = false;

		super.create();

		// Piccolo ritardo: il video va creato quando lo state è già attivo,
		// altrimenti si sente l'audio ma non si vede l'immagine
		new FlxTimer().start(0.1, function(tmr:FlxTimer)
		{
			if (!leaving)
				startIntro();
		});
	}

	function startIntro():Void
	{
		#if VIDEOS_ALLOWED
		var fileName:String = Paths.video('HaxeFlixelIntro');

		#if sys
		var found:Bool = FileSystem.exists(fileName);
		#else
		var found:Bool = OpenFlAssets.exists(fileName);
		#end

		if (!found)
		{
			FlxG.log.error('Video not found: ' + fileName);
			goToTitle();
			return;
		}

		// canSkip = false: lo skip lo gestiamo noi con ENTER in update()
		vidSprite = new VideoSprite(fileName, false, false, false);
		vidSprite.finishCallback = goToTitle;
		vidSprite.onSkip = goToTitle;
		insert(0, vidSprite);
		vidSprite.videoSprite.play();
		#else
		FlxG.log.warn('Platform not supported!');
		goToTitle();
		#end
	}

	function goToTitle():Void
	{
		if (leaving)
			return;
		leaving = true;
		FlxG.switchState(TitleState.new);
	}

	override function update(elapsed:Float)
	{
		if (FlxG.keys.justPressed.ENTER)
			goToTitle();

		super.update(elapsed);
	}
}
