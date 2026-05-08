# Tech World Sweep 3 — Operations & Infrastructure

**Date:** 2026-05-08
**Phase:** 5 of 6
**Skill:** `/tw-sweep3` → `/tw-design-patterns` + `/tw-performance-profile` + `/dependency-audit` + `/tw-production-ready`

---

## Pattern Vocabulary (Phase 1 — Post-54 PRs)

### Patterns Correctly Applied (13)

| # | Pattern | Where | Notes |
|---|---------|-------|-------|
| 1 | Service Locator | `Locator`/`locate<T>()` | Scope-limited: static + dynamic + optional `maybeLocate` |
| 2 | Observer | ValueNotifier, ChangeNotifier, Streams throughout | Fine-grained: `currentMap`, `activeChallenge`, `gameReady`, etc. |
| 3 | Component (Flame ECS) | `lib/flame/components/` | Priority-based depth sort, proper mixin composition |
| 4 | Facade | `RoomSession` | Clean 4-method API: `create()`, `connect()`, `enableMedia()`, `leave()` |
| 5 | Strategy | `EvaluationEngine`, `MapAlgorithm` | Abstract class + switch dispatch |
| 6 | Adapter | `FrameSource` (3 video pipelines) | Conditional exports, crisp boundary |
| 7 | Command/Memento | `MapEditOp`, `UndoManager` | CRDT ops with inverse, fresh counters for undo |
| 8 | State | `DreamfinderState`, `_ConnectionState` | Enum-driven animation/connection state |
| 9 | Template Method | Flame `onLoad()`/`update()` inheritance | `PlayerComponent`, `DreamfinderComponent` |
| 10 | Sealed Hierarchies | `FreeCastResult`, `DoorCastResult`, `AuthUser` | Compiler-enforced exhaustive dispatch |
| 11 | Factory Method | `RoomSession.create()`, `MapEditBatch.fromJson` | `@visibleForTesting` injection |
| 12 | Flyweight | Static `Paint` objects in terminal/door | Shared immutable canvas primitives |
| 13 | Deferred Observer | `gameReady.waitForTrue()` | One-shot listener with auto-unsubscription |

### Patterns Misused (3)

| # | Pattern | Issue | File |
|---|---------|-------|------|
| 1 | Service Locator | `overwrite: true` default — silent double-registration | `lib/utils/locator.dart` |
| 2 | Singleton | `botStatusNotifier` global, mutated from 6 files, persists across sessions | `lib/flame/components/bot_status.dart` |
| 3 | Observer | `_waitForGameReady` listener not cancelled on early dispose | `lib/flame/tech_world.dart:402–419` |

### Missing Patterns (4)

| # | Pattern | Why Needed |
|---|---------|------------|
| 1 | Command (protocol) | 22+ LiveKit topics as stringly-typed dispatch; 14 subscription fields to tear down |
| 2 | Adapter (LiveKit SDK) | SDK types leak through `LiveKitService` public API |
| 3 | Repository (tileset) | Tile load/cache/decode logic scattered across 3 methods |
| 4 | Visitor (CastResult) | Potential `is` checks instead of exhaustive `switch` on sealed class |

### Anti-Patterns (3)

| # | Anti-Pattern | Evidence |
|---|-------------|----------|
| 1 | Stringly-typed bot identity | `isBotIdentity(participant.identity)` — closed set as String |
| 2 | God Object drift | `TechWorld` at ~1538 lines, owns 14+ subscription fields |
| 3 | Stringly-typed CRDT layer | `structureValueToJson('open')` — `TileType` enum serialised as raw string |

### Phase 1 vs Phase 3 Comparison

| Category | Phase 1 (pre-fixes) | Phase 3 (post-54 PRs) |
|----------|---------------------|----------------------|
| Correctly applied | 8 | 13 |
| Misused | 5 | 3 |
| Missing | 4 | 4 |
| Anti-patterns | 4 | 3 |

