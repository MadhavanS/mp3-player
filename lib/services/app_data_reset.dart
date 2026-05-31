import 'app_data_reset_stub.dart'
    if (dart.library.io) 'app_data_reset_io.dart'
    as impl;

/// Erases local app data so the next launch matches a fresh install.
Future<void> wipeAllLocalAppData() => impl.wipeAllLocalAppData();
