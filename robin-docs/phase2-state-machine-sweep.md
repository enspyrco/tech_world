# Phase 2: State Machine Sweep

Read-only audit of all state machines in Tech World, covering explicit enums,
implicit boolean machines, transition maps, invariants, and illegal state
analysis.

---

## 1. Inventory of All State Machines

### 1a. Explicit Enum-Based State Machines (with transitions)

| # | Enum | File | Values | Is State Machine? |
|---|------|------|--------|-------------------|
| 1 | `WireStatus` | `lib/widgets/wire_states.dart` | pending, active, complete, error | **Yes** -- linear lifecycle |
| 2 | `BotStatus` | `lib/flame/components/bot_status.dart` | absent, idle, thinking | **Yes** -- presence + activity |
| 3 | `ConnectionResult` | `lib/livekit/livekit_service.dart` | connected, alreadyConnected, tokenNetworkError, tokenAuthError, tokenUnknownError, roomFailed | **No** -- return value, not a state |
| 4 | `DreamfinderState` | `lib/flame/shared/dreamfinder_state.dart` | working, surprised, idle, walk{Down,Left,Up,Right,DownLeft,DownRight,UpLeft,UpRight} | **Yes** -- animation FSM |
| 5 | `AuthMode` | `lib/auth/auth_gate.dart` | login, register | **Yes** -- UI toggle |
| 6 | `_MicState` | `lib/spellbook/speech_cast_overlay.dart` | idle, listening, resolving | **Yes** -- cast lifecycle |
| 7 | `ServiceStatus` | `lib/infra/infra_health_state.dart` | up, warn, down, unknown | **Yes** -- per-service health |

### 1b. Enums That Are NOT State Machines (value sets / classifiers)

| Enum | File | Purpose |
|------|------|---------|
| `Wire` | `lib/widgets/wire_states.dart` | Identifier for parallel join wires (tilesets, server, camera, chat, gameReady) |
| `Difficulty` | `lib/editor/challenge.dart` | Challenge difficulty tier |
| `CodeChallengeId` | `lib/editor/challenge.dart` | Closed set of 23 code challenges |
| `PromptChallengeId` | `lib/prompt/prompt_challenge.dart` | Closed set of 18 prompt challenges |
| `EvaluationTier` | `lib/prompt/prompt_challenge.dart` | How a challenge is evaluated (deterministic/structural/behavioral) |
| `CastFeedback` | `lib/prompt/cast_result.dart` | Qualitative cast outcome (unclear/fizzled/backfired/resonates) |
| `SpellSchool` | `lib/prompt/spell_school.dart` | 6 schools of magic |
| `SpellEffectType` | `lib/spellbook/spell_effect.dart` | Visual effect categories |
| `WordId` | `lib/spellbook/word_of_power.dart` | 18 words of power |
| `SpellElement` | `lib/spellbook/word_of_power.dart` | 6 elemental affinities |
| `WordRole` | `lib/spellbook/word_of_power.dart` | Grammatical role (substance/action/modifier) |
| `ConversationType` | `lib/chat/conversation.dart` | group vs dm |
| `Direction` | `lib/flame/shared/direction.dart` | 8 compass directions + none |
| `TileType` | `lib/map_editor/map_editor_state.dart` | Grid cell type |
| `EditorTool` | `lib/map_editor/map_editor_state.dart` | Active painting tool |
| `ActiveLayer` | `lib/map_editor/map_editor_state.dart` | Which layer is being edited |
| `OpLayer` | `lib/map_editor/crdt/map_edit_op.dart` | CRDT operation target layer |
| `MapAlgorithm` | `lib/flame/maps/generators/map_generator.dart` | Procedural generation algorithm |
| `TerminalMode` | `lib/flame/maps/terminal_mode.dart` | Terminal interaction type (code/prompt) |
| `TmxWarningKind` | `lib/flame/maps/tmx_importer.dart` | TMX import warning categories |
| `ParticipantTrackType` | `lib/livekit/widgets/participant_info.dart` | Video track type |
| `StatsType` | `lib/livekit/widgets/participant_stats.dart` | Participant stats category |
| `SimulateScenarioResult` | `lib/livekit/exts.dart` | Test simulation scenarios |

