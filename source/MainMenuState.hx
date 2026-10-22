package;

import Achievements;
import backend.HaxeCommit;
import editors.MasterEditorMenu;
import flixel.effects.FlxFlicker;
import flixel.input.keyboard.FlxKey;
import haxe.Json;

/**
 * Main menu custom (porting di mainMenu.lua).
 * Due soli bottoni: FREEPLAY e OPTIONS.
 */
class MainMenuState extends MusicBeatState
{
  // Usati da altri file (TitleState, Discord RPC...): NON rimuovere
  public static final gitCommit:String = HaxeCommit.getGitCommitHash();

  public static var psychEngineJSVersion:String = '1.52.0'; // This is also used for Discord RPC
  public static var psychEngineVersion:String = '0.6.3'; // This is also used for Discord RPC
  public static var curSelected:Int = 0;

  // ---------------------------------------------------------------
  // CONFIGURAZIONE BOTTONI
  // image    = percorso dell'immagine/xml dentro images/
  // idle     = prefisso animazione bottone normale
  // selected = prefisso animazione bottone evidenziato
  // ---------------------------------------------------------------
  var buttons:Array<MenuButton> = [
    {
      id: 'freeplay',
      image: 'customMenu/buttons/button2',
      idle: '2basic',
      selected: '2white'
    },
    {
      id: 'options',
      image: 'customMenu/buttons/menu_options', // il TUO menu_options.png + menu_options.xml (stessa cartella di button2)
      idle: 'options basic',
      selected: 'options white'
    }
  ];

  // Percorso del file di configurazione (in mods/data/mainMenu.json).
  // Se il file manca o ha errori vengono usati questi valori di default.
  static final CONFIG_PATH:String = 'data/mainMenu.json';

  // Posizione finale del primo bottone (riferita a 1280x720, come nel lua)
  var buttonX:Float = 820;
  var buttonY:Float = 340;
  var buttonSpacing:Float = 140; // distanza verticale tra i bottoni

  // Lampeggio alla conferma (come nel lua)
  static final FLICKER_INTERVAL:Float = 0.07;
  static final FLICKER_DURATION:Float = 1.68;

  var menuItems:FlxTypedGroup<FlxSprite>;
  var bg:FlxSprite;

  // ---------------------------------------------------------------
  // LORD X (appare a caso a ogni ingresso nel menu)
  // ---------------------------------------------------------------
  var scaryChance:Float = 60; // probabilita' in % (0-100)
  var scaryImage:String = 'scaryx'; // mods/images/scaryx.png
  var scaryMusicName:String = 'scaryMenu'; // mods/music/scaryMenu.ogg
  var scaryX:Float = 0; // posizione (riferita a 1280x720)
  var scaryY:Float = 0;
  var scaryHeight:Float = 720; // altezza finale dell'immagine (riferita a 720)

  static var scaryMusic:Dynamic = null; // la musica scary attualmente in riproduzione (se c'e')
  var scaryMode:Bool = false;
  var scarySprite:FlxSprite;

  private var camGame:FlxCamera;
  private var camAchievement:FlxCamera;

  var debugKeys:Array<FlxKey>;
  var selectedSomethin:Bool = false;

