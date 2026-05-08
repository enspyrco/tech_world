# Phase 2: Distributed State Consistency Audit

**Auditor:** Claude (Phase 2 sub-agent)
**Date:** 2026-05-06
**Scope:** All LiveKit data channel topics, Firestore state, and in-memory game state across simultaneous clients
**Status:** READ-ONLY audit -- no code changes

---

## Summary Statistics

| Metric | Value |
|--------|-------|
| Scenarios analyzed | 10 |
| CRITICAL findings | 2 |
| HIGH findings | 4 |
| MEDIUM findings | 3 |
| LOW findings | 1 |
| LiveKit topics audited | 14 (of ~25 total) |
| State stores audited | 4 (in-memory, Firestore, CRDT version map, Lamport clock) |

---

## Scenario Analysis

### DS-1: Door Unlock Has No Client-Side Subscriber (CRITICAL)

**Description:** When Player A unlocks a door, `unlockDoor()` broadcasts a `door-unlock` message over LiveKit (line 1921-1928 of `tech_world.dart`). However, **no client subscribes to the `door-unlock` topic anywhere in the codebase**. The only match for "door-unlock" as a topic string is the publish call itself.

**Code references:**
- `lib/flame/tech_world.dart:1910-1931` -- `unlockDoor()` publishes `{'type': 'door-unlock', 'doorX': ..., 'doorY': ...}` on topic `door-unlock`
- Grep for `door-unlock` across all `.dart` files returns only the publish site and a comment in `cast_effects.dart`

**Current behavior:** Door unlocks are purely local. Player A sees the door open; all other players see it locked. Their pathfinding grid still treats the door position as a barrier.

**Failure mode:** Players B, C, etc. cannot walk through a door that Player A unlocked. The game world is permanently inconsistent between clients for the rest of the session. Late-joiners also never learn about prior unlocks because there is no state-sync protocol for door state.

**Severity:** **CRITICAL**

**Recommended fix:** Add a `dataReceived` listener filtering for topic `door-unlock` in `connectToLiveKit()`. On receipt, look up the `DoorData` at `(doorX, doorY)` in `currentMap.value.doors`, call `door.isUnlocked = true`, remove the barrier via `_barriersComponent.removeBarrierAt()`, and recompute `nearbyLockedDoor`. Also include door state in the late-join sync payload.

---

### DS-2: Position Updates Use Unreliable Delivery With No Fallback (CRITICAL)

**Description:** Position updates are published with `reliable: false` (line 480 of `livekit_service.dart`). There is no dead-reckoning, no periodic heartbeat, and no "last known position" reconciliation. If a position packet is dropped, the remote player's sprite stays wherever its last received path ended.

**Code references:**
- `lib/livekit/livekit_service.dart:467-482` -- `publishPosition()` uses `reliable: false`
- `lib/flame/tech_world.dart:1127-1161` -- `positionReceived` listener applies paths
- `lib/flame/tech_world.dart:1828-1848` -- `onTapDown` publishes position on tap

**Current behavior:** Each tap publishes the full path (list of waypoints + directions). If the UDP packet carrying the path is lost, the remote player appears stuck at the end of their previous path. No subsequent packet corrects this because positions are event-based (path-starts), not state-based (current-position snapshots).

**Failure mode:** On any single dropped packet, a remote player appears frozen at a stale position indefinitely. This also breaks proximity detection (audio, video bubbles, door proximity) for that player, since `ProximityService` and the bubble system use `miniGridPosition` from the stale component.

**Severity:** **CRITICAL**

**Recommended fix:** Two mitigations: (1) Periodic reliable position heartbeat (e.g., every 2 seconds) that sends just the current grid position -- acts as a correction for any missed path updates. (2) The path listener should store a "last-known-good" timestamp per player and flag players as "possibly stale" after a timeout, triggering a position request.

---

### DS-3: CRDT Sync-Request Thundering Herd (HIGH)

**Description:** When a late-joining editor sends a `sync-request` on the `map-edit-sync` topic, **all editors in the room** see it and respond with a full state snapshot (line 660-668 of `map_sync_service.dart`). The `_handleSyncRequest` method is targeted only by the `destinationIdentities: [requesterId]` on the response, but every editor builds and sends a full snapshot.

**Code references:**
- `lib/map_editor/map_sync_service.dart:550-565` -- `requestSync()` broadcasts `sync-request`
- `lib/map_editor/map_sync_service.dart:660-668` -- `_handleSyncRequest()` builds and sends full snapshot