---

## Scorecard

| Audit | Score /5 | Critical Gaps |
|-------|---------|---------------|
| Performance | 3.2 | Per-frame allocations, no viewport culling, DateTime.now() throttle |
| Dependencies | 3.2 | Git fork supply-chain risk, 62 packages outdated, 3 major versions deferred |
| Production Readiness | 3.25 | No Crashlytics, debug-signed Android, single reconnect attempt, no staging env |
| **Overall** | **3.2** | |

### Production Readiness Sub-Scores

| Dimension | Score /5 |
|-----------|---------|
| Observability | 3 |
| Reliability | 4 |
| Data Integrity | 3.5 |
| Performance | 3 |
| Concurrency | 3.5 |
| Deployment Safety | 2.5 |

---

## Findings by Priority

### CRITICAL (3)

| # | Finding | Audit | File(s) |
|---|---------|-------|---------|
| C1 | **No crash reporting** — No Crashlytics, no `FlutterError.onError`, no `runZonedGuarded`. Production exceptions invisible. | Prod Ready | `lib/main.dart:62–66`, `pubspec.yaml` |
| C2 | **Android release signed with debug key** — Cannot ship to Play Store. | Prod Ready | `android/app/build.gradle.kts:39` |
| C3 | **Firebase API keys committed** — `firebase_options.dart` not gitignored; iOS/Android keys in public repo. | Prod Ready | `lib/firebase_options.dart` |

### HIGH (11)

| # | Finding | Audit | File(s) |
|---|---------|-------|---------|
| H1 | **Per-frame Paint/TextPainter allocations** in 4 bubble components — 3+ Paint objects + TextPainters created every `render()`. | Perf | `player_bubble_component.dart:41–55`, `bot_bubble_component.dart:67–111`, `video_bubble_component.dart:600–846` |
| H2 | **O(n) BFS queue** — `queue.removeAt(0)` on List in `_findMergeGroup`. | Perf | `bubble_manager.dart:698–735` |
| H3 | **No viewport culling** — all components update/render regardless of camera. | Perf | All `lib/flame/components/` |
| H4 | **DateTime.now() per frame per bubble** — should use `dt` accumulator. | Perf | `video_bubble_component.dart:407–445` |
| H5 | **Single reconnect attempt, no backoff** — 2s fixed delay, one try, then permanent disconnect. | Prod Ready | `room_session.dart:235–261` |
| H6 | **Non-atomic Firestore writes** — `updateRoomMap` + `updateRoomName` are separate writes. | Prod Ready | `room_service.dart:56–66`, `main.dart:577–583` |
| H7 | **seedWizardsTower race** — simultaneous first-logins create duplicate rooms. | Prod Ready | `room_service.dart:142–176` |
| H8 | **Diagnostic print() in production** — 6 bare `print('[DIAG]...')` in video pipeline. | Perf + Prod | `video_frame_web_v2.dart:339–426` |
| H9 | **[skip-tests] deploy bypass** — any commit message can skip tests and deploy to prod. | Prod Ready | `.github/workflows/deploy.yml:47,81–85` |
| H10 | **No dev/staging environment** — hardcoded LiveKit URL + Firebase project. | Prod Ready | `livekit_service.dart:67` |
| H11 | **CRDT sync no error handling** — one malformed packet tears down collaborative editor stream. | Prod Ready | `map_sync_service.dart:676–773` |

### MEDIUM (14)

