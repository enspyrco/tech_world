import 'package:tech_world/flame/tiles/tile_layer_data.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';

/// Compute priority overrides from a barrier set for y-based depth sorting.
///
/// Detects patterns that need non-default priority:
///
/// **Wall caps** — the tile directly above a north-facing barrier edge. These
/// need priority bumped to the barrier's y so they sort with the wall face
/// rather than their own (lower) y position.
///
/// **Vertical doorway lintels** — a barrier at (x, y) with open space at
/// (x, y+1) and another barrier at (x, y+2). The wall runs vertically and
/// the door opens horizontally.
///
/// **Horizontal doorway lintels** — detected by scanning for horizontal
/// sequences of non-barrier tiles (gaps) flanked by barriers on both sides
/// at the same y. The gap tiles above are bumped to y+1 and rendered
/// half-height so they occlude a player walking through without fully
/// covering a player walking above the wall.
///
/// This is a pure function: barriers in, overrides out. No tile data needed.
Map<(int, int), int> computePriorityOverrides(Set<(int, int)> barriers) {
  if (barriers.isEmpty) return const {};

  final overrides = <(int, int), int>{};

  for (final (x, y) in barriers) {
    final isNorthFacing = !barriers.contains((x, y - 1));

    // Vertical wall, horizontal gap: gap at (x, y+1), wall resumes at (x, y+2)
    final isVerticalDoorwayLintel =
        !barriers.contains((x, y + 1)) && barriers.contains((x, y + 2));

    // Wall cap: tile above a north-facing edge gets priority bumped to the
    // barrier's y so it sorts with the wall face. This occludes the player's
    // head when walking above any wall (horizontal or vertical).
    if (isNorthFacing && y - 1 >= 0) {
      overrides.putIfAbsent((x, y - 1), () => y);
    }

    // Vertical doorway lintel: bump to y+2 (strictly greater than player at y+1).
    if (isVerticalDoorwayLintel) {
      overrides[(x, y)] = y + 2;

      // Extended occlusion: tile above the lintel also gets y+2 to cover
      // the player's full 64px height.
      if (y - 1 >= 0) {
        overrides[(x, y - 1)] = y + 2;
      }
    }

    // Horizontal doorway lintel: barrier at (x, y) is the left edge of a gap.
    // Scan right to find where the gap ends and another barrier resumes.
    if (!barriers.contains((x + 1, y))) {
      // There's a gap starting at x+1. Scan to find where wall resumes.
      var gapEnd = x + 1;
      while (gapEnd < x + 10 && !barriers.contains((gapEnd, y))) {
        gapEnd++;
      }
      // gapEnd is now the x of the barrier on the right side of the gap.
      // Only treat as a doorway if we found a barrier (not just ran off).
      if (barriers.contains((gapEnd, y))) {
        final gapWidth = gapEnd - (x + 1);
        // Reasonable door width: 1-3 tiles.
        if (gapWidth >= 1 && gapWidth <= 3) {
          final lintelPriority = y + 1;

          // Bump tiles ABOVE the gap (the visual lintel overhang) — NOT
          // the gap tiles themselves, which are floor and should stay behind
          // the player.
          if (y - 1 >= 0) {
            for (var gx = x + 1; gx < gapEnd; gx++) {
              _setMax(overrides, (gx, y - 1), lintelPriority);
            }
          }

          // Door frame columns keep natural priority (y). Bumping them
          // to y+1 would match the priority of a player at y+1 (just below
          // the door), causing their head to clip against the frame.
        }
      }
    }
  }

  return overrides;
}

/// Compute which tile positions need half-height (bottom-only) rendering.
///
/// These are the tiles directly above horizontal doorway gaps — they contain
/// both floor art (top half) and wall overhang art (bottom half). The floor
/// layer renders the full tile behind the player; the object layer renders
/// only the bottom half in front. This "alpha punch" lets the player show
/// through the floor portion while the overhang occludes them.
///
/// Returns a set of (x, y) positions that should use half-height sprites.
Set<(int, int)> computeLintelOverlayPositions(Set<(int, int)> barriers) {
  if (barriers.isEmpty) return const {};

  final overlays = <(int, int)>{};

  for (final (x, y) in barriers) {
    if (!barriers.contains((x + 1, y))) {
      var gapEnd = x + 1;
      while (gapEnd < x + 10 && !barriers.contains((gapEnd, y))) {
        gapEnd++;
      }
      if (barriers.contains((gapEnd, y))) {
        final gapWidth = gapEnd - (x + 1);
        if (gapWidth >= 1 && gapWidth <= 3 && y - 1 >= 0) {
          // Only tiles directly above the gap opening need half-height
          // rendering. Flanking tiles above the wall edges are solid wall
          // art and should render full-height.
          for (var gx = x + 1; gx < gapEnd; gx++) {
            overlays.add((gx, y - 1));
          }
        }
      }
    }
  }

  return overlays;
}

/// Set override to [priority] only if it's higher than any existing value.
void _setMax(Map<(int, int), int> overrides, (int, int) key, int priority) {
  overrides.update(key, (existing) => existing > priority ? existing : priority,
      ifAbsent: () => priority);
}

// ---------------------------------------------------------------------------
// Wall bitmask — 4-bit cardinal neighbor mask for wall tile selection.
// ---------------------------------------------------------------------------

/// Direction bit constants for the 4-bit wall bitmask.
///
/// ```
///        N=1
///  W=8 | cell | E=2
///        S=4
/// ```
abstract final class WallBitmask {
  static const int n = 1; // barrier at (x, y-1)
  static const int e = 2; // barrier at (x+1, y)
  static const int s = 4; // barrier at (x, y+1)
  static const int w = 8; // barrier at (x-1, y)

