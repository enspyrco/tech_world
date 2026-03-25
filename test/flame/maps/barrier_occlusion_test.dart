import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/barrier_occlusion.dart';
import 'package:tech_world/flame/tiles/tile_layer_data.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';

void main() {
  group('computePriorityOverrides', () {
    test('empty barriers returns empty overrides', () {
      final overrides = computePriorityOverrides(<(int, int)>{});
      expect(overrides, isEmpty);
    });

    test('vertical wall with doorway gap detects lintel', () {
      final barriers = {
        (4, 14), (4, 15), (4, 16),
        // gap at y=17
        (4, 18),
      };

      final overrides = computePriorityOverrides(barriers);

      expect(overrides[(4, 16)], equals(18));
      expect(overrides[(4, 15)], equals(18)); // extended occlusion
    });

    test('horizontal wall does not produce false lintels', () {
      final barriers = {
        for (var x = 5; x <= 10; x++) (x, 7),
      };

      final overrides = computePriorityOverrides(barriers);

      for (final entry in overrides.entries) {
        expect(entry.value, isNot(equals(9)),
            reason: 'horizontal wall should not produce lintel overrides');
      }
    });

    test('wall cap tiles get priority of barrier below', () {
      final barriers = {(5, 7), (5, 8)};
      final overrides = computePriorityOverrides(barriers);
      expect(overrides[(5, 6)], equals(7));
    });

    test('all north-facing barriers get wall caps', () {
      // Horizontal wall: all barriers are north-facing → all get wall caps.
      final barriers = {(5, 7), (6, 7), (7, 7)};
      final overrides = computePriorityOverrides(barriers);
      expect(overrides[(5, 6)], equals(7));
      expect(overrides[(6, 6)], equals(7));
      expect(overrides[(7, 6)], equals(7));
    });

    test('L-junction: all north-facing barriers get wall caps', () {
      final barriers = {(4, 7), (4, 8), (5, 7), (6, 7)};
      final overrides = computePriorityOverrides(barriers);
      // All north-facing barriers get wall caps at y-1.
      expect(overrides[(4, 6)], equals(7));
      expect(overrides[(5, 6)], equals(7));
      expect(overrides[(6, 6)], equals(7));
    });

    test('L-Room barriers produce correct lintel at (4,16)', () {
      final barriers = <(int, int)>{
        (4, 7), (4, 8), (4, 9), (4, 10), (4, 11),
        (4, 12), (4, 13), (4, 14), (4, 15), (4, 16),
        (4, 18), (4, 19), (4, 20), (4, 21), (4, 22),
        (4, 23), (4, 24), (4, 25), (4, 26), (4, 27),
        (4, 28), (4, 29),
        (5, 7), (6, 7), (7, 7), (8, 7), (9, 7),
        (10, 7), (11, 7), (12, 7), (13, 7), (14, 7),
        (15, 7), (16, 7), (17, 7),
      };

      final overrides = computePriorityOverrides(barriers);

      expect(overrides[(4, 16)], equals(18));
      expect(overrides[(4, 15)], equals(18));
      expect(
        overrides.entries.where((e) => e.value == 20).isEmpty,
        isTrue,
        reason: '(4,18) should not be a lintel — (4,19) is a barrier',
      );
    });

    test('horizontal doorway: gap tiles above bumped, flanking above NOT', () {
      // Horizontal wall at y=23, gap at x=7.
      final barriers = {
        (5, 23), (6, 23),
        // gap at x=7
        (8, 23), (9, 23), (10, 23),
      };

      final overrides = computePriorityOverrides(barriers);

      // Gap tile at y should NOT be bumped — it's floor.
      expect(overrides.containsKey((7, 23)), isFalse);
      // Flanking barriers keep natural priority — no bump.
      expect(overrides.containsKey((6, 23)), isFalse);
      expect(overrides.containsKey((8, 23)), isFalse);
      // Gap tile ABOVE bumped (lintel overhang).
      expect(overrides[(7, 22)], equals(24));
      // Flanking tiles ABOVE get wall cap priority (y=23), NOT lintel
      // priority (y+1=24). Wall caps occlude correctly without the
      // elevated priority that was causing full-coverage occlusion.
      expect(overrides[(6, 22)], equals(23));
      expect(overrides[(8, 22)], equals(23));
    });

    test('horizontal doorway 2-wide: flanking above get wall cap priority',
        () {
      final barriers = {
        (5, 23), (6, 23),
        // gap at x=7, x=8
        (9, 23), (10, 23),
      };

      final overrides = computePriorityOverrides(barriers);

      expect(overrides.containsKey((7, 23)), isFalse);
      expect(overrides.containsKey((8, 23)), isFalse);
      // Flanking barriers keep natural priority — no bump.
      expect(overrides.containsKey((6, 23)), isFalse);
      expect(overrides.containsKey((9, 23)), isFalse);
      // Gap tiles above bumped to lintel priority.
      expect(overrides[(7, 22)], equals(24));
      expect(overrides[(8, 22)], equals(24));
      // Flanking tiles above get wall cap priority (y=23), not lintel (24).
      expect(overrides[(6, 22)], equals(23));
      expect(overrides[(9, 22)], equals(23));
    });

    test('multiple doorways in same wall', () {
      final barriers = {
        (4, 5), (4, 6),
        // gap at y=7
        (4, 8), (4, 9),
        // gap at y=10
        (4, 11), (4, 12),
      };

      final overrides = computePriorityOverrides(barriers);

      expect(overrides[(4, 6)], equals(8));
      expect(overrides[(4, 5)], equals(8));
      expect(overrides[(4, 9)], equals(11));
      expect(overrides[(4, 8)], equals(11));
    });
  });

  group('buildObjectLayerFromBarriers', () {
    test('copies floor tiles at barrier positions', () {
      final floor = TileLayerData();
      floor.setTile(4, 7, const TileRef(tilesetId: 'test', tileIndex: 42));
      floor.setTile(4, 8, const TileRef(tilesetId: 'test', tileIndex: 43));

      final barriers = {(4, 7), (4, 8)};
      final objectLayer = buildObjectLayerFromBarriers(
        floorLayer: floor,
        barriers: barriers,
      );

      expect(objectLayer.tileAt(4, 7)?.tileIndex, equals(42));
      expect(objectLayer.tileAt(4, 8)?.tileIndex, equals(43));
    });

    test('copies wall cap tiles above north-facing vertical wall edges', () {
      final floor = TileLayerData();
      floor.setTile(5, 6, const TileRef(tilesetId: 'test', tileIndex: 10));
      floor.setTile(5, 7, const TileRef(tilesetId: 'test', tileIndex: 20));
      floor.setTile(5, 8, const TileRef(tilesetId: 'test', tileIndex: 30));

      final barriers = {(5, 7), (5, 8)};
      final objectLayer = buildObjectLayerFromBarriers(
        floorLayer: floor,
        barriers: barriers,
      );

      expect(objectLayer.tileAt(5, 6)?.tileIndex, equals(10));
      expect(objectLayer.tileAt(5, 7)?.tileIndex, equals(20));
    });

    test('all north-facing barriers get wall caps in object layer', () {
      final floor = TileLayerData();
      floor.setTile(5, 6, const TileRef(tilesetId: 'test', tileIndex: 10));
      floor.setTile(5, 7, const TileRef(tilesetId: 'test', tileIndex: 20));
      floor.setTile(6, 6, const TileRef(tilesetId: 'test', tileIndex: 11));
      floor.setTile(6, 7, const TileRef(tilesetId: 'test', tileIndex: 21));

      final barriers = {(5, 7), (6, 7)};
      final objectLayer = buildObjectLayerFromBarriers(
        floorLayer: floor,
        barriers: barriers,
      );

      // Barrier tiles in the object layer.
      expect(objectLayer.tileAt(5, 7)?.tileIndex, equals(20));
      expect(objectLayer.tileAt(6, 7)?.tileIndex, equals(21));
      // Wall caps at y=6 — all north-facing barriers get them.
      expect(objectLayer.tileAt(5, 6)?.tileIndex, equals(10));
      expect(objectLayer.tileAt(6, 6)?.tileIndex, equals(11));
    });

    test('horizontal doorway: gap lintel tiles at y-1, no flanking at y-1',
        () {
      final floor = TileLayerData();
      floor.setTile(6, 22, const TileRef(tilesetId: 'test', tileIndex: 60));
      floor.setTile(7, 22, const TileRef(tilesetId: 'test', tileIndex: 70));
      floor.setTile(8, 22, const TileRef(tilesetId: 'test', tileIndex: 80));

      // Horizontal wall at y=23, gap at x=7.
      final barriers = {(5, 23), (6, 23), (8, 23), (9, 23)};
      final objectLayer = buildObjectLayerFromBarriers(
        floorLayer: floor,
        barriers: barriers,
      );

      // Gap tile above (7,22) IS in the object layer (lintel overhang).
      expect(objectLayer.tileAt(7, 22)?.tileIndex, equals(70));
      // Flanking tiles above (6,22) and (8,22) are wall caps (all
      // north-facing barriers get wall caps).
      expect(objectLayer.tileAt(6, 22)?.tileIndex, equals(60));
      expect(objectLayer.tileAt(8, 22)?.tileIndex, equals(80));
    });

    test('copies extended occlusion tiles above doorway lintels', () {
      final floor = TileLayerData();
      floor.setTile(4, 15, const TileRef(tilesetId: 'test', tileIndex: 1));
      floor.setTile(4, 16, const TileRef(tilesetId: 'test', tileIndex: 2));
      floor.setTile(4, 18, const TileRef(tilesetId: 'test', tileIndex: 3));

      final barriers = {(4, 15), (4, 16), (4, 18)};
      final objectLayer = buildObjectLayerFromBarriers(
        floorLayer: floor,
        barriers: barriers,
      );

      expect(objectLayer.tileAt(4, 16)?.tileIndex, equals(2));
      expect(objectLayer.tileAt(4, 15)?.tileIndex, equals(1));
    });

    test('returns empty layer when no barriers', () {
      final floor = TileLayerData();
      floor.setTile(5, 5, const TileRef(tilesetId: 'test', tileIndex: 1));
      final objectLayer = buildObjectLayerFromBarriers(
        floorLayer: floor,
        barriers: <(int, int)>{},
      );
      expect(objectLayer.isEmpty, isTrue);
    });

    test('skips positions where floor has no tile', () {
      final floor = TileLayerData();
      final barriers = {(4, 7)};
      final objectLayer = buildObjectLayerFromBarriers(
        floorLayer: floor,
        barriers: barriers,
      );
      expect(objectLayer.tileAt(4, 7), isNull);
    });
  });

  group('computeLintelOverlayPositions', () {
    test('returns empty for no barriers', () {
      expect(computeLintelOverlayPositions(<(int, int)>{}), isEmpty);
    });

    test('detects overlay positions above 1-wide horizontal doorway', () {
      final barriers = {
        (5, 23), (6, 23),
        // gap at x=7
        (8, 23), (9, 23),
      };

      final overlays = computeLintelOverlayPositions(barriers);

      expect(overlays, contains((7, 22)));
      expect(overlays.contains((6, 22)), isFalse);
      expect(overlays.contains((8, 22)), isFalse);
    });

    test('detects overlay positions above 2-wide horizontal doorway', () {
      final barriers = {
        (5, 23), (6, 23),
        // gap at x=7, x=8
        (9, 23), (10, 23),
      };

      final overlays = computeLintelOverlayPositions(barriers);

      expect(overlays, contains((7, 22)));
      expect(overlays, contains((8, 22)));
      expect(overlays.contains((6, 22)), isFalse);
      expect(overlays.contains((9, 22)), isFalse);
    });

    test('does not include positions for vertical doorways', () {
      final barriers = {
        (4, 14), (4, 15), (4, 16),
        // gap at y=17
        (4, 18),
      };

      final overlays = computeLintelOverlayPositions(barriers);
      expect(overlays, isEmpty);
    });
  });
}