### 1c. Sealed Class Hierarchies (algebraic state machines)

| Sealed Class | File | Variants |
|--------------|------|----------|
| `DoorCastResult` | `lib/spellbook/door_cast_result.dart` | CastPass, DoorCastNoMatch, DoorCastNotLearned, CastWrongDoor |
| `FreeCastResult` | `lib/spellbook/free_cast_result.dart` | FreeCastNoMatch, FreeCastNotLearned, CastComboKnown, CastComboKnownPartial, CastComboNovel |
| `AuthUser` subclasses | `lib/auth/auth_user.dart` | AuthUser, SignedOutUser, PlaceholderUser |

### 1d. Implicit Boolean-Flag State Machines

| Location | Flags | Complexity |
|----------|-------|------------|
| `_MyAppState` (main.dart) | 12+ boolean/nullable fields | 2^12 theoretical, ~8 valid states |
| `DreamfinderComponent` | 4 booleans | 2^4=16 theoretical, ~5 valid |
| `LiveKitService` | 2 booleans (`_isConnecting`, `_isConnected`) | 2^2=4, 3 valid |
| `TechWorld` | `_isLoadingMap` + `mapEditorActive` + `_liveKitService?` nullability | Compound |

---

## 2. Transition Maps

### 2a. WireStatus (per-wire lifecycle)

```
                 +---> error
                 |
  pending ---> active ---> complete
```

**Transitions:**
- `pending -> active`: `WireStates.start(wire)` -- wire operation begins
- `active -> complete`: `WireStates.complete(wire)` -- wire operation succeeds
- `active -> error`: `WireStates.error(wire)` -- wire operation fails
- `pending -> complete`: **also possible** -- `complete()` called directly on wires
  skipped due to server failure (camera/chat marked complete without going active)

**Guard:** `allComplete` checks all 5 wires reached `complete`.

**Issue P2-W1 [LOW]:** No transition from `error -> active` (retry). Once a wire
errors, the only recovery is to leave the room and rejoin. This is acceptable for
v1 but a retry mechanism would improve UX.

**Issue P2-W2 [LOW]:** `pending -> complete` bypass (lines 397-399, 412-413 of
main.dart) -- when LiveKit connection fails, dependent wires (camera, chat) are
marked `complete` without ever being `active`. This is intentional (the overlay
must dismiss) but semantically odd. The overlay treats "complete" as "done" not
"succeeded", which is correct behavior but confusing naming.

---

### 2b. BotStatus (global ValueNotifier)

```
  absent <---> idle <---> thinking
    ^                        |
    |________________________|
```

**Transitions:**
- `absent -> idle`: Bot participant joins LiveKit room
- `idle -> thinking`: Bot begins processing a request
- `thinking -> idle`: Bot finishes processing
- `idle -> absent`: Bot participant leaves room
- `thinking -> absent`: Connection lost (forced by main.dart line 589:
  `botStatusNotifier.value = BotStatus.absent`)

**Invariant:** `BotStatus != absent => bot participant exists in LiveKit room`

**Issue P2-B1 [MEDIUM]:** BotStatus is a *global* `ValueNotifier` (singleton in
`bot_status.dart`), not scoped per room. If the user leaves room A where the bot
was `thinking` and joins room B, the stale `thinking` state persists until someone
explicitly resets it. The `_handleConnectionLost` in main.dart resets to `absent`,
but `_leaveRoom` does NOT reset BotStatus. This means:

1. User is in Room A, bot is `thinking`
2. User calls `_leaveRoom()` (line 528)
3. `_leaveRoom` disposes LiveKit but never touches `botStatusNotifier`
4. User joins Room B -- `botStatusNotifier.value` is still `thinking`
5. Chat panel shows bot as "thinking" even though no bot is present

**Fix:** Add `botStatusNotifier.value = BotStatus.absent;` to `_leaveRoom()`.

---

### 2c. DreamfinderState (animation FSM)

