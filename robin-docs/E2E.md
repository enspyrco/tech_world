# E2E Event Tests — What's Being Tested

## Overview

77 tests in `test/e2e/` verify the event-sink pipeline end-to-end: dispatch → sink capture → serialization → assertion. No mocks — real services against `FakeFirebaseFirestore`, real `ProximityService`, real `castSuccessEvents`/`performCast`.

Run: `flutter test test/e2e/`

## The Capture Sink Pattern

Every test registers a `List<AppEvent>` as a sink, runs a scenario, and asserts on the list:

```dart
final captured = <AppEvent>[];
registerSink(captured.add);
// ... run scenario ...
expect(captured.map((e) => e.runtimeType).toList(), [WordLearned, ChallengeCompleted]);
```

No mocks needed. The event sequence IS the specification.

## Test Groups

### 1. Pipeline Smoke (3 tests)

Fires all 34 event types through dispatch and verifies:
- All 34 arrive at the capture sink
- Every event serializes to valid JSON with `type` and `timestamp` fields
- All 34 `type` strings are unique (no collisions)
- JSONL lines contain no embedded newlines

### 2. Per-Type Serialization (34 tests)

One test per event type verifying every field round-trips correctly through `toJson()`. Enum-valued fields get one test per variant:

| Event | Tests | What's checked |
|-------|-------|----------------|
| `WordLearned` | 1 | wordId, challengeId |
| `ChallengeCompleted` | 1 | wire-format challengeId |
| `SpellCastFailed` | 4 | 3 reason variants + null transcript omission |
| `DoorUnlocked` | 1 | doorX, doorY |
| `RemoteDoorUnlocked` | 1 | doorX, doorY, type string |
| `PlayerMoved` | 1 | destX, destY |
| `TerminalOpened` | 1 | challengeId, terminalX, terminalY |
| `TerminalClosed` | 1 | type-only (no data fields) |
| `AvatarSelected` | 1 | avatarId |
| `MediaEnabled` | 1 | type-only |
| `RoomJoined` | 1 | roomId, roomName |
| `RoomLeft` | 2 | roomId present + roomId null omission |
| `RoomCreated` | 1 | roomId, roomName |
| `RoomMapSaved` | 1 | type string |
| `RoomDeleted` | 1 | roomId, roomName |
| `UserSignedIn` | 1 | userId, displayName |
| `UserSignedOut` | 1 | type-only |
| `ProfileUpdated` | 1 | displayName |
| `CodeSubmitted` | 4 | 3 result variants + fromWire parsing (pass/PASS/fail/null/garbage) |
| `MapEditorEntered` | 1 | mapId, mapName |
| `MapEditorExited` | 2 | applied=true + applied=false |
| `MapEdited` | 8 | all 8 MapEditAction variants (paintTile, paintWall, eraseWall, paintTerrain, eraseTerrain, paintTileRef, undo, redo) |
| `PlayerEnteredProximity` | 1 | playerId |
| `PlayerLeftProximity` | 1 | playerId |
| `BotJoined` | 1 | identity (including agent-* format) |
| `BotLeft` | 1 | type-only |
| `ScreenShareToggled` | 2 | started=true + started=false |
| `LiveKitConnected` | 1 | roomName |
| `LiveKitDisconnected` | 2 | reason present + reason null omission |
| `GroupMessageSent` | 2 | messageId + challengeId present + challengeId null omission |
| `DmSent` | 1 | peerId, conversationId |
| `HelpRequested` | 1 | challengeId |
| `BotSpoke` | 2 | both BotSpokeContext variants (group, help) |
| `AppLogRecord` | 7 | 4 severity variants + error/stackTrace present + error/stackTrace null omission |

### 3. Cast Completion E2E (7 tests)

Real code paths through `applyCastSuccessEffects` and `performCast` with `FakeFirebaseFirestore`:

