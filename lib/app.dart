import 'package:flutter/material.dart';

import 'audio/player_controller.dart';
import 'features/library/library_screen.dart';
import 'theme/app_theme.dart';

class Mp3PlayerApp extends StatefulWidget {
  const Mp3PlayerApp({super.key});

  @override
  State<Mp3PlayerApp> createState() => _Mp3PlayerAppState();
}

class _Mp3PlayerAppState extends State<Mp3PlayerApp> {
  late final PlayerController _player = PlayerController();

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlayerControllerScope(
      controller: _player,
      child: MaterialApp(
        title: 'MP3 Player',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.material,
        home: const LibraryScreen(),
      ),
    );
  }
}