```
                         noticePlayer()
  working ─────────────────────────────> surprised
    ^                                       |
    |  _resetWanderCooldown()               | animationTicker.onComplete
    |                                       v
    |  <── complete walk ──  walkX  <──  _walkToPlayer()
    |                                       |
    |                                       v  (path empty)
    +────── wander done ─────────────── idle <── greeting done
    ^                                       |
    |   _startWander()                      | _wanderCooldown expires
    |                                       v
    +────── walk complete ────────────  walkX (wandering)
```

**States:** working, surprised, idle, walkDown/Left/Up/Right/DownLeft/DownRight/UpLeft/UpRight

**Key transitions:**
- Initial: `working` (onLoad)
- `working -> surprised`: `noticePlayer()` called (first human joins)
- `surprised -> walkX`: surprise animation completes, `_walkToPlayer()` starts
- `walkX -> idle`: greeting walk finishes (path exhausted while `_isGreeting`)
- `idle -> walkX`: `_startWander()` fires when `_wanderCooldown` expires
- `walkX -> working`: wander walk finishes (path exhausted while `_isWandering`)
- Any -> walkX: `moveFromServer()` overrides with `_serverControlled = true`

---

### 2d. DreamfinderComponent Boolean Machine (4 flags)

| _hasNoticedPlayer | _isWandering | _isGreeting | _serverControlled | Logical State |
|:-:|:-:|:-:|:-:|:--|
| F | F | F | F | **INITIAL** -- working idle, waiting to notice player |
| F | T | F | F | **WANDERING (pre-notice)** -- autonomous exploration |
| T | F | T | F | **GREETING** -- surprised reaction + walk to player |
| T | F | F | F | **POST-GREETING** -- idle/working, wander cooldown active |
| T | T | F | F | **WANDERING (post-notice)** -- autonomous exploration |
| T/F | F | F | T | **SERVER CONTROLLED** -- bot server drives movement |

**Valid combinations: 6 out of 16 theoretical**

**Illegal combinations that code doesn't guard against:**

| _hasNoticedPlayer | _isWandering | _isGreeting | _serverControlled | Why illegal |
|:-:|:-:|:-:|:-:|:--|
| F | F | T | F | Can't greet before noticing |
| * | T | T | F | Can't wander and greet simultaneously |
| * | T | * | T | `moveFromServer` sets `_isWandering = false`, but no guard on entry |

**Issue P2-D1 [LOW]:** `moveFromServer()` sets `_serverControlled = true` and
`_isWandering = false`, `_isGreeting = false` but never resets `_serverControlled`
back to `false`. Once the server sends a position update, the component stays in
`_serverControlled = true` forever. The `update()` method checks
`!_serverControlled` before ticking the wander cooldown (line 80), so autonomous
behavior never resumes after a server movement. This is arguably by design (server
takes over) but the flag is never cleared even if the server stops sending updates.

**Issue P2-D2 [LOW]:** `noticePlayer()` can only fire once (`_hasNoticedPlayer`
guard), but if `_serverControlled` was already true when the first human joins,
the notice will clear `_isWandering`/`_isGreeting` and start the surprise
animation, but the `update()` loop won't tick the wander cooldown afterwards
because `_serverControlled` is still true.

---

### 2e. _MicState (voice-cast FAB)

```
  idle ──── tap mic ──── listening ──── STT result ──── resolving
    ^                       |                              |
    |                       | tap to cancel                |
    |                       v                              |
    +─────── cancel ────── idle                            |
    |                                                      |
    +────────────── cast feedback rendered ─────────────────+
```

**Transitions:**
- `idle -> listening`: `_onTapMic` called, `speechCast.castAt()` begins STT
- `listening -> idle`: User taps mic again (cancel) or walks away from door
- `listening -> resolving`: STT transcript received, cast pipeline processing
- `resolving -> idle`: `_renderFeedback` completes, `_resolving = false`

**Guard:** `if (_resolving) return;` prevents double-tap during resolution.

**Issue P2-M1 [LOW]:** `_MicState` is a derived enum computed from two booleans
(`listening`, `resolving`) via `_MicState.resolve()`. The two booleans live in
different places: `listening` comes from `SpeechCastService.listening` (a
`ValueNotifier<bool>`), while `_resolving` is local `_SpeechCastOverlayState`.
This split is clean but means the state derivation happens at render time, not at
transition time -- no single place enforces that `listening && resolving` can't
both be true (which would render as `listening` due to the if-chain priority).

