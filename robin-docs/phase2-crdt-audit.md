# Phase 2 -- CRDT Collaborative Map Editing Audit

**Date:** 2026-05-06  
**Scope:** Algebraic law verification, undo/redo interaction, sync protocol, determinism  
**Status:** READ-ONLY audit -- no code modified

---

## 1. CRDT Design Summary

The map editor uses a **Last-Writer-Wins Register (LWW-Register)** CRDT, keyed per `(x, y, layer)` cell. Each cell independently tracks the most recent write using a Lamport clock with lexicographic player-ID tiebreaker.

**Core components:**

| Component | File | Role |
|-----------|------|------|
| `MapEditOp` | `lib/map_editor/crdt/map_edit_op.dart` | Single cell edit with `inverse()` for undo |
| `MapEditBatch` | same file | Atomic group of ops sharing one counter |
| `CellVersionMap` | `lib/map_editor/crdt/cell_version_map.dart` | LWW conflict resolution -- `shouldApply()` + `record()` |
| `UndoManager` | `lib/map_editor/crdt/undo_manager.dart` | Lamport clock + undo/redo stacks |
| `MapSyncService` | `lib/map_editor/map_sync_service.dart` | Proxy wrapping `MapEditorState`, sync protocol |

**Wire protocol:** Two LiveKit data channel topics:
- `map-edit` (broadcast, reliable) -- individual edit batches
- `map-edit-sync` (broadcast/targeted, reliable) -- full-state sync for late-join

**Conflict resolution rule** (CellVersionMap:21-31): An op wins if:
1. Its counter is strictly greater than the recorded counter, OR
2. Counters are equal AND `op.playerId.compareTo(recorded) > 0`

---

## 2. Algebraic Law Verification

### 2.1 LWW Merge Commutativity

**Law:** `merge(A, B) == merge(B, A)` -- applying ops A then B yields the same result as B then A.

**Code references:** `CellVersionMap.shouldApply()` at `cell_version_map.dart:21-31`

**Status: HOLDS**

**Evidence:** The `shouldApply` predicate computes a total order on `(counter, playerId)` pairs. For any two ops A and B targeting the same cell:
- If A.counter != B.counter, the higher counter always wins regardless of application order.
- If A.counter == B.counter, the lexicographically greater playerId always wins regardless of application order.

This is a standard LWW-Register construction. The fuzz test at `cell_version_map_test.dart:154-200` confirms this with 50 random ops across 10 random orderings -- all produce identical version maps.

The value-tracking fuzz test at `cell_version_map_test.dart:203-252` further confirms that the *winning values* (not just version entries) converge.

### 2.2 LWW Merge Associativity

**Law:** `merge(merge(A, B), C) == merge(A, merge(B, C))`

**Code references:** `CellVersionMap.shouldApply()` at `cell_version_map.dart:21-31`

**Status: HOLDS**

**Evidence:** Since the conflict resolution computes a total order, the merge is a `max` operation over `(counter, playerId)` pairs. The `max` function over a totally ordered set is trivially associative: `max(max(a,b), c) == max(a, max(b,c))`. The per-cell independence (keyed by `(x, y, layer)`) preserves this property across the full state.

### 2.3 LWW Merge Idempotence

**Law:** `merge(A, A) == A`

**Code references:** `CellVersionMap.shouldApply()` at `cell_version_map.dart:21-31`, specifically line 27-28

**Status: HOLDS**

**Evidence:** When the same op is applied twice: on the second application, `op.counter == counter` and `op.playerId.compareTo(playerId) == 0` (i.e., not `> 0`), so `shouldApply` returns `false`. The state remains unchanged. The `record()` call (line 34-37) writes `(counter, playerId)` -- writing the same value is idempotent by construction.

### 2.4 Lamport Clock Monotonicity

**Law:** Each player's counter must strictly increase; receiving a remote op must advance the local clock past the remote counter.