**Current behavior:** With N editors, a single sync-request triggers N full snapshots (each containing structure, floor, objects, terrain, walls, and version data for the entire grid). Only the first response is needed; subsequent ones overwrite state redundantly.

**Failure mode:** (1) Bandwidth waste -- N full grid snapshots when only 1 is needed. (2) The receiving client applies each snapshot sequentially in `_handleSyncResponse()`, but only completes the `_syncCompleter` once. Subsequent snapshots still call `_handleSyncResponse()` and overwrite state, potentially reverting edits that arrived in the sync buffer between the first and Nth snapshot. (3) The final sync state may reflect a snapshot from an editor whose state was staler than the first responder's.

**Severity:** **HIGH**

**Recommended fix:** Either (1) have only the editor with the highest Lamport clock respond, or (2) add a guard in `_handleSyncResponse()` that ignores responses after the first one (set `_isSyncing = false` immediately after the first response is applied).

---

### DS-4: Sync Buffer May Reject Valid Edits (HIGH)

**Description:** During late-join sync, incoming `map-edit` messages are buffered in `_syncBuffer` and replayed after the sync snapshot arrives (line 578-579 and 769-775 of `map_sync_service.dart`). However, the snapshot includes the version map at the time the snapshot was built. If a buffered edit has a counter lower than the snapshot's version for that cell, `shouldApply()` returns `false` and the edit is silently dropped.

**Code references:**
- `lib/map_editor/map_sync_service.dart:576-579` -- edits buffered during sync
- `lib/map_editor/map_sync_service.dart:769-775` -- `_flushSyncBuffer()` replays via `_onRemoteEdit`
- `lib/map_editor/crdt/cell_version_map.dart:21-31` -- `shouldApply()` compares counter+playerId

**Current behavior:** The version map is loaded from the snapshot (line 754-755), then buffered edits are replayed. An edit made by another player *during* the sync window but *before* the snapshot was built will have a counter lower than the snapshot's version and be rejected -- even though it's a newer edit that happened to arrive out of order.

**Failure mode:** Edits concurrent with sync can be silently lost on the joining client, causing permanent divergence with other editors. The editing client sees the edit; the joining client does not.

**Severity:** **HIGH**

**Recommended fix:** Apply the snapshot's version map, then only reject buffered edits that are strictly older than the snapshot (compare counter against the snapshot's reported clock, not per-cell versions). Alternatively, track the snapshot's Lamport clock and only apply buffered edits with counters strictly above it.

---

### DS-5: Map Switching is Not Broadcast to Other Players (HIGH)

**Description:** When a player selects a different map via `MapSelector`, it calls `techWorld.loadMap(map)` (line 124-127 of `map_selector.dart`). `loadMap()` updates the local game world and notifies the bot via `publishMapInfo()` (line 1819), but **does not notify other human players**. There is no `map-switch` topic and no listener for map changes from other players.

**Code references:**
- `lib/widgets/map_selector.dart:122-127` -- `onSelected` calls `loadMap()`
- `lib/flame/tech_world.dart:1771-1825` -- `loadMap()` calls `publishMapInfo()` only to bots

**Current behavior:** Player A switches to a different map; Players B and C remain on the old map. Each player sees different barriers, terminals, doors, and spawn points. Position coordinates become meaningless across different maps.

**Failure mode:** Complete game state divergence. Players occupy the same LiveKit room but inhabit different game worlds. Position updates still arrive but refer to positions on different maps, causing ghost players walking through walls or teleporting to impossible locations.