  override function create()
  {
    MusicBeatState.windowNameSuffix = " - Main Menu";
    loadConfig();
    Paths.clearStoredMemory();
    Paths.clearUnusedMemory();

    #if MODS_ALLOWED
    Mods.pushGlobalMods();
    #end
    Mods.loadTopMod();

    #if DISCORD_ALLOWED
    // Updating Discord Rich Presence
    DiscordClient.changePresence("In the Menus", null);
    #end
    debugKeys = ClientPrefs.copyKey(ClientPrefs.keyBinds.get('debug_1'));

    camGame = initPsychCamera();
    camAchievement = new FlxCamera();
    camAchievement.bgColor.alpha = 0;
    FlxG.cameras.add(camAchievement, false);

    transIn = FlxTransitionableState.defaultTransIn;
    transOut = FlxTransitionableState.defaultTransOut;

    persistentUpdate = persistentDraw = true;

    // ----- LORD X: tiro la probabilita' a ogni ingresso nel menu -----
    // (se manca il png o la musica non rischio crash: resta il menu normale)
    scaryMode = FlxG.random.bool(scaryChance)
      && Paths.fileExists('images/' + scaryImage + '.png', openfl.utils.AssetType.IMAGE)
      && Paths.fileExists('music/' + scaryMusicName + '.ogg', openfl.utils.AssetType.MUSIC);

    final scaryPlaying:Bool = FlxG.sound.music != null && FlxG.sound.music.playing && FlxG.sound.music == scaryMusic;

    if (scaryMode)
    {
      // musica alternativa (parte da volume 0, l'update() la alza piano)
      if (!scaryPlaying)
      {
        FlxG.sound.playMusic(Paths.music(scaryMusicName), 0);
        scaryMusic = FlxG.sound.music;
      }
    }
    else
    {
      // menu normale: se prima suonava la musica scary la sostituisco con quella normale,
      // se non suona niente la riavvio (la musica normale parte dal TitleState)
      if (scaryPlaying || FlxG.sound.music == null || !FlxG.sound.music.playing)
      {
        Paths.playMenuMusic(true);
        scaryMusic = null;
      }
    }

    // ----- SFONDO ANIMATO -----
    bg = new FlxSprite();
    bg.frames = Paths.getSparrowAtlas('customMenu/MainMenu');
    bg.animation.addByPrefix('BG', 'BG', 24, true);
    bg.animation.play('BG');
    bg.scale.set(FlxG.width / 1280, FlxG.height / 720);
    bg.updateHitbox();
    bg.setPosition(0, 0);
    bg.scrollFactor.set(0, 0);
    bg.antialiasing = ClientPrefs.globalAntialiasing;
    add(bg);

    // ----- LORD X (solo se e' uscito il 60%) -----
    if (scaryMode)
    {
      scarySprite = new FlxSprite();
      scarySprite.loadGraphic(Paths.image(scaryImage));
      final targetH:Float = scaryHeight * (FlxG.height / 720);
      scarySprite.setGraphicSize(0, targetH); // larghezza proporzionale
      scarySprite.updateHitbox();
      scarySprite.setPosition(scaryX * (FlxG.width / 1280), scaryY * (FlxG.height / 720));
      scarySprite.scrollFactor.set(0, 0);
      scarySprite.antialiasing = ClientPrefs.globalAntialiasing;
      add(scarySprite);
    }

    // ----- BOTTONI -----
    menuItems = new FlxTypedGroup<FlxSprite>();
    add(menuItems);

    final targetX:Float = buttonX * (FlxG.width / 1280);
    final baseY:Float = buttonY * (FlxG.height / 720);
    final spacing:Float = buttonSpacing * (FlxG.height / 720);

    for (i in 0...buttons.length)
    {
      final b:MenuButton = buttons[i];

      final menuItem:FlxSprite = new FlxSprite(0, baseY + (i * spacing));
      menuItem.frames = Paths.getSparrowAtlas(b.image);
      final prefixes:Array<String> = getAnimPrefixes(menuItem);
      trace('[MainMenu] ' + b.id + ' (' + b.image + ') animazioni trovate: ' + prefixes);
      menuItem.animation.addByPrefix('idle', resolvePrefix(prefixes, b.idle, ['basic', 'idle', 'normal'], 0), 24);
      menuItem.animation.addByPrefix('selected', resolvePrefix(prefixes, b.selected, ['white', 'select', 'hover', 'high'], 1), 24);
      menuItem.animation.play('idle');
      menuItem.ID = i;
      menuItem.scrollFactor.set(0, 0);
      menuItem.antialiasing = ClientPrefs.globalAntialiasing;
      menuItem.updateHitbox();
      menuItem.screenCenter(X);
      menuItems.add(menuItem);

      // entra scivolando dal centro fino alla posizione finale (come il doTweenX del lua)
      FlxTween.tween(menuItem, {x: targetX}, 2, {ease: FlxEase.expoOut});
    }

    if (curSelected >= buttons.length || curSelected < 0) curSelected = 0;
    changeItem();

    #if ACHIEVEMENTS_ALLOWED
    // Unlocks "Freaky on a Friday Night" achievement if it's a Friday and between 18:00 PM and 23:59 PM
    if (DateUtils.isFunkin()) Achievements.unlock('friday_night_play');

    #if MODS_ALLOWED
    Achievements.reloadList();
    #end
    #end

    super.create();
  }

  override function update(elapsed:Float)
  {
    if (FlxG.sound.music != null && FlxG.sound.music.volume < 0.8)
    {
      FlxG.sound.music.volume += 0.5 * elapsed;
      if (FreeplayState.vocals != null) FreeplayState.vocals.volume += 0.5 * elapsed;
    }

    if (!selectedSomethin)
    {
      // F5 = rilegge mainMenu.json e ricostruisce il menu (senza ricompilare)
      if (FlxG.keys.justPressed.F5)
      {
        FlxG.resetState();
        return;
      }

      if (controls.UI_UP_P)
      {
        FlxG.sound.play(Paths.sound('scrollMenu'));
        changeItem(-1);
      }

      if (controls.UI_DOWN_P)
      {
        FlxG.sound.play(Paths.sound('scrollMenu'));
        changeItem(1);
      }

      if (controls.BACK)
      {
        selectedSomethin = true;
        FlxG.sound.play(Paths.sound('cancelMenu'));
        FlxG.switchState(TitleState.new);
      }
      else if (controls.ACCEPT)
      {
        confirmSelection();
      }
      #if (desktop)
      else if (FlxG.keys.anyJustPressed(debugKeys))
      {
        selectedSomethin = true;
        FlxG.switchState(MasterEditorMenu.new);
      }
      #end
    }

    super.update(elapsed);
  }

