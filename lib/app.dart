import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart' show PlayerState;

import 'audio/notification_art_uri.dart';
import 'audio/player_controller.dart';
import 'features/shell/main_shell.dart';
import 'platform/android_home_widget_bridge.dart';
import 'services/accent_settings_store.dart';
import 'services/font_settings_store.dart';
import 'services/player_chrome_background_store.dart';
import 'services/theme_settings_store.dart';
import 'theme/accent_color_option.dart';
import 'theme/app_font_option.dart';
import 'theme/app_theme.dart';
import 'theme/player_chrome_background.dart';
import 'widgets/action_pill_toast.dart';

class Mp3PlayerApp extends StatefulWidget {
  const Mp3PlayerApp({super.key});

  @override
  State<Mp3PlayerApp> createState() => _Mp3PlayerAppState();
}

class _Mp3PlayerAppState extends State<Mp3PlayerApp> {
  late final PlayerController _player = PlayerController();
  AppThemeSetting _themeSetting = AppThemeSetting.automatic;
  AppFontOption _fontOption = AppFontOption.system;
  AppAccentColorOption _accentOption = AppAccentColorOption.themeDefault;
  Color _customAccentColor = AppAccentColorOption.blue.swatchColor;
  PlayerChromeBackgroundKind _playerChromeBackgroundKind =
      PlayerChromeBackgroundKind.themeDefault;
  Color? _playerChromeCustomBackground;
  DateTime _themeClock = DateTime.now();
  Timer? _themeTimer;

  Timer? _androidWidgetSyncDebounce;
  Timer? _androidWidgetProgressTimer;
  StreamSubscription<PlayerState>? _androidWidgetPlayerStateSub;

  bool get _syncAndroidHomeWidget =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void _onPlayerControllerChanged() => _scheduleAndroidHomeWidgetSync();

  @override
  void initState() {
    super.initState();
    _player.addListener(_onPlayerControllerChanged);
    _attachAndroidWidgetProgressTicker();
    _loadTheme();
  }

  void _attachAndroidWidgetProgressTicker() {
    if (!_syncAndroidHomeWidget) return;
    _androidWidgetPlayerStateSub = _player.audioPlayer.playerStateStream.listen(
      (state) {
        _androidWidgetProgressTimer?.cancel();
        if (!mounted || !state.playing) return;
        _androidWidgetProgressTimer = Timer.periodic(
          const Duration(seconds: 1),
          (_) async {
            if (!mounted || !_player.isPlaying) {
              _androidWidgetProgressTimer?.cancel();
              return;
            }
            await AndroidHomeWidgetBridge.syncPlaybackProgress(
              playing: _player.isPlaying,
              positionMs: _player.position.inMilliseconds,
              durationMs: _player.duration?.inMilliseconds ?? 0,
            );
          },
        );
      },
    );
  }

