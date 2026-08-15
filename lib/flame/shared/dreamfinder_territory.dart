import 'dart:math';

/// Default half-width (Chebyshev radius, in grid cells) of Dreamfinder's
/// territory when a map does not author one explicitly.
///
/// A radius of 3 gives a 7×7 square — big enough to feel like a place, small
/// enough that a roaming host isn't distracting during a live demo.
const int kDreamfinderTerritoryRadius = 3;

/// The authored ("designed") description of Dreamfinder's territory on a map:
/// a square centred on [center] extending [radius] cells in each direction
/// (Chebyshev). Resolve to a concrete, grid-clamped [TerritoryRect] via
/// [resolve] before use.
///
/// This is the *authoring* form — ergonomic to write in a [GameMap]. The
/// *resolved* form ([TerritoryRect]) is the single definition every consumer
/// reads: the overlay draws it, Dreamfinder wanders within it, and the bot
/// only hears players standing inside it.
class DreamfinderTerritory {
  const DreamfinderTerritory({
    required this.center,
    this.radius = kDreamfinderTerritoryRadius,
  });

  /// Centre cell of the territory, in mini-grid coordinates.
  final Point<int> center;

  /// Chebyshev half-width, in grid cells.
  final int radius;

  /// Clamp the authored square to the grid, yielding the concrete inclusive
  /// cell rectangle every consumer reads.
  TerritoryRect resolve(int gridSize) => TerritoryRect(
        minX: (center.x - radius).clamp(0, gridSize - 1),
        minY: (center.y - radius).clamp(0, gridSize - 1),
        maxX: (center.x + radius).clamp(0, gridSize - 1),
        maxY: (center.y + radius).clamp(0, gridSize - 1),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DreamfinderTerritory &&
          center == other.center &&
          radius == other.radius;

  @override
  int get hashCode => Object.hash(center, radius);
}

/// A concrete, grid-clamped cell rectangle (inclusive bounds) describing where
/// Dreamfinder walks, listens, and is drawn.
///
/// This is the single source of truth for "Dreamfinder's square". It is
/// resolved once (client-side, from the [GameMap]) and shipped verbatim to the
/// bot over the `map-info` channel, so the drawn box, the wander bound, and the
/// audio gate can never drift apart.
class TerritoryRect {
  const TerritoryRect({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });

  /// Parse the wire form `[minX, minY, maxX, maxY]` (as published in
  /// `map-info`). Returns null if the shape is wrong.
  static TerritoryRect? tryParse(List<dynamic>? wire) {
    if (wire == null || wire.length != 4) return null;
    final ints = wire.map((e) => (e as num).round()).toList();
    return TerritoryRect(
      minX: ints[0],
      minY: ints[1],
      maxX: ints[2],
      maxY: ints[3],
    );
  }

  final int minX;
  final int minY;
  final int maxX;
  final int maxY;

  /// Whether cell ([x], [y]) lies inside the square (inclusive).
  bool contains(int x, int y) =>
      x >= minX && x <= maxX && y >= minY && y <= maxY;

  /// Centre cell (integer-floored) of the rectangle.
  Point<int> get center => Point((minX + maxX) ~/ 2, (minY + maxY) ~/ 2);

  /// Wire form published in `map-info`: `[minX, minY, maxX, maxY]`.
  List<int> toWire() => [minX, minY, maxX, maxY];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TerritoryRect &&
          minX == other.minX &&
          minY == other.minY &&
          maxX == other.maxX &&
          maxY == other.maxY;

  @override
  int get hashCode => Object.hash(minX, minY, maxX, maxY);
}