| # | Finding | Audit | File(s) |
|---|---------|-------|---------|
| M1 | `_buildBubblePath` called twice per render pass (64-point sinusoidal path). | Perf | `video_bubble_component.dart:648,725` |
| M2 | Paint per scan line in `_drawHologramBoot` (~20 allocations/frame). | Perf | `video_bubble_component.dart:788–845` |
| M3 | `otherPlayerPositions` clones Map every 200ms. | Perf | `tech_world.dart:372–385` |
| M4 | `TextPainter` not disposed in `PlayerBubbleComponent`, `BotBubbleComponent`. | Perf | `player_bubble_component.dart:58–76` |
| M5 | `_findMergeGroup` BFS runs every frame even when no bubble moved. | Perf | `bubble_manager.dart:649–695` |
| M6 | JPS grid clone (64×64) on every tap. | Perf | `path_component.dart:64–73` |
| M7 | `locate<TechWorld>()` called 6+ times per build. | Perf | `main.dart` |
| M8 | `code_forge_web` git fork bypasses pub.dev; diverging from upstream 2.9.0. | Deps | `pubspec.yaml` |
| M9 | 62 packages behind resolvable versions. | Deps | `pubspec.lock` |
| M10 | **Speaking-stopped never emitted** — voice ripples never dismiss for remote participants. | Prod Ready | `livekit_service.dart:714–718` |
| M11 | `enableMedia()` swallows camera/mic errors. | Prod Ready | `room_session.dart:203–207` |
| M12 | No analytics events — user journeys invisible. | Prod Ready | — |
| M13 | Image decoding on main isolate blocks UI. | Prod Ready | `main.dart:654–661` |
| M14 | Dreamfinder API key committed with literal default. | Prod Ready | `room_session.dart:135–139` |

### LOW (7)

| # | Finding | Audit | File(s) |
|---|---------|-------|---------|
| L1 | 5 sequential `setState()` during startup. | Perf | `main.dart:164–214` |
| L2 | Up to 4096 individual SpriteComponents for tile objects. | Perf | `tile_object_layer_component.dart:57–120` |
| L3 | `_updateShaderUniforms()` runs every frame for disabled shader. | Perf | `video_bubble_component.dart:635–639` |
| L4 | `_leaveRoom` not guarded against re-entry. | Prod Ready | `main.dart:466–499` |
| L5 | `re_highlight` at 0.0.3 pre-release (niche dep risk). | Deps | `pubspec.yaml` |
| L6 | No explicit player count cap — performance cliff at 10+ participants. | Prod Ready | — |
| L7 | Progress is client-authoritative (no server-side validation). | Prod Ready | — |

---

## Pattern-Based Remediation

The synthesis phase identified that **most findings cluster around missing or inconsistently-applied patterns**. The following fixes are ordered by blast radius (how many findings each resolves):

### Fix A: Chain of Responsibility for Error Handling → fixes C1, H8, H11

**Missing pattern:** No error pipeline. Errors are treated as exceptional rather than as a signal class flowing through a chain.

**Implementation:**
```dart
// main.dart
void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(...);
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    runApp(const MyApp());
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

// map_sync_service.dart — add onError to stream subscription
_dataSubscription = ...listen(_onDataReceived, onError: (e, st) {
  _log.severe('CRDT stream error', e, st);
});

// video_frame_web_v2.dart — replace 6 print() with _log.fine()
```

**Resolves:** C1 (crash reporting), H8 (diagnostic prints), H11 (CRDT stream teardown).

### Fix B: Flyweight + Template Method Base Class → fixes H1, M1, M2, M4

**Root cause:** Flyweight applied at module level (static constants) but not at instance level. Each bubble component creates Paints ad-hoc in `render()`.

**Implementation:** Create `BubbleComponent extends PositionComponent`:
- `onLoad()` allocates all `Paint` instances as final fields
- `render()` is Template Method: `renderShadow()` → `renderBackground()` → `renderContent()` → `renderBorder()`
- `TextPainter` pre-allocated, `layout()` on state change not per frame
- `_buildBubblePath` called once per frame, cached

**Resolves:** H1 (per-frame allocations), M1 (double path build), M2 (hologram scan paints), M4 (TextPainter leak).

### Fix C: State Machine for Reconnection → fixes H5

**Root cause:** `_ConnectionState` enum is a tag, not a behavior carrier. Reconnection logic is imperative with no backoff.

