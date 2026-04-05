// Platform-aware tileset caching.
//
// On native platforms (`dart.library.io`), wraps downloads with a disk cache
// via TilesetCacheService. On web, returns the download function unchanged
// (relies on browser HTTP cache).
export 'tileset_cache_provider_stub.dart'
    if (dart.library.io) 'tileset_cache_provider_native.dart';
