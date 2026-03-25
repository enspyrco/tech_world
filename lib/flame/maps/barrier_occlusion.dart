import 'package:tech_world/flame/tiles/tile_layer_data.dart';

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

          // Bump the flanking barrier tiles (door frame columns) at y.
          // Do NOT bump flanking tiles ABOVE (y-1) — those are full-height
          // floor tiles that would fully occlude players walking above the
          // wall.
          _setMax(overrides, (x, y), lintelPriority);
          _setMax(overrides, (gapEnd, y), lintelPriority);
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

/// Build an object layer by promoting floor tiles at barrier positions into
/// individually y-sorted sprites.
///
/// The floor layer renders as a single cached [Picture] — it can't participate
/// in per-sprite depth sorting. This function copies floor tiles at barrier
/// positions (plus wall caps and lintel extended occlusion tiles) into a
/// separate object layer where each tile is an individual [SpriteComponent]
/// in the World's priority sort.
///
/// The floor layer keeps its copies underneath — harmless duplication that
/// prevents visual gaps when the object layer is hidden (e.g. editor mode).
TileLayerData buildObjectLayerFromBarriers({
  required TileLayerData floorLayer,
  required Set<(int, int)> barriers,
}) {
  final layer = TileLayerData();
  if (barriers.isEmpty) return layer;

  // Compute which positions need object-layer tiles.
  final positions = <(int, int)>{};

  for (final (x, y) in barriers) {
    // The barrier tile itself.
    positions.add((x, y));

    final isNorthFacing = !barriers.contains((x, y - 1));

    // Vertical wall, horizontal gap.
    final isVerticalDoorwayLintel =
        !barriers.contains((x, y + 1)) && barriers.contains((x, y + 2));

    // Wall cap: 1 row above any north-facing edge.
    if (isNorthFacing && y - 1 >= 0) {
      positions.add((x, y - 1));
    }

    // Vertical doorway: extended occlusion above lintel.
    if (isVerticalDoorwayLintel && y - 1 >= 0) {
      positions.add((x, y - 1));
    }

    // Horizontal doorway: scan for gap to the right.
    if (!barriers.contains((x + 1, y))) {
      var gapEnd = x + 1;
      while (gapEnd < x + 10 && !barriers.contains((gapEnd, y))) {
        gapEnd++;
      }
      if (barriers.contains((gapEnd, y))) {
        final gapWidth = gapEnd - (x + 1);
        if (gapWidth >= 1 && gapWidth <= 3) {
          // Add tiles ABOVE the gap (visual lintel) to the object layer.
          // The gap tiles themselves are floor — they stay in the floor layer.
          if (y - 1 >= 0) {
            for (var gx = x + 1; gx < gapEnd; gx++) {
              positions.add((gx, y - 1));
            }
          }
          // Do NOT add flanking tiles above (y-1) — those are full-height
          // floor tiles that would fully occlude players walking above.
        }
      }
    }
  }

  // Copy floor tiles at computed positions.
  for (final (x, y) in positions) {
    final ref = floorLayer.tileAt(x, y);
    if (ref != null) {
      layer.setTile(x, y, ref);
    }
  }

  return layer;
}