**Code references:**
- `UndoManager.nextCounter()` at `undo_manager.dart:25` -- `++_counter` (pre-increment)
- `UndoManager.advanceClock()` at `undo_manager.dart:31-33` -- `_counter = max(_counter, remoteClock)`

**Status: PARTIAL -- subtle weakness**

**Evidence:** `nextCounter()` correctly uses pre-increment, ensuring strictly increasing local counters. `advanceClock()` correctly uses `max()` to advance past observed remote values.

**Issue (P3 -- Low):** `advanceClock` sets `_counter = max(_counter, remoteClock)` but does NOT set `_counter = max(_counter, remoteClock) + 1`. This means after receiving a remote op with counter=10, the local clock sits at 10. The *next* local op will get counter=11 via `nextCounter()`, which is correct. But there is a window where `clock == remoteClock` without any local op at that counter value. This is semantically fine for LWW (the tiebreaker handles `counter==counter` via playerId), but it means the local clock does not strictly dominate observed remote clocks until the next local operation. This is standard Lamport clock behavior and not a bug, but worth noting: if the system ever needed to detect "have I seen all ops up to my clock value" (causal delivery), this would be insufficient.

### 2.5 Late-Join Sync Correctness

**Law:** A late-joining client should converge to the same state as existing editors.

**Code references:**
- `MapSyncService._handleSyncRequest()` at `map_sync_service.dart:660-669`
- `MapSyncService._buildSnapshot()` at `map_sync_service.dart:777-835`
- `MapSyncService._handleSyncResponse()` at `map_sync_service.dart:671-767`
- `MapSyncService._flushSyncBuffer()` at `map_sync_service.dart:769-775`

**Status: PARTIAL -- two issues**

**Issue S1 (P2 -- Medium): Thundering herd on sync-request.**
`_handleSyncRequest` at line 660-669 responds to ANY `sync-request` from another player. The sync-request is broadcast to ALL participants (line 555-559). Every editor in the room responds with a full snapshot. With N editors, a late-join produces N-1 full snapshots.

Furthermore, `_handleSyncResponse` at line 671 processes the *first* sync-response that arrives and applies it. If multiple responses arrive, each one overwrites the state from the previous one. Since the snapshot includes the version map (line 754-755), the last response's version map replaces all prior ones. This is *technically* convergent (each snapshot is a consistent view), but:
- **Bandwidth waste:** O(N) full snapshots for one join
- **Race with buffer:** If sync-responses arrive with different orderings of concurrent ops, the last one to arrive determines the base state, then `_flushSyncBuffer` applies buffered ops on top. The final state is correct *only if* the version map from the accepted snapshot is a superset of all ops that happened before the sync started.

**Issue S2 (P2 -- Medium): Version map not merged -- last writer wins at the snapshot level.**
`_handleSyncResponse` at line 754-755 calls `_versionMap.loadFromJson(versions)` which calls `_versions.clear()` (cell_version_map.dart:72) before loading. If the late-joiner had already recorded some versions (e.g., from local edits before requesting sync, or from a prior sync-response), they are wiped. The buffered ops in `_syncBuffer` will be replayed after, and their `shouldApply` checks use the freshly loaded version map, so they will be correctly accepted/rejected. But any local ops made *before* `requestSync()` will have their version entries erased, meaning a subsequent remote op at a lower counter could incorrectly overwrite them.

In practice, this is mitigated because `requestSync()` is called at join time before any local edits. But the API does not enforce this invariant.

### 2.6 Undo/Redo Interaction with Remote Ops

**Law:** Undoing a local op should produce a correct result even if remote ops modified the same cell concurrently.

**Code references:**
- `UndoManager.createUndo()` at `undo_manager.dart:59-66`
- `UndoManager.createRedo()` at `undo_manager.dart:72-94`
- `MapSyncService.undo()` at `map_sync_service.dart:522-529`
- `MapSyncService.redo()` at `map_sync_service.dart:532-539`

**Status: PARTIAL -- intentional-but-surprising behavior**

