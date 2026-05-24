/// Shared album-art resolution limits (display, disk cache, hot LRU).
const int kAlbumArtMinDimension = 96;

/// Written by [primeAlbumArtDiskCache] and preferred for Now Playing / hero art.
const int kAlbumArtPrimeDimension = 1024;

/// Upper bound for decode / resize / [Image.memory] cache size.
const int kAlbumArtMaxDimension = 1024;

/// List rows and mini player — keep thumbnails smaller for RAM and scroll cost.
const int kAlbumArtListMaxDimension = 384;

/// Hot LRU is only used (and populated) when the UI asks at or below this size so
/// a list thumbnail is not upscaled on Now Playing.
const int kAlbumArtHotLruMaxTargetDimension = 384;

/// Disk cache files tried largest-first ([cachedAlbumArtForPathAnyDimension]).
const List<int> kPathAlbumArtDiskDimensions = [
  1024,
  512,
  256,
  192,
  128,
];

int clampAlbumArtDimension(int requested) =>
    requested.clamp(kAlbumArtMinDimension, kAlbumArtMaxDimension);

bool albumArtTargetUsesHotLru(int targetDimension) =>
    targetDimension <= kAlbumArtHotLruMaxTargetDimension;