  // ---------------------------------------------------------------
  // CONFIG JSON
  // ---------------------------------------------------------------
  function loadConfig():Void
  {
    try
    {
      if (!Paths.fileExists(CONFIG_PATH, openfl.utils.AssetType.TEXT))
      {
        trace('[MainMenu] ' + CONFIG_PATH + ' non trovato: uso i valori di default');
        return;
      }

      final cfg:Dynamic = Json.parse(Paths.getTextFromFile(CONFIG_PATH));
      if (cfg == null) return;

      final btn:Dynamic = cfgObj(cfg, 'buttons');
      buttonX = cfgNum(btn, 'x', buttonX);
      buttonY = cfgNum(btn, 'y', buttonY);
      buttonSpacing = cfgNum(btn, 'spacing', buttonSpacing);

      if (btn != null && Reflect.hasField(btn, 'list'))
      {
        final arr:Array<Dynamic> = Reflect.field(btn, 'list');
        final list:Array<MenuButton> = [];
        for (b in arr)
        {
          list.push(
            {
              id: cfgStr(b, 'id', 'freeplay'),
              image: cfgStr(b, 'image', 'customMenu/buttons/button2'),
              idle: cfgStr(b, 'idle', ''),
              selected: cfgStr(b, 'selected', '')
            });
        }
        if (list.length > 0) buttons = list;
      }

      final sc:Dynamic = cfgObj(cfg, 'scary');
      scaryChance = cfgNum(sc, 'chance', scaryChance);
      scaryImage = cfgStr(sc, 'image', scaryImage);
      scaryMusicName = cfgStr(sc, 'music', scaryMusicName);
      scaryX = cfgNum(sc, 'x', scaryX);
      scaryY = cfgNum(sc, 'y', scaryY);
      scaryHeight = cfgNum(sc, 'height', scaryHeight);

      trace('[MainMenu] configurazione caricata da ' + CONFIG_PATH);
    }
    catch (e:Dynamic)
    {
      trace('[MainMenu] errore nel leggere ' + CONFIG_PATH + ': ' + e + ' (uso i valori di default)');
    }
  }

  function cfgObj(o:Dynamic, field:String):Dynamic
  {
    return (o != null && Reflect.hasField(o, field)) ? Reflect.field(o, field) : null;
  }

  function cfgNum(o:Dynamic, field:String, def:Float):Float
  {
    if (o != null && Reflect.hasField(o, field))
    {
      final v:Dynamic = Reflect.field(o, field);
      if (v != null) return v;
    }
    return def;
  }

  function cfgStr(o:Dynamic, field:String, def:String):String
  {
    if (o != null && Reflect.hasField(o, field))
    {
      final v:Dynamic = Reflect.field(o, field);
      if (v != null) return Std.string(v);
    }
    return def;
  }

  // Elenco dei prefissi delle animazioni presenti nell'xml (nome frame senza il numero finale)
  function getAnimPrefixes(spr:FlxSprite):Array<String>
  {
    final result:Array<String> = [];
    if (spr.frames == null) return result;

    for (frame in spr.frames.frames)
    {
      if (frame == null || frame.name == null) continue;
      final prefix:String = ~/[0-9]+$/.replace(frame.name, '');
      if (!result.contains(prefix)) result.push(prefix);
    }
    return result;
  }

  // Usa il prefisso scritto in config se esiste nell'xml, altrimenti lo cerca per parola chiave,
  // altrimenti prende il primo (idle) / il secondo (selected) prefisso dell'xml.
  function resolvePrefix(available:Array<String>, configured:String, keywords:Array<String>, fallbackIndex:Int):String
  {
    if (available.contains(configured)) return configured;

    for (p in available)
      for (k in keywords)
        if (p.toLowerCase().indexOf(k) != -1) return p;

    if (available.length == 0) return configured;
    return available[Std.int(Math.min(fallbackIndex, available.length - 1))];
  }

  function confirmSelection()
  {
    selectedSomethin = true;
    FlxG.sound.play(Paths.sound('confirmMenu'));

    menuItems.forEach(function(spr:FlxSprite) {
      if (curSelected != spr.ID)
      {
        // gli altri bottoni svaniscono
        FlxTween.tween(spr, {alpha: 0}, 0.4,
          {
            ease: FlxEase.quadOut,
            onComplete: function(twn:FlxTween) {
              spr.kill();
            }
          });
      }
      else
      {
        // il bottone scelto lampeggia, poi si apre il menu
        FlxFlicker.flicker(spr, FLICKER_DURATION, FLICKER_INTERVAL, false, false, function(flick:FlxFlicker) {
          openMenu(buttons[curSelected].id);
        });
      }
    });
  }

  function openMenu(id:String)
  {
    switch (id)
    {
      case 'freeplay':
        FlxG.switchState(FreeplayState.new);
      case 'options':
        LoadingState.loadAndSwitchState(options.OptionsState.new);
    }
  }

  function changeItem(huh:Int = 0)
  {
    curSelected += huh;

    if (curSelected >= menuItems.length) curSelected = 0;
    if (curSelected < 0) curSelected = menuItems.length - 1;

    menuItems.forEach(function(spr:FlxSprite) {
      spr.animation.play('idle');
      spr.updateHitbox();

      if (spr.ID == curSelected)
      {
        spr.animation.play('selected');
        spr.centerOffsets();
      }
    });
  }
}

typedef MenuButton =
{
  var id:String;
  var image:String;
  var idle:String;
  var selected:String;
}