**Implementation:** Promote to sealed class:
```dart
sealed class ConnectionState {}
class Disconnected extends ConnectionState {}
class Connecting extends ConnectionState {}
class Connected extends ConnectionState {}
class Reconnecting extends ConnectionState { final int attempt; final Duration delay; }
class ReconnectFailed extends ConnectionState {}
```
Exponential backoff: 2s → 4s → 8s (max 3 attempts). Replaces `_disposed` + `_isReconnecting` boolean pair.

**Resolves:** H5 (single reconnect), plus makes connection lifecycle testable.

### Fix D: Unit of Work for Firestore → fixes H6, H7

**Root cause:** No pattern enforcing atomic writes.

**Implementation:**
```dart
// Combine into single WriteBatch
Future<void> saveRoom(String roomId, GameMap map, String name) async {
  final batch = _firestore.batch();
  batch.update(ref, {'mapData': ..., 'name': ..., 'updatedAt': FieldValue.serverTimestamp()});
  await batch.commit();
}

// Use transaction for seedWizardsTower
await _firestore.runTransaction((tx) async {
  final snapshot = await tx.get(query);
  if (snapshot.docs.isEmpty) {
    tx.set(newRoomRef, {...});
  }
});
```

**Resolves:** H6 (non-atomic writes), H7 (duplicate room race).

### Fix E: Stateful Observer for Speaking → fixes M10

**Root cause:** Observer publisher emits only the positive arm. No state to diff previous speakers.

**Implementation:** Add `_previousSpeakers = <String>{}` to `LiveKitService`. Diff against `event.speakers` to synthesise `(participant, false)` events.

**Resolves:** M10 (voice ripples never dismiss).

### Fix F: Dirty Flag + Queue for BFS → fixes H2, M5

**Root cause:** No Memento/dirty-flag to skip BFS when positions unchanged. Wrong data structure for queue.

**Implementation:** `bool _bubblePositionsDirty = false` set on position change; `Queue<String>` from `dart:collection`.

**Resolves:** H2 (O(n) dequeue), M5 (per-frame BFS when no motion).

### Fix G: Composite + Picture Cache for Object Tiles → fixes L2, partially H3

**Root cause:** Floor tiles use Composite+Picture (correct); object tiles use 4096 individual sprites (inconsistent).

**Implementation:** Batch static object tiles into `ui.Picture` during `onLoad()`. Only dynamic tiles (editor mode) need individual components.

**Resolves:** L2 (4096 sprites), partially H3 (reduces render call count).

### Fix H: Adapter Around LiveKit SDK → fixes M8 (partially)

**Root cause:** SDK types (`RemoteParticipant`, `VideoTrack`) leak through `LiveKitService` public API.

**Implementation:** Define `AppParticipant`, `AppVideoTrack`. Convert at LiveKit boundary. This creates a seam for testing and reduces `code_forge_web` coupling.

---

## Cross-Cutting Themes

### Theme 1: Pattern Applied Once, Not Generalized

Three distinct instances:
- **Flyweight:** Applied to floor tile `Paint` constants → not to bubble `Paint` instances
- **Composite+Picture:** Applied to floor tile layer → not to object tile layer
- **Facade:** Applied to service layer (`RoomSession`) → not to world layer (`TechWorld`)

The codebase has good pattern literacy. The gap is architectural enforcement — no mechanism ensures a successful pattern application is extended to structurally similar code.

### Theme 2: Observer Complete in Subscribers, Broken in Publisher

All four Observer chains (LiveKit streams, ValueNotifiers, proximity, CRDT) handle subscription lifecycle correctly. The single broken instance is `speakingChanged` — it emits `true` but never `false`. The subscribers are defensive; the publisher is a thin SDK wrapper that didn't audit completeness.

**Rule for new streams:** Every SDK event wrapping must verify both entry and exit signals are emitted.

### Theme 3: Production Events Have No Sinks