---

### 2f. LiveKitService Connection Machine (2 booleans)

| _isConnecting | _isConnected | Logical State |
|:-:|:-:|:--|
| F | F | **DISCONNECTED** -- initial/disposed |
| T | F | **CONNECTING** -- token retrieval + room connect in progress |
| F | T | **CONNECTED** -- room active |
| T | T | **ILLEGAL** -- should never occur |

**Transitions:**
- `DISCONNECTED -> CONNECTING`: `connect()` called
- `CONNECTING -> CONNECTED`: Room connection succeeds
- `CONNECTING -> DISCONNECTED`: Token retrieval or connection fails
- `CONNECTED -> DISCONNECTED`: `disconnect()` called or `RoomDisconnectedEvent`

**Guards:**
- `connect()`: Returns `alreadyConnected` if `_isConnecting || _isConnected`
- `disconnect()`: Returns early if `!_isConnected || _room == null`

**Issue P2-L1 [MEDIUM]:** No guard against `(true, true)` -- the combination
`_isConnecting = true && _isConnected = true` is impossible in the current code
flow because `_isConnecting` is set to `false` on the same line as
`_isConnected = true` (line 277-278). However, if `RoomDisconnectedEvent` fires
during the initial `connect()` setup (after `_room!.connect()` returns but before
line 277 executes), the event handler (line 627) would set `_isConnected = false`
and null `_room`, then the original `connect()` flow would set
`_isConnected = true` and `_isConnecting = false` -- referencing a now-null
`_room`. This is a narrow race window but theoretically possible.

**Issue P2-L2 [MEDIUM]:** `disconnect()` (line 310) checks
`!_isConnected || _room == null` but doesn't check `_isConnecting`. If
`disconnect()` is called while a `connect()` is in-flight (e.g., user quickly
taps Leave Room), it returns immediately without waiting for the connection
attempt to finish. The in-flight `connect()` will then complete and set
`_isConnected = true` on a service the caller thought was disposed.

---

### 2g. _MyAppState Implicit State Machine (THE BIG ONE)

#### Boolean/Nullable Flags (12+ fields)

| Field | Type | Meaning |
|-------|------|---------|
| `_initialized` | bool | Firebase + services init complete |
| `_avatarLoaded` | bool | Profile fetch from Firestore complete |
| `_selectedAvatar` | Avatar? | Null = show selection screen |
| `_currentUserId` | String? | Null = signed out |
| `_isAnonymous` | bool | Guest mode |
| `_currentRoom` | RoomData? | Null = lobby view |
| `_liveKitService` | LiveKitService? | Null = no LiveKit connection |
| `_liveKitConnectionFailed` | bool | Connection error banner |
| `_isReconnecting` | bool | Auto-reconnect in progress |
| `_showJoinOverlay` | bool | Circuit-board overlay visible |
| `_roomService` | RoomService? | Null = not signed in |
| `_chatService` | ChatService? | Null = not in room |
| `_spellbookService` | SpellbookService? | Null = not signed in |

#### Valid Application States

```
LAUNCH ──> INIT ──> AUTH_GATE ──> PROFILE_LOAD ──> AVATAR_SELECT ──> LOBBY
                        ^                                              |
                        |                           _joinRoom()        v
                        |                                         JOINING
                        |                                    (5 parallel wires)
                        |                                              |
                     sign out                                          v
                        |                                         IN_ROOM
                        |                                         /      \
                        |                       connection lost  /        \ _leaveRoom()
                        |                                       v          |
                        +──────────────────────── RECONNECTING   |
                                                      |          |
                                                      +──────────+
                                                           |
                                                           v
                                                        LOBBY
```

#### State-to-Flags Mapping

