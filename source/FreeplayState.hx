package;

import WeekData;
import editors.ChartingState;
import flixel.addons.display.FlxBackdrop;
import flixel.input.keyboard.FlxKey;
import flixel.util.FlxSave;
import flixel.util.FlxTimer;

/**
 * Freeplay custom (porting di freeplay.lua).
 * - Le settimane e le canzoni arrivano da weeks/*.json (week1 = lord-x, week2 = anti-x)
 * - A sinistra i frame delle settimane, a destra la sidebar con le canzoni
 * - SU/GIU' cambia settimana, INVIO entra nelle canzoni, INVIO sulla canzone la avvia
 */
class FreeplayState extends MusicBeatState
{
  // ---------------------------------------------------------------
  // CONFIGURAZIONE
  // ---------------------------------------------------------------
  // file della settimana (weeks/NOME.json) -> nome immagine in customMenu/fpstuff/
  // (e titolo mostrato nella sidebar). Se una settimana non e' qui, usa il nome del file.
  static final FRAME_NAMES:Map<String, String> = [
    'week1' => 'lord-x',
    'week2' => 'anti-x'
  ];

  // true = mostra SOLO le settimane che stanno in una cartella mod (nasconde quelle del gioco base)
  static final ONLY_MOD_WEEKS:Bool = true;

  static final FRAME_X:Float = 80; // x dei frame
  static final FRAME_Y:Float = 190; // y del frame selezionato
  static final FRAME_SPACING:Float = 447; // distanza verticale tra i frame
  static final FRAME_W_FALLBACK:Int = 219; // misure del segnaposto se manca l'immagine
  static final FRAME_H_FALLBACK:Int = 347;
  static final BLACK_LINE_X:Float = 80 + 219;

  static final SIDEBAR_SCROLL:Float = 0.5; // altezze di sidebar al secondo (negativo = scorre verso l'alto)
  static final SONGS_CENTER_Y:Float = 320; // y centrale della lista canzoni
  static final SONGS_SPACING:Float = 60;
  static final MENU_FONT:String = 'sonic-cd-menu-font.otf';

  // canzone segreta: resta nascosta finche' non viene completata (la sblocca mods/data/conscience/unlock.lua)
  static final SECRET_SONG:String = 'conscience';

  // ---------------------------------------------------------------
  var weekGroups:Array<WeekGroup> = [];

  var weekSelec:Int = 0;
  var songSelec:Int = 0;
  var inSongs:Bool = false;
  var busy:Bool = false;

  var curDifficulty:Int = -1;

  // codice per aprire la canzone segreta: scrivi 0707 nel freeplay
  static final SECRET_CODE:Array<FlxKey> = [FlxKey.ZERO, FlxKey.SEVEN, FlxKey.ZERO, FlxKey.SEVEN];
  var secretCodeIndex:Int = 0;

  var bg:FlxSprite;
  var blackLine:FlxSprite;
  var sidebar:FlxBackdrop;
  var titleText:FlxText;
  var weekSprites:Array<FlxSprite> = [];
  var songTexts:FlxTypedGroup<FlxText>;

  var sidebarX:Float = 0;
  var sidebarW:Float = 0;

  // Questi static servono ad altri file (PlayState, MainMenuState...): NON rimuoverli
  // true = apri il freeplay, seleziona la canzone segreta e avviala da solo (lo imposta StartupState)
  public static var autoStartSecret:Bool = false;

  public static var curPlaying:Bool = false;
  public static var instPlaying:Int = -1;
  public static var vocals:FlxSound = null;
  public static var opponentVocals:FlxSound = null;