Three event types need production sinks — none exist:
1. **Error events** → no Crashlytics
2. **Analytics events** → no Firebase Analytics
3. **Diagnostic events** → bare `print()` instead of structured logging

The `package:logging` infrastructure is already in place (`_log = Logger(...)`) — it just needs production-grade sinks attached at the root logger.

### Theme 4: State Pattern Used as Label, Not Behavior

Both `_ConnectionState` and `BotStatus` are tag enums. Behavior is scattered through `if`/`switch` in calling code. Adding a new state (e.g., "reconnecting-with-backoff") requires modifying every consumer — violating the Open-Closed Principle.

### Theme 5: Security Surface Has No Pattern Boundary

Firebase API keys and Dreamfinder API key are secrets at the wrong abstraction level. `const String.fromEnvironment(...)` with a committed literal default bakes secrets into repo history forever.

---

## Recommended PR Groupings (Phase 5 Fixes)

Following the convention: bundle trivial fixes; separate PRs for design decisions.

| PR | Fix | Type | Cage-match? |
|----|-----|------|-------------|
| 1 | Crashlytics + `runZonedGuarded` + `FlutterError.onError` | Fix A (partial) | No — well-established pattern |
| 2 | Replace 6 diagnostic `print()` → `_log.fine()` + CRDT stream `onError` | Fix A (partial) | No — mechanical |
| 3 | `BubbleComponent` base class with pre-allocated Paints | Fix B | **Yes** — new type, design decision |
| 4 | Reconnection backoff State Machine | Fix C | **Yes** — changes connection lifecycle |
| 5 | Firestore `WriteBatch` + `seedWizardsTower` transaction | Fix D | No — standard Firestore pattern |
| 6 | Speaking-stopped Observer fix | Fix E | No — small, clear |
| 7 | BFS dirty flag + Queue data structure | Fix F | No — algorithm fix |
| 8 | `DateTime.now()` → `dt` accumulator in video bubbles | Standalone | No — mechanical |
| 9 | Dependency upgrades: `flutter pub upgrade` (minor versions) | Standalone | No — within constraints |

**Items deferred to Nick:**
- C2: Android release signing (requires production keystore)
- C3: Firebase API keys gitignore (requires key rotation)
- H9: `[skip-tests]` deploy bypass (deploy pipeline governance)
- H10: Staging environment (infrastructure decision)
- M8: `code_forge_web` git fork → pub.dev migration (Nick's fork)
- M14: Dreamfinder API key default removal (key rotation)

---

## Appendix: Dependency Details

### Outdated Packages (Tier 1 — Major Version Jumps)

| Package | Current | Latest | Gap |
|---------|---------|--------|-----|
| `file_picker` | 8.3.7 | 11.0.2 | 3 major |
| `sign_in_with_apple` | 7.0.1 | 8.0.0 | 1 major (SPM) |
| `xml` | 6.6.1 | 7.0.1 | 1 major |
| `flame_test` | 1.19.2 | 2.2.4 | 1 major |

### Outdated Packages (Tier 2 — Minor Version Bumps, Safe to Upgrade)

| Package | Current | Latest |
|---------|---------|--------|
| `flame` | 1.34.0 | 1.37.0 |
| `livekit_client` | 2.6.1 | 2.7.0 |
| `firebase_core` | 4.3.0 | 4.7.0 |
| `firebase_auth` | 6.1.3 | 6.4.0 |
| `cloud_firestore` | 6.1.1 | 6.3.0 |
| `dart_webrtc` | 1.6.0 | 1.8.1 |
| `flutter_webrtc` | 1.2.1 | 1.4.1 |

### Supply Chain

- **No CVEs** affecting current versions
- **No unused dependencies** (all 25 direct deps confirmed imported)
- **No license conflicts** (MIT/BSD-3/Apache 2.0 throughout)
- **One git dependency:** `code_forge_web` (Nick's fork, commit-pinned)