**Severity:** **HIGH** (in rooms where map switching is available; in the Wizard's Tower public room the map is fixed, reducing practical impact)

**Recommended fix:** Broadcast a `map-switch` message containing the map data (or room ID). Other clients should listen and call `loadMap()` when they receive it. Alternatively, lock map switching to the room owner only or require consensus.

---

### DS-6: Avatar Selection Has No Uniqueness Constraint (HIGH)

**Description:** Avatar selection is per-player with no server-side or consensus-based uniqueness enforcement. Each player picks from the same set of 3 predefined avatars (`NPC11`, `NPC12`, `NPC13`).

**Code references:**
- `lib/avatar/predefined_avatars.dart:4-8` -- only 3 avatars, no deduplication
- `lib/avatar/avatar_selection_screen.dart` -- local selection, no check against other players
- `lib/livekit/livekit_service.dart:157-164` -- `publishAvatar()` broadcasts choice but doesn't validate uniqueness

**Current behavior:** Multiple players can select the same avatar. Avatar broadcasts are fire-and-forget; there is no rejection or conflict resolution. The `publishAvatar()` method uses reliable delivery, but only to inform -- not to coordinate.

**Failure mode:** Two or more players appear as identical sprites. With only 3 avatars this is almost guaranteed in any room with 4+ players. While not a state-consistency bug per se, it undermines the game's visual identity system.

**Severity:** **MEDIUM** (cosmetic, but directly affects multiplayer UX)

**Recommended fix:** Either expand the avatar pool significantly, or implement server-side avatar reservation (e.g., a Firestore document per room tracking claimed avatars with a transaction-based claim/release).

---

### DS-7: Bot Disconnection During Challenge Evaluation (MEDIUM)

**Description:** Code challenge evaluation (`onSubmit` in `main.dart:1284-1320`) and prompt challenge evaluation (`ChatEvaluationEngine`) both send messages to the bot and await a response with a 30-second timeout. If the bot disconnects during evaluation, the `Completer` is never completed and eventually times out.

**Code references:**
- `lib/main.dart:1284-1320` -- code challenge submission waits for `chatService.sendMessage()`
- `lib/chat/chat_service.dart:419-447` -- 30-second timeout on `completer.future`
- `lib/prompt/chat_evaluation_engine.dart:18-42` -- prompt evaluation via same `sendMessage()`

**Current behavior:** On bot disconnect, the 30-second timeout fires, a "taking a while" system message appears, and `botStatusNotifier` is reset. The player's code/prompt submission is lost -- there's no retry mechanism or queuing.

**Failure mode:** The player's submission is silently lost. The challenge remains incomplete even if the code/prompt was correct. The player must re-submit after the bot reconnects, but may not realize the evaluation was lost vs. genuinely failed.

**Severity:** **MEDIUM**

**Recommended fix:** (1) Detect bot disconnect mid-evaluation and show a clear "bot disconnected, will retry" message. (2) Queue the pending submission and re-send when the bot returns. (3) The `_pendingMessages` map should be drained on bot disconnect with an explicit "bot left" error rather than waiting for timeout.

---

### DS-8: Room Deletion During Gameplay Has No Notification (MEDIUM)

**Description:** `RoomService.deleteRoom()` (line 74 of `room_service.dart`) deletes the Firestore document but does not notify connected players. There is no Firestore real-time listener on the room document and no LiveKit topic for room deletion.

**Code references:**
- `lib/rooms/room_service.dart:74` -- `deleteRoom()` is a simple Firestore delete
- `lib/main.dart:528-567` -- `_leaveRoom()` only runs when triggered by the UI or connection loss

**Current behavior:** If the room owner deletes a room while other players are in it, those players continue playing normally (LiveKit room persists independently of Firestore). When they eventually leave and try to rejoin, the room won't exist.

**Failure mode:** Players in a deleted room have a degraded but functional experience. Their progress (Firestore writes to `users/{uid}`) continues working since it's not tied to the room document. However, any attempt to save map edits (`updateRoomMap`) will fail silently or throw. Chat history persistence to the now-deleted room's Firestore path may also fail.

**Severity:** **MEDIUM**

**Recommended fix:** Either (1) broadcast a `room-deleted` message on LiveKit and force-kick connected players, or (2) set up a Firestore real-time listener on the room document and navigate to lobby on deletion.

---

### DS-9: Late-Join State Sync Gaps (MEDIUM)

**Description:** When a player joins a room, `connectToLiveKit()` handles existing participants (line 1172-1175 of `tech_world.dart`) and avatar re-publishing (line 1270-1273). However, several state categories are never synced to late-joiners:

1. **Door state** -- no sync. Unlocked doors appear locked to joiners.
2. **Player positions** -- joiners create components at `Vector2.zero()` or the spawn point. They don't know where existing players actually are until those players move again.
3. **Map editor state** -- handled by `requestSync()` if the joiner enters editor mode, but not proactively pushed.
4. **Current map** -- late-joiners load the room's Firestore map, which may differ from runtime map switches.
5. **Challenge completion state** -- loaded from Firestore per-user, so this is actually correct.

**Code references:**
- `lib/flame/tech_world.dart:1104-1277` -- `connectToLiveKit()` setup
- `lib/flame/tech_world.dart:1142-1157` -- player component created from first position update (at spawn point fallback)
- No topic for broadcasting current door state or current position on join

**Current behavior:** Late-joiners see all doors locked (even if some were unlocked during the session), see all players at spawn or `(0,0)` until they move, and may be on a different map if someone used `MapSelector`.

**Failure mode:** Immediate visual inconsistency on join. Gradually self-corrects for position (when players move) but never self-corrects for doors or maps.

**Severity:** **MEDIUM** (partially overlaps with DS-1 and DS-5; fixing those will largely resolve this)

**Recommended fix:** Implement a "state sync on join" protocol: the joining player sends a `state-request`, and the longest-connected player responds with current door states, current map ID, and all player positions. This could share the `map-edit-sync` infrastructure.

---

### DS-10: Chat Message Ordering and Deduplication (LOW)

**Description:** Chat messages use reliable delivery (default in `publishJson()`). Message IDs are `DateTime.now().millisecondsSinceEpoch.toString()`, which provides millisecond-granularity ordering and reasonable uniqueness. Deduplication uses a `LinkedHashSet<String>` capped at 500 entries (line 57-59 of `chat_service.dart`).

**Code references:**
- `lib/chat/chat_service.dart:363` -- message ID is `DateTime.now().millisecondsSinceEpoch`
- `lib/chat/chat_service.dart:57-61` -- deduplication set with 500-entry cap
- `lib/chat/chat_service.dart:132-141` -- `_markSeen()` trims oldest half when cap is hit

**Current behavior:** Messages are ordered by arrival time at each client (inserted into `_messages` list in receive order). Reliable LiveKit delivery ensures FIFO ordering within a single sender. Cross-sender ordering depends on network latency. Deduplication prevents the same message from appearing twice.

**Failure mode:** (1) Very long sessions (250+ round-trips) could overflow the deduplication set after trimming, allowing ancient message IDs to be "unseen" and potentially reprocessed if somehow re-delivered. This is unlikely with reliable delivery. (2) Two messages sent in the same millisecond from different clients could theoretically share an ID, but the dedup set prevents the second from being processed -- silently dropping a legitimate message. In practice, this is extremely unlikely.

**Severity:** **LOW**

**Recommended fix:** Use UUIDs for message IDs instead of timestamps to eliminate the (theoretical) collision risk. Increase the dedup set cap or switch to a time-based eviction strategy.

---

## Priority-Ranked Issue List

| Rank | ID | Severity | Summary | Effort |
|------|----|----------|---------|--------|
| 1 | DS-1 | CRITICAL | Door unlock broadcasts have no subscriber -- doors never sync | Small (add listener + handler) |
| 2 | DS-2 | CRITICAL | Position uses unreliable delivery with no correction mechanism | Medium (add heartbeat + stale detection) |
| 3 | DS-5 | HIGH | Map switching is local-only -- no broadcast to other players | Medium (add topic + listener + conflict resolution) |
| 4 | DS-3 | HIGH | CRDT sync thundering herd -- N editors all send full snapshots | Small (guard against multiple responses) |
| 5 | DS-4 | HIGH | Sync buffer drops valid edits when their counter < snapshot version | Medium (change flush strategy) |
| 6 | DS-6 | HIGH | No avatar uniqueness constraint with only 3 avatars | Small (expand pool) or Medium (reservation system) |
| 7 | DS-7 | MEDIUM | Bot disconnect loses in-flight challenge submissions | Medium (queue + retry) |
| 8 | DS-8 | MEDIUM | Room deletion has no notification to connected players | Small (Firestore listener or kick message) |
| 9 | DS-9 | MEDIUM | Late-join state sync misses doors, positions, and map identity | Medium (join-sync protocol) |
| 10 | DS-10 | LOW | Millisecond-precision message IDs have theoretical collision risk | Small (use UUID) |

---

## Cross-Cutting Observations

### No Authoritative Server

All game state lives in clients. There is no game server -- LiveKit provides transport only. This means every state-consistency problem must be solved client-side, typically via:
- CRDT (map editing -- well-implemented)
- Fire-and-forget broadcast (position, avatar, door unlock -- partially broken)
- Firestore (progress, spellbook, rooms -- reliable but not real-time)

The CRDT layer for map editing is the most mature distributed protocol in the codebase. Door state, position state, and map identity all lack equivalent protocols.

### Pattern: Publish Without Subscribe

DS-1 (door-unlock) is the clearest example, but the pattern of "broadcast a message and assume all clients handle it" appears frequently. The codebase would benefit from a protocol registry that pairs each publish with a required subscribe, enforced by test or lint.

### Rooms vs. LiveKit Rooms

A "room" in Tech World is a Firestore document (map data + ownership). A LiveKit room is the real-time communication channel. These are loosely coupled: the LiveKit room name is the Firestore document ID. But their lifecycles are independent -- deleting the Firestore document does not disconnect LiveKit participants, and LiveKit disconnection does not affect the Firestore document.