  /// Cardinal neighbor offsets indexed by bit position.
  static const List<(int, int)> offsets = [
    (0, -1), // N (bit 0)
    (1, 0), // E (bit 1)
    (0, 1), // S (bit 2)
    (-1, 0), // W (bit 3)
  ];
}

/// Compute the 4-bit cardinal bitmask for a barrier at ([cx], [cy]).
///
/// Each bit indicates whether a barrier exists in that cardinal direction.
/// Returns a value 0–15.
int computeWallBitmask(int cx, int cy, Set<(int, int)> barriers) {
  var mask = 0;
  for (var i = 0; i < 4; i++) {
    final (dx, dy) = WallBitmask.offsets[i];
    if (barriers.contains((cx + dx, cy + dy))) {
      mask |= 1 << i;
    }
  }
  return mask;
}

// ---------------------------------------------------------------------------
// Wall tile indices from `room_builder_office` tileset.
// ---------------------------------------------------------------------------

/// Tileset containing the wall tiles.
///
/// Currently only `room_builder_office` has wall art. When a second tileset
/// with walls is needed, this should become a parameter or per-map config
/// rather than a constant.
const wallTilesetId = 'room_builder_office';

/// Face tiles: gray stone brick from row 8 (indices 128–130).
///
/// - 129: fill (middle / default)
/// - 128: left border (left end / isolated)
/// - 130: right border (right end)
const _faceTiles = <int, int>{
  0: 128, // isolated
  WallBitmask.n: 129,
  WallBitmask.e: 128,
  WallBitmask.s: 129,
  WallBitmask.w: 130,
  WallBitmask.n | WallBitmask.s: 129,
  WallBitmask.e | WallBitmask.w: 129,
  WallBitmask.n | WallBitmask.e: 128,
  WallBitmask.n | WallBitmask.w: 130,
  WallBitmask.s | WallBitmask.e: 128,
  WallBitmask.s | WallBitmask.w: 130,
  WallBitmask.n | WallBitmask.e | WallBitmask.w: 129,
  WallBitmask.s | WallBitmask.e | WallBitmask.w: 129,
  WallBitmask.n | WallBitmask.s | WallBitmask.e: 128,
  WallBitmask.n | WallBitmask.s | WallBitmask.w: 130,
  WallBitmask.n | WallBitmask.e | WallBitmask.s | WallBitmask.w: 129,
};

/// Cap tiles: smooth gray from row 5 (indices 90–92).
///
/// - 91: fill (default)
/// - 90: left shading (left end)
/// - 92: right edge (right end)
const _capTiles = <int, int>{
  0: 90,
  WallBitmask.n: 91,
  WallBitmask.e: 90,
  WallBitmask.s: 91,
  WallBitmask.w: 92,
  WallBitmask.n | WallBitmask.s: 91,
  WallBitmask.e | WallBitmask.w: 91,
  WallBitmask.n | WallBitmask.e: 90,
  WallBitmask.n | WallBitmask.w: 92,
  WallBitmask.s | WallBitmask.e: 90,
  WallBitmask.s | WallBitmask.w: 92,
  WallBitmask.n | WallBitmask.e | WallBitmask.w: 91,
  WallBitmask.s | WallBitmask.e | WallBitmask.w: 91,
  WallBitmask.n | WallBitmask.s | WallBitmask.e: 90,
  WallBitmask.n | WallBitmask.s | WallBitmask.w: 92,
  WallBitmask.n | WallBitmask.e | WallBitmask.s | WallBitmask.w: 91,
};

/// Look up the face tile index for a barrier with the given neighbor [bitmask].
int? faceForBitmask(int bitmask) => _faceTiles[bitmask];

/// Look up the cap tile index for a wall-top with the given neighbor [bitmask].
int? capForBitmask(int bitmask) => _capTiles[bitmask];

// ---------------------------------------------------------------------------
// Object layer generation from barriers.
// ---------------------------------------------------------------------------

/// Build an object layer from barriers with proper wall face + cap tiles.
///
/// Places dedicated wall face and cap tiles from `room_builder_office`,
/// selected by 4-bit cardinal bitmask. This avoids the floor-pixel-bleed
/// problem where copied floor tiles occlude the player with floor art.
TileLayerData buildObjectLayerFromBarriers(Set<(int, int)> barriers) {
  if (barriers.isEmpty) return TileLayerData();
  return _buildWallObjectLayer(barriers);
}

/// Build object layer using dedicated wall tiles.
TileLayerData _buildWallObjectLayer(Set<(int, int)> barriers) {
  final layer = TileLayerData();

  for (final (x, y) in barriers) {
    final bitmask = computeWallBitmask(x, y, barriers);

    // Face tile at barrier position.
    final faceIndex = faceForBitmask(bitmask);
    if (faceIndex != null) {
      layer.setTile(
          x, y, TileRef(tilesetId: wallTilesetId, tileIndex: faceIndex));
    }

    // Cap tile at y-1 for north-facing walls.
    final isNorthFacing = !barriers.contains((x, y - 1));
    if (isNorthFacing && y - 1 >= 0) {
      final capIndex = capForBitmask(bitmask);
      if (capIndex != null) {
        layer.setTile(
          x,
          y - 1,
          TileRef(tilesetId: wallTilesetId, tileIndex: capIndex),
        );
      }
    }
  }

  return layer;
}

