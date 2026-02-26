import 'package:flame/sprite.dart';
import 'package:tech_world/map_editor/map_editor_state.dart' show ActiveLayer;

/// Metadata describing a tileset sprite sheet.
///
/// Each tileset is a grid of [tileSize]x[tileSize] pixel tiles arranged
/// in rows and columns within a single PNG image.
class Tileset {
  const Tileset({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.tileSize,
    required this.columns,
    required this.rows,
    this.barrierTileIndices = const {},
    this.availableLayers = const {ActiveLayer.floor, ActiveLayer.objects},
    this.layerRowRanges = const {},
  });

  /// Unique identifier used in [TileRef.tilesetId].
  final String id;

  /// Human-readable display name.
  final String name;

  /// Path to the tileset image relative to `assets/images/`.
  final String imagePath;

  /// Size of each tile in pixels (square).
  final int tileSize;

  /// Number of tile columns in the sprite sheet.
  final int columns;

  /// Number of tile rows in the sprite sheet.
  final int rows;

  /// Tile indices within this tileset that represent solid/impassable objects.
  ///
  /// When a tile with one of these indices is painted on a visual layer, the
  /// map editor can automatically create a barrier on the structure grid.
  /// Defaults to empty (no tiles tagged).
  final Set<int> barrierTileIndices;

  /// Which editor layers this tileset should appear in.
  ///
  /// Defaults to both [ActiveLayer.floor] and [ActiveLayer.objects].
  /// Floor-only tilesets (e.g. terrains) are hidden from the Objects tab,
  /// and object-only tilesets (e.g. furniture) are hidden from the Floor tab.
  final Set<ActiveLayer> availableLayers;

  /// Per-layer row ranges that control which rows the [TilePalette] displays.
  ///
  /// Each entry maps an [ActiveLayer] to a list of `(startRow, endRow)`
  /// ranges (inclusive start, exclusive end). When empty, all rows are shown
  /// for every layer the tileset appears on.
  final Map<ActiveLayer, List<(int, int)>> layerRowRanges;

  /// Whether [tileIndex] represents a solid, impassable tile.
  bool isTileBarrier(int tileIndex) => barrierTileIndices.contains(tileIndex);

  /// Total number of tiles in the sheet.
  int get tileCount => columns * rows;

  /// Row ranges to display for [layer].
  ///
  /// Returns the configured ranges if present, otherwise falls back to the
  /// full sheet `[(0, rows)]`.
  List<(int, int)> rowRangesForLayer(ActiveLayer layer) {
    return layerRowRanges[layer] ?? [(0, rows)];
  }

  /// Whether [row] is visible for [layer] based on [layerRowRanges].
  bool isRowVisibleForLayer(int row, ActiveLayer layer) {
    final ranges = rowRangesForLayer(layer);
    return ranges.any((range) => row >= range.$1 && row < range.$2);
  }

  /// Map a visual row (position in the compacted palette) to an actual
  /// tileset row within the given [ranges].
  ///
  /// Clamps to the last visible row if [visualRow] exceeds the total.
  static int visualRowToActualRow(
      int visualRow, List<(int, int)> ranges) {
    var remaining = visualRow;
    for (final (start, end) in ranges) {
      final rangeSize = end - start;
      if (remaining < rangeSize) return start + remaining;
      remaining -= rangeSize;
    }
    // Clamp to last visible row.
    final (_, lastEnd) = ranges.last;
    return lastEnd - 1;
  }

  /// Map an actual tileset row to a visual row in the compacted palette.
  ///
  /// Returns `null` if the row is not in any visible range.
  static int? actualRowToVisualRow(
      int actualRow, List<(int, int)> ranges) {
    var offset = 0;
    for (final (start, end) in ranges) {
      if (actualRow >= start && actualRow < end) {
        return offset + (actualRow - start);
      }
      offset += end - start;
    }
    return null;
  }

  /// Clamp a visual row selection to a single row range.
  ///
  /// Given a drag start and end in visual coordinates, if the two rows fall in
  /// different ranges, both are clamped to the range containing [dragStartVisualRow].
  /// Returns `(startVisualRow, endVisualRow)` in min/max order.
  static (int, int) clampSelectionToRange(
    int dragStartVisualRow,
    int dragEndVisualRow,
    List<(int, int)> ranges,
  ) {
    var startVisualRow = dragStartVisualRow < dragEndVisualRow
        ? dragStartVisualRow
        : dragEndVisualRow;
    var endVisualRow = dragStartVisualRow < dragEndVisualRow
        ? dragEndVisualRow
        : dragStartVisualRow;

    // Use the drag origin (not min/max) to determine the anchor range.
    final anchorActual = visualRowToActualRow(dragStartVisualRow, ranges);
    final otherActual = visualRowToActualRow(dragEndVisualRow, ranges);

    // Find which range contains the drag-start (anchor) row.
    (int, int)? anchorRange;
    for (final range in ranges) {
      if (anchorActual >= range.$1 && anchorActual < range.$2) {
        anchorRange = range;
        break;
      }
    }

    if (anchorRange != null &&
        !(otherActual >= anchorRange.$1 && otherActual < anchorRange.$2)) {
      // Different ranges — clamp both ends to the anchor's range.
      // anchorRange came from iterating ranges, so its start is always found.
      final rangeVisualStart = actualRowToVisualRow(anchorRange.$1, ranges);
      assert(rangeVisualStart != null, 'anchor range start must exist in ranges');
      if (rangeVisualStart == null) return (startVisualRow, endVisualRow);
      final rangeVisualEnd =
          rangeVisualStart + (anchorRange.$2 - anchorRange.$1) - 1;
      endVisualRow = endVisualRow.clamp(rangeVisualStart, rangeVisualEnd);
      startVisualRow = startVisualRow.clamp(rangeVisualStart, rangeVisualEnd);
    }

    return (startVisualRow, endVisualRow);
  }
}

/// A [Tileset] paired with its loaded [SpriteSheet], ready for rendering.
class LoadedTileset {
  const LoadedTileset({
    required this.tileset,
    required this.spriteSheet,
  });

  final Tileset tileset;
  final SpriteSheet spriteSheet;
}
