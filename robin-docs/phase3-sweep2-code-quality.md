# Tech World Sweep 2 — Code Quality

**Phase 3 / Quality | 2026-05-07**

---

## Pattern Vocabulary (from Phase 1)

13 GOF patterns identified in active use:

| Pattern | Location | Status |
|---------|----------|--------|
| Service Locator | `utils/locator.dart` | In use — minor misuse via `maybeLocate` |
| Observer (3-tier) | ValueNotifier / ChangeNotifier / StreamController | In use — correct |
| Composite | Flame component tree | In use — correct (framework) |
| Strategy | `native/frame_source.dart` (video capture) | Exemplary |
| Bridge | 6 conditional export files | In use — correct |
| Command + Memento | `map_editor/crdt/` (undo/redo) | Exemplary |
| Template Method | `prompt/evaluation_engine.dart` | In use — correct |
| Null Object | `auth/auth_user.dart` (PlaceholderUser) | In use — correct |
| Sealed/Visitor | `spellbook/free_cast_result.dart` | Exemplary |
| Flyweight | `terminal_component.dart` (static Paint) | In use — correct |
| Proxy | `map_sync_service.dart` wrapping MapEditorState | In use — correct |
| Facade | `livekit_service.dart` over LiveKit Room | In use — correct |
| Factory Method | `map_edit_op.dart` (fromJson) | In use — correct |

4 anti-patterns:
- God Object (TechWorld 2081 lines)
- Dead service (ProximityService)
- Stringly-typed data channel topics
- Callback pyramid (main.dart build)

---

## Scorecard

| Audit | Score /5 | Key Finding |
|-------|---------|-------------|
| Tech Debt | 2.5 | Two god objects (TechWorld + _MyAppState), 1800 lines dead code, hardcoded API key |
| Style | 3.5 | Excellent domain language & sealed classes; dragged down by repetition in main.dart |
| Test Health | 3.4 | Strong CRDT/spell tests; LiveKitService tests are structural facades, main.dart untested |

---

## Findings by Priority

### CRITICAL

#### CR-1: God Object — TechWorld (2081 lines, 30+ fields, 40+ methods)
**File:** `lib/flame/tech_world.dart`
**Patterns involved:** Mediator (overloaded), missing Strategy/Observer extraction
**Audits flagging:** Tech Debt (C-2), Style (type-switching dispatch), Test Health (untested LiveKit wiring)

TechWorld combines 10+ responsibilities: LiveKit subscription management, component lifecycle (players, bots, Dreamfinder, bubbles, doors, terminals), pathfinding, map loading, video bubble physics, shader loading, proximity detection, door unlock, speech transcripts, editor integration, infra health. The class is the single largest maintenance risk and the primary reason LiveKit integration is untested — it can't be instantiated in isolation.

**Pattern diagnosis:** TechWorld is a Mediator that grew beyond its coordination role. It now *owns* the things it mediates. The bubble lifecycle, LiveKit subscription wiring, and proximity detection are three independent concerns tangled into one class.

---

#### CR-2: God Widget — _MyAppState (1734 lines, 20+ fields)
**File:** `lib/main.dart`
**Patterns involved:** Missing Facade for room lifecycle, missing State pattern for app state machine
**Audits flagging:** Tech Debt (C-3), Style (5x StreamBuilder duplication), Test Health (zero tests)

`_MyAppState` manages: Firebase init, auth, avatar selection, room join/leave/create/save/delete, LiveKit lifecycle, service registration, reconnect logic, 5 nested `StreamBuilder<AuthUser>`, and 6 overlay panels. The `build()` method spans ~600 lines with 5 levels of nesting.

**Pattern diagnosis:** The implicit state machine (unauthenticated → authenticated → joining → connected → reconnecting → leaving) is implemented as 12+ boolean flags and nullable fields. This is the classic symptom of a missing State pattern.

---

#### CR-3: 3 of 8 ValueNotifiers not disposed in TechWorld
**File:** `lib/flame/tech_world.dart` lines 2071–2078
**Pattern involved:** Observer (incomplete teardown)

`playerGridPosition`, `activePromptChallenge`, and `gameReady` are not disposed. Listeners fire after disposal, potentially corrupting state or preventing GC.

