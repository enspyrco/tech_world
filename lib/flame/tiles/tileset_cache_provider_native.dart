import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:tech_world/flame/tiles/tileset_cache_service.dart';

/// Native implementation — wraps downloads with a local disk cache.
///
/// Returns a function with the same signature as [download] but backed by
/// [TilesetCacheService] (memory → disk → remote). Falls back to plain
/// [download] if the cache directory cannot be resolved.
Future<Future<Uint8List?> Function(String)> createCachedDownloader(
  Future<Uint8List?> Function(String) download,
) async {
  try {
    final appDir = await getApplicationSupportDirectory();
    final cache = TilesetCacheService(
      cacheDir: Directory('${appDir.path}/tileset_cache'),
      download: download,
    );
    return cache.getTilesetImage;
  } catch (_) {
    return download;
  }
}
