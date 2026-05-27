/// Shared album-art resolution limits (display, disk cache, hot LRU).
const int kAlbumArtMinDimension = 96;

/// Written by [primeAlbumArtDiskCache] and preferred for Now Playing / hero art.
const int kAlbumArtPrimeDimension = 1024;

/// Upper bound for decode / resize / [Image.memory] cache size.
const int kAlbumArtMaxDimension = 1024;

/// List rows and mini player — keep thumbnails smaller for RAM and scroll cost.
const int kAlbumArtListMaxDimension = 384;

/// Hot LRU only for list/mini decode sizes. Now Playing often requests ~250–500px;
/// reusing a ~168px list thumb caused visible pixelation when upscaled.
const int kAlbumArtHotLruMaxTargetDimension = 192;

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