  override function create()
  {
    Paths.clearStoredMemory();
    Paths.clearUnusedMemory();
    Paths.gc();

    persistentUpdate = true;
    PlayState.isStoryMode = false;
    WeekData.reloadWeekFiles(false);

    #if DISCORD_ALLOWED
    // Updating Discord Rich Presence
    DiscordClient.changePresence("In the Menus", null);
    #end

    // ----- LETTURA SETTIMANE / CANZONI -----
    if (WeekData.weeksList.length > 0)
    {
      for (w in WeekData.weeksList)
        trace('[Freeplay] settimana trovata: ' + w + ' (cartella mod: "' + WeekData.weeksLoaded.get(w).folder + '")');

      // solo le settimane che stanno nella cartella mod (le settimane del gioco base hanno la cartella vuota)
      collectWeeks(function(leWeek:WeekData, fileName:String) return !ONLY_MOD_WEEKS || (leWeek.folder != null && leWeek.folder.length > 0));

      // se i tuoi json non stanno in una cartella mod, ripiego sui nomi della mappa FRAME_NAMES
      if (weekGroups.length < 1 && ONLY_MOD_WEEKS)
      {
        trace('[Freeplay] nessuna settimana in cartelle mod, uso FRAME_NAMES');
        collectWeeks(function(leWeek:WeekData, fileName:String) return FRAME_NAMES.exists(fileName));
      }
    }

    if (weekGroups.length < 1)
    {
      FlxTransitionableState.skipNextTransIn = true;
      persistentUpdate = false;
      final msg:String = "NO WEEKS ADDED FOR FREEPLAY\n\nPress ACCEPT to go to the Week Editor Menu.\nPress BACK to return to Main Menu.";
      FlxG.switchState(new ErrorState(msg, function() FlxG.switchState(new editors.WeekEditorState()), function() FlxG.switchState(new MainMenuState())));
      return;
    }

    #if PRELOAD_ALL
    if (!curPlaying) Conductor.changeBPM(TitleState.titleJSON.bpm);
    #end

    MusicBeatState.windowNameSuffix = " - Freeplay Menu";

    final sx:Float = FlxG.width / 1280;
    final sy:Float = FlxG.height / 720;

    // ----- SFONDO -----
    bg = new FlxSprite().loadGraphic(Paths.image('customMenu/backgroundlool'));
    bg.scale.set(sx, sy);
    bg.updateHitbox();
    bg.setPosition(0, 0);
    bg.scrollFactor.set(0, 0);
    bg.antialiasing = ClientPrefs.globalAntialiasing;
    add(bg);

    // ----- LINEA NERA -----
    blackLine = new FlxSprite(BLACK_LINE_X, 0).makeGraphic(10, FlxG.height, FlxColor.BLACK);
    blackLine.scrollFactor.set(0, 0);
    add(blackLine);

    // ----- SIDEBAR CHE SCORRE -----
    final sbGraphic = Paths.image('customMenu/sidebar');
    sidebar = new FlxBackdrop(sbGraphic, Y);
    sidebar.scale.set(sy, sy);
    sidebar.updateHitbox();
    sidebarW = sbGraphic.width * sy;
    sidebarX = FlxG.width - sidebarW;
    sidebar.x = sidebarX;
    sidebar.velocity.y = SIDEBAR_SCROLL * sbGraphic.height * sy;
    sidebar.scrollFactor.set(0, 0);
    sidebar.antialiasing = ClientPrefs.globalAntialiasing;
    add(sidebar);

    // ----- FRAME DELLE SETTIMANE -----
    for (i in 0...weekGroups.length)
    {
      final spr:FlxSprite = new FlxSprite(FRAME_X, FRAME_Y);
      final graphic = Paths.image('customMenu/fpstuff/' + weekGroups[i].frameName);
      if (graphic != null) spr.loadGraphic(graphic);
      else
      {
        trace('Manca customMenu/fpstuff/' + weekGroups[i].frameName + '.png');
        spr.makeGraphic(FRAME_W_FALLBACK, FRAME_H_FALLBACK, FlxColor.GRAY);
      }
      spr.scrollFactor.set(0, 0);
      spr.antialiasing = ClientPrefs.globalAntialiasing;
      weekSprites.push(spr);
      add(spr);
    }

    // ----- TITOLO -----
    titleText = new FlxText(sidebarX + 50, 30, sidebarW, '', 50);
    titleText.setFormat(Paths.font(MENU_FONT), 50, FlxColor.WHITE, CENTER);
    titleText.scrollFactor.set(0, 0);
    add(titleText);

    // ----- CANZONI -----
    songTexts = new FlxTypedGroup<FlxText>();
    add(songTexts);

    changeWeek(0, false);
    updateWeekFrames(true);

    super.create();

    if (autoStartSecret) startSecretSong();
  }

  // avvio automatico di conscience dopo introrestart: schermo nero sopra tutto e poi parte la canzone
  function startSecretSong()
  {
    autoStartSecret = false;
    busy = true;

    final cover:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
    cover.scrollFactor.set(0, 0);
    add(cover);

    var found:Bool = false;
    for (w in 0...weekGroups.length)
    {
      for (s in 0...weekGroups[w].songs.length)
      {
        if (Paths.formatToSongPath(weekGroups[w].songs[s].songName) == SECRET_SONG)
        {
          weekSelec = w;
          songSelec = s;
          found = true;
        }
      }
    }

    if (!found)
    {
      trace('[Freeplay] canzone segreta non trovata, torno al menu');
      FlxG.switchState(TitleState.new);
      return;
    }

    new FlxTimer().start(0.1, function(tmr:FlxTimer)
    {
      inSongs = true;
      playSelectedSong();
    });
  }

