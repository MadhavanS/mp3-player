String formatYoutubeDurationMs(int? durationMs) {
  if (durationMs == null || durationMs <= 0) return '';
  final totalSeconds = durationMs ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours}:${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes}:${seconds.toString().padLeft(2, '0')}';
}
