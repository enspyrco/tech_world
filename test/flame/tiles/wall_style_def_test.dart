import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/barrier_occlusion.dart';
import 'package:tech_world/flame/tiles/wall_style_def.dart';

void main() {
  // Style #7 (clean light gray) in the repacked 30-col LimeZu wall sheet.
  // Rows 4-5, group 0 (cols 0-9) → baseIndex = 4 * 30 + 0 = 120.
  final style = WallStyleDef(
    id: 'modern_gray_07',
    tilesetId: 'limezu_walls',
    baseIndex: 120,
    columns: 30,
  );

  /// Helper to compute the local position (col, row) within the 10×2 block
  /// from an absolute tile index.
  (int col, int row) localPos(int tileIndex) {
    final baseRow = style.baseIndex ~/ style.columns; // 4
    final baseCol = style.baseIndex % style.columns; // 0
    final absRow = tileIndex ~/ style.columns;
    final absCol = tileIndex % style.columns;
    return (absCol - baseCol, absRow - baseRow);
  }

  group('WallStyleDef', () {
    test('tilesetId and id are accessible', () {
      expect(style.tilesetId, 'limezu_walls');
      expect(style.id, 'modern_gray_07');
    });

    group('capForBitmask', () {
      test('isolated wall (no E, no W) → position (3,0)', () {
        // No neighbors, or only N/S neighbors.
        for (final mask in [0, WallBitmask.n, WallBitmask.s, WallBitmask.n | WallBitmask.s]) {
          final cap = style.capForBitmask(mask);
          expect(localPos(cap), (3, 0), reason: 'bitmask=$mask → isolated cap');
        }
      });

      test('left end (has E, no W) → position (0,0)', () {
        final cap = style.capForBitmask(WallBitmask.e);
        expect(localPos(cap), (0, 0));
      });

      test('right end (has W, no E) → position (2,0)', () {
        final cap = style.capForBitmask(WallBitmask.w);
        expect(localPos(cap), (2, 0));
      });

      test('middle (has E and W) → position (1,0)', () {
        final cap = style.capForBitmask(WallBitmask.e | WallBitmask.w);
        expect(localPos(cap), (1, 0));
      });

      test('N and S bits do not affect cap selection', () {
        // Cap selection depends only on E/W.
        final baseCase = style.capForBitmask(WallBitmask.e);
        expect(
          style.capForBitmask(WallBitmask.e | WallBitmask.n),
          baseCase,
        );
        expect(
          style.capForBitmask(WallBitmask.e | WallBitmask.s),
          baseCase,
        );
        expect(
          style.capForBitmask(WallBitmask.e | WallBitmask.n | WallBitmask.s),
          baseCase,
        );
      });
    });

    group('faceForBitmask', () {
      test('isolated, has S → position (5,1) — LR strip', () {
        final face = style.faceForBitmask(WallBitmask.s);
        expect(localPos(face), (5, 1));
      });

      test('isolated, no S → position (3,1) — BLR end', () {
        final face = style.faceForBitmask(0);
        expect(localPos(face), (3, 1));
      });

      test('left end, has S → position (7,0)', () {
        final face = style.faceForBitmask(WallBitmask.e | WallBitmask.s);
        expect(localPos(face), (7, 0));
      });

      test('left end, no S → position (7,1)', () {
        final face = style.faceForBitmask(WallBitmask.e);
        expect(localPos(face), (7, 1));
      });

      test('right end, has S → position (9,0)', () {
        final face = style.faceForBitmask(WallBitmask.w | WallBitmask.s);
        expect(localPos(face), (9, 0));
      });

      test('right end, no S → position (9,1)', () {
        final face = style.faceForBitmask(WallBitmask.w);
        expect(localPos(face), (9, 1));
      });

      test('middle, has S → position (8,0) — fill', () {
        final face = style.faceForBitmask(
          WallBitmask.e | WallBitmask.w | WallBitmask.s,
        );
        expect(localPos(face), (8, 0));
      });

      test('middle, no S → position (8,1) — bottom edge', () {
        final face = style.faceForBitmask(WallBitmask.e | WallBitmask.w);
        expect(localPos(face), (8, 1));
      });

      test('N bit does not affect face selection', () {
        final withoutN = style.faceForBitmask(WallBitmask.e | WallBitmask.s);
        final withN = style.faceForBitmask(
          WallBitmask.n | WallBitmask.e | WallBitmask.s,
        );
        expect(withN, withoutN);
      });
    });

    group('absolute tile index math', () {
      test('baseIndex 120 in 30-col sheet → row 4, col 0', () {
        // The very first tile in the block (position 0,0 = TL cap)
        // should be at absolute index 120 (row 4, col 0).
        final cap = style.capForBitmask(WallBitmask.e); // position (0,0)
        expect(cap, 120);
      });

      test('position (8,1) in 30-col sheet → absolute index 158', () {
        // Row 5, col 8 → 5 * 30 + 8 = 158
        final face = style.faceForBitmask(WallBitmask.e | WallBitmask.w);
        expect(face, 158);
      });
    });
  });

  group('defaultWallStyleId', () {
    test('is defined and maps to a valid style', () {
      expect(defaultWallStyleId, isNotEmpty);
      expect(lookupWallStyle(defaultWallStyleId), isNotNull);
    });
  });

  group('lookupWallStyle', () {
    test('returns style for known ID', () {
      final result = lookupWallStyle(defaultWallStyleId);
      expect(result, isNotNull);
      expect(result!.tilesetId, 'limezu_walls');
    });

    test('returns backward-compat style for gray_brick ID', () {
      final result = lookupWallStyle('gray_brick');
      expect(result, isNotNull);
      expect(result!.id, 'gray_brick');
      expect(result.tilesetId, 'room_builder_office');
    });

    test('gray_brick face tiles match original hardcoded values', () {
      final style = lookupWallStyle('gray_brick')!;
      // Original: 128 (left), 129 (fill), 130 (right).
      expect(style.faceForBitmask(WallBitmask.e | WallBitmask.w), 129);
      expect(style.faceForBitmask(WallBitmask.e), 128);
      expect(style.faceForBitmask(WallBitmask.w), 130);
      expect(style.faceForBitmask(0), 128); // isolated
    });

    test('gray_brick cap tiles match original hardcoded values', () {
      final style = lookupWallStyle('gray_brick')!;
      // Original: 90 (left), 91 (fill), 92 (right).
      expect(style.capForBitmask(WallBitmask.e | WallBitmask.w), 91);
      expect(style.capForBitmask(WallBitmask.e), 90);
      expect(style.capForBitmask(WallBitmask.w), 92);
      expect(style.capForBitmask(0), 90); // isolated
    });

    test('returns null for unknown ID', () {
      expect(lookupWallStyle('nonexistent_style'), isNull);
    });
  });
}
