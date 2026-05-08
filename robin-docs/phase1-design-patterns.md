# Tech World — Gang of Four Design Patterns Report

**Phase 1 / Foundation | 2026-05-06**

## Summary Statistics

- 175 Dart files across `lib/`
- 84 usages of `ValueNotifier`/`addListener`/`ValueListenableBuilder`
- 97 stream/observer usages
- 60 `Locator.add`/`locate<` service-locator calls
- 24 factory constructors

---

## Part 1: Patterns Already In Use

### 1.1 Service Locator (architecturally central)

**Files:** `lib/utils/locator.dart` (lines 16-67), used throughout `main.dart`, `tech_world.dart`, and every service consumer.

Hand-rolled Service Locator. Singleton `Locator` holds `Map<Type, Object>` with global `locate<T>()` alias. Static and dynamic services cleanly separated by lifecycle:

- **Static** (never removed): `AuthService`, `TechWorld`, `TechWorldGame` — registered at app init.
- **Dynamic** (sign-in/sign-out): `LiveKitService`, `ChatService`, `ProximityService`, `ProgressService`, `SpellbookService`, `InfraHealthService`, `MapSyncService`.

Dynamic lifetime management is correct: `main.dart:_leaveRoom()` calls `Locator.remove<T>()` in the right disposal order (consumers before producers).

**Limitation:** Only one object per type — acknowledged in code comment at line 1-4.

### 1.2 Observer — Three-tier ValueNotifier / ChangeNotifier / StreamController

**ValueNotifier (fine-grained reactive state):**
- `TechWorld`: 8 public `ValueNotifier` fields: `currentMap`, `playerGridPosition`, `nearbyLockedDoor`, `activeChallenge`, `activePromptChallenge`, `activeTerminalPosition`, `mapEditorActive`, `gameReady`.
- `MapSyncService`: `undoRedoChanged` (lines 45-46).
- `InfraHealthService`: `healthState` (line 49).
- UI layer uses `ValueListenableBuilder` throughout `main.dart`.

**ChangeNotifier (coarser invalidation):**
- `MapEditorState extends ChangeNotifier` (line 53): notifies on every edit mutation.

**StreamController.broadcast() (async event bus):**
- `LiveKitService`: 8 broadcast `StreamController`s (lines 68-82) — `participantJoined`, `participantLeft`, `speakingChanged`, `trackSubscribed`, `trackUnsubscribed`, `localTrackPublished`, `dataReceived`, `connectionLost`.
- `ProximityService`: `_proximityController` (line 29).
- `SpellbookService`: `_controller` for learned words (line 33).

The three-tier split is rational: `ValueNotifier` for UI-reactive state, `ChangeNotifier` for editor bulk invalidation, `StreamController` for async events from external systems.

### 1.3 Component / Composite (Flame ECS)

**Files:** All files under `lib/flame/components/`

Flame's `Component` tree is a textbook Composite. `TechWorld` (extends `World`) is the composite root. Leaf components: `PlayerComponent`, `TerminalComponent`, `DoorComponent`, `PathComponent`, `BotCharacterComponent`, `DreamfinderComponent`, `VideoBubbleComponent`, `BotBubbleComponent`, `SpeechBubbleComponent`, `TileFloorComponent`, `TileObjectLayerComponent`, `BarriersComponent`, `BubbleFieldComponent`, `MergedVideoBubbleComponent`.

The `priority` system (set each frame from `position.y`) drives depth-sorting — standard ECS usage.

### 1.4 Strategy — Video Capture Pipelines

**Files:** `lib/native/frame_source.dart`, `canvas_capture.dart`, `video_frame_capture.dart`, `direct_track_capture.dart`, `web_video_capture.dart`

`FrameSource` (lines 7-14) is an abstract Strategy interface with two methods: `hasNewFrame` and `consumeFrame()`. Three implementations:

1. `VideoFrameCapture` (FFI/macOS) — direct shared memory from native code.
2. `CanvasCapture` (web canvas readback) — Three.js iframe bridge.
3. `DirectTrackCapture` (web MediaStreamTrackProcessor) — no-DOM path.

Platform dispatch uses Dart's conditional exports — compile-time Strategy selection. **Cleanest GoF usage in the codebase.**

### 1.5 Bridge — Platform Abstraction via Conditional Exports