| Application State | _initialized | _currentUserId | _avatarLoaded | _selectedAvatar | _currentRoom | _showJoinOverlay | _liveKitService |
|:--|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| LAUNCH | F | null | F | null | null | F | null |
| INIT | T | null | F | null | null | F | null |
| AUTH_GATE | T | null | F | null | null | F | null |
| PROFILE_LOAD | T | set | F | null | null | F | null |
| AVATAR_SELECT | T | set | T | null | null | F | null |
| LOBBY | T | set | T | set | null | F | null |
| JOINING | T | set | T | set | set | T | null->set |
| IN_ROOM | T | set | T | set | set | F | set |
| IN_ROOM (no LK) | T | set | T | set | set | F | null |
| RECONNECTING | T | set | T | set | set | F | set |

#### Render Logic (build method, line 896+)

The `build()` method uses a cascading if-chain to determine what to show:

```
1. !_initialized -> LoadingScreen
2. AuthUser is SignedOutUser -> AuthGate
3. !_avatarLoaded || _roomService == null -> LoadingScreen("Loading profile")
4. _selectedAvatar == null -> AvatarSelectionScreen
5. _currentRoom == null -> RoomBrowser (lobby)
6. else -> GameWidget + overlays
```

This is a **correctly prioritized chain** -- each condition narrows to the next
valid state. The priority ordering prevents contradictory renders.

---

## 3. Invariant Analysis

### Structural Invariants (should always hold)

| ID | Invariant | Holds? | Evidence |
|----|-----------|--------|----------|
| I1 | `_currentRoom != null => _initialized` | **Yes** | `_currentRoom` only set in `_joinRoom`/`_onCreateRoom`, which require prior init |
| I2 | `_currentRoom != null => _currentUserId != null` | **Yes** | `_joinRoom` returns early if `userId == null` |
| I3 | `_liveKitService != null => _currentRoom != null` | **Mostly** | `_leaveRoom` nulls both; `_createServices` only called with a room. But `_onCreateRoom` sets `_currentRoom` with `id: ''` before LiveKit connects -- transient window |
| I4 | `_chatService != null => _liveKitService != null` | **Yes** | Created together in `_createServices` |
| I5 | `_isReconnecting => _currentRoom != null` | **Yes** | `_handleConnectionLost` returns early if `_currentRoom == null` |
| I6 | `_showJoinOverlay => _currentRoom != null` | **Yes** | Set true in `_joinRoom` only after `_currentRoom` is set |
| I7 | `mapEditorActive => _currentRoom != null` | **Yes** | Editor only visible when signed in + in room |
| I8 | `_avatarLoaded => _currentUserId != null` (during session) | **Yes** | Set only in `_onAuthStateChanged` after userId is set |

### Broken/Weak Invariants

| ID | Expected Invariant | Status | Explanation |
|----|-------------------|--------|-------------|
| I9 | `_liveKitConnectionFailed => _currentRoom != null` | **WEAK** | `_leaveRoom` resets both, but during reconnect there's a window where `_liveKitConnectionFailed = true` and a concurrent `_leaveRoom` call could null `_currentRoom` first |
| I10 | `BotStatus != absent => LiveKitService.isConnected` | **BROKEN** | See P2-B1 -- `_leaveRoom` doesn't reset BotStatus |

---

## 4. Illegal State Transitions / Race Conditions

### Issue P2-R1 [HIGH]: Concurrent _joinRoom and _leaveRoom

**Scenario:** User taps "Join Room", then immediately taps "Leave" while the
5-wire join is in progress.

**Analysis:** `_joinRoom` is an async method that runs 5 concurrent wire
operations. If `_leaveRoom` is called while `_joinRoom` is still running:

1. `_leaveRoom` disposes `_liveKitService`, sets `_currentRoom = null`
2. Wire B/C/D (still in flight) hold references to `_liveKitService!` (captured
   before leaveRoom ran) -- those references are now to a disposed service
3. The `Future.wait` in `_joinRoom` eventually completes
4. The finally block tries `setState(() => _showJoinOverlay = false)` but
   `_currentRoom` is already null

**No guard exists** -- `_joinRoom` doesn't check for concurrent teardown, and
there's no mutex or `_isJoining` flag.

### Issue P2-R2 [MEDIUM]: Concurrent _joinRoom calls

**Scenario:** User somehow triggers `_joinRoom` twice (e.g., double-tap on room
card in lobby).