**Fix:** Three-line fix. Add `.dispose()` calls.

---

### HIGH

#### HI-1: ~1800 lines dead LiveKit scaffolding
**Files:** `lib/livekit/pages/` (4 files), `lib/livekit/widgets/` (5 files), `proximity_video_overlay.dart`
**Pattern involved:** Lava Flow anti-pattern

The original LiveKit sample app UI was kept but is unreachable — video is now rendered as Flame components. `ConnectPage` is never navigated to from outside `livekit/`.

**Fix:** Delete all ~10 files. Zero functional impact.

---

#### HI-2: Stringly-typed data channel topics (22+ topic strings across 6 files)
**Files:** `livekit_service.dart`, `chat_service.dart`, `infra_health_service.dart`, `dreamfinder_avatar_bridge_web.dart`, `oracle_service.dart`, `tech_world.dart`, `map_sync_service.dart`
**Pattern involved:** Missing enum — violates CLAUDE.md's "stringly-typing is a smell" rule

A typo in any subscriber silently drops messages. `MapSyncService` already uses private `const` strings — the pattern exists but isn't applied consistently.

**Fix:** `enum DataTopic` with `wireName` field, matching the `CodeChallengeId` / `PromptChallengeId` pattern.

---

#### HI-3: Hardcoded API key (Dreamfinder)
**File:** `lib/main.dart` lines 469–470

48-char hex key as `defaultValue` in `String.fromEnvironment`. Compiled into binary, visible in disassembly.

**Fix:** Set `defaultValue: ''`, throw on empty, inject via `--dart-define` in CI.

---

#### HI-4: LiveKitService tests are structural facades, not behavioural
**File:** `test/livekit/livekit_service_test.dart`

7 of ~40 tests are `expect(service.X, isA<Stream>())` — trivial type assertions. Message parsing, avatar parsing, and listener callbacks are untested.

**Critical sub-issue:** `position_parsing_test.dart` tests a **copy** of `_parsePlayerPath` written directly in the test file, not the production method. Changes to the real method won't break this test.

---

#### HI-5: Bot identity hardcoded as `'bot-claude'` string in 5+ files
**Files:** `conversation_list_tile.dart`, `chat_panel.dart`, `dm_thread_view.dart`, `chat_service.dart`, `livekit_service.dart`, `oracle_service.dart`
**Pattern involved:** Missing use of existing BotConfig constants

`BotConfig` and `clawdBot.identity` exist specifically for this.

**Fix:** Replace all string literals with `clawdBot.identity`.

---

#### HI-6: ChatService.sendMessage returns `Map<String, dynamic>?` (missing abstraction)
**File:** `lib/chat/chat_service.dart` line 334

The return type leaks JSON wire format. `main.dart` does `response?['challengeResult'] == 'pass'` — a string comparison on an untyped map. A bot protocol change from `'pass'` to `'passed'` silently breaks all challenge completion.

**Fix:** `BotResponse` sealed class or record with `.passed` getter.

---

#### HI-7: 30+ `Future.delayed(10ms)` in chat tests — flakiness hazard
**File:** `test/chat/chat_service_test.dart`

On a loaded CI runner these timing-dependent delays could fail. Also present in `tech_world_auth_test.dart` (50ms) and `service_lifecycle_test.dart` (10ms, 30ms).

**Fix:** Replace with `await Future<void>.delayed(Duration.zero)` or `pumpEventQueue()`.

---

### MEDIUM

#### ME-1: Duplicated connection sequence (3 copies in main.dart)
**Files:** `lib/main.dart` — `_joinRoom`, `_setupLiveKit`, `_handleConnectionLost`

Same connect → enableCamera → enableMic → loadHistory sequence in three places, with a duplicated `ConnectionResult → message` switch expression.

**Fix:** Extract `_activateRoom()` and `_connectionFailureMessage()`.

---

#### ME-2: ProximityService registered but never consumed
**Files:** `lib/proximity/proximity_service.dart`, `lib/main.dart`, `lib/flame/tech_world.dart`
**Pattern involved:** Dead Observer

Created, registered in Locator, disposed — but `checkProximity()` is never called. TechWorld computes Chebyshev distance inline. Only live method is static `calculateOpacity`.

