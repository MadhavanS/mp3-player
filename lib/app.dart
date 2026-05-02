import 'dart:async';

import 'package:flutter/material.dart';

import 'audio/player_controller.dart';
import 'features/shell/main_shell.dart';
import 'services/theme_settings_store.dart';
import 'theme/app_theme.dart';

class Mp3PlayerApp extends StatefulWidget {
  const Mp3PlayerApp({super.key});

  @override
  State<Mp3PlayerApp> createState() => _Mp3PlayerAppState();
}

class _Mp3PlayerAppState extends State<Mp3PlayerApp> {
  late final PlayerController _player = PlayerController();
  AppThemeSetting _themeSetting = AppThemeSetting.automatic;
  DateTime _themeClock = DateTime.now();
  Timer? _themeTimer;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final s = await ThemeSettingsStore.load();
    if (!mounted) return;
    setState(() {
      _themeSetting = s;
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
        title: 'MP3 Player',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.themeFor(resolved),
        home: MainShell(
          themeSetting: _themeSetting,
          onThemeSettingChanged: _setThemeSetting,
        ),
      ),
    );
  }
}
