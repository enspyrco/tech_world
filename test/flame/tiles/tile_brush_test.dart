import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/tiles/tile_brush.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';

void main() {
  group('TileBrush', () {
    test('single-tile brush has width and height of 1', () {
      const brush = TileBrush(
        tilesetId: 'test',
        startCol: 2,
        startRow: 3,
        columns: 4,
      );

      expect(brush.width, 1);
      expect(brush.height, 1);
      expect(brush.isMultiTile, isFalse);
    });

    test('multi-tile brush reports isMultiTile', () {
      const brush = TileBrush(
        tilesetId: 'test',
        startCol: 0,
        startRow: 0,
        columns: 4,
        width: 3,
        height: 2,
      );

      expect(brush.isMultiTile, isTrue);
    });

    test('tileRefAt returns correct TileRef for single tile', () {
      const brush = TileBrush(
        tilesetId: 'test',
        startCol: 2,
        startRow: 3,
        columns: 4,
      );

      final ref = brush.tileRefAt(0, 0);
      // row 3, col 2 in a 4-column grid → index = 3 * 4 + 2 = 14
      expect(ref, const TileRef(tilesetId: 'test', tileIndex: 14));
    });

    test('tileRefAt computes correct indices for multi-tile brush', () {
      // A 3×2 brush starting at col=1, row=2 in a 16-column tileset.
      const brush = TileBrush(
        tilesetId: 'office',
        startCol: 1,
        startRow: 2,
        columns: 16,
        width: 3,
        height: 2,
      );

      // (dx=0, dy=0) → row=2, col=1 → 2*16+1 = 33
      expect(brush.tileRefAt(0, 0),
          const TileRef(tilesetId: 'office', tileIndex: 33));

      // (dx=2, dy=0) → row=2, col=3 → 2*16+3 = 35
      expect(brush.tileRefAt(2, 0),
          const TileRef(tilesetId: 'office', tileIndex: 35));

      // (dx=0, dy=1) → row=3, col=1 → 3*16+1 = 49
      expect(brush.tileRefAt(0, 1),
          const TileRef(tilesetId: 'office', tileIndex: 49));

      // (dx=2, dy=1) → row=3, col=3 → 3*16+3 = 51
      expect(brush.tileRefAt(2, 1),
          const TileRef(tilesetId: 'office', tileIndex: 51));
    });

    test('equality compares all fields', () {
      const a = TileBrush(
        tilesetId: 'test',
        startCol: 1,
        startRow: 2,
        columns: 4,
        width: 3,
        height: 2,
      );
      const b = TileBrush(
        tilesetId: 'test',
        startCol: 1,
        startRow: 2,
        columns: 4,
        width: 3,
        height: 2,
      );
      const c = TileBrush(
        tilesetId: 'test',
        startCol: 1,
        startRow: 2,
        columns: 4,
        width: 2,
        height: 2,
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('toString includes all fields', () {
      const brush = TileBrush(
        tilesetId: 'test',
        startCol: 1,
        startRow: 2,
        columns: 4,
        width: 3,
        height: 2,
      );

      expect(brush.toString(), contains('test'));
      expect(brush.toString(), contains('col=1'));
      expect(brush.toString(), contains('row=2'));
      expect(brush.toString(), contains('3×2'));
    });
  });
}
