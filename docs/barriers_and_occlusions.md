# Barriers & Wall Occlusion

How the barrier system, auto-barriers, and wall occlusion interact — and the pitfalls we hit when combining them with tileset-based object painting.

## Two Kinds of Barriers

### Structural barriers

Defined in predefined maps (e.g. the L-Room's L-shaped walls) or painted manually via the Structure layer in the editor. These correspond to real walls in the background PNG — the image has wall art at those positions.

### Auto-barriers

Created automatically when tiles are painted on visual layers:

- **Object layer**: ANY tile creates an auto-barrier (furniture, plants, etc. are always impassable).
- **Floor layer**: only tiles tagged in `Tileset.barrierTileIndices` create auto-barriers (e.g. fences in `ext_terrains`).

Auto-barriers are tracked in `MapEditorState._autoBarrierCells` and are reversible — erasing the tile removes the barrier. See `_maybeCreateAutoBarrier()` and `_maybeRemoveAutoBarrier()` in `map_editor_state.dart`.

## Wall Occlusion

`WallOcclusionComponent` creates **opaque sprite overlays** cut from the background PNG for each barrier cell. Each overlay extends 1 cell above the barrier (covering the "wall face" visible in the PNG) and uses `priority: barrier.y` for Flame's y-sorted depth ordering.

**Effect**: a player north of a wall (lower y, lower priority) renders *behind* the overlay. A player south (higher y, higher priority) renders *in front*. This creates the illusion of walking behind walls.

### Why it only works for structural walls

The overlays are literally sliced from the background image. For structural walls in the L-Room, the background PNG has wall art at those pixel coordinates, so the overlays look correct.

For auto-barriers from painted objects (e.g. a plant placed on the open floor), the background image at that position is just **floor texture**. The overlay becomes an opaque rectangle of floor that renders on top of the object tile sprites — hiding them.

## The Bug: Object Tiles Hidden After Exiting Editor

### Symptoms

Paint object tiles in the map editor on a map with a background image (e.g. L-Room). Objects are visible in the editor preview. Exit editor mode — objects partially or fully disappear. Multi-cell-tall objects (like plants) show only the bottom tile; the rest is covered by floor-colored rectangles.

### Root cause

`_loadMapComponents()` was passing **all** barriers (structural + auto) to `WallOcclusionComponent`. Auto-barriers from object tiles generated wall occlusion overlays that covered the object sprites with opaque background slices.

The priority math makes it worse for multi-tile objects:

```
Object tile at (x, y-1): priority y-1
Object tile at (x, y):   priority y, auto-barrier at (x, y)
Wall occlusion overlay:  priority y, covers (x, y-1) through (x, y)
```

The overlay at priority `y` renders *after* the sprite at priority `y-1`, hiding the top tile of the object.

### Fix

In `_loadMapComponents()`, filter the barrier list before passing it to `WallOcclusionComponent`:

```dart
final wallBarriers = map.objectLayer != null
    ? map.barriers
          .where((b) => map.objectLayer!.tileAt(b.x, b.y) == null)
          .toList()
    : map.barriers;
```

Any barrier cell that has an object tile is an auto-barrier from tile painting — exclude it from wall occlusion. Structural walls (which don't have object tiles) keep their occlusion behaviour unchanged.

## Layer Filtering in the Tile Palette

A related change: `Tileset.availableLayers` controls which editor layers each tileset appears in. This prevents placing floor-oriented tilesets (like `ext_terrains`) on the Objects tab, which would incorrectly make terrain tiles impassable via auto-barriers.

| Tileset | Available Layers | Rationale |
|---------|-----------------|-----------|
| `test` | floor, objects | Testing |
| `room_builder_office` | floor, objects | Walls (floor) + furniture (objects) |
| `modern_office` | objects | Furniture, plants, partitions |
| `ext_terrains` | floor | Terrain, grass, paths |
| `ext_worksite` | objects | Construction equipment |
| `ext_hotel_hospital` | objects | Building facades |
| `ext_school` | floor, objects | Buildings (objects) + courts (floor) |
| `ext_office` | objects | Exterior buildings |

## Known Limitation

If a user places an object tile directly on a structural wall barrier, that wall segment loses its occlusion overlay (because the filter sees an object tile there and excludes it). In practice this is unlikely — structural walls aren't on open cells where users typically paint objects — but it's worth noting for future work.
