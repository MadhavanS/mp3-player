import 'package:path/path.dart' as p;

/// Synthetic/junk dirs that must not appear as browsable folders or library tracks.
bool _segmentIsExcludedDotThumbnails(String pathSegment) =>
    pathSegment.toLowerCase() == '.thumbnails';

/// True when [segment] alone is `.thumbnails` (case-insensitive).
bool basenameIsExcludedLibraryFolder(String basename) =>
    _segmentIsExcludedDotThumbnails(basename);

bool pathPassesLibraryVisibility(String absolutePath) {
  for (final seg in p.split(p.normalize(absolutePath))) {
    if (seg.isEmpty || seg == '.') continue;
    if (_segmentIsExcludedDotThumbnails(seg)) return false;
  }
  return true;
}
