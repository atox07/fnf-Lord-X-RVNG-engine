package;

import flixel.group.FlxGroup;
import flixel.input.gamepad.FlxGamepad;
import flixel.input.keyboard.FlxKey;
import openfl.Assets;

// Lo teniamo perché altri file del fork potrebbero referenziarlo
typedef TitleData =
{
  titlex:Float,
  titley:Float,
  startx:Float,
  starty:Float,
  gfx:Float,
  gfy:Float,
  backgroundSprite:String,
  bpm:Int,
  endY:Float,
}

class TitleState extends MusicBeatState
{
  public static var muteKeys:Array<FlxKey> = [FlxKey.ZERO];
  public static var volumeDownKeys:Array<FlxKey> = [FlxKey.NUMPADMINUS, FlxKey.MINUS];
  public static var volumeUpKeys:Array<FlxKey> = [FlxKey.NUMPADPLUS, FlxKey.PLUS];

  public static var initialized:Bool = false;
  public static var closedState:Bool = false;

  public var inCutscene:Bool = false;

  var canPause:Bool = true;

  var blackScreen:FlxSprite;
  var credGroup:FlxGroup;

  var bg:FlxSprite;
  var logoBlBUMP:FlxSprite;
  var titleText:FlxSprite;

  var mustUpdate:Bool = false;

  public static var titleJSON:TitleData;

  public static var updateVersion:String = '';

  override public function create():Void
  {
    Paths.clearStoredMemory();
    Paths.clearUnusedMemory();

    MusicBeatState.windowNameSuffix = " - Title Screen";

    MusicBeatState.windowNamePrefix = Assets.getText(Paths.txt("windowTitleBase", "preload"));

    super.create();

    #if CHECK_FOR_UPDATES
    if (ClientPrefs.checkForUpdates && !closedState && !Main.askedToUpdate)
    {
      trace('Checking for a update...');
      final http = new haxe.Http("https://raw.githubusercontent.com/JordanSantiagoYT/FNF-JS-Engine/main/THECHANGELOG.md");
      var returnedData:Array<String> = [];

      http.onData = function(data:String) {
        var versionEndIndex:Int = data.indexOf(';');
        returnedData[0] = data.substring(0, versionEndIndex);

        // Extract the changelog after the version number
        returnedData[1] = data.substring(versionEndIndex + 1, data.length);
        updateVersion = returnedData[0];
        final curVersion:String = MainMenuState.psychEngineJSVersion.trim();
        final cleanVersion:String = curVersion.split(" (")[0]; // Removes everything after " ("
        #if debug
        trace(cleanVersion);
        #end
        trace('Current version online: ' + updateVersion + ', your version: ' + cleanVersion);
        if (updateVersion != cleanVersion && CoolUtil.isVersionNewer(updateVersion, cleanVersion))
        {
          trace("Versions don't match!");
          OutdatedState.currChanges = returnedData[1];
          mustUpdate = true;
          Main.askedToUpdate = true;
        }
        if (updateVersion == curVersion)
        {
          trace('The versions match!');
        }
        else
          trace('$updateVersion is less than $cleanVersion. Skipping update as it\'s likely a nightly version');
      }

      http.onError = function(error) {
        trace("[ERROR] it's a error $error");
      }

      http.request();
    }
    #end

    Highscore.load();

    // IGNORE THIS!!!
    titleJSON = Json.parse(Paths.getTextFromFile('images/gfDanceTitle.json'));

    if (!initialized)
    {
      persistentUpdate = true;
      persistentDraw = true;
    }

    if (FlxG.save.data.weekCompleted != null)
    {
      StoryMenuState.weekCompleted = FlxG.save.data.weekCompleted;
    }

    FlxG.mouse.visible = false;

    if (FlxG.save.data.flashing == null && !FlashingState.leftState)
    {
      FlxTransitionableState.skipNextTransIn = true;
      FlxTransitionableState.skipNextTransOut = true;
      FlxG.switchState(FlashingState.new);
    }
    else
    {
      // Come nell'originale sonic.exe: parte con un piccolo ritardo
      new FlxTimer().start(0.1, function(tmr:FlxTimer) {
        startIntro();
      });
    }
  }

  function startIntro()
  {
    if (!initialized)
    {
      // Musica del titolo di sonic.exe (mods/music/freakyMenu.ogg)
      FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);
      FlxG.sound.music.fadeIn(5, 0, 0.7);
    }