  function collectWeeks(accept:(WeekData, String) -> Bool)
  {
    weekGroups = [];
    final secretUnlocked:Bool = isSecretUnlocked() || autoStartSecret;

    for (i in 0...WeekData.weeksList.length)
    {
      final fileName:String = WeekData.weeksList[i];
      if (weekIsLocked(fileName)) continue;

      final leWeek:WeekData = WeekData.weeksLoaded.get(fileName);
      if (!accept(leWeek, fileName)) continue;

      WeekData.setDirectoryFromWeek(leWeek);

      final list:Array<SongMetadata> = [];
      for (song in leWeek.songs)
      {
        if (!secretUnlocked && Paths.formatToSongPath(song[0]) == SECRET_SONG) continue;

        var colors:Array<Int> = song[2];
        if (colors == null || colors.length < 3) colors = [146, 113, 253];
        list.push(new SongMetadata(song[0], i, song[1], FlxColor.fromRGB(colors[0], colors[1], colors[2])));
      }

      if (list.length > 0)
      {
        final frameName:String = FRAME_NAMES.exists(fileName) ? FRAME_NAMES.get(fileName) : fileName;
        weekGroups.push({fileName: fileName, frameName: frameName, songs: list});
      }
    }
    Mods.loadTopMod();
  }

  // ---------------------------------------------------------------
  // UPDATE
  // ---------------------------------------------------------------
  override function update(elapsed:Float)
  {
    if (FlxG.sound.music != null && FlxG.sound.music.volume < 0.7) FlxG.sound.music.volume += 0.5 * elapsed;

    if (!busy) checkSecretCode();

    if (!busy && weekGroups.length > 0)
    {
      if (inSongs) updateSongsMode();
      else
        updateWeeksMode();
    }

    super.update(elapsed);
  }

  // 0707 -> ricarica il freeplay con autoStartSecret: la canzone segreta compare e parte da sola
  function checkSecretCode()
  {
    var key:FlxKey = FlxG.keys.firstJustPressed();
    if (key == FlxKey.NONE) return;

    // il tastierino numerico vale come la riga dei numeri
    if (key == FlxKey.NUMPADZERO) key = FlxKey.ZERO;
    if (key == FlxKey.NUMPADSEVEN) key = FlxKey.SEVEN;

    if (key == SECRET_CODE[secretCodeIndex]) secretCodeIndex++;
    else
      secretCodeIndex = (key == SECRET_CODE[0]) ? 1 : 0;

    if (secretCodeIndex >= SECRET_CODE.length)
    {
      secretCodeIndex = 0;
      busy = true;
      autoStartSecret = true;
      FlxG.resetState();
    }
  }

  function updateWeeksMode()
  {
    if (controls.BACK)
    {
      busy = true;
      persistentUpdate = false;
      curPlaying = false;
      FlxG.sound.play(Paths.sound('cancelMenu'));
      FlxG.switchState(MainMenuState.new);
      return;
    }

    if (weekGroups.length > 1)
    {
      if (controls.UI_UP_P) changeWeek(-1);
      if (controls.UI_DOWN_P) changeWeek(1);
    }

    if (controls.ACCEPT)
    {
      inSongs = true;
      songSelec = 0;
      updateSongTexts();
      setupDifficulties();
    }
  }

  function updateSongsMode()
  {
    final list:Array<SongMetadata> = weekGroups[weekSelec].songs;

    if (controls.BACK)
    {
      inSongs = false;
      FlxG.sound.play(Paths.sound('cancelMenu'));
      updateSongTexts();
      return;
    }

    if (list.length > 1)
    {
      if (controls.UI_UP_P) changeSong(-1);
      if (controls.UI_DOWN_P) changeSong(1);
    }

    if (FlxG.keys.justPressed.CONTROL)
    {
      persistentUpdate = false;
      openSubState(new GameplayChangersSubstate());
    }
    else if (controls.RESET)
    {
      persistentUpdate = false;
      openSubState(new ResetScoreSubState(list[songSelec].songName, curDifficulty, list[songSelec].songCharacter));
      FlxG.sound.play(Paths.sound('scrollMenu'));
    }
    else if (controls.ACCEPT)
    {
      playSelectedSong();
    }
  }

