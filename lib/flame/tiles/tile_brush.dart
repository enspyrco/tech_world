import 'package:tech_world/flame/tiles/tile_ref.dart';

/// A rectangular brush of one or more tiles from a tileset sprite sheet.
///
/// A single-tile selection is represented as a 1×1 brush. Multi-tile
/// selections store the top-left corner (column/row in the tileset grid)
/// and the rectangle dimensions, allowing [tileRefAt] to compute the
/// [TileRef] for any offset within the brush.
class TileBrush {
  const TileBrush({
    required this.tilesetId,
    required this.startCol,
    required this.startRow,
    required this.columns,
    this.width = 1,
    this.height = 1,
  });

  /// The tileset this brush selects from.
  final String tilesetId;

  /// Top-left column in the tileset grid.
  final int startCol;

  /// Top-left row in the tileset grid.
  final int startRow;

  /// Number of columns in the tileset (needed to compute tile indices).
  final int columns;

  /// Brush width in tiles.
  final int width;

  /// Brush height in tiles.
  final int height;

  /// Whether this brush covers more than one tile.
  bool get isMultiTile => width > 1 || height > 1;

  /// Return the [TileRef] at offset ([dx], [dy]) within the brush rectangle.
  TileRef tileRefAt(int dx, int dy) {
    return TileRef(
      tilesetId: tilesetId,
      tileIndex: (startRow + dy) * columns + (startCol + dx),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TileBrush &&
          tilesetId == other.tilesetId &&
          startCol == other.startCol &&
          startRow == other.startRow &&
          columns == other.columns &&
          width == other.width &&
          height == other.height;

  @override
  int get hashCode =>
      Object.hash(tilesetId, startCol, startRow, columns, width, height);

  @override
  String toString() =>
      'TileBrush($tilesetId, col=$startCol, row=$startRow, $width×$height)';
}
