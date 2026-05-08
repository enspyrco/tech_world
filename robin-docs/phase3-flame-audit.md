# Phase 3 Flame Engine Audit

**Audited:** 2026-05-07  
**Scope:** All Flame components in `lib/flame/`, shaders in `shaders/`, and map generators in `lib/flame/maps/generators/`  
**Policy:** Read-only — no files modified.

---

## Component Health Table

| Component | LOC | Responsibility | Priority | Lifecycle | Issues |
|---|---|---|---|---|---|
| `TechWorld` (World) | 2119 | God-object: LiveKit integration, bubble physics, map loading, player lifecycle, pathfinding orchestration | N/A (World) | `onLoad` / `dispose` — mostly clean | God-object concern; `_showHint` memory risk; door-unlock grid staleness (HIGH) |
| `TechWorldGame` (FlameGame) | 39 | Bootstraps game, owns `TilesetRegistry`, loads NPC images | N/A | `onLoad` — clean | None |
| `PlayerComponent` | 214 | Animated sprite + MoveEffect chain for player/remote players | Updated per-frame: `position.y ~/ 32` | `onLoad` — animations built; no `onRemove` | No `onRemove` — MoveEffects are children and auto-removed by Flame; OK |
| `DreamfinderComponent` | 348 | Animated sprite + state machine + autonomous wandering | Updated per-frame: `position.y ~/ 32` | No `onRemove` | No `onRemove`; `animationTicker.onComplete` callback closure leak risk (MEDIUM) |
| `BotCharacterComponent` | 129 | Static sprite + MoveEffect movement for Clawd | Updated per-frame: `position.y ~/ 32` | `onLoad` loads image | Image loaded via `Flame.images.load` (not `game.images`) — may double-cache (LOW) |
| `BarriersComponent` | 92 | Stores barrier points; creates visual rectangles in World | None | `onLoad` — rectangles added to world | `removeBarrierAt` modifies `_points` but does not notify `PathComponent` to invalidate cached grid (HIGH) |
| `PathComponent` | 188 | JPS pathfinding, Bresenham expansion | None | Stateless; `_grid` cached lazily | Door-unlock grid staleness; start==end edge case (MEDIUM) |
| `TileFloorComponent` | 202 | Renders floor tiles; caches static tiles as `Picture`; ticks animated tiles | Priority: -1 (fixed) | `onRemove` disposes `Picture` and clears data — clean | None significant |
| `TileObjectLayerComponent` | 180 | Renders object tiles as `SpriteComponent`s injected into parent World | Per-tile: `priorityOverrides[(x,y)] ?? y` | `onRemove` → calls `hide()` which removes sprites from World | After `hide()` then remove, sprites orphaned in world if `add` was not called yet (LOW) |
| `VideoBubbleComponent` | 906 | Video frame capture (FFI/Web), breathing/ripple animation, shader effects | Set by parent each frame | `onRemove` disposes capture and current frame — clean | `_processNativeFrame` is async-void: concurrent calls possible (MEDIUM); shader disabled with TODO (MEDIUM); 8 `print('[DIAG]')` statements in production path (LOW) |
| `BubbleFieldComponent` | 122 | Metaball glow field shader between nearby bubbles | Set by parent each frame | No `onRemove` needed — shader is a value type | None |
| `MergedVideoBubbleComponent` | 149 | Multi-video merged blob shader (Voronoi blend) | Set by parent each frame | Static `_placeholder` image never disposed (LOW) | |
| `PlayerBubbleComponent` | 92 | Static avatar circle with initial letter | Set by parent each frame | None needed | None |
| `BotBubbleComponent` | 183 | Animated Zzz/thinking-dots above Clawd | Set by parent each frame | `onMount` adds listener; `onRemove` removes listener — clean | None |
| `TerminalComponent` | 81 | Tappable terminal tile; delegates to callback | Fixed (topLeft anchor) | None needed | None |
| `DoorComponent` | 81 | Locked/unlocked door tile | `door.position.y` (fixed) | None needed | None |
| `SpeechBubbleComponent` | 221 | Typewriter speech text with fade-out | Set by parent at creation | `onRemove` disposes cached `Paragraph` — clean | None |
| `MapPreviewComponent` | 151 | Editor canvas preview (cached `Picture`) | None | `onRemove` removes listener and disposes Picture — clean | None |

---

## Rendering Issues

### MEDIUM — Same-y tie-breaking undefined between player and wall tile

**Location:** `player_component.dart:138`, `tile_object_layer_component.dart:66`