**Evidence:** The undo system creates inverse batches with *fresh* counters (undo_manager.dart:62). This is explicitly documented: "Undo and redo work by creating new inverse batches with fresh counters, so they participate in normal CRDT conflict resolution. If another player edited the same cell since, the undo's higher counter wins -- which is correct because explicit undo intent should override."

This design choice is defensible but has consequences:

**Issue U1 (P3 -- Low): Undo overrides remote edits unconditionally.**
If Alice edits cell (5,5) at counter=1, Bob edits the same cell at counter=100, then Alice undoes, the undo gets counter=2 (Alice's local clock, which was advanced to 100 by `advanceClock`). Wait -- actually, `advanceClock(100)` sets Alice's clock to 100, so `nextCounter()` returns 101. The undo batch at counter=101 beats Bob's counter=100, so Alice's undo wins. This is the intended behavior per the doc comment, but it means Alice can unknowingly revert Bob's work. In a small team this is acceptable; in a larger setting it could be surprising.

**Issue U2 (P3 -- Low): Redo replays with stale oldValue.**
`createRedo()` at line 74-93 replays the *original* ops (with original `oldValue`/`newValue`) under a fresh counter. The `oldValue` in the original op reflects the state at the time of the original edit, which may no longer match the current cell state if remote ops intervened. This doesn't affect CRDT correctness (only `newValue` is applied; `oldValue` is only used for subsequent undo), but it means a subsequent undo of the redo will attempt to restore a value that may never have been the actual cell state. The error is self-limiting: each undo/redo cycle gets a fresh counter, so convergence is maintained.

### 2.7 Terrain Automapping Correctness

**Law:** Given identical terrain grid state, automapping must produce identical floor tiles.

**Code references:**
- `MapEditorState.paintTerrain()` at `map_editor_state.dart:264-283`
- `MapEditorState._reevaluateTerrainCell()` at `map_editor_state.dart:318-332`
- `computeBitmask()` at `terrain_bitmask.dart:89-91`
- `simplifyBitmask()` at `terrain_bitmask.dart:69-84`

**Status: HOLDS**

**Evidence:** Terrain automapping is a pure function of the terrain grid state:
1. `terrainGrid.setTerrain(x, y, id)` records the semantic terrain type
2. `computeBitmask()` reads the 8 Moore neighbors, producing a deterministic 8-bit mask
3. `simplifyBitmask()` masks out irrelevant corner bits deterministically
4. `terrain.tileIndexForBitmask(bitmask)` maps bitmask to tile index

The function `evaluateRules()` in `automap_engine.dart:32-57` is explicitly documented as pure. The bitmask computation has no randomness or ordering dependency.

**Note:** Terrain ops in the CRDT transmit the *result* (both terrain-layer and floor-layer diffs), not the bitmask computation. Remote clients apply the computed tiles directly without re-evaluating bitmasks. This is correct and efficient -- it means remote clients don't need terrain brush definitions to apply terrain edits.

### 2.8 Wall Autotiling Correctness

**Law:** Given identical wall positions and styles, wall autotiling must produce identical object-layer tiles.

**Code references:**
- `buildWallTilesForRegion()` at `barrier_occlusion.dart:284-369`
- `computeWallBitmask()` at `barrier_occlusion.dart:163-172`
- `MapSyncService.paintWall()` at `map_sync_service.dart:99-193`

**Status: HOLDS**

**Evidence:** Like terrain, wall autotiling is a deterministic function of wall positions. The bitmask computation uses cardinal neighbors only (4-bit, 0-15 range). The style lookup, face/body/cap selection, and inherited E/W logic are all deterministic given the same wall positions.

Wall edits in the CRDT transmit the computed diffs (wall-layer + structure-layer + object-layer), so remote clients apply pre-computed tiles directly.

**Note:** The lintel (doorway cap) logic at `barrier_occlusion.dart:337-354` scans up to 10 cells to the right to find a gap-closing wall. This is deterministic but the scan range (10) is a magic number that could silently produce incorrect results for very wide doorways. The op transmission of pre-computed diffs means this only matters during local editing, not during CRDT sync.

### 2.9 Version Vector Completeness

**Law:** All layers that can be edited must be tracked in the version vector.

**Code references:**
- `OpLayer` enum at `map_edit_op.dart:4` -- `{structure, floor, objects, terrain, walls}`
- `CellVersionMap._versions` at `cell_version_map.dart:15` -- keyed by `(int, int, OpLayer)`
- All edit methods in `MapSyncService` produce ops with explicit `OpLayer` values

**Status: HOLDS**

**Evidence:** The `OpLayer` enum has exactly 5 values: `structure`, `floor`, `objects`, `terrain`, `walls`. Every edit method in `MapSyncService` produces ops with one of these layers:
- `paintTile()` -> `OpLayer.structure`
- `paintTileRef()` -> `OpLayer.objects` or `OpLayer.floor` + `OpLayer.structure` for auto-barriers
- `paintTerrain()` -> `OpLayer.terrain` + `OpLayer.floor`
- `paintWall()` -> `OpLayer.walls` + `OpLayer.structure` + `OpLayer.objects`

All 5 layers are tracked. The `CellVersionMap` keys on the full `(x, y, OpLayer)` tuple, so different layers at the same position are independently versioned. The serialization round-trip (`toJson`/`loadFromJson`) preserves all layers.

### 2.10 Conflict Resolution Determinism

**Law:** Given the same set of ops in any order, all clients must converge to the same state.

**Code references:** `CellVersionMap.shouldApply()` + `record()` at `cell_version_map.dart:21-37`

**Status: HOLDS for pure LWW -- PARTIAL for compound ops**

**Evidence for pure LWW convergence:** The `(counter, playerId)` total order ensures deterministic winner selection regardless of application order. The fuzz tests confirm this empirically with 50 ops across 10 random orderings.

**Issue D1 (P2 -- Medium): Compound ops within a batch can partially apply.**
A single `MapEditBatch` may contain ops across multiple layers and cells (e.g., `paintWall` produces wall + structure + object ops in one batch). In `_onRemoteEdit()` at `map_sync_service.dart:596-601`, each op within a batch is independently checked against the version map:

```dart
for (final op in batch.ops) {
  if (_versionMap.shouldApply(op)) {
    _applyOpLocally(op);
    _versionMap.record(op);
  }
}
```

If some ops in a batch win and others lose (because different cells/layers have different version histories), the batch is partially applied. For wall painting, this means the wall-layer op could be applied while the corresponding structure-layer op is rejected (or vice versa), leaving the cell in an inconsistent state where it has a wall style but isn't a barrier, or is a barrier without wall rendering.

This is inherent to per-cell LWW and hard to avoid without moving to a batch-level conflict resolution. The current design accepts this trade-off.

---

## 3. Undo/Redo Interaction Analysis

### Design
The undo system is well-designed as a **Command + Memento** pattern. Key properties:

1. **Fresh counters on undo/redo:** Every undo and redo batch gets a new Lamport counter via `nextCounter()`, making it a first-class CRDT operation. Remote clients apply it through normal conflict resolution.

2. **Inverse reversal:** `MapEditBatch.inverse()` reverses the op list order and swaps `oldValue`/`newValue`, correctly undoing multi-cell edits in reverse order.

3. **Redo replays originals:** `createRedo()` replays the original ops (not the inverse of the inverse), avoiding accumulated rounding of values.

### Interaction with Remote Ops

**Scenario:** Alice edits (5,5) at c=1. Bob edits (5,5) at c=50. Alice undoes.

- Alice's `advanceClock(50)` advances her clock to 50.
- Alice's undo gets c=51 (via `nextCounter()`).
- The undo batch with c=51 > Bob's c=50, so Alice's undo wins everywhere.
- Bob's client receives Alice's undo (c=51) and applies it, reverting his edit.

This is the **intended** behavior per the doc comment at `undo_manager.dart:7-10`. The rationale is "explicit undo intent should override." Whether this is correct depends on the use case -- for a small team collaborating in real-time, it's reasonable.

### Undo Stack Pruning

The undo stack has a `maxUndoDepth` of 500 (undo_manager.dart:12). When exceeded, the oldest batch is removed (undo_manager.dart:43-44) via `removeAt(0)`. The pruned batch's ops remain in the version map and on remote clients, but the local user can no longer undo them. This is standard and correct.

---

## 4. Sync Protocol Analysis

### Flow

```
Late-joiner (Alice)                    Existing editors (Bob, Charlie)
       |                                        |
       |--- sync-request (broadcast) ---------->|
       |    [_isSyncing = true]                 |
       |    [_syncBuffer starts collecting]     |
       |                                        |
       |<-- sync-response (targeted) --- Bob ---|
       |<-- sync-response (targeted) --- Charlie| (thundering herd)
       |                                        |
       |    [applies first response]            |
       |    [may apply second response,         |
       |     overwriting first]                 |
       |                                        |
       |    [_flushSyncBuffer: replay buffered  |
       |     edits through normal CRDT path]    |
       |    [_isSyncing = false]                |
```

### Issues

**S1. Thundering herd (P2):** Already described in section 2.5. All editors respond to every sync-request. Fix: elect a single responder (e.g., lexicographically smallest playerId, or first to claim).

**S2. Version map clobbered (P2):** Already described in section 2.5. `loadFromJson` clears before loading. If multiple sync-responses arrive, only the last one's version map survives.

**S3. 5-second timeout may be too short (P3):** `requestSync()` at `map_sync_service.dart:562` uses a 5-second timeout. On poor connections or large maps, the sync-response may arrive late. After timeout, `_flushSyncBuffer()` runs and `_isSyncing` becomes false. A late sync-response would then be processed by `_handleSyncResponse` which checks `if (!_isSyncing) return` (line 672), so it would be silently dropped. This is correct (no state corruption) but means the late-joiner operates without the full state. Subsequent edits from others will be applied normally, but the joiner's initial view may be incomplete.

**S4. No deduplication of sync-responses (P3):** If two sync-responses arrive before the completer fires, both are processed sequentially. The second one's `_versionMap.loadFromJson()` clears the version entries from the first, potentially allowing ops that were correctly rejected under the first response to pass under the second. Again, convergence is eventually restored by normal CRDT resolution, but there may be transient visual flicker.

---

## 5. Additional Issues from Phase 1 Context

### M1. `OpLayer.values.byName` throws on unknown layer (P1 -- High)

**File:** `map_edit_op.dart:65`, `cell_version_map.dart:77`

**Evidence:** `OpLayer.values.byName(json['layer'])` throws `ArgumentError` if the string doesn't match any enum value. If a new layer is added in a future version and an older client receives an op with that layer name, the entire `_onDataReceived` handler crashes. Since `_onDataReceived` is the sole listener on the LiveKit data stream (map_sync_service.dart:28-31), an uncaught exception kills the sync loop for that client.

**Severity:** P1 -- a single malformed or forward-incompatible op permanently breaks the client's sync.

**Recommendation:** Wrap in try-catch or use a `tryByName` pattern that returns null for unknown layers, logging a warning and skipping the op.

### M2. `toJson()` null ambiguity for old/new values (P3 -- Low)

**File:** `map_edit_op.dart:79-80`

**Evidence:** The serialization uses `if (oldValue != null) 'old': oldValue` -- when `oldValue` is null, the `'old'` key is omitted entirely. On deserialization (`fromJson` at line 66), `json['old']` returns null for both "key absent" and "key present with null value". This means the round-trip is lossy: a `MapEditOp` with `oldValue: null, newValue: null` serializes to `{'x': ..., 'y': ..., 'layer': ...}`, and deserializes back with both values null.

In practice, `oldValue: null` and "no old value" are semantically identical (both mean "cell was empty"), so this is not a functional bug. But if the semantics ever diverge (e.g., null meaning "unknown" vs "empty"), this would become a real issue.

---

## 6. Priority-Ranked Issues

| # | ID | Severity | Description | File:Line |
|---|----|----------|-------------|-----------|
| 1 | M1 | **P1** | `OpLayer.values.byName` throws on unknown layer, killing sync loop | `map_edit_op.dart:65`, `cell_version_map.dart:77` |
| 2 | S1 | **P2** | Thundering herd: all editors respond to sync-request with full snapshots | `map_sync_service.dart:660-669` |
| 3 | S2 | **P2** | Version map clobbered by `loadFromJson` clear-before-load on multiple sync-responses | `cell_version_map.dart:71-72` |
| 4 | D1 | **P2** | Compound ops within a batch partially apply, causing cross-layer inconsistency (wall without barrier, or barrier without wall) | `map_sync_service.dart:596-601` |
| 5 | U1 | **P3** | Undo unconditionally overrides remote edits at same cell | `undo_manager.dart:59-66` (by design) |
| 6 | U2 | **P3** | Redo replays with stale `oldValue`, so subsequent undo restores wrong state | `undo_manager.dart:72-94` |
| 7 | S3 | **P3** | 5-second sync timeout may drop responses on slow connections | `map_sync_service.dart:562` |
| 8 | S4 | **P3** | No deduplication of sync-responses; multiple responses processed sequentially | `map_sync_service.dart:671-767` |
| 9 | M2 | **P3** | `toJson` omits null old/new keys, making absent vs null indistinguishable | `map_edit_op.dart:79-80` |
| 10 | -- | **P4** | Lamport clock sits at remote value (not remote+1) until next local op | `undo_manager.dart:31-33` (standard behavior) |

---

## 7. Test Coverage Assessment

The existing tests are well-structured:

- **`cell_version_map_test.dart`**: Covers first write, higher/lower counter, tie-breaking, layer independence, serialization round-trip, and two fuzz tests (50 ops, 10 orderings each). Good coverage.

- **`undo_manager_test.dart`**: Covers counter increment, clock advance, push/undo/redo cycle, redo stack clearing, multiple undo/redo, empty stack handling, and clear. Good coverage.

- **`map_edit_op_test.dart`**: Covers serialization round-trip (string and map values), null omission, inverse, equality. Good coverage.

- **`map_sync_service_test.dart`**: Covers local edits (publish, skip no-op), remote edits (apply, ignore own, LWW higher/lower), undo/redo (revert, re-apply, notifier), late-join sync (request, respond), wall sync (paint, remote, cascade, snapshot, erase, lintel). Good coverage.

**Missing test coverage:**

1. No test for the partial-application scenario (D1) -- a batch where some ops win and others lose.
2. No test for multiple sync-responses arriving (S2 + S4).
3. No test for sync timeout behavior (S3).
4. No test for unknown `OpLayer` in deserialization (M1).
5. No test for concurrent undo with remote edits on the same cell (U1).

---

## 8. Summary

The CRDT implementation is **fundamentally sound**. The three core algebraic laws (commutativity, associativity, idempotence) all hold for the LWW-Register at the per-cell level. The Lamport clock is correctly maintained. Terrain and wall autotiling are deterministic. Version vector coverage is complete.

The main risks are operational rather than algebraic:
- **M1** (P1) is the most urgent: a single forward-incompatible op kills a client's sync permanently.
- **S1/S2** (P2) are the sync protocol's thundering herd and version-map clobbering, which cause bandwidth waste and transient inconsistency.
- **D1** (P2) is the partial-application of compound batches, which can leave cross-layer state inconsistent.

The undo/redo design is intentionally aggressive (undo always wins over remote edits), which is a defensible choice for a small-team collaborative editor but should be documented as an explicit design decision.
