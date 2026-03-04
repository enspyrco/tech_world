import 'package:flame/cache.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/tiles/tileset.dart';
import 'package:tech_world/flame/tiles/tileset_registry.dart';

const _testTileset = Tileset(
  id: 'dynamic_test',
  name: 'Dynamic Test Tileset',
  imagePath: 'custom/dynamic_test.png',
  tileSize: 32,
  columns: 1,
  rows: 1,
  isCustom: true,
);

void main() {
  group('TilesetRegistry.loadFromImage', () {
    late TilesetRegistry registry;

    setUp(() {
      registry = TilesetRegistry(images: Images());
    });

    testWidgets('registers a tileset from a pre-decoded image',
        (tester) async {
      final image = await generateImage(32, 32);

      registry.loadFromImage(_testTileset, image);

      expect(registry.isLoaded('dynamic_test'), isTrue);
      expect(registry.get('dynamic_test'), isNotNull);
      expect(registry.get('dynamic_test')!.tileset.id, 'dynamic_test');
      expect(registry.get('dynamic_test')!.tileset.isCustom, isTrue);
    });

    testWidgets('creates a valid SpriteSheet for the tileset',
        (tester) async {
      final image = await generateImage(32, 32);

      registry.loadFromImage(_testTileset, image);

      // Should be able to get a sprite for tile index 0.
      final sprite = registry.getSpriteForTile('dynamic_test', 0);
      expect(sprite, isNotNull);
    });

    testWidgets('does nothing if tileset is already loaded', (tester) async {
      final image1 = await generateImage(32, 32);
      final image2 = await generateImage(64, 64);

      registry.loadFromImage(_testTileset, image1);
      registry.loadFromImage(_testTileset, image2);

      // Should still have the first image (32x32).
      expect(registry.isLoaded('dynamic_test'), isTrue);
      final cached = registry.images.fromCache('custom/dynamic_test.png');
      expect(cached.width, 32);
    });

    testWidgets('injects image into Flame cache', (tester) async {
      final image = await generateImage(32, 32);

      registry.loadFromImage(_testTileset, image);

      // The image should be findable in the cache.
      final cached = registry.images.fromCache('custom/dynamic_test.png');
      expect(cached, isNotNull);
      expect(cached.width, 32);
    });
  });

  group('TilesetRegistry.unload', () {
    late TilesetRegistry registry;

    setUp(() {
      registry = TilesetRegistry(images: Images());
    });

    testWidgets('removes a loaded tileset', (tester) async {
      final image = await generateImage(32, 32);
      registry.loadFromImage(_testTileset, image);

      final removed = registry.unload('dynamic_test');

      expect(removed, isTrue);
      expect(registry.isLoaded('dynamic_test'), isFalse);
      expect(registry.get('dynamic_test'), isNull);
    });

    testWidgets('clears image from Flame cache', (tester) async {
      final image = await generateImage(32, 32);
      registry.loadFromImage(_testTileset, image);

      registry.unload('dynamic_test');

      // Accessing cleared image should throw.
      expect(
        () => registry.images.fromCache('custom/dynamic_test.png'),
        throwsA(anything),
      );
    });

    test('returns false for unknown tileset ID', () {
      final removed = registry.unload('nonexistent');
      expect(removed, isFalse);
    });
  });

  group('Tileset JSON serialization', () {
    test('toJson serializes structural metadata', () {
      const tileset = Tileset(
        id: 'desert',
        name: 'Desert Tileset',
        imagePath: 'https://storage.example.com/tilesets/desert.png',
        tileSize: 32,
        columns: 8,
        rows: 10,
        isCustom: true,
      );

      final json = tileset.toJson();

      expect(json['id'], 'desert');
      expect(json['name'], 'Desert Tileset');
      expect(json['imagePath'],
          'https://storage.example.com/tilesets/desert.png');
      expect(json['tileSize'], 32);
      expect(json['columns'], 8);
      expect(json['rows'], 10);
    });

    test('fromJson reconstructs a custom tileset', () {
      final json = {
        'id': 'desert',
        'name': 'Desert Tileset',
        'imagePath': 'https://storage.example.com/tilesets/desert.png',
        'tileSize': 32,
        'columns': 8,
        'rows': 10,
      };

      final tileset = Tileset.fromJson(json);

      expect(tileset.id, 'desert');
      expect(tileset.name, 'Desert Tileset');
      expect(tileset.imagePath,
          'https://storage.example.com/tilesets/desert.png');
      expect(tileset.tileSize, 32);
      expect(tileset.columns, 8);
      expect(tileset.rows, 10);
      expect(tileset.isCustom, isTrue);
      expect(tileset.barrierTileIndices, isEmpty);
      expect(tileset.tileCount, 80);
    });

    test('round-trip: toJson → fromJson preserves data', () {
      const original = Tileset(
        id: 'custom_abc123',
        name: 'My Tileset',
        imagePath: 'https://example.com/tileset.png',
        tileSize: 16,
        columns: 20,
        rows: 15,
        isCustom: true,
      );

      final roundTripped = Tileset.fromJson(original.toJson());

      expect(roundTripped.id, original.id);
      expect(roundTripped.name, original.name);
      expect(roundTripped.imagePath, original.imagePath);
      expect(roundTripped.tileSize, original.tileSize);
      expect(roundTripped.columns, original.columns);
      expect(roundTripped.rows, original.rows);
      expect(roundTripped.isCustom, isTrue);
    });
  });
}
