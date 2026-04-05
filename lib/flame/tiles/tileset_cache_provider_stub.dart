import 'dart:typed_data';

/// Web stub — no disk caching, just returns the download function unchanged.
Future<Future<Uint8List?> Function(String)> createCachedDownloader(
  Future<Uint8List?> Function(String) download,
) async =>
    download;