**Fix:** Delete the service. Move `calculateOpacity` to a utility.

---

#### ME-3: 5 nested `StreamBuilder<AuthUser>` with identical guards
**File:** `lib/main.dart`

Five independent StreamBuilders subscribe to the same auth stream, each repeating `!snapshot.hasData || snapshot.data is SignedOutUser || _currentRoom == null || _selectedAvatar == null`.

**Fix:** Single auth StreamBuilder at root, extract child widgets.

---

#### ME-4: `MapEditOp.oldValue/newValue` are `dynamic`
**File:** `lib/map_editor/crdt/map_edit_op.dart` lines 37–41

The CRDT command stores untyped values. Layer-specific bugs are runtime crashes instead of compile-time errors.

**Fix:** Sealed `OpValue` hierarchy or at minimum `Object?` with casts at dispatch sites.

---

#### ME-5: Silent exception swallow in `_loadVideoBubbleShader`
**File:** `lib/flame/tech_world.dart` lines 880–888

The other two shader loaders log warnings. This one silently catches and discards.

**Fix:** Add `_log.warning('Video bubble shader failed to load', e)`.

---

#### ME-6: `MapEditorPanel` — 1268 lines with Locator calls inside build
**File:** `lib/map_editor/map_editor_panel.dart`

`_MapToolbarState` calls `Locator.maybeLocate<MapSyncService>()` in `initState`, silently inert if called before registration.

**Fix:** Propagate `MapSyncService?` as constructor parameter.

---

#### ME-7: Missing test categories

| Category | Status |
|----------|--------|
| CRDT idempotence | Not tested (commutativity tested, idempotence not) |
| State machine transitions | Only auth→unauth tested; connected/reconnecting untested |
| LiveKit message parsing fuzz | Absent — no malformed payload tests |
| Flame component onRemove cleanup | Not tested |
| InfraHealthService | Zero tests (181 lines) |
| main.dart orchestration | Zero tests (1734 lines) |

---

#### ME-8: DreamfinderComponent boolean state machine
**File:** `lib/flame/components/dreamfinder_component.dart` lines 43–48

Four booleans (`_hasNoticedPlayer`, `_isWandering`, `_isGreeting`, `_serverControlled`) define 16 combinations; only ~5 are valid.

**Fix:** `enum DreamfinderBehavior { idle, greeting, wandering, serverControlled }`.

---

### LOW

#### LO-1: `AvatarId`, `MapId`, `TilesetId`, `RoomType` still raw String
Acknowledged in CLAUDE.md as "pending — refactor when touching."

#### LO-2: Stale TODO in CLAUDE.md about deleted `functions/` directory

#### LO-3: Various undisposed notifiers/subscriptions
- `_logSubscription` in main.dart never cancelled on dispose
- `MapEditorState` not disposed in `_MyAppState`
- `MapSyncService.undoRedoChanged` not disposed

#### LO-4: `Direction.values.asNameMap()` allocated every frame
**File:** `lib/livekit/livekit_service.dart` line ~185
Creates a new Map on every position update. Cache as top-level constant.

#### LO-5: `Locator` has no `reset()` — tests leak state
**File:** `lib/utils/locator.dart`
Test tearDown has a comment "This is a workaround" and does nothing.

---

## Pattern-Based Remediation

### The Core Insight

The tech debt, style issues, and test gaps share a common root: **two classes (TechWorld and _MyAppState) have absorbed responsibilities that should be separate concerns**. This is not just a size problem — it's a *pattern* problem. Both classes started as legitimate Mediators/Facades but grew into God Objects because new features were wired in directly rather than through extracted subsystems.

### Remediation 1: Extract BubbleManager from TechWorld (Observer + Strategy)

**Fixes:** CR-1 (god object), ME-2 (dead ProximityService), Style (type-switching), Test Health (untestable bubble logic)

```dart
class BubbleManager {
  final Map<String, PositionComponent> _bubbles = {};
  
  void updateProximity(Point<int> playerGrid, Map<String, Point<int>> others) { ... }
  void applyRepulsion(double dt) { ... }
  void updateMergeGroups() { ... }
  
  // Replaces TechWorld._updatePlayerBubbles, _applyBubbleRepulsion,
  // _updateBubbleField, _createBubbleForPlayer, _setBubbleOpacity
}
```

