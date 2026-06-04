import 'package:flutter/widgets.dart';

import 'app.dart';
import 'platform/windows_window.dart';
import 'services/app_startup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await prepareWindowsWindowManager();
  await ensureJustAudioBackgroundInitialized();
  runApp(const MadPlayerApp());
}
