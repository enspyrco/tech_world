import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/tiles/tileset_registry.dart';

/// Minimal fake for testing — we only need the animation lookup, not sprite
/// loading.
TilesetRegistry _createRegistry() {
  // TilesetRegistry requires an Images instance for sprite loading, but
  // getAnimationForTile only uses the tile_animations lookup — no images
  // needed. We test the lookup function directly on TilesetRegistry.
  //
  // Since the method delegates to lookupAnimationForTile(), we test it
  // through the registry to verify integration.
  return TilesetRegistry.forTesting();
}

void main() {
  group('TilesetRegistry.getAnimationForTile', () {
    late TilesetRegistry registry;

    setUp(() {
      registry = _createRegistry();
    });

    test('returns animation for base tile index', () {
      // Waterfall top-left cliff: row 48, col 24 = index 1560
      final anim = registry.getAnimationForTile('ext_terrains', 48 * 32 + 24);
      expect(anim, isNotNull);
      expect(anim!.baseTileIndex, 48 * 32 + 24);
    });

    test('returns animation for non-base frame index', () {
      // Frame 2 of waterfall top-left cliff: row 48, col 27 = index 1563
      final anim = registry.getAnimationForTile('ext_terrains', 48 * 32 + 27);
      expect(anim, isNotNull);
      // Should map back to the base index (frame 1).
      expect(anim!.baseTileIndex, 48 * 32 + 24);
    });

    test('returns null for non-animated tile', () {
      final anim = registry.getAnimationForTile('ext_terrains', 0);
      expect(anim, isNull);
    });

    test('returns null for unknown tileset', () {
      final anim = registry.getAnimationForTile('nonexistent', 1560);
      expect(anim, isNull);
    });

    test('finds waterfall body animation', () {
      // Waterfall body water right: row 50, col 26 = index 1626
      final anim = registry.getAnimationForTile('ext_terrains', 50 * 32 + 26);
      expect(anim, isNotNull);
      expect(anim!.frameCount, 2);
      expect(anim.frameIndices, [50 * 32 + 26, 50 * 32 + 29]);
    });
  });
}