  void _scheduleAndroidHomeWidgetSync() {
    if (!_syncAndroidHomeWidget) return;
    _androidWidgetSyncDebounce?.cancel();
    _androidWidgetSyncDebounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_pushAndroidHomeWidgetState());
    });
  }

  Future<void> _pushAndroidHomeWidgetState() async {
    if (!_syncAndroidHomeWidget || !mounted) return;
    final track = _player.currentTrack;
    final palette = _themeSetting.paletteAt(_themeClock);
    final palForWidget = _materialPaletteFor(palette);
    final isDark = palForWidget.scaffoldBackground.computeLuminance() < 0.5;

    var artPath = '';
    if (track != null) {
      final uri = await uriForNotificationAlbumArt(track);
      if (uri != null && uri.isScheme('file')) {
        artPath = uri.toFilePath();
      }
    }

    await AndroidHomeWidgetBridge.sync(
      hasTrack: track != null,
      title: track?.title ?? '',
      artist: track?.artist ?? '',
      artFilePath: artPath.isEmpty ? null : artPath,
      playing: _player.isPlaying,
      positionMs: _player.position.inMilliseconds,
      durationMs: _player.duration?.inMilliseconds ?? 0,
      canSkipNext: _player.canSkipNext,
      isDarkTheme: isDark,
    );
  }

  Future<void> _loadTheme() async {
    var s = await ThemeSettingsStore.load();
    final font = await FontSettingsStore.load();
    final accent = await AccentSettingsStore.load();
    var chromeBgKind = await PlayerChromeBackgroundStore.loadKind();
    final chromeBgColor = await PlayerChromeBackgroundStore.loadCustomColor();
    var migratedPrefs = false;
    if (s == AppThemeSetting.light || s == AppThemeSetting.dark) {
      s = AppThemeSetting.automatic;
      migratedPrefs = true;
    }
    if (s == AppThemeSetting.grey) {
      s = AppThemeSetting.player;
      chromeBgKind = PlayerChromeBackgroundKind.grey;
      migratedPrefs = true;
    }
    if (migratedPrefs) {
      await ThemeSettingsStore.save(s);
      await PlayerChromeBackgroundStore.saveKind(chromeBgKind);
    }
    if (!mounted) return;
    setState(() {
      _themeSetting = s;
      _fontOption = font;
      _accentOption = accent.option;
      _customAccentColor = accent.customAccent;
      _playerChromeBackgroundKind = chromeBgKind;
      _playerChromeCustomBackground = chromeBgColor;
      _themeClock = DateTime.now();
    });
    _rescheduleThemeTimer();
    _scheduleAndroidHomeWidgetSync();
  }

  void _rescheduleThemeTimer() {
    _themeTimer?.cancel();
    if (_themeSetting != AppThemeSetting.automatic) return;
    _themeTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() => _themeClock = DateTime.now());
      _scheduleAndroidHomeWidgetSync();
    });
  }

  Future<void> _setThemeSetting(AppThemeSetting setting) async {
    setState(() {
      _themeSetting = setting;
      _themeClock = DateTime.now();
    });
    await ThemeSettingsStore.save(setting);
    _rescheduleThemeTimer();
    _scheduleAndroidHomeWidgetSync();
  }

  Future<void> _setFontOption(AppFontOption option) async {
    setState(() => _fontOption = option);
    await FontSettingsStore.save(option);
  }

  Future<void> _setAccentOption(AppAccentColorOption option) async {
    setState(() => _accentOption = option);
    await AccentSettingsStore.save(
      option,
      option == AppAccentColorOption.custom ? _customAccentColor : null,
    );
  }

  Future<void> _setCustomAccentColor(Color color) async {
    setState(() {
      _customAccentColor = color;
      _accentOption = AppAccentColorOption.custom;
    });
    await AccentSettingsStore.save(AppAccentColorOption.custom, color);
  }

  AppPalette _materialPaletteFor(AppThemePalette resolved) {
    var base = AppPalette.forPalette(resolved);
    if (resolved == AppThemePalette.player ||
        resolved == AppThemePalette.playerSoft ||
        resolved == AppThemePalette.silver ||
        resolved == AppThemePalette.daisy) {
      base = AppPalette.applyPlayerChromeBackground(
        paletteKey: resolved,
        base: base,
        kind: _playerChromeBackgroundKind,
        customScaffold: _playerChromeCustomBackground,
      );
    }
    return base;
  }

  Future<void> _setPlayerChromeBackgroundKind(
    PlayerChromeBackgroundKind kind,
  ) async {
    setState(() => _playerChromeBackgroundKind = kind);
    await PlayerChromeBackgroundStore.saveKind(kind);
    _scheduleAndroidHomeWidgetSync();
  }

  Future<void> _setPlayerChromeCustomBackground(Color color) async {
    setState(() {
      _playerChromeCustomBackground = color;
      _playerChromeBackgroundKind = PlayerChromeBackgroundKind.custom;
    });
    await PlayerChromeBackgroundStore.saveKind(
      PlayerChromeBackgroundKind.custom,
    );
    await PlayerChromeBackgroundStore.saveCustomColor(color);
    _scheduleAndroidHomeWidgetSync();
  }

  Color get _resolvedAccent => _accentOption.resolveColorForPalette(
    _themeSetting.paletteAt(_themeClock),
    customColor: _customAccentColor,
  );

  @override
  void dispose() {
    _androidWidgetSyncDebounce?.cancel();
    _androidWidgetProgressTimer?.cancel();
    _androidWidgetPlayerStateSub?.cancel();
    _player.removeListener(_onPlayerControllerChanged);
    _themeTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _themeSetting.paletteAt(_themeClock);
    final paletteOverride =
        (resolved == AppThemePalette.player ||
            resolved == AppThemePalette.playerSoft ||
            resolved == AppThemePalette.silver ||
            resolved == AppThemePalette.daisy)
        ? _materialPaletteFor(resolved)
        : null;
    var theme = AppTheme.themeFor(
      resolved,
      controlAccent: _resolvedAccent,
      fontFamily: _fontOption.fontFamily,
      paletteOverride: paletteOverride,
    );
    if (_fontOption == AppFontOption.fraunces) {
      theme = theme.copyWith(
        textTheme: GoogleFonts.frauncesTextTheme(theme.textTheme),
      );
    } else if (_fontOption == AppFontOption.eduNswActHandCursive) {
      theme = theme.copyWith(
        textTheme: GoogleFonts.eduNswActCursiveTextTheme(theme.textTheme),
      );
    }
    return PlayerControllerScope(
      controller: _player,
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        title: 'MadPlay',
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: MainShell(
          themeSetting: _themeSetting,
          onThemeSettingChanged: _setThemeSetting,
          fontOption: _fontOption,
          onFontOptionChanged: _setFontOption,
          accentColorOption: _accentOption,
          customAccentColor: _customAccentColor,
          onAccentColorOptionChanged: _setAccentOption,
          onCustomAccentColorChanged: _setCustomAccentColor,
          playerChromeBackgroundKind: _playerChromeBackgroundKind,
          playerChromeCustomBackground: _playerChromeCustomBackground,
          onPlayerChromeBackgroundKindChanged: _setPlayerChromeBackgroundKind,
          onPlayerChromeCustomBackgroundChanged: _setPlayerChromeCustomBackground,
        ),
      ),
    );
  }
}
