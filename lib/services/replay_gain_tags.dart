import '../audio/replay_gain.dart';
import 'replay_gain_tags_stub.dart'
    if (dart.library.io) 'replay_gain_tags_io.dart' as impl;

Future<ReplayGainAdjustment> readReplayGainTags(String? filePath) =>
    impl.readReplayGainTags(filePath);
