import 'package:shared_preferences/shared_preferences.dart';

/// Web: clears Flutter preferences only (no local file caches).
Future<void> wipeAllLocalAppData() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
}
