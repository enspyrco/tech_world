import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/tiles/tileset_cache_service.dart';

void main() {
  late Directory tempDir;
  late Uint8List fakeImageBytes;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('tileset_cache_test_');
    fakeImageBytes = Uint8List.fromList([137, 80, 78, 71, 0, 1, 2, 3]);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('TilesetCacheService', () {
    test('returns bytes from downloader on cache miss', () async {
      var downloadCalled = false;
      final cache = TilesetCacheService(
        cacheDir: tempDir,
        download: (id) async {
          downloadCalled = true;
          return fakeImageBytes;
        },
      );

      final result = await cache.getTilesetImage('limezu_walls');

      expect(downloadCalled, isTrue);
      expect(result, equals(fakeImageBytes));
    });

    test('writes downloaded bytes to disk cache', () async {
      final cache = TilesetCacheService(
        cacheDir: tempDir,
        download: (_) async => fakeImageBytes,
      );

      await cache.getTilesetImage('limezu_walls');

      final cachedFile = File('${tempDir.path}/limezu_walls.png');
      expect(cachedFile.existsSync(), isTrue);
      expect(cachedFile.readAsBytesSync(), equals(fakeImageBytes));
    });

    test('returns cached bytes on second call without re-downloading', () async {
      var downloadCount = 0;
      final cache = TilesetCacheService(
        cacheDir: tempDir,
        download: (_) async {
          downloadCount++;
          return fakeImageBytes;
        },
      );

      await cache.getTilesetImage('limezu_walls');
      final result = await cache.getTilesetImage('limezu_walls');

      expect(downloadCount, equals(1));
      expect(result, equals(fakeImageBytes));
    });

    test('reads from disk cache on fresh instance', () async {
      // Pre-populate disk cache.
      final cacheFile = File('${tempDir.path}/test_tileset.png');
      cacheFile.writeAsBytesSync(fakeImageBytes);

      var downloadCalled = false;
      final cache = TilesetCacheService(
        cacheDir: tempDir,
        download: (_) async {
          downloadCalled = true;
          return Uint8List(0);
        },
      );

      final result = await cache.getTilesetImage('test_tileset');

      expect(downloadCalled, isFalse);
      expect(result, equals(fakeImageBytes));
    });

    test('returns null when download returns null', () async {
      final cache = TilesetCacheService(
        cacheDir: tempDir,
        download: (_) async => null,
      );

      final result = await cache.getTilesetImage('nonexistent');

      expect(result, isNull);
      // No file should be cached.
      final cachedFile = File('${tempDir.path}/nonexistent.png');
      expect(cachedFile.existsSync(), isFalse);
    });

    test('caches different tilesets independently', () async {
      final bytes1 = Uint8List.fromList([1, 2, 3]);
      final bytes2 = Uint8List.fromList([4, 5, 6]);

      final cache = TilesetCacheService(
        cacheDir: tempDir,
        download: (id) async => id == 'a' ? bytes1 : bytes2,
      );

      final result1 = await cache.getTilesetImage('a');
      final result2 = await cache.getTilesetImage('b');

      expect(result1, equals(bytes1));
      expect(result2, equals(bytes2));
    });
  });
}