Two players at the same `y` pixel row get `priority = position.y.round() ~/ 32` which can be identical. Flame's sort is stable for equal priorities (insertion order), but the order is not deterministic across map loads or player joins. Two remote players at the same grid row will flicker relative to each other.

**Suggested fix:** Use a sub-key derived from `id` to break ties (e.g. `priority = (position.y.round() ~/ 32) * 10000 + id.hashCode.abs() % 10000`). This makes the order stable and deterministic without breaking the overall y-sort.

---

### LOW — Bubble priority uses parent priority + 1, not y-based

**Location:** `tech_world.dart:585–607` (`_updateBubblePositions`)

Video bubbles are sorted at `playerComponent.priority + 1`. Since player priority is `position.y ~/ 32`, this is correct in practice — bubbles always render above their owner. But if two players are at y-values that differ by less than 32px within the same grid row, their bubbles could render in the wrong order relative to each other's characters. Low likelihood but theoretically possible.

---

### LOW — Lintel occlusion: gap scan stops at `x+10`

**Location:** `barrier_occlusion.dart:59` (`computePriorityOverrides`) and `computeLintelOverlayPositions`

Both functions scan right up to `x + 10` cells to find the far wall of a doorway. Doors wider than 10 tiles (impossible in the current editor which enforces 1–3 tile gaps) would silently fail to produce lintel tiles. The `gapWidth >= 1 && gapWidth <= 3` guard is correct, but the `while gapEnd < x + 10` bound is an implicit dependency on door width limits. If door limits ever change, the scan bound needs to change too.

**Suggested fix:** Replace the magic `10` with a named constant (`_maxDoorwayGapScan = 10`).

---

### LOW — Shader disabled with TODO

**Location:** `video_bubble_component.dart:631–635`

The `ImageFilter.shader` application on the video bubble is commented out with `TODO: re-enable once frame capture is verified working`. The shader program is still loaded (wasting GPU memory) and uniforms are still updated each frame (wasting CPU), but the visual effect never fires.

---

## Pathfinding Issues

### HIGH — Door unlock does not invalidate the JPS grid

**Location:** `tech_world.dart:1921`, `tech_world.dart:1965`, `path_component.dart:64`

When a door unlocks (`unlockDoor` / `_handleRemoteDoorUnlock`), `BarriersComponent.removeBarrierAt` is called, which correctly removes the door cell from `_points`. However, `PathComponent` holds a separately cached `pf.Grid` (`_grid`) that was created from the barriers at first use. This grid is **never invalidated** after a door unlock.

Result: after a door unlocks, JPS still treats the door cell as an impassable barrier. The player cannot path through the newly opened door without restarting the session or switching maps (which calls `_pathComponent?.barriers = _barriersComponent`, which sets `_grid = null`).

**Proof:**
- `removeBarrierAt` only modifies `BarriersComponent._points` (line 61).
- `PathComponent._grid` is rebuilt lazily (`_grid ??= _barriers.createGrid()`).
- `PathComponent.barriers` setter (which nulls `_grid`) is only called in `_loadMapComponents` (line 1518), not in `unlockDoor` or `_handleRemoteDoorUnlock`.

**Fix:** Call `_pathComponent?.invalidateGrid()` in both `unlockDoor` and `_handleRemoteDoorUnlock` after calling `removeBarrierAt`.

---

### MEDIUM — start == end produces empty path (silent, no animation)

**Location:** `path_component.dart:67–73`

When `calculatePath(start: s, end: s)` is called (e.g. player taps their current cell), JPS returns a single-element list `[[sx, sy]]`. The `_expandPath` early-return for `jumpPoints.length == 1` produces `[[sx, sy]]`, so `_miniGridPoints` has one point, `_largeGridPoints` has one point, and `_pathDirections` is empty. `PlayerComponent.move` is then called with empty `directions` and a single point: `position = largeGridPoints.first` — correct (no-op teleport to current position). This is fine but the tap produces no animation feedback. Not a crash, but a usability note.

---

### MEDIUM — Unreachable goal produces empty path silently

**Location:** `path_component.dart:67–73`

If the tapped cell is inside a barrier or blocked by walls on all sides, JPS returns an empty list. `_expandPath([])` returns `[]`. `PlayerComponent.move([], [])` hits the branch at line 163: `if (directions.isEmpty && largeGridPoints.isNotEmpty) { position = largeGridPoints.first; return; }` — but `largeGridPoints` is empty too, so neither branch fires, the player simply doesn't move. This is silent with no feedback. The existing `_showHint` call in `_onTerminalInteract` demonstrates the pattern; a similar hint for blocked paths would improve UX.

