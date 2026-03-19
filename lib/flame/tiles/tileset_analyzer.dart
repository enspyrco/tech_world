import 'dart:typed_data';
import 'dart:ui' as ui;

/// Result of analyzing a tileset image for barrier properties.
///
/// Tiles are classified by scanning each column for vertical runs of
/// non-transparent tiles. The bottom tile of each run is a barrier (base),
/// and upper tiles are non-barriers (walk-behind-able via y-depth sorting).
class TilesetAnalysisResult {
  const TilesetAnalysisResult({
    required this.barrierIndices,
    required this.nonBarrierIndices,
  });

  /// Base tiles — bottom of each vertical run. These block movement.
  final Set<int> barrierIndices;

  /// Upper tiles — non-base parts of vertical runs. Walk-behind-able.
  final Set<int> nonBarrierIndices;
}

/// Analyze RGBA pixel data to classify tiles as barrier or non-barrier.
///
/// For each column in the tileset grid, scans top-to-bottom for vertical
/// runs of consecutive non-transparent tiles:
/// - Bottom tile of each run → barrier (base)
/// - Upper tiles of each run → non-barrier (walk-behind)
/// - Single-tile runs → barrier (standalone object)
///
/// Takes pre-obtained [ByteData] (RGBA, 4 bytes/pixel) for testability —
/// no `dart:ui` dependency needed.
TilesetAnalysisResult analyzeTilesetBarriers(
  ByteData rgbaPixels, {
  required int imageWidth,
  required int tileSize,
  required int columns,
  required int rows,
}) {
  final barriers = <int>{};
  final nonBarriers = <int>{};

  // Pre-compute which tiles have any non-transparent pixel.
  final hasContent = List.filled(columns * rows, false);

  for (var row = 0; row < rows; row++) {
    for (var col = 0; col < columns; col++) {
      if (_tileHasContent(rgbaPixels, imageWidth, tileSize, col, row)) {
        hasContent[row * columns + col] = true;
      }
    }
  }

  // Scan each column for vertical runs.
  for (var col = 0; col < columns; col++) {
    int? runStart; // First row of the current run (null = no active run).

    for (var row = 0; row <= rows; row++) {
      final opaque = row < rows && hasContent[row * columns + col];

      if (opaque && runStart == null) {
        // Start a new run.
        runStart = row;
      } else if (!opaque && runStart != null) {
        // End of run — classify tiles.
        final runEnd = row - 1; // Last row in the run (inclusive).
        // Bottom tile → barrier.
        barriers.add(runEnd * columns + col);
        // Upper tiles → non-barrier.
        for (var r = runStart; r < runEnd; r++) {
          nonBarriers.add(r * columns + col);
        }
        runStart = null;
      }
    }
  }

  return TilesetAnalysisResult(
    barrierIndices: barriers,
    nonBarrierIndices: nonBarriers,
  );
}

/// Async convenience wrapper that obtains pixel data from a [ui.Image].
Future<TilesetAnalysisResult> analyzeTilesetImage(
  ui.Image image, {
  required int tileSize,
  required int columns,
  required int rows,
}) async {
  final byteData = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  if (byteData == null) {
    return const TilesetAnalysisResult(
      barrierIndices: {},
      nonBarrierIndices: {},
    );
  }
  return analyzeTilesetBarriers(
    byteData,
    imageWidth: image.width,
    tileSize: tileSize,
    columns: columns,
    rows: rows,
  );
}

/// Check whether any pixel in the tile at ([col], [row]) has alpha > 0.
bool _tileHasContent(
  ByteData pixels,
  int imageWidth,
  int tileSize,
  int col,
  int row,
) {
  final startX = col * tileSize;
  final startY = row * tileSize;

  for (var py = startY; py < startY + tileSize; py++) {
    for (var px = startX; px < startX + tileSize; px++) {
      final offset = (py * imageWidth + px) * 4;
      // Alpha channel is the 4th byte (index +3) in RGBA.
      if (pixels.getUint8(offset + 3) > 0) return true;
    }
  }
  return false;
}
