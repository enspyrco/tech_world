import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/barrier_occlusion.dart';

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

  group('buildObjectLayerFromWalls', () {
    test('places face tiles at barrier positions', () {
      final barriers = {(4, 7), (4, 8)};
      final objectLayer = buildObjectLayerFromWalls(barriers);

      // Each barrier should have a face tile.
      expect(objectLayer.tileAt(4, 7), isNotNull);
      expect(objectLayer.tileAt(4, 8), isNotNull);
    });

    test('places cap tiles above north-facing barriers', () {
      // Vertical wall: (5,7) is north-facing (nothing at (5,6)).
      final barriers = {(5, 7), (5, 8)};
      final objectLayer = buildObjectLayerFromWalls(barriers);

      // Cap tile at y-1 of the north-facing barrier.
      expect(objectLayer.tileAt(5, 6), isNotNull);
      // (5,7) is the top barrier, so y-1 = 6 gets a cap.
      // (5,8) has a barrier above at (5,7), so no cap at (5,7) from (5,8).
      // But (5,7) already has a face tile from the barrier itself.
      expect(objectLayer.tileAt(5, 7), isNotNull);
    });

    test('returns empty layer when no barriers', () {
      final objectLayer = buildObjectLayerFromWalls(<(int, int)>{});
      expect(objectLayer.isEmpty, isTrue);
    });

    test('isolated barrier gets face and cap tiles', () {
      final barriers = {(4, 7)};
      final objectLayer = buildObjectLayerFromWalls(barriers);

      // Face tile at barrier position.
      expect(objectLayer.tileAt(4, 7), isNotNull);
      // Cap tile above (north-facing since no barrier at (4,6)).
      expect(objectLayer.tileAt(4, 6), isNotNull);
    });

    test('horizontal wall: all barriers get caps above', () {
      final barriers = {(5, 7), (6, 7), (7, 7)};
      final objectLayer = buildObjectLayerFromWalls(barriers);

      // All are north-facing (nothing at y=6).
      expect(objectLayer.tileAt(5, 6), isNotNull);
      expect(objectLayer.tileAt(6, 6), isNotNull);
      expect(objectLayer.tileAt(7, 6), isNotNull);
    });

    test('horizontal doorway: cap tiles placed above gap as lintel', () {
      // Wall-wall-gap-wall-wall pattern: door at x=7
      //   (5,10) (6,10) [gap at 7,10] (8,10) (9,10)
      // The gap at (7,10) should get a cap tile at (7,9) — the lintel.
      final walls = {(5, 10), (6, 10), (8, 10), (9, 10)};
      final objectLayer = buildObjectLayerFromWalls(walls);

      // Lintel: cap tile above the gap.
      expect(objectLayer.tileAt(7, 9), isNotNull,
          reason: 'Lintel cap should be placed above doorway gap');
    });

    test('wider doorway: cap tiles placed above all gap cells', () {
      // 2-tile wide door: gaps at x=7 and x=8
      //   (5,10) (6,10) [gap 7,10] [gap 8,10] (9,10) (10,10)
      final walls = {(5, 10), (6, 10), (9, 10), (10, 10)};
      final objectLayer = buildObjectLayerFromWalls(walls);

      expect(objectLayer.tileAt(7, 9), isNotNull,
          reason: 'Lintel cap above left gap cell');
      expect(objectLayer.tileAt(8, 9), isNotNull,
          reason: 'Lintel cap above right gap cell');
    });

    test('no lintel for gap wider than 3 tiles', () {
      // 4-tile gap — too wide to be a door
      final walls = {(5, 10), (10, 10)};
      final objectLayer = buildObjectLayerFromWalls(walls);

      // No lintel tiles above the gap.
      expect(objectLayer.tileAt(6, 9), isNull);
      expect(objectLayer.tileAt(7, 9), isNull);
      expect(objectLayer.tileAt(8, 9), isNull);
      expect(objectLayer.tileAt(9, 9), isNull);
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