---

### LOW — Bresenham expansion: `pf_util.getLine` is untyped (`List<dynamic>`)

**Location:** `path_component.dart:173`

The `pf_util.getLine` call is cast as `List<dynamic>`, and each element is accessed as `line[j][0] as int`. If the pathfinding library's line output format ever changes (e.g. switching from `[[int, int]]` to `[Point<int>]`), this will throw a runtime `CastError` with no compile-time protection.

---

## Physics Issues

### MEDIUM — Repulsion force scaling assumes 60fps

**Location:** `tech_world.dart:749`

```dart
final push = direction * (overlap * 0.5 * clampedDt / 0.016);
```

The `clampedDt / 0.016` factor is an explicit 60fps normalization. `dt` is already clamped to `min(dt, 0.05)` (20fps floor), which limits runaway forces on low-frame-rate sessions. However, on high-refresh displays (120fps, `dt ≈ 0.008`), the push magnitude halves relative to 60fps, causing sluggish repulsion. The clamp prevents the reverse problem (large dt → overshooting), so stability is safe, but the scaling is frame-rate-dependent on high-refresh displays.

---

### LOW — Tether cap applied after damping, not before

**Location:** `tech_world.dart:761–767`

```dart
var disp = _bubbleDisplacements[key] ?? Vector2.zero();
disp = disp * _repulsionDamping + (forces[key] ?? Vector2.zero());
if (disp.length > _maxTetherDistance) {
  disp = disp.normalized() * _maxTetherDistance;
}
```

The tether cap is applied to the *fully accumulated* displacement after adding new force. This means a bubble can briefly exceed `_maxTetherDistance` if a large force is applied in one frame (before clamping), because the clamp happens after addition. In practice `_maxTetherDistance = 24px` and forces are small, but the ordering is conceptually inverted — cap should apply to the pre-force displacement to prevent accumulated history from inflating the cap.

---

### LOW — BFS merge group uses `removeAt(0)` on a `List` (O(n²))

**Location:** `tech_world.dart:699`

The BFS queue in `_findMergeGroup` uses `queue.removeAt(0)` which is O(n) per removal for a `List`. With the current cap of `maxMergedBubbles = 4`, this is negligible. If the cap were raised, a `Queue<String>` would be appropriate.

---

## Lifecycle Issues

### HIGH — `_processNativeFrame` is `async void` with no concurrent-call guard

**Location:** `video_bubble_component.dart:452`

`_processNativeFrame` is declared `Future<void> _processNativeFrame()` but called as fire-and-forget (`_processNativeFrame()` at line 449). It calls `_capture!.markConsumed()` and then awaits async image decoding. If the component is removed (and `_disposeCapture()` called) while the async decode is still in flight, `_currentFrame?.dispose()` is called at `onRemove`, but the in-flight frame may then be assigned to the now-nulled `_currentFrame` field afterwards. This creates a use-after-dispose risk on the `ui.Image` returned by `_decodeRgbaImage`.

Also, if the update loop calls `_checkForNewNativeFrame` again before the previous `_processNativeFrame` completes (`hasNewFrame` may be true again), a second concurrent decoding call fires. The null-check `if (_capture == null) return` at the top only protects against post-dispose calls, not concurrent calls.

**Fix:** Add a `bool _nativeDecoding = false` guard, set it true on entry and false on exit (in a `try/finally`), and skip `_processNativeFrame` if already decoding.

---

### MEDIUM — `DreamfinderComponent.animationTicker.onComplete` callback can dangle

**Location:** `dreamfinder_component.dart:193–197`

```dart
animationTicker?.onComplete = () {
  animationTicker?.onComplete = null;
  _walkToPlayer(playerPosition);
};
```

If `moveFromServer` is called while the `noticePlayer` surprise animation is playing, `_removeAllEffects()` is called but the `animationTicker.onComplete` callback is NOT cleared. When the surprise animation finishes, the callback fires and `_walkToPlayer` is called — even though `_serverControlled` is now true and the server is directing movement. This creates conflicting movement commands.

**Fix:** Clear `animationTicker?.onComplete = null` in `moveFromServer` before calling `_move`.

---

### MEDIUM — `_showHint` TextComponent not tracked; leaks on `TechWorld` teardown

**Location:** `tech_world.dart:2006–2023`

```dart
final hint = TextComponent(...);
add(hint);
Future.delayed(const Duration(seconds: 2), () {
  hint.removeFromParent();
});
```

