import 'package:flutter_test/flutter_test.dart';
import 'package:mp3_player/audio/art_availability_notifier.dart';

void main() {
  test('markAvailable notifies once per path', () {
    final n = ArtAvailabilityNotifier();
    var count = 0;
    n.addListener(() => count++);

    n.markAvailable('path-a');
    expect(count, 1);
    expect(n.hasArt('path-a'), isTrue);

    n.markAvailable('path-a');
    expect(count, 1);
  });

  test('markAvailableAll batches with beginBatch/endBatch', () {
    final n = ArtAvailabilityNotifier();
    var count = 0;
    n.addListener(() => count++);

    n.beginBatch();
    n.markAvailable('a');
    n.markAvailable('b');
    expect(count, 0);
    n.endBatch();
    expect(count, 1);
    expect(n.hasArt('a'), isTrue);
    expect(n.hasArt('b'), isTrue);
  });
}
