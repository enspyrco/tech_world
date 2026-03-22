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
      // Wall at x=4 from y=14 to y=18, with gap at y=17.
      // Barrier at (4,16) is the lintel: gap at y+1=17, wall resumes at y+2=18.
      final barriers = {
        (4, 14), (4, 15), (4, 16), // above gap
        // gap at y=17
        (4, 18), // below gap
      };

      final overrides = computePriorityOverrides(barriers);

      // Lintel at (4,16) should get priority 18 (y+2) — strictly greater
      // than a player in the gap at y=17 (priority 17).
      expect(overrides[(4, 16)], equals(18));

      // Extended occlusion: tile above lintel at (4,15) also gets priority 18
      // to cover the full 64px player sprite height.
      expect(overrides[(4, 15)], equals(18));
    });

    test('horizontal wall does not produce false lintels', () {
      // Horizontal wall at y=7 from x=5 to x=10.
      // South-facing edges should NOT be detected as lintels — players south
      // of a wall should appear in front, not behind.
      final barriers = {
        for (var x = 5; x <= 10; x++) (x, 7),
      };

      final overrides = computePriorityOverrides(barriers);

      // No barrier has the lintel pattern (gap at y+1, barrier at y+2),
      // so no priority should be bumped to y+2.
      for (final entry in overrides.entries) {
        expect(
          entry.value,
          isNot(equals(9)), // y+2 = 7+2 = 9 would be a false lintel
          reason: 'horizontal wall should not produce lintel overrides',
        );
      }
    });

    test('wall cap tiles get priority of barrier below', () {
      // North-facing edge: barrier at (5,7) with open space at (5,6).
      // The wall cap tile at (5,6) should sort with the wall face at y=7.
      final barriers = {(5, 7), (5, 8)};

      final overrides = computePriorityOverrides(barriers);

      // Wall cap at (5,6) gets priority 7 (the barrier y below).
      expect(overrides[(5, 6)], equals(7));
    });

    test('L-Room barriers produce correct lintel at (4,16)', () {
      // Actual L-Room barrier layout.
      final barriers = <(int, int)>{
        // Vertical wall at x=4 (gap at y=17 for door)
        (4, 7), (4, 8), (4, 9), (4, 10), (4, 11),
        (4, 12), (4, 13), (4, 14), (4, 15), (4, 16),
        (4, 18), (4, 19), (4, 20), (4, 21), (4, 22),
        (4, 23), (4, 24), (4, 25), (4, 26), (4, 27),
        (4, 28), (4, 29),
        // Horizontal wall at y=7
        (5, 7), (6, 7), (7, 7), (8, 7), (9, 7),
        (10, 7), (11, 7), (12, 7), (13, 7), (14, 7),
        (15, 7), (16, 7), (17, 7),
      };

      final overrides = computePriorityOverrides(barriers);

      // Only (4,16) qualifies as a lintel: gap at (4,17), wall at (4,18).
      expect(overrides[(4, 16)], equals(18));
      expect(overrides[(4, 15)], equals(18)); // extended occlusion

      // (4,18) is NOT a lintel — open at (4,19)? No, (4,19) IS a barrier.
      // So (4,18) has gap at y+1=19? No, (4,19) is a barrier, so no gap.
      // Only (4,16) should be a lintel.
      expect(
        overrides.entries
            .where((e) => e.value == 20) // y+2 for (4,18) would be 20
            .isEmpty,
        isTrue,
        reason: '(4,18) should not be a lintel — (4,19) is a barrier',
      );
    });

    test('horizontal wall with 1-wide vertical doorway gap detects lintel', () {
      // Horizontal wall at y=23 from x=5 to x=10, with gap at x=7.
      final barriers = {
        (5, 23), (6, 23), // left of gap
        // gap at x=7
        (8, 23), (9, 23), (10, 23), // right of gap
      };

      final overrides = computePriorityOverrides(barriers);

      // Gap tile (7,23) should NOT be bumped — it's floor.
      expect(overrides.containsKey((7, 23)), isFalse,
          reason: 'gap tile is floor, should not get priority override');
      // Flanking barriers bumped to y+1=24.
      expect(overrides[(6, 23)], equals(24));
      expect(overrides[(8, 23)], equals(24));
      // Tiles ABOVE the gap (visual lintel overhang) bumped.
      expect(overrides[(6, 22)], equals(24));
      expect(overrides[(7, 22)], equals(24));
      expect(overrides[(8, 22)], equals(24));
    });

    test('horizontal wall with 2-wide vertical doorway gap detects lintel', () {
      // Horizontal wall at y=23, gap at x=7 and x=8 (2 tiles wide).
      final barriers = {
        (5, 23), (6, 23), // left of gap
        // gap at x=7 and x=8
        (9, 23), (10, 23), // right of gap
      };

      final overrides = computePriorityOverrides(barriers);

      // Gap tiles (7,23) and (8,23) should NOT be bumped — they're floor.
      expect(overrides.containsKey((7, 23)), isFalse);
      expect(overrides.containsKey((8, 23)), isFalse);
      // Flanking barriers bumped.
      expect(overrides[(6, 23)], equals(24));
      expect(overrides[(9, 23)], equals(24));
      // Tiles ABOVE the gap (visual lintel overhang) bumped.
      expect(overrides[(7, 22)], equals(24));
      expect(overrides[(8, 22)], equals(24));
    });

    test('multiple doorways in same wall', () {
      // Vertical wall with two gaps.
      final barriers = {
        (4, 5), (4, 6),
        // gap at y=7
        (4, 8), (4, 9),
        // gap at y=10
        (4, 11), (4, 12),
      };

      final overrides = computePriorityOverrides(barriers);

      // Lintel at (4,6): gap at y+1=7, barrier at y+2=8.
      expect(overrides[(4, 6)], equals(8));
      expect(overrides[(4, 5)], equals(8)); // extended occlusion

      // Lintel at (4,9): gap at y+1=10, barrier at y+2=11.
      expect(overrides[(4, 9)], equals(11));
      expect(overrides[(4, 8)], equals(11)); // extended occlusion
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

    test('copies wall cap tiles above north-facing edges', () {
      final floor = TileLayerData();
      // Barrier at (5,7) with open space above — north-facing edge.
      floor.setTile(5, 6, const TileRef(tilesetId: 'test', tileIndex: 10));
      floor.setTile(5, 7, const TileRef(tilesetId: 'test', tileIndex: 20));

      final barriers = {(5, 7)};
      final objectLayer = buildObjectLayerFromBarriers(
        floorLayer: floor,
        barriers: barriers,
      );

      // Wall cap at (5,6) should be in the object layer.
      expect(objectLayer.tileAt(5, 6)?.tileIndex, equals(10));
      // Barrier tile at (5,7) should also be in the object layer.
      expect(objectLayer.tileAt(5, 7)?.tileIndex, equals(20));
    });

    test('copies extended occlusion tiles above doorway lintels', () {
      final floor = TileLayerData();
      floor.setTile(4, 15, const TileRef(tilesetId: 'test', tileIndex: 1));
      floor.setTile(4, 16, const TileRef(tilesetId: 'test', tileIndex: 2));
      // gap at y=17
      floor.setTile(4, 18, const TileRef(tilesetId: 'test', tileIndex: 3));

      final barriers = {(4, 15), (4, 16), (4, 18)};
      final objectLayer = buildObjectLayerFromBarriers(
        floorLayer: floor,
        barriers: barriers,
      );

      // Lintel at (4,16) — in object layer.
      expect(objectLayer.tileAt(4, 16)?.tileIndex, equals(2));
      // Extended occlusion at (4,15) — already a barrier, should be present.
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
      // No tile at (4,7) in the floor.

      final barriers = {(4, 7)};
      final objectLayer = buildObjectLayerFromBarriers(
        floorLayer: floor,
        barriers: barriers,
      );

      // No tile to copy — should be null.
      expect(objectLayer.tileAt(4, 7), isNull);
    });
  });

  group('computeLintelOverlayPositions', () {
    test('returns empty for no barriers', () {
      expect(computeLintelOverlayPositions(<(int, int)>{}), isEmpty);
    });

    test('detects overlay positions above 1-wide horizontal doorway', () {
      final barriers = {
        (5, 23), (6, 23), // left of gap
        // gap at x=7
        (8, 23), (9, 23), // right of gap
      };

      final overlays = computeLintelOverlayPositions(barriers);

      // Only the tile directly above the gap — not flanking wall tiles.
      expect(overlays, contains((7, 22))); // above gap
      expect(overlays.contains((6, 22)), isFalse,
          reason: 'flanking wall tile should not be half-height');
      expect(overlays.contains((8, 22)), isFalse,
          reason: 'flanking wall tile should not be half-height');
    });

    test('detects overlay positions above 2-wide horizontal doorway', () {
      final barriers = {
        (5, 23), (6, 23), // left of gap
        // gap at x=7, x=8
        (9, 23), (10, 23), // right of gap
      };

      final overlays = computeLintelOverlayPositions(barriers);

      // Only tiles directly above the gap opening.
      expect(overlays, contains((7, 22)));
      expect(overlays, contains((8, 22)));
      // Flanking wall tiles render full-height.
      expect(overlays.contains((6, 22)), isFalse);
      expect(overlays.contains((9, 22)), isFalse);
    });

    test('does not include positions for vertical doorways', () {
      // Vertical wall with horizontal gap — no overlay needed.
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