If the user switches maps or disconnects within the 2-second window, `_removeMapComponents` / `disconnectFromLiveKit` do not track or cancel these hint components. The `Future.delayed` callback will attempt `hint.removeFromParent()` on an already-removed component (Flame handles this gracefully — it's a no-op), but the TextComponent remains in the component tree for up to 2 seconds after the map has changed, potentially rendering over the new map.

A minor issue, but worth noting: if the map teardown removes the world entirely, the delayed callback is harmless (Flame ignores removes on unmounted components). The real risk is just visual: hints from map A briefly display on map B.

---

### MEDIUM — `BotCharacterComponent.onLoad` uses `Flame.images.load` instead of `game.images`

**Location:** `bot_character_component.dart:82`

```dart
_clawdImage = await Flame.images.load(spriteAsset);
```

`Flame.images` is the global singleton image cache. `TechWorldGame.onLoad` loads NPC sprites via `game.images.loadAll(...)`, which uses the game's own `Images` instance. Using `Flame.images.load` in `BotCharacterComponent` bypasses the game image cache, preventing cache hits when the same asset is loaded multiple times and bypassing the game's disposal lifecycle.

**Fix:** Mix in `HasGameReference<TechWorldGame>` and use `game.images.load(spriteAsset)` instead.

---

### LOW — `MergedVideoBubbleComponent._placeholder` is never disposed

**Location:** `merged_video_bubble_component.dart:97–100`

```dart
static ui.Image? _placeholder;
...
_placeholder ??= _createPlaceholder();
```

The static `_placeholder` image is created once and reused, but never explicitly disposed. Because it is `static`, it lives for the entire app lifetime. The image is tiny (1×1px) so the memory cost is negligible, but it leaks the `ui.Image` object if the engine is torn down and restarted. In practice this never happens (one game lifetime per app run), so severity is LOW.

---

### LOW — 8 `print('[DIAG]')` calls in production code

**Location:** `video_bubble_component.dart:234,241,248,253,262,266,274,280`

Eight `// ignore: avoid_print` + `print('[DIAG] ...')` calls fire on every video capture initialization attempt. Since initialization retries up to `_maxCaptureRetries = 10` times at 0.5s intervals per bubble per session join, this produces up to 80 console lines per player join in production. These should be converted to `_log.fine(...)` calls.

---

## Map Generation Issues

### MEDIUM — Cave generator can produce zero-open-cell maps

**Location:** `cave_generator.dart:23–26`, `grid_utils.dart:92–115`

```dart
final region = largestOpenRegion(grid);
removeDisconnectedRegions(grid, region);
final spawn = findSpawnPoint(grid, region);
```

If `caveFillChance` is very high (e.g. 1.0 — all walls) and smoothing collapses all cells to walls, `largestOpenRegion` returns an empty set. `removeDisconnectedRegions` with an empty `keepRegion` fills the entire grid. `findSpawnPoint` then falls back to `const Point(25, 25)`, which is a wall cell. The returned `GameMap` has `spawnPoint` on a barrier, causing the player to spawn inside a wall.

The dungeon generator avoids this via room-based carving (rooms always produce open cells), and the maze generator always carves at `(1,1)` first. The cave generator is the only one at risk.

**Fix:** After `removeDisconnectedRegions`, assert `region.isNotEmpty` or fall back to a predefined map.

---

### MEDIUM — Dungeon generator: spawn on wall possible if no rooms placed

**Location:** `dungeon_generator.dart:56–59`

```dart
final spawn = rooms.isNotEmpty
    ? Point(_centerX(rooms.first), _centerY(rooms.first))
    : findSpawnPoint(grid, region);
```

If `dungeonMaxRooms = 0` or all room placement attempts fail (e.g. very small room size relative to grid), `rooms` is empty. The fallback `findSpawnPoint(grid, region)` finds the centroid of the largest open region — but since no rooms were carved and all corridors failed, `region` is the entire filled grid (all walls), which is empty. `findSpawnPoint` on an empty region returns `const Point(25, 25)`, which is a wall.

**Fix:** Guard with a minimum `dungeonMinRoomSize` assertion, or guarantee at least one room is placed before connecting corridors.

---

### LOW — Maze generator: spawn fixed at `(1, 1)` regardless of connectivity

**Location:** `maze_generator.dart:61`

```dart
final spawn = const Point(startX, startY);
```

The maze algorithm always carves `(1,1)` first, so spawn is always walkable. However, after `removeDisconnectedRegions`, any open cells not in the largest region are walled off. Since the recursive backtracker from `(1,1)` visits all odd-coordinate cells, the maze is always fully connected — so spawn is always in the largest region. This is correct as implemented, but the lack of a walkability assertion makes the invariant implicit.

---

### LOW — All generators use `gridSize = 50` hardcoded; no min/max validation

**Location:** `map_generator.dart`, `cave_generator.dart`, `dungeon_generator.dart`, `maze_generator.dart`

`GeneratorConfig` has no validation on its parameters (e.g. `dungeonMinRoomSize` could be > `dungeonMaxRoomSize`, or `caveFillChance` could be > 1.0). Invalid configs silently produce degenerate maps. A factory constructor with `assert` guards would prevent this.

---

## What's Already Good

1. **Shader correctness**: All three GLSL shaders (`metaball_field.frag`, `video_bubble.frag`, `merged_video_bubble.frag`) correctly avoid array initializers, dynamic loop bounds, and dynamic sampler indexing. The metaball shader uses the `#define BALL(b)` macro pattern instead of a loop. The merged-video shader uses explicit `if (count > N)` branches and named distance variables instead of arrays. Both are CanvasKit-compatible.

2. **Uniform binding consistency**: Float uniform indices in `BubbleFieldComponent.render` and `MergedVideoBubbleComponent.render` match their GLSL declarations exactly. The shader comment headers (e.g. `// 0,1 — component pixel size`) map 1:1 with `setFloat(i++, ...)` call order.

3. **Depth sorting**: The y-priority system is well-designed. `TileObjectLayerComponent` correctly injects sprites directly into the parent `World` rather than as children, enabling global y-priority sorting. The `computePriorityOverrides` function correctly handles wall caps, vertical doorway lintels (`y+2`), and horizontal doorway lintels (`y+1`) as pure functions with no side effects. The `debugPriorities` flag is useful.

4. **Video bubble disposal**: `VideoBubbleComponent.onRemove` correctly disposes `_capture`, `_webCapture`, `_remoteWebCapture`, `_rtcRenderer`, and `_currentFrame`. Frame disposal uses `Future.microtask` on web to defer until CanvasKit finishes any in-progress render pass — this is the right pattern.

5. **Bubble physics stability**: The combination of `_repulsionDamping = 0.85` and `_maxTetherDistance = 24px` ensures the spring system cannot oscillate indefinitely. Damping removes energy each frame; the cap prevents accumulated displacement from growing unboundedly. The `clampedDt = min(dt, 0.05)` guard prevents force explosions on frame drops.

6. **Map connectivity**: All three generators call `removeDisconnectedRegions` after carving, ensuring the player can always reach any open cell from spawn (within the largest connected region). The `floodFill` uses 8-directional movement (matching the game's Chebyshev distance model), so connectivity is consistent with actual movement.

7. **BFS merge detection**: The `_findMergeGroup` BFS in `TechWorld` correctly finds the largest connected component (not just any connected pair), returns early with `[]` when fewer than 2 bubbles are near each other, and caps the merge group at `maxMergedBubbles = 4` to match the shader's 4-sampler limit.

8. **JPS grid cloning**: `_grid!.clone()` is correctly called before each `findPath` call, preventing JPS's internal state mutation from corrupting the cached grid between pathfinding calls.

9. **LiveKit subscription cleanup**: `disconnectFromLiveKit` cancels all 11 stream subscriptions, removes `InfraHealthService` from the locator, clears speech bubbles, player bubbles, bubble displacements, and removes all player/bot components. The cleanup is comprehensive.

10. **Animated tile sync**: `TileFloorComponent` uses shared `AnimationTicker` instances per `baseTileIndex`, so all instances of the same water/lava tile animate in sync — correct for pixel-art games.

---

## Summary of Findings by Severity

| Severity | Count | Key Items |
|---|---|---|
| HIGH | 2 | Door unlock doesn't invalidate JPS grid; `_processNativeFrame` async-void concurrent risk |
| MEDIUM | 8 | Same-y player tie-breaking; `DreamfinderComponent` `onComplete` dangle; `_showHint` map-switch leak; `BotCharacterComponent` uses global image cache; cave/dungeon spawn-on-wall edge cases; repulsion force is fps-dependent; silent unreachable-goal path |
| LOW | 9 | Lintel scan magic constant; shader loaded but disabled; static placeholder leak; 8 production print calls; tether cap ordering; BFS O(n²) queue; Bresenham untyped cast; maze spawn implicit invariant; no config validation |