Six conditional-export files implement Bridge by decoupling abstraction from implementation at compile time. `SttService` and `TtsService` follow the same pattern for speech features (web-only). Correct and pragmatic.

### 1.6 Command + Memento — CRDT Undo/Redo

**Files:** `lib/map_editor/crdt/map_edit_op.dart`, `undo_manager.dart`, `map_sync_service.dart`

`MapEditOp` (with `inverse()` at line 43) is a Command with reversibility — the Memento is embedded as `oldValue`/`newValue`. `MapEditBatch` bundles multiple Commands for atomic undo/redo. `UndoManager` (lines 11-101) is the Invoker with undo/redo stacks.

The insight that undo participates in CRDT conflict resolution rather than bypassing it is well-executed.

### 1.7 Template Method — EvaluationEngine

**File:** `lib/prompt/evaluation_engine.dart`

`EvaluationEngine` (abstract class, line 17) defines the template for challenge evaluation. `ChatEvaluationEngine` is the concrete implementation. Clean Template Method.

### 1.8 Null Object — PlaceholderUser

**File:** `lib/auth/auth_user.dart` (lines 36-39)

`PlaceholderUser` extends `AuthUser` with empty strings for `id` and `displayName`, representing "auth state not yet determined." Eliminates null checks in auth stream consumers. Well-used.

### 1.9 Sealed Class / Discriminated Union (Visitor-like)

**Files:** `lib/spellbook/free_cast_result.dart`, `door_cast_result.dart`

`sealed class FreeCastResult` and `sealed class DoorCastResult` provide exhaustive `switch` on sealed hierarchies. **Most algebraically clean pattern in the codebase** — idiomatic Dart 3.

### 1.10 Flyweight — Static Paint objects

**File:** `lib/flame/components/terminal_component.dart` (lines 32-50)

`_bgPaint`, `_borderPaint`, `_completedBorderPaint`, `_promptStyle`, `_checkmarkStyle` are `static final`. Textbook Flyweight for shared immutable rendering state.

### 1.11 Proxy — MapSyncService wrapping MapEditorState

**File:** `lib/map_editor/map_sync_service.dart`

`MapSyncService` wraps `MapEditorState` and intercepts every mutation to capture before/after state, produce CRDT ops, push to undo stack, and broadcast. Protection/Virtual Proxy adding CRDT tracking transparently.

### 1.12 Facade — LiveKitService

**File:** `lib/livekit/livekit_service.dart`

Facade over LiveKit's `Room`, `EventsListener`, and track management. Exposes domain-specific surface: `publishPosition`, `publishMapInfo`, `publishTerminalActivity`. Raw `Room` is private. Well-executed.

### 1.13 Factory Method — MapEditBatch / MapEditOp

**File:** `lib/map_editor/crdt/map_edit_op.dart` (lines 56-68, 132-147)

`fromJson` factory constructors and `MapEditBatch.inverse(counter:)` transformation factory. Correct usage.

---

## Part 2: Patterns Used Incorrectly

### 2.1 Service Locator — `maybeLocate<T>()` with silent null propagation

**File:** `lib/flame/tech_world.dart` (lines 341-343), `main.dart` (lines 1261-1263, 1382-1385)

```dart
Locator.maybeLocate<ProgressService>()?.isChallengeCompleted(...) ?? false
```

Silently makes `_isCodeChallengeCompleted` return `false` when ProgressService hasn't loaded — a race condition disguised as optional access. Fix: always register before reachable, or add `bool get isLoaded` guard.

### 2.2 State pattern — boolean flags instead of State objects (DreamfinderComponent)

**File:** `lib/flame/components/dreamfinder_component.dart` (lines 43-48)

Four booleans (`_hasNoticedPlayer`, `_isWandering`, `_isGreeting`, `_serverControlled`) define 2^4 = 16 combinations but only ~5 are valid. Should be a single enum: `enum DreamfinderBehavior { idle, greeting, wandering, serverControlled }`.

### 2.3 Observer — ProximityService registered but never subscribed to

**File:** `lib/proximity/proximity_service.dart`, `main.dart` line 474

`ProximityService` is created and registered with `Locator.add<ProximityService>` but `checkProximity()` is never called and `proximityEvents` is never subscribed to. Actual proximity logic (Chebyshev distance) is inlined directly in `TechWorld._updatePlayerBubbles()`. Dead service with duplicated logic.

