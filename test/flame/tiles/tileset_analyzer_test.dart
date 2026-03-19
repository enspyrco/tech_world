import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/tiles/tileset_analyzer.dart';

void main() {
  /// Build RGBA pixel data for a tileset grid.
  ///
  /// [opaqueCells] is a set of (col, row) pairs that should contain at least
  /// one non-transparent pixel. All other cells are fully transparent.
  /// Each tile is [tileSize]x[tileSize] pixels.
  ByteData buildPixelData({
    required int columns,
    required int rows,
    required int tileSize,
    required Set<(int, int)> opaqueCells,
  }) {
    final imageWidth = columns * tileSize;
    final imageHeight = rows * tileSize;
    final bytes = ByteData(imageWidth * imageHeight * 4);

    for (final (col, row) in opaqueCells) {
      // Place a single opaque pixel in the center of the tile.
      final px = col * tileSize + tileSize ~/ 2;
      final py = row * tileSize + tileSize ~/ 2;
      final offset = (py * imageWidth + px) * 4;
      bytes.setUint8(offset, 255); // R
      bytes.setUint8(offset + 1, 0); // G
      bytes.setUint8(offset + 2, 0); // B
      bytes.setUint8(offset + 3, 255); // A
    }

    return bytes;
  }

  group('analyzeTilesetBarriers', () {
    test('all transparent tiles → both sets empty', () {
      final pixels = buildPixelData(
        columns: 4,
        rows: 4,
        tileSize: 16,
        opaqueCells: {},
      );

      final result = analyzeTilesetBarriers(
        pixels,
        imageWidth: 64,
        tileSize: 16,
        columns: 4,
        rows: 4,
      );

      expect(result.barrierIndices, isEmpty);
      expect(result.nonBarrierIndices, isEmpty);
    });

    test('single opaque tile → barrier, not non-barrier', () {
      final pixels = buildPixelData(
        columns: 4,
        rows: 4,
        tileSize: 16,
        opaqueCells: {(1, 2)}, // col 1, row 2 → index 9
      );

      final result = analyzeTilesetBarriers(
        pixels,
        imageWidth: 64,
        tileSize: 16,
        columns: 4,
        rows: 4,
      );

      expect(result.barrierIndices, contains(2 * 4 + 1)); // index 9
      expect(result.nonBarrierIndices, isEmpty);
    });

    test('vertical 2-tile run → bottom=barrier, top=non-barrier', () {
      final pixels = buildPixelData(
        columns: 4,
        rows: 4,
        tileSize: 16,
        opaqueCells: {(0, 1), (0, 2)}, // col 0, rows 1–2
      );

      final result = analyzeTilesetBarriers(
        pixels,
        imageWidth: 64,
        tileSize: 16,
        columns: 4,
        rows: 4,
      );

      // Row 2, col 0 → index 8 → barrier (bottom of run)
      expect(result.barrierIndices, contains(2 * 4 + 0));
      // Row 1, col 0 → index 4 → non-barrier (top of run)
      expect(result.nonBarrierIndices, contains(1 * 4 + 0));
    });

    test('vertical 3-tile run → bottom=barrier, top 2=non-barrier', () {
      final pixels = buildPixelData(
        columns: 4,
        rows: 4,
        tileSize: 16,
        opaqueCells: {(2, 0), (2, 1), (2, 2)}, // col 2, rows 0–2
      );

      final result = analyzeTilesetBarriers(
        pixels,
        imageWidth: 64,
        tileSize: 16,
        columns: 4,
        rows: 4,
      );

      // Row 2, col 2 → index 10 → barrier (bottom)
      expect(result.barrierIndices, contains(2 * 4 + 2));
      // Row 0, col 2 → index 2 → non-barrier
      expect(result.nonBarrierIndices, contains(0 * 4 + 2));
      // Row 1, col 2 → index 6 → non-barrier
      expect(result.nonBarrierIndices, contains(1 * 4 + 2));
    });

    test('two runs in same column with gap → each treated independently', () {
      final pixels = buildPixelData(
        columns: 2,
        rows: 6,
        tileSize: 16,
        opaqueCells: {
          (0, 0), (0, 1), // first run: rows 0–1
          // row 2: gap (transparent)
          (0, 3), (0, 4), // second run: rows 3–4
        },
      );

      final result = analyzeTilesetBarriers(
        pixels,
        imageWidth: 32,
        tileSize: 16,
        columns: 2,
        rows: 6,
      );

      // First run: bottom = row 1 (barrier), top = row 0 (non-barrier)
      expect(result.barrierIndices, contains(1 * 2 + 0)); // index 2
      expect(result.nonBarrierIndices, contains(0 * 2 + 0)); // index 0

      // Second run: bottom = row 4 (barrier), top = row 3 (non-barrier)
      expect(result.barrierIndices, contains(4 * 2 + 0)); // index 8
      expect(result.nonBarrierIndices, contains(3 * 2 + 0)); // index 6
    });

    test('multiple columns analyzed independently', () {
      final pixels = buildPixelData(
        columns: 3,
        rows: 3,
        tileSize: 16,
        opaqueCells: {
          (0, 0), (0, 1), // col 0: 2-tile run
          (2, 1), // col 2: single tile
        },
      );

      final result = analyzeTilesetBarriers(
        pixels,
        imageWidth: 48,
        tileSize: 16,
        columns: 3,
        rows: 3,
      );

      // Col 0: bottom = row 1 (barrier), top = row 0 (non-barrier)
      expect(result.barrierIndices, contains(1 * 3 + 0)); // index 3
      expect(result.nonBarrierIndices, contains(0 * 3 + 0)); // index 0

      // Col 2: single tile at row 1 → barrier
      expect(result.barrierIndices, contains(1 * 3 + 2)); // index 5
    });

    test('full row of opaque tiles → each is standalone barrier', () {
      final pixels = buildPixelData(
        columns: 4,
        rows: 3,
        tileSize: 16,
        opaqueCells: {(0, 1), (1, 1), (2, 1), (3, 1)}, // row 1, all cols
      );

      final result = analyzeTilesetBarriers(
        pixels,
        imageWidth: 64,
        tileSize: 16,
        columns: 4,
        rows: 3,
      );

      // Each is a standalone single-tile run → all barriers
      for (var col = 0; col < 4; col++) {
        expect(result.barrierIndices, contains(1 * 4 + col));
      }
      expect(result.nonBarrierIndices, isEmpty);
    });

    test('alpha threshold: pixel with alpha=1 counts as non-transparent', () {
      final imageWidth = 2 * 16;
      final bytes = ByteData(imageWidth * 2 * 16 * 4);
      // Tile (0,0): single pixel with alpha=1 (barely visible)
      final offset = (8 * imageWidth + 8) * 4;
      bytes.setUint8(offset + 3, 1); // A=1

      final result = analyzeTilesetBarriers(
        bytes,
        imageWidth: imageWidth,
        tileSize: 16,
        columns: 2,
        rows: 2,
      );

      expect(result.barrierIndices, contains(0)); // standalone → barrier
    });

    test('alpha=0 is transparent (not counted)', () {
      final imageWidth = 2 * 16;
      final bytes = ByteData(imageWidth * 2 * 16 * 4);
      // All zeros → fully transparent

      final result = analyzeTilesetBarriers(
        bytes,
        imageWidth: imageWidth,
        tileSize: 16,
        columns: 2,
        rows: 2,
      );

      expect(result.barrierIndices, isEmpty);
      expect(result.nonBarrierIndices, isEmpty);
    });
  });
}
