import 'dart:async';

import 'package:flutter/material.dart';

import 'audio/player_controller.dart';
import 'features/shell/main_shell.dart';
import 'services/accent_settings_store.dart';
import 'services/theme_settings_store.dart';
import 'theme/accent_color_option.dart';
import 'theme/app_theme.dart';
import 'widgets/action_pill_toast.dart';

class Mp3PlayerApp extends StatefulWidget {
  const Mp3PlayerApp({super.key});

  @override
  State<Mp3PlayerApp> createState() => _Mp3PlayerAppState();
}

class _Mp3PlayerAppState extends State<Mp3PlayerApp> {
  late final PlayerController _player = PlayerController();
  AppThemeSetting _themeSetting = AppThemeSetting.automatic;
  AppAccentColorOption _accentOption = AppAccentColorOption.blue;
  Color _customAccentColor = AppAccentColorOption.blue.swatchColor;
  DateTime _themeClock = DateTime.now();
  Timer? _themeTimer;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final s = await ThemeSettingsStore.load();
    final accent = await AccentSettingsStore.load();
    if (!mounted) return;
    setState(() {
      _themeSetting = s;
      _accentOption = accent.option;
      _customAccentColor = accent.customAccent;
      _themeClock = DateTime.now();
    });
    _rescheduleThemeTimer();
  }

  void _rescheduleThemeTimer() {
    _themeTimer?.cancel();
    if (_themeSetting != AppThemeSetting.automatic) return;
    _themeTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() => _themeClock = DateTime.now());
    });
  }

  Future<void> _setThemeSetting(AppThemeSetting setting) async {
    setState(() {
      _themeSetting = setting;
      _themeClock = DateTime.now();
    });
    await ThemeSettingsStore.save(setting);
    _rescheduleThemeTimer();
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

  Color get _resolvedAccent => _accentOption == AppAccentColorOption.custom
      ? _customAccentColor
      : _accentOption.swatchColor;

  @override
  void dispose() {
    _themeTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _themeSetting.paletteAt(_themeClock);
    return PlayerControllerScope(
      controller: _player,
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        title: 'MP3 Player',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.themeFor(
          resolved,
          controlAccent: _resolvedAccent,
        ),
        home: MainShell(
          themeSetting: _themeSetting,
          onThemeSettingChanged: _setThemeSetting,
          accentColorOption: _accentOption,
          customAccentColor: _customAccentColor,
          onAccentColorOptionChanged: _setAccentOption,
          onCustomAccentColorChanged: _setCustomAccentColor,
        ),
      ),
    );
  }
}
