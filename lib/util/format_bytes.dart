/// Human-readable byte sizes for storage and network display.
String formatFileSize(int bytes) {
  if (bytes < 0) bytes = 0;
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Network throughput (bytes per second).
String formatTransferRate(double bytesPerSecond) {
  if (bytesPerSecond.isNaN || bytesPerSecond <= 0) return '—';
  if (bytesPerSecond < 1024) {
    return '${bytesPerSecond.round()} B/s';
  }
  if (bytesPerSecond < 1024 * 1024) {
    return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
  }
  return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(2)} MB/s';
}