**Analysis:** `_joinRoom` has no re-entrancy guard. Two concurrent joins would
create duplicate `WireStates`, duplicate `LiveKitService` instances (via
`_createServices`), and race on `_currentRoom`.

### Issue P2-R3 [MEDIUM]: _handleConnectionLost during _joinRoom

**Scenario:** LiveKit connects (Wire B completes) then immediately disconnects
before Wire C/D finish.

**Analysis:**
1. `_listenForConnectionLoss()` is called after Wire B's server connection
2. `_handleConnectionLost` fires, sets `_isReconnecting = true`, waits 2s, tries
   `_liveKitService!.connect()`
3. Meanwhile, Wire C (camera/mic) is still running on the old, now-disconnected
   service
4. The reconnect attempt calls `_liveKitService!.connect()` which checks
   `_isConnecting || _isConnected` -- but `_isConnected` was set to `false` by
   `RoomDisconnectedEvent` handler, so reconnect proceeds
5. Wire C's `setCameraEnabled` on the old room object may throw or silently fail

### Issue P2-R4 [LOW]: _onCreateRoom leaves transient invalid state

**Scenario:** User creates a new room.

**Analysis:** `_onCreateRoom()` sets `_currentRoom` to a `RoomData(id: '')` --
an empty-string ID -- before the user saves. This means:
- `_currentRoom != null` is true (shows game view)
- `_currentRoom!.id` is empty
- No LiveKit room exists yet (no `_liveKitService`)
- The `_mapEditorState.roomId` is null

This is a deliberate transient state for the editor flow, but any code that
assumes `_currentRoom!.id` is a valid Firestore document ID during this window
would break.

### Issue P2-R5 [LOW]: Sign-out during async operations

**Scenario:** User signs out while `_joinRoom`, `_saveRoom`, or
`_handleConnectionLost` is in-flight.

**Analysis:** `_onAuthStateChanged(SignedOutUser)` calls `_leaveRoom()` then nulls
all services. Any in-flight async operation that awaits after this point will find
null services. The `try/catch` blocks in individual wire operations will catch
thrown errors, but the `_joinRoom` flow doesn't check whether the user is still
signed in between wire completions.

---

## 5. Missing Transitions

| ID | Missing Transition | Impact |
|----|--------------------|--------|
| M1 | `WireStatus.error -> WireStatus.active` (retry) | No per-wire retry; must rejoin room entirely |
| M2 | `_serverControlled -> false` in DreamfinderComponent | Server-controlled mode is permanent once entered |
| M3 | `BotStatus` reset in `_leaveRoom` | Stale bot status across room transitions |
| M4 | `_isLoadingMap` reset on exception in `loadMap` | Actually handled -- `finally` block at line 1822-1823 |
| M5 | Reconnect attempt limit | `_handleConnectionLost` tries exactly once; no exponential backoff or max retries |

---

## 6. Priority-Ranked Issues

### HIGH

| ID | Issue | Location | Description |
|----|-------|----------|-------------|
| P2-R1 | No join/leave mutex | `_MyAppState._joinRoom` / `_leaveRoom` | Concurrent join+leave can dispose services that in-flight wire operations still reference. Needs `_isJoining` guard or cancellation token. |

### MEDIUM

| ID | Issue | Location | Description |
|----|-------|----------|-------------|
| P2-B1 | BotStatus not reset on leave | `_MyAppState._leaveRoom` | `botStatusNotifier.value` not set to `absent` when leaving a room. Stale status carries to next room. One-line fix. |
| P2-L1 | Connect/disconnect race window | `LiveKitService.connect` | `RoomDisconnectedEvent` during connect setup could leave `_isConnected` and `_room` in inconsistent state. |
| P2-L2 | No connecting guard in disconnect | `LiveKitService.disconnect` | `disconnect()` ignores in-flight `connect()`, allowing ghost connections. |
| P2-R2 | No re-entrancy guard on join | `_MyAppState._joinRoom` | Double-tap on room card could trigger two concurrent join sequences. |
| P2-R3 | Connection loss during wire setup | `_MyAppState._joinRoom` | Reconnect handler can race with Wire C/D on a disconnected room object. |

