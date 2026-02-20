/// A reference to a specific tile in a tileset sprite sheet.
///
/// Identifies a 32x32 sprite by its tileset and index within that tileset's
/// grid (row-major order, 0-based).
class TileRef {
  const TileRef({required this.tilesetId, required this.tileIndex});

  /// The ID of the tileset this tile belongs to.
  final String tilesetId;

  /// Zero-based index into the tileset's grid (row-major order).
  ///
  /// For a tileset with `columns` per row:
  ///   row = tileIndex ~/ columns
  ///   col = tileIndex % columns
  final int tileIndex;

  /// Create from a JSON map.
  factory TileRef.fromJson(Map<String, dynamic> json) {
    return TileRef(
      tilesetId: json['tilesetId'] as String,
      tileIndex: json['tileIndex'] as int,
    );
  }

  /// Serialize to a JSON map.
  Map<String, dynamic> toJson() => {
        'tilesetId': tilesetId,
        'tileIndex': tileIndex,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TileRef &&
          tilesetId == other.tilesetId &&
          tileIndex == other.tileIndex;

  @override
  int get hashCode => Object.hash(tilesetId, tileIndex);

  @override
  String toString() => 'TileRef($tilesetId, $tileIndex)';
}