  override function closeSubState()
  {
    persistentUpdate = true;
    super.closeSubState();
  }

  // ---------------------------------------------------------------
  // SELEZIONE
  // ---------------------------------------------------------------
  function changeWeek(change:Int = 0, playSound:Bool = true)
  {
    if (playSound && change != 0) FlxG.sound.play(Paths.sound('scrollMenu'));

    weekSelec += change;
    if (weekSelec >= weekGroups.length) weekSelec = 0;
    if (weekSelec < 0) weekSelec = weekGroups.length - 1;

    songSelec = 0;
    titleText.text = weekGroups[weekSelec].frameName.toUpperCase();

    buildSongTexts();
    setupDifficulties();
    if (change != 0) updateWeekFrames(false);
  }

  function changeSong(change:Int)
  {
    FlxG.sound.play(Paths.sound('scrollMenu'));

    final total:Int = weekGroups[weekSelec].songs.length;
    songSelec += change;
    if (songSelec >= total) songSelec = 0;
    if (songSelec < 0) songSelec = total - 1;

    updateSongTexts();
    setupDifficulties();
  }

  // Un solo tween (y + alpha) per frame: prima cancello quello vecchio, cosi' non si combattono
  function updateWeekFrames(instant:Bool)
  {
    for (i in 0...weekSprites.length)
    {
      final spr:FlxSprite = weekSprites[i];
      final offset:Int = i - weekSelec;
      final targetY:Float = FRAME_Y + FRAME_SPACING * offset;
      final targetAlpha:Float = (offset == 0) ? 1 : 0.5;

      FlxTween.cancelTweensOf(spr);
      if (instant)
      {
        spr.y = targetY;
        spr.alpha = targetAlpha;
      }
      else
        FlxTween.tween(spr, {y: targetY, alpha: targetAlpha}, 0.5, {ease: FlxEase.expoOut});
    }
  }

  function buildSongTexts()
  {
    for (t in songTexts.members)
      if (t != null) t.destroy();
    songTexts.clear();

    final list:Array<SongMetadata> = weekGroups[weekSelec].songs;
    final startY:Float = SONGS_CENTER_Y - (SONGS_SPACING / 2) * (list.length - 1);

    for (i in 0...list.length)
    {
      final t:FlxText = new FlxText(sidebarX + 50, startY + SONGS_SPACING * i, sidebarW, list[i].songName.toLowerCase(), 40);
      t.setFormat(Paths.font(MENU_FONT), 40, FlxColor.BLACK, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.WHITE);
      t.borderSize = 2.5;
      t.scrollFactor.set(0, 0);
      songTexts.add(t);
    }
    updateSongTexts();
  }

  // canzone scelta = testo bianco senza bordo, le altre nere con bordo bianco
  function updateSongTexts()
  {
    for (i in 0...songTexts.members.length)
    {
      final t:FlxText = songTexts.members[i];
      if (t == null) continue;

      if (inSongs && i == songSelec)
      {
        t.color = FlxColor.WHITE;
        t.borderStyle = FlxTextBorderStyle.NONE;
      }
      else
      {
        t.color = FlxColor.BLACK;
        t.borderStyle = FlxTextBorderStyle.OUTLINE;
        t.borderColor = FlxColor.WHITE;
        t.borderSize = 2.5;
      }
    }
  }

  // ---------------------------------------------------------------
  // DIFFICOLTA' E AVVIO CANZONE
  // ---------------------------------------------------------------
  function setupDifficulties()
  {
    final song:SongMetadata = weekGroups[weekSelec].songs[songSelec];
    Mods.currentModDirectory = song.folder;
    PlayState.storyWeek = song.week;

    CoolUtil.difficulties = CoolUtil.defaultDifficulties.copy();
    var diffStr:String = WeekData.getCurrentWeek().difficulties;
    if (diffStr != null) diffStr = diffStr.trim();

    if (diffStr != null && diffStr.length > 0)
    {
      final diffs:Array<String> = diffStr.split(',');
      var i:Int = diffs.length - 1;
      while (i > 0)
      {
        if (diffs[i] != null)
        {
          diffs[i] = diffs[i].trim();
          if (diffs[i].length < 1) diffs.remove(diffs[i]);
        }
        --i;
      }

      if (diffs.length > 0 && diffs[0].length > 0) CoolUtil.difficulties = diffs;
    }

    // difficolta' di default della settimana (es. "Hard" per le tue), altrimenti la prima disponibile
    final defIndex:Int = CoolUtil.difficulties.indexOf(CoolUtil.defaultDifficulty);
    curDifficulty = defIndex > -1 ? defIndex : 0;

    PlayState.storyDifficulty = curDifficulty;
  }