### LOW

| ID | Issue | Location | Description |
|----|-------|----------|-------------|
| P2-W1 | No wire retry | `WireStates` | Error is a terminal state per wire; only recovery is full rejoin. |
| P2-W2 | Semantic naming | `WireStates.complete` | Skipped wires marked "complete" rather than "skipped". |
| P2-D1 | Permanent server control | `DreamfinderComponent._serverControlled` | Flag never reset; autonomous behavior stops permanently. |
| P2-D2 | Notice vs server-controlled | `DreamfinderComponent.noticePlayer` | Notice fires but autonomous loop never resumes if server-controlled. |
| P2-M1 | Split boolean derivation | `_MicState` | State computed from two sources at render time, no transition-time enforcement. |
| P2-R4 | Transient empty room ID | `_MyAppState._onCreateRoom` | `_currentRoom.id == ''` during editor flow. |
| P2-R5 | Sign-out during async | `_MyAppState._onAuthStateChanged` | In-flight operations may reference nulled services after sign-out. |
| M1 | No wire retry transition | `WireStates` | error is terminal. |
| M2 | No server-control release | `DreamfinderComponent` | `_serverControlled` lacks a reset path. |
| M5 | Single reconnect attempt | `_handleConnectionLost` | No exponential backoff or retry limit. |

---

## 7. Architectural Observations

### What's Done Well

1. **WireStates** is a clean, focused state machine with proper `ChangeNotifier`
   integration. The `allComplete` guard is correct.

2. **Sealed class hierarchies** (`DoorCastResult`, `FreeCastResult`) are
   excellent -- compiler-enforced exhaustiveness with zero runtime overhead.
   The intentional disjointness of door-cast vs free-cast hierarchies prevents
   routing errors at compile time.

3. **The build-method cascade** in `_MyAppState` is correctly ordered so that
   each condition gates the next. This prevents impossible UI states (e.g.,
   showing the game before auth, showing the editor before avatar selection).

4. **DreamfinderState enum** properly separates animation concerns from behavior
   concerns. The `walkStateFromDirection` mapping is exhaustive.

5. **ConnectionResult** is correctly modeled as a return value (algebraic type)
   rather than mutable state -- it classifies the outcome of a single operation.

### What Needs Work

1. **`_MyAppState` is a god widget** with 12+ state fields, 6+ services, and
   ~800 lines of state management. The implicit state machine should be
   extracted into an explicit state class (e.g., `AppLifecycle` enum with
   LAUNCH/AUTH/PROFILE/AVATAR/LOBBY/JOINING/IN_ROOM/RECONNECTING variants).
   This would make illegal states unrepresentable.

2. **LiveKitService connection flags** (`_isConnecting`, `_isConnected`) should
   be a single `ConnectionState` enum: `disconnected`, `connecting`, `connected`.
   This eliminates the illegal `(true, true)` combination by construction.

3. **DreamfinderComponent's 4 booleans** should be collapsed into a single
   `DreamfinderBehavior` enum: `initial`, `wandering`, `greeting`,
   `postGreeting`, `serverControlled`. The `_hasNoticedPlayer` flag would become
   implicit (any state past `initial` means noticed).

4. **No cancellation mechanism** for async operations. A `CancelableOperation`
   or cancellation token pattern would prevent race conditions in join/leave.

---

## 8. Recommended Refactoring Priority

1. **Add `_isJoining` guard to `_joinRoom`** (P2-R1) -- immediate safety fix,
   prevents the worst race condition.

2. **Reset `botStatusNotifier` in `_leaveRoom`** (P2-B1) -- one-line fix,
   prevents user-visible bug.

3. **Extract `AppLifecycleState` enum from `_MyAppState`** -- medium effort,
   high payoff. Makes 10/12 boolean flags redundant.

4. **Replace LiveKitService boolean pair with `ConnectionState` enum** (P2-L1,
   P2-L2) -- small refactor, eliminates a class of bugs.

5. **Add `_serverControlled` reset path in DreamfinderComponent** (P2-D1) --
   simple timeout or explicit release message from server.