| Test | Events expected |
|------|-----------------|
| Successful cast | WordLearned → ChallengeCompleted |
| performCast pass (after learning word) | WordLearned → ChallengeCompleted |
| performCast fail (word not learned) | empty |
| Wrong door cast | empty |
| No-match cast | empty |
| Null transcript cast | empty |
| All 18 prompt challenges | 2 events each (WordLearned + ChallengeCompleted) |
| Idempotent replay | still emits 2 events |

### 4. Proximity E2E (7 tests)

Real `ProximityService` with simulated player positions:

| Test | Events expected |
|------|-----------------|
| Player enters range | PlayerEnteredProximity |
| Player leaves range | PlayerLeftProximity |
| Player far away | empty |
| Player disconnects (removed from map) | PlayerLeftProximity |
| Multiple players (2 near, 1 far) | 2× PlayerEnteredProximity |
| Stay in range (no movement) | no re-fire |
| Enter → leave → re-enter | 3 events in order |

### 5. Session Lifecycle (2 tests)

Full gameplay sequences verified as ordered event lists:

**Full session (17 events):**
```
user_signed_in → avatar_selected → room_joined → livekit_connected →
media_enabled → bot_joined → player_moved → player_entered_proximity →
terminal_opened → code_submitted → terminal_closed → door_unlocked →
player_left_proximity → bot_left → livekit_disconnected → room_left →
user_signed_out
```

**Map editing session (11 events):**
```
map_editor_entered → paintTile → paintWall → paintTerrain → undo →
redo → eraseWall → eraseTerrain → paintTileRef → room_map_saved →
map_editor_exited
```
Asserts all 8 `MapEditAction` variants appear.

## Fire All Events CLI

`test/e2e/fire_all_events.dart` — fires all 34 event types and prints JSONL to stdout:

```bash
flutter test test/e2e/fire_all_events.dart 2>/dev/null | grep '^{' | jq .
```

## What's NOT Tested (and why)

Events dispatched from LiveKit-dependent code (ChatService, TechWorld, LiveKitService) can't be triggered without mocking the LiveKit SDK. These events are tested for serialization (per-type tests) but not for dispatch-site correctness:

- `BotJoined`/`BotLeft` — dispatched inside `ChatService._trackBotPresence` (LiveKit participant stream)
- `BotSpoke` — dispatched inside `ChatService._handleMessage` (LiveKit data channel)
- `GroupMessageSent`/`DmSent`/`HelpRequested` — dispatched inside ChatService send methods (LiveKit publish)
- `PlayerMoved` — dispatched inside `TechWorld.onTapDown` (Flame component)
- `TerminalOpened`/`TerminalClosed` — dispatched inside TechWorld (Flame component)
- `DoorUnlocked`/`RemoteDoorUnlocked` — dispatched inside TechWorld (Flame component)
- `LiveKitConnected`/`LiveKitDisconnected` — dispatched inside LiveKitService
- `RoomJoined`/`RoomLeft` — dispatched inside `_MyAppState` (widget lifecycle)
- `UserSignedIn`/`UserSignedOut` — dispatched inside `_MyAppState` (Firebase auth)
- `ScreenShareToggled`/`AvatarSelected`/`ProfileUpdated` — dispatched inside widgets
- `MapEditorEntered`/`MapEditorExited` — dispatched inside TechWorld
- `MapEdited` — dispatched inside MapSyncService (needs LiveKit for publishing)
- `MediaEnabled` — dispatched inside RoomSession (needs LiveKit)
- `CodeSubmitted`/`RoomCreated`/`RoomMapSaved`/`RoomDeleted` — dispatched inside `_MyAppState`

These would require widget tests (`pumpWidget`) or LiveKit mocks. The session lifecycle tests verify that the event SEQUENCE is coherent even though they dispatch manually rather than through code paths.

## Key Files

| File | Purpose |
|------|---------|
| `test/e2e/event_pipeline_test.dart` | 77 E2E tests |
| `test/e2e/fire_all_events.dart` | CLI — fires all 34 events to stdout as JSONL |