### 2.4 Missing `dispose()` on 3 of 8 ValueNotifiers

**File:** `lib/flame/tech_world.dart` (lines 2071-2079)

`TechWorld.dispose()` disposes 5 of 8 ValueNotifiers but omits `playerGridPosition`, `activePromptChallenge`, and `gameReady`. Latent memory leak.

### 2.5 Singleton — Locator static map not resettable

**File:** `lib/utils/locator.dart` (line 20)

`static final Map<Type, Object> _objectOfType = {}` — no `Locator.reset()`. Stale entries persist on hot-restart. Tests may leak state between cases.

---

## Part 3: Anti-Patterns

### 3.1 God Object — TechWorld (2081 lines)

**File:** `lib/flame/tech_world.dart`

Combines: map lifecycle, bubble lifecycle, video track handling, LiveKit subscriptions, proximity detection (inlined), audio management, bot handling, editor mode, path recalculation, speech transcripts, door unlock, tileset prefetching. 30+ private fields. Primary maintenance risk.

**Recommendation:** Extract `BubbleManager`, `LiveKitIntegration`, and `MapLoader` to halve the line count.

### 3.2 Stringly-typed data channel topics

Topic strings `'position'`, `'chat'`, `'speech-transcript'`, `'map-info'`, etc. scattered as string literals across multiple files. CLAUDE.md already identifies this smell. Needs `DataTopic` enum with wire names.

### 3.3 Temporal coupling — `connectToLiveKit` preconditions invisible

**File:** `lib/flame/tech_world.dart` (lines 1100-1277)

`LiveKitService` must already be in Locator or the method silently returns. Ordering precondition documented only in a comment. Fix: pass `LiveKitService` as a parameter or add assertion.

### 3.4 Callback pyramid in `main.dart` build method

**File:** `lib/main.dart` (lines 896-1491)

`StreamBuilder` -> `ValueListenableBuilder` -> `ValueListenableBuilder` -> `ValueListenableBuilder` four levels deep. Some private widget extraction exists (`_SpellbookButton`, etc.) but incompletely applied.

---

## Part 4: Recommendations

| # | Recommendation | Pattern | Effort |
|---|---------------|---------|--------|
| R1 | Replace DreamfinderComponent booleans with enum | State | Small |
| R2 | Extract BubbleManager from TechWorld | Mediator/SRP | Medium |
| R3 | Activate or delete ProximityService | Observer cleanup | Small |
| R4 | Add `DataTopic` enum for wire topics | Enum/Strategy | Small |
| R5 | Topic-keyed dispatch table in connectToLiveKit | Chain of Responsibility | Small |
| R6 | Abstract `ServiceBase` with `onDispose()` template | Template Method | Medium |
| R7 | Dispose all 8 ValueNotifiers in TechWorld | Observer cleanup | Trivial |
| R8 | Add `Locator.resetForTesting()` | Singleton | Trivial |

---

## Summary Table

| Pattern | Location | Status |
|---------|----------|--------|
| Service Locator | `utils/locator.dart` | In use — minor misuse via `maybeLocate` |
| Observer (3-tier) | `tech_world.dart`, `map_editor/`, `livekit/` | In use — correct |
| Component/Composite | `flame/components/` | In use — correct (Flame ECS) |
| Strategy | `native/frame_source.dart` | In use — exemplary |
| Bridge | `native/canvas_capture.dart` et al. | In use — correct |
| Command + Memento | `map_editor/crdt/` | In use — exemplary |
| Template Method | `prompt/evaluation_engine.dart` | In use — correct |
| Null Object | `auth/auth_user.dart` | In use — correct |
| Sealed/Visitor | `spellbook/free_cast_result.dart` | In use — exemplary |
| Flyweight | `terminal_component.dart` | In use — correct |
| Proxy | `map_sync_service.dart` | In use — correct |
| Facade | `livekit_service.dart` | In use — correct |
| Factory Method | `map_edit_op.dart` | In use — correct |
| God Object (anti) | `tech_world.dart` | Present — needs decomposition |
| Dead service (anti) | `proximity_service.dart` | Registered, never used |
| Stringly-typed (anti) | Multiple files | Needs `DataTopic` enum |
| Callback pyramid (anti) | `main.dart:build()` | Needs widget extraction |
