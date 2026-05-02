import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:metadata_god/metadata_god.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    try {
      await MetadataGod.initialize();
    } catch (e, st) {
      debugPrint('MetadataGod.initialize: $e\n$st');
    }
  }
  runApp(const Mp3PlayerApp());
}