    Conductor.changeBPM(190);
    persistentUpdate = true;

    // Sfondo animato (mods/images/NewTitleMenuBG.png + .xml)
    bg = new FlxSprite(0, 0);
    bg.frames = Paths.getSparrowAtlas('NewTitleMenuBG');
    bg.animation.addByPrefix('idle', "TitleMenuSSBG instance 1", 24);
    bg.animation.play('idle');
    bg.alpha = .75;
    bg.scale.x = 3;
    bg.scale.y = 3;
    bg.antialiasing = true;
    bg.updateHitbox();
    bg.screenCenter();
    add(bg);

    // Logo (mods/images/logo.png)
    logoBlBUMP = new FlxSprite(0, 0);
    logoBlBUMP.loadGraphic(Paths.image('logo'));
    logoBlBUMP.antialiasing = true;
    logoBlBUMP.scale.x = .5;
    logoBlBUMP.scale.y = .5;
    logoBlBUMP.screenCenter();
    add(logoBlBUMP);

    // "Press Enter" (mods/images/titleEnterNEW.png + .xml)
    titleText = new FlxSprite(0, 0);
    titleText.frames = Paths.getSparrowAtlas('titleEnterNEW');
    titleText.animation.addByPrefix('idle', "Press Enter to Begin instance 1", 24);
    titleText.animation.addByPrefix('press', "ENTER PRESSED instance 1", 24, false);
    titleText.antialiasing = true;
    titleText.animation.play('idle');
    titleText.updateHitbox();
    titleText.screenCenter();
    add(titleText);

    // Schermo nero che copre tutto finché non finisce la risata
    credGroup = new FlxGroup();
    add(credGroup);

    blackScreen = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
    credGroup.add(blackScreen);

    if (initialized)
    {
      // Si torna al titolo da un altro menu: niente intro
      skipIntro();
    }
    else
    {
      initialized = true;
      // La risata di apertura: quando finisce si scopre il titolo
      FlxG.sound.play(Paths.sound('TitleLaugh'), 1, false, null, false, function() {
        skipIntro();
      });
    }
  }

  var transitioning:Bool = false;

  override function update(elapsed:Float)
  {
    if (FlxG.sound.music != null) Conductor.songPosition = FlxG.sound.music.time;

    var pressedEnter:Bool = FlxG.keys.justPressed.ENTER || controls.ACCEPT;

    var gamepad:FlxGamepad = FlxG.gamepads.lastActive;

    if (gamepad != null)
    {
      if (gamepad.justPressed.START) pressedEnter = true;
    }

    if (initialized && !transitioning && skippedIntro && titleText != null)
    {
      if (pressedEnter)
      {
        if (ClientPrefs.flashing)
        {
          titleText.animation.play('press');
          titleText.animation.finishCallback = function(a:String) {
            remove(titleText);
          }
        }

        FlxG.camera.flash(FlxColor.RED, 0.2);
        FlxG.sound.play(Paths.sound('menumomentclick'));
        FlxG.sound.play(Paths.sound('menulaugh'));
        FlxTween.tween(bg, {alpha: 0}, 1);

        new FlxTimer().start(1, function(tmr:FlxTimer) {
          FlxTween.tween(logoBlBUMP, {alpha: 0}, 1);
        });

        transitioning = true;

        new FlxTimer().start(4, function(tmr:FlxTimer) {
          remove(titleText); // nel caso i flash siano disattivati
          if (FlxG.sound.music != null) FlxG.sound.music.stop();

          if (mustUpdate)
          {
            FlxG.switchState(OutdatedState.new);
          }
          else
          {
            FlxG.switchState(MainMenuState.new);
          }
          closedState = true;
        });
      }
    }

    // ENTER durante la risata salta l'intro
    if (initialized && pressedEnter && !skippedIntro && credGroup != null)
    {
      skipIntro();
    }

    super.update(elapsed);
  }

  var skippedIntro:Bool = false;

  function skipIntro():Void
  {
    if (!skippedIntro)
    {
      FlxG.sound.play(Paths.sound('showMoment', 'shared'), .4);

      FlxG.camera.flash(FlxColor.RED, 2);
      remove(credGroup);
      skippedIntro = true;
    }
  }
}