  function playSelectedSong()
  {
    setupDifficulties();

    final song:SongMetadata = weekGroups[weekSelec].songs[songSelec];
    final songLowercase:String = Paths.formatToSongPath(song.songName);
    final poop:String = Highscore.formatSong(songLowercase, curDifficulty);

    trace(poop);
    CoolUtil.currentDifficulty = CoolUtil.difficultyString();
    trace('[Freeplay] AVVIO canzone="' + song.songName + '" chart="' + poop + '" settimana=' + song.week + ' cartellaMod="' + song.folder
      + '" difficolta=' + CoolUtil.currentDifficulty);

    if (sys.FileSystem.exists(Paths.modsJson(songLowercase + '/' + poop))
      || sys.FileSystem.exists(Paths.json(songLowercase + '/' + poop))
      || OpenFlAssets.exists(Paths.modsJson(songLowercase + '/' + poop))
      || OpenFlAssets.exists(Paths.json(songLowercase + '/' + poop)))
    {
      busy = true;
      persistentUpdate = false;

      PlayState.SONG = Song.loadFromJson(poop, songLowercase);
      PlayState.storyDifficulty = curDifficulty;
      PlayState.isStoryMode = PlayState.wasOriginallyFreeplay = ClientPrefs.alwaysTriggerCutscene;

      trace('CURRENT WEEK: ' + WeekData.getWeekFileName());
      trace('STAGE DEL CHART: ' + PlayState.SONG.stage);
      curPlaying = false;

      if (FlxG.keys.pressed.SHIFT) LoadingState.loadAndSwitchState(ChartingState.new);
      else
        LoadingState.loadAndSwitchState(PlayState.new);

      if (FlxG.sound.music != null) FlxG.sound.music.volume = 0;
      destroyFreeplayVocals();
    }
    else
    {
      FlxG.sound.play(Paths.sound('invalidJSON'));
      CoolUtil.coolError("Non trovo il chart di '"
        + song.songName
        + "' ("
        + poop
        + ".json).\nControlla che il nome in weeks/"
        + WeekData.getWeekFileName()
        + ".json coincida con la cartella in data/ e con il nome del json.",
        "JS Engine Anti-Crash Tool");
    }
  }

  // legge il save scritto dal Lua (initSaveData('conscienceSecret', 'conscienceSecret'))
  function isSecretUnlocked():Bool
  {
    #if sys
    if (sys.FileSystem.exists('conscience_unlocked.flag')) return true; // scritto da unlock.lua
    #end
    final save:FlxSave = new FlxSave();
    save.bind('conscienceSecret', 'conscienceSecret');
    return save.data.unlocked == true;
  }

  function weekIsLocked(name:String):Bool
  {
    var leWeek:WeekData = WeekData.weeksLoaded.get(name);
    return (!leWeek.startUnlocked
      && leWeek.weekBefore.length > 0
      && (!StoryMenuState.weekCompleted.exists(leWeek.weekBefore) || !StoryMenuState.weekCompleted.get(leWeek.weekBefore)));
  }

  public static function destroyFreeplayVocals()
  {
    if (vocals != null) vocals.stop();
    vocals = FlxDestroyUtil.destroy(vocals);

    if (opponentVocals != null) opponentVocals.stop();
    opponentVocals = FlxDestroyUtil.destroy(opponentVocals);
  }
}

typedef WeekGroup =
{
  var fileName:String;
  var frameName:String;
  var songs:Array<SongMetadata>;
}

class SongMetadata
{
  public var songName:String = "";
  public var week:Int = 0;
  public var songCharacter:String = "";
  public var color:Int = -7179779;
  public var folder:String = "";

  public function new(song:String, week:Int, songCharacter:String, color:Int)
  {
    this.songName = song;
    this.week = week;
    this.songCharacter = songCharacter;
    this.color = color;
    this.folder = Mods.currentModDirectory;
    if (this.folder == null) this.folder = '';
  }
}
