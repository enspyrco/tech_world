import 'dart:io';
import 'dart:typed_data';

/// Caches tileset images on the local file system, falling back to a
/// remote download function on cache miss.
///
/// Each tileset is stored as `{cacheDir}/{tilesetId}.png`. Content-hash-based
/// IDs guarantee that the same content always maps to the same filename,
/// so no cache invalidation is needed.
///
/// Typical usage:
///
/// ```dart
/// final cacheDir = await getApplicationSupportDirectory();
/// final cache = TilesetCacheService(
///   cacheDir: Directory('${cacheDir.path}/tileset_cache'),
///   download: (id) => TilesetStorageService().downloadTilesetImage(id),
/// );
/// final bytes = await cache.getTilesetImage('limezu_walls');
/// ```
class TilesetCacheService {
  TilesetCacheService({
    required this.cacheDir,
    required Future<Uint8List?> Function(String tilesetId) download,
  }) : _download = download;

  /// Local directory where cached tileset PNGs are stored.
  final Directory cacheDir;

  final Future<Uint8List?> Function(String tilesetId) _download;

  /// In-memory cache to avoid repeated disk reads within the same session.
  final Map<String, Uint8List> _memoryCache = {};

  /// Get tileset image bytes, checking memory → disk → remote in order.
  ///
  /// Returns `null` if the tileset doesn't exist remotely.
  Future<Uint8List?> getTilesetImage(String tilesetId) async {
    // 1. Memory cache.
    final cached = _memoryCache[tilesetId];
    if (cached != null) return cached;

    // 2. Disk cache.
    final file = File('${cacheDir.path}/$tilesetId.png');
    if (file.existsSync()) {
      final bytes = await file.readAsBytes();
      _memoryCache[tilesetId] = bytes;
      return bytes;
    }

    // 3. Remote download.
    final bytes = await _download(tilesetId);
    if (bytes == null) return null;

    // Write to disk (create directory if needed).
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }
    await file.writeAsBytes(bytes);

    _memoryCache[tilesetId] = bytes;
    return bytes;
  }
}
