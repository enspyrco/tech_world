import 'package:tech_world/flame/tiles/tile_animation.dart';

/// Predefined tile animations keyed by tileset ID.
///
/// Animation is a tileset-level property. Each entry maps a tileset to its
/// list of [TileAnimation]s. When a tile renderer encounters a tile whose
/// index appears in any animation's [TileAnimation.frameIndices], it renders
/// the animation instead of a static sprite.
///
/// Currently defines waterfall animations for `ext_terrains`.
///
/// This is `final` rather than `const` because the entries use [_idx] helper
/// calls and collection-for syntax, which aren't const-evaluable in Dart.
final Map<String, List<TileAnimation>> tileAnimations = {
  'ext_terrains': _extTerrainsAnimations,
};

// ---------------------------------------------------------------------------
// ext_terrains (32 columns × 74 rows, 32×32px tiles)
//
// Waterfall section: rows 48-53, cols 24-30.
// Two animation frames laid out side-by-side:
//   Frame 1: cols 24-26 (left panel)
//   Frame 2: cols 27-29 (right panel)
//
// Index formula: row * 32 + col
// ---------------------------------------------------------------------------

/// Helper to compute a tile index in a 32-column tileset.
int _idx(int row, int col) => row * 32 + col;

final List<TileAnimation> _extTerrainsAnimations = [
  // --- Waterfall top (row 48) ---
  // Left cliff top
  TileAnimation(
    baseTileIndex: _idx(48, 24),
    frameIndices: [_idx(48, 24), _idx(48, 27)],
    stepTime: 0.35,
  ),
  // Water top left
  TileAnimation(
    baseTileIndex: _idx(48, 25),
    frameIndices: [_idx(48, 25), _idx(48, 28)],
    stepTime: 0.35,
  ),
  // Water top right
  TileAnimation(
    baseTileIndex: _idx(48, 26),
    frameIndices: [_idx(48, 26), _idx(48, 29)],
    stepTime: 0.35,
  ),

  // --- Waterfall body (rows 49-51) ---
  for (final row in [49, 50, 51]) ...[
    // Left cliff wall
    TileAnimation(
      baseTileIndex: _idx(row, 24),
      frameIndices: [_idx(row, 24), _idx(row, 27)],
      stepTime: 0.35,
    ),
    // Water body left
    TileAnimation(
      baseTileIndex: _idx(row, 25),
      frameIndices: [_idx(row, 25), _idx(row, 28)],
      stepTime: 0.35,
    ),
    // Water body right
    TileAnimation(
      baseTileIndex: _idx(row, 26),
      frameIndices: [_idx(row, 26), _idx(row, 29)],
      stepTime: 0.35,
    ),
  ],

  // --- Waterfall bottom (rows 52-53) ---
  for (final row in [52, 53]) ...[
    TileAnimation(
      baseTileIndex: _idx(row, 24),
      frameIndices: [_idx(row, 24), _idx(row, 27)],
      stepTime: 0.35,
    ),
    TileAnimation(
      baseTileIndex: _idx(row, 25),
      frameIndices: [_idx(row, 25), _idx(row, 28)],
      stepTime: 0.35,
    ),
    TileAnimation(
      baseTileIndex: _idx(row, 26),
      frameIndices: [_idx(row, 26), _idx(row, 29)],
      stepTime: 0.35,
    ),
  ],
];

/// O(1) lookup index: maps (tilesetId, tileIndex) → [TileAnimation].
///
/// Built lazily from [tileAnimations] on first access. Every frame index in
/// every animation is registered, so painting any frame of an animation in
/// the editor will trigger it.
final Map<String, Map<int, TileAnimation>> _animationIndex = _buildIndex();

Map<String, Map<int, TileAnimation>> _buildIndex() {
  final index = <String, Map<int, TileAnimation>>{};
  for (final entry in tileAnimations.entries) {
    final tilesetMap = <int, TileAnimation>{};
    for (final anim in entry.value) {
      for (final frameIndex in anim.frameIndices) {
        tilesetMap[frameIndex] = anim;
      }
    }
    index[entry.key] = tilesetMap;
  }
  return index;
}

/// Look up the [TileAnimation] for a tile in a given tileset.
///
/// Returns the animation if [tileIndex] is any frame of an animation in
/// [tilesetId], or `null` if the tile is static.
///
/// Uses an O(1) indexed map rather than linear search, so this is efficient
/// even when called per-tile during map loading.
TileAnimation? lookupAnimationForTile(String tilesetId, int tileIndex) {
  return _animationIndex[tilesetId]?[tileIndex];
}