Makes bubble physics testable in isolation. Eliminates ProximityService duplication.

### Remediation 2: Extract RoomSession from _MyAppState (Facade + State)

**Fixes:** CR-2 (god widget), ME-1 (duplicated connection), ME-3 (5× StreamBuilder), Test Health (untestable orchestration)

```dart
class RoomSession {
  final LiveKitService liveKit;
  final ChatService chat;
  final ProgressService progress;
  // ... all room-scoped services
  
  static Future<RoomSession> join(RoomData room, AuthUser user) async { ... }
  Future<void> reconnect() async { ... }
  Future<void> leave() async { ... }
}
```

Makes service lifecycle testable, eliminates duplicated connection sequence, reduces `_MyAppState` to a widget that owns a `RoomSession?`.

### Remediation 3: DataTopic enum (Strategy at the wire boundary)

**Fixes:** HI-2 (stringly-typed topics), reduces risk of HI-5 (bot identity leaks)

```dart
enum DataTopic {
  position('position'),
  chat('chat'),
  chatResponse('chat-response'),
  // ... 19 more
  ;
  const DataTopic(this.wireName);
  final String wireName;
  static DataTopic? parse(String wire) => ...;
}
```

Follows the existing `CodeChallengeId` / `PromptChallengeId` pattern. Enables exhaustive switch on topic dispatch.

### Remediation 4: DreamfinderBehavior enum (State pattern)

**Fixes:** ME-8 (boolean state machine)

```dart
enum DreamfinderBehavior { idle, greeting, noticing, wandering, serverControlled }
```

Replaces 4 booleans. One field, exhaustive switch in `update()`.

### Remediation 5: Extract position parser + upgrade LiveKit tests

**Fixes:** HI-4 (facade tests), position_parsing_test copy bug

Make `_parsePlayerPath` a top-level function so the test imports the real code. Add malformed-payload tests for `DataChannelMessage.json`.

---

## Prioritised Fix Order

| Rank | ID | Fix | Effort | Unblocks |
|------|-----|-----|--------|----------|
| 1 | CR-3 | Dispose 3 missing ValueNotifiers | Trivial | — |
| 2 | HI-3 | Remove hardcoded API key | S | — |
| 3 | HI-1 | Delete ~1800 lines dead code | S | Clarity |
| 4 | HI-2 | DataTopic enum | S-M | HI-5, exhaustive dispatch |
| 5 | HI-5 | Replace bot identity string literals | S | — |
| 6 | HI-6 | BotResponse type for sendMessage | S | — |
| 7 | ME-5 | Log shader load failure | Trivial | — |
| 8 | ME-8 | DreamfinderBehavior enum | S | — |
| 9 | ME-2 | Delete ProximityService | S | — |
| 10 | HI-4 | Fix position_parsing_test + upgrade LiveKit tests | M | Test coverage |
| 11 | HI-7 | Replace Future.delayed(10ms) in tests | M | CI stability |
| 12 | ME-1 | Extract _activateRoom + _connectionFailureMessage | S | — |
| 13 | CR-2 | Extract RoomSession from _MyAppState | L | ME-3, test coverage |
| 14 | CR-1 | Extract BubbleManager from TechWorld | L | Test coverage |

Items 1–9 are small, independent PRs. Items 10–12 are medium. Items 13–14 are architectural refactors that should follow the small wins.

---

## What's Already Good

Don't change these — they're the strongest parts of the codebase:

- **Spell algebra** — sealed classes, 2×2 confidence lattice, pure functions, exhaustive tests
- **CRDT undo/redo** — Command+Memento with Lamport clocks, convergence fuzz tests
- **Video capture Strategy** — FrameSource interface with 3 implementations, cleanest GOF usage
- **Domain vocabulary** — words of power, schools, casting, doors, terminals — consistent throughout
- **MapSyncService tests** — FakeLiveKitService, round-trip verification, wall cascade tests
- **Sealed cast results** — DoorCastResult, FreeCastResult — most algebraically clean pattern
- **Observer 3-tier split** — ValueNotifier for UI, ChangeNotifier for bulk, StreamController for async
