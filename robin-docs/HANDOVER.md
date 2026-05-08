# Handover — Tech World Audit

**Date:** 2026-05-09
**Status:** Phases 1–5 complete, Phase 6 in progress. 63 PRs shipped, 4 architectural refactors, 14 audit reports, 20 cage-match reviews. 1686 tests passing.

---

## What's Been Done

### Phase 1: Foundation (complete)
- `/tw-design-patterns` — 13 patterns identified, 5 misuses, 4 anti-patterns → `phase1-design-patterns.md`
- `/tw-protocol-audit` — 25 LiveKit topics mapped → `phase1-protocol-audit.md`

### Phase 2: Correctness (complete)
- `/tw-distributed-state` → `phase2-distributed-state.md`
- `/tw-crdt-audit` → `phase2-crdt-audit.md`
- `/tw-state-machine-sweep` — 30 enums, 7 FSMs, 4 implicit machines → `phase2-state-machine-sweep.md`
- `/tw-challenge-audit` — 41 challenges verified → `phase2-challenge-audit.md`

### Phase 3: Quality (complete)
- `/tw-sweep2` — tech debt + style + test health → `phase3-sweep2-code-quality.md`
- `/tw-flame-audit` — game engine health → `phase3-flame-audit.md`
- `/tw-video-pipeline` — 3 capture pipelines → `phase3-video-pipeline.md`
- **Refactor 1:** BubbleManager extracted from TechWorld (-33%) → `ARCHITECTURAL_REFACTOR1.md`
- **Refactor 2:** RoomSession extracted from _MyAppState (-10%) → `ARCHITECTURAL_REFACTOR2.md`
- **Refactor 3:** LiveKitGameBridge — 14 subscriptions extracted (260 lines) → PR #413
- **Refactor 4:** DoorManager — door unlock/proximity extracted (152 lines) → PR #413

### Phase 4: Security (complete)
- `/tw-sweep1` — security + deps + protocol → `phase4-sweep1-security.md`
- `/tw-bot-integration` — 3 AI agents, eval parsing, oracle → `phase4b-bot-integration.md`
- `/tw-platform-parity` — 4 platforms, WASM, stubs → `phase4b-platform-parity.md`

### Phase 5: Operations (complete)
- `/tw-sweep3` — performance (3.2/5) + deps (3.2/5) + production readiness (3.25/5) + pattern synthesis → `phase5-sweep3-operations.md`
- Cross-cutting theme: "pattern applied once, not generalised"
- 6 items deferred to Nick

### Phase 6: Structural (in progress)
- `/tw-add-events` + `/tw-production-sinks` — 34 sealed event types, 40 dispatch sites across 10 files, console + JSONL file sinks, log bridge for all `_log.*` calls → PR #412
- 77 E2E tests: pipeline smoke, per-type serialization, cast completion flow, proximity scenarios, session lifecycle sequences
- `fire_all_events.dart` CLI fires all 34 events as JSONL to stdout
- Cage-match: 2 rounds — caught empty-batch crash, hot-restart sink duplication, stringly-typed enum, PII in test data
- Docs: `robin-docs/LOGS.md` (event catalogue), `robin-docs/E2E.md` (test coverage)
- `/tw-architecture-sweep` — 10 refactors from `architect.tmp`:
  - `LiveKitTopic` enum (26 topics wired into 10 files)
  - `SpeakerRole` enum (replaces `'dreamfinder'`/`'user'` strings)
  - `calculateOpacity` moved to BubbleManager
  - `ProgressService`/`MapSyncService` DI injection
  - **`botStatusNotifier` eliminated** — ChatService owns `_botStatus` as `ValueListenable<BotStatus>`, 9 consumer sites updated, global removed
  - **`applyCodeSubmitEffects`** — shared `_persistCompletion` helper, code path dispatches `ChallengeCompleted`
  - **`LiveKitGameBridge`** — 14 subscriptions + InfraHealthService extracted (260 lines)
  - **`DoorManager`** — unlock, proximity, remote-unlock extracted (152 lines)
  - TechWorld: 1570 → 1299 lines
  - 108 contract tests in `test/architecture/`, `ARCHITECTURE.md`
  - → PR #413, cage-match: architect.tmp leak, force-unwrap, stale docs
  - **Deferred:** MapLoader extraction (~400 lines, 10+ dependencies)
- Remaining: `/tw-category-sweep`

---

## 63 PRs Shipped

All PRs opened against upstream (`enspyrco/tech_world`). None merged by Nick yet.

### Phase 6 — Structural (2 PRs, #412–#413)

| PR# | Branch | What | Cage-match |
|-----|--------|------|------------|
| #412 | `audit/add-events` | Event-sink system: 34 types, 40 dispatch sites, sinks, log bridge, 77 E2E tests | 2 rounds (empty-batch crash, hot-restart, enum, PII) |
| #413 | `audit/architecture-sweep` | LiveKitTopic enum, SpeakerRole enum, DI injection, LiveKitGameBridge (260 lines), DoorManager (152 lines), botStatusNotifier eliminated, applyCodeSubmitEffects, 108 contract tests, ARCHITECTURE.md. TechWorld 1570→1299 lines. | 1 round (architect.tmp leak, force-unwrap, stale ARCHITECTURE.md) |

### Phase 3a — Sweep2 fixes (14 PRs)

| PR# | Branch | What | Cage-match |
|-----|--------|------|------------|
| — | `audit/dispose-notifiers` | Dispose 3 leaked ValueNotifiers + log shader failure | — |
| — | `audit/remove-api-key` | Remove hardcoded Dreamfinder API key | — |
| — | `audit/delete-dead-livekit` | Delete 2,849 lines dead LiveKit scaffolding | — |
| — | `audit/data-topic-enum` | 25-value `DataTopic` enum | Approved, nits fixed |
| — | `audit/bot-identity-constants` | `clawdBot.identity` constants | — |
| — | `audit/bot-response-type` | `BotResponse` class at service boundary | Approved, nits fixed |
| — | `audit/dreamfinder-state-enum` | `DreamfinderBehavior` enum | Approved, nits fixed |
| — | `audit/delete-proximity-service` | Delete dead service (-621 lines) | — |
| — | `audit/fix-livekit-tests` | Position parser + 8 fuzz tests | — |
| — | `audit/fix-test-delays` | 54 timing-dependent delays → Duration.zero | — |
| — | `audit/extract-connection-helpers` | Extract `_failureMessageFor` | — |
| #320 | `audit/extract-bubble-manager` | **Refactor 1** — 730 lines moved, 21 new tests | 2 rounds |
| #321 | `audit/add-ci-workflow` | CI for fork PRs | — |
| #337 | `audit/extract-room-session` | **Refactor 2** — 10 nullable fields → 1, 10 new tests | 1 round |

### Phase 3b — Flame + Video pipeline fixes (13 PRs, #351–#363)

| PR# | Branch | What | Cage-match |
|-----|--------|------|------------|
| #351 | `audit/fix-door-pathfinding` | **HIGH:** Invalidate JPS grid on door unlock | Approved, +2 tests |
| #352 | `audit/fix-native-frame-guard` | **HIGH:** `_nativeFrameInFlight` guard | — |
| #353 | `audit/fix-wasm-dynamic-types` | **HIGH:** `dynamic` → `Object?` in createFromStream | — |
| #354 | `audit/fix-map-spawn-safety` | **MED:** Cave/dungeon spawn safety + 3 tests | Approved, clamp fix |
| #355 | `audit/fix-bot-image-cache` | **MED:** `Flame.images` → `game.images` | — |
| #356 | `audit/fix-bubble-physics` | **MED:** FPS-independent repulsion | Approved, constant corrected |
| #357 | `audit/fix-player-priority` | **MED:** Deterministic depth-sort | 2 bugs found & fixed |
| #358 | `audit/fix-web-capture-init` | **MED:** `_asyncInitInFlight` guard | — |
| #359 | `audit/fix-pending-unmute` | **MED:** Static → instance `_pendingUnmute` | Approved, doc fix |
| #360 | `audit/fix-iframe-bridge` | **MED:** Canvas retry, origin check, safe mood cast | — |
| #361 | `audit/delete-dead-web-v1` | **LOW:** Delete 3 dead V1 files (-381 lines) | — |
| #362 | `audit/cleanup-diag-prints` | **LOW:** 8 prints → `_log.fine()` | — |
| #363 | `audit/cleanup-misc` | **LOW:** Readback null, FFI try/catch, BFS Queue | — |

### Phase 4a — Security fixes (14 PRs, #381–#394)

| PR# | Branch | What | Cage-match |
|-----|--------|------|------------|
| #381 | `audit/fix-infra-heal-targeting` | **HIGH:** Target infra-heal to Dreamfinder only | — |
| #382 | `audit/fix-dreamfinder-key-default` | **HIGH:** Remove hardcoded API key default | — |
| #383 | `audit/fix-map-edit-try-catch` | **HIGH:** Guard MapEditBatch.fromJson | — |
| #384 | `audit/fix-firestore-private-rooms` | **HIGH:** Restrict private room reads | — |
| #385 | `audit/fix-ffi-safety-guards` | **LOW:** FFI buffer size guard | — |
| #386 | `audit/fix-dm-regex-fallback` | **MED:** Remove bypassable regex | — |
| #387 | `audit/fix-editor-privilege-escalation` | **HIGH:** Block editor privilege escalation | — |
| #388 | `audit/add-protocol-version` | **LOW:** Add `v: 1` + `kProtocolVersion` constant | Approved |
| #389 | `audit/fix-dm-sender-trust` | **MED:** Transport senderId for DM + group chat | Approved |
| #390 | `audit/fix-position-bounds` | **MED:** Clamp remote position coordinates | Fixed: comments + 2 tests |
| #391 | `audit/fix-spriteasset-whitelist` | **MED:** Validate spriteAsset against avatars | — |
| #392 | `audit/wire-data-topic-enum` | **CRIT:** Wire DataTopic enum into 27 production sites | Fixed: unused import |
| #393 | `audit/pubdev-code-forge` | **DEP:** code_forge_web git → pub.dev ^2.9.0 | — |
| #394 | `audit/fix-door-unlock-sender` | **MED:** Verify door-unlock sender | Approved |

### Phase 4 cage-match follow-ups (5 PRs, #395–#396)

| PR# | Branch | What |
|-----|--------|------|
| #395 | `audit/fix-dispose-capture-unmute` | Cancel pendingUnmute before dispose |
| #396 | `audit/fix-bot-identity-set` | Centralise `_agentPrefixes` constant |
| — | (commit on #388) | Extract `kProtocolVersion` constant |
| — | (commit on #389) | Use transport senderId for group chat |
| — | (commit on #389) | Document senderName as cosmetic-only |

### Phase 4b — Bot Integration + Platform Parity (9 PRs, #397–#405)

| PR# | Branch | What | Cage-match |
|-----|--------|------|------------|
| #397 | `audit/fix-challenge-result-case` | Case-fold `challengeResult == 'pass'` | — |
| #398 | `audit/fix-help-timeout` | 60s → 30s help request timeout | — |
| #399 | `audit/fix-bot-spawn-index` | Guard botIndex for agent-* identities | — |
| #400 | `audit/fix-oracle-sender-scope` | Scope oracle response to bot sender | — |
| #401 | `audit/fix-adaptive-stream` | Default adaptiveStream false in dev page | — |
| #402 | `audit/fix-socket-exception-web` | Document SocketException platform split | — |
| #403 | `audit/fix-dynamic-param` | `dynamic` → `Object` in createFromVideoElement | — |
| #404 | `audit/remove-bot-tap-toggle` | Remove demo tap toggle mutating global state | Fixed: orphaned test |
| #405 | `audit/fix-eval-parsing` | Anchor RESULT/FEEDBACK parsing + brevity + dead loop | Fixed: regex, off-by-one, +4 tests |

### Phase 5 — Operations fixes (6 PRs, #406–#411)

| PR# | Branch | What | Cage-match |
|-----|--------|------|------------|
| #406 | `audit/sweep3-mechanical-fixes` | print→log, speaking-stopped, BFS queue, dt throttle, CRDT guard | — |
| #407 | `audit/add-crashlytics` | Firebase Crashlytics + `runZonedGuarded` + `FlutterError.onError` | — |
| #408 | `audit/firestore-atomicity` | `updateRoomMapAndName` + `seedWizardsTower` single-write | — |
| #409 | `audit/dep-upgrades` | 69 dependency upgrades (Flame 1.37, LiveKit 2.7, Firebase suite) | — |
| #410 | `audit/bubble-component-base` | Cache Paint objects + bubble path in 3 components | Fixed: TextPainter leak, dead path cache |
| #411 | `audit/reconnect-backoff` | Exponential backoff (2s→4s→8s) + auth abort + 3 new tests | Fixed: coupled constants, auth message, +3 tests |

---

## Cage-Match Pattern (confirmed across 20 reviews)

**Certainty correlates inversely with correctness.** Key catches across all phases:
- PR #410: Path cache looked solid but `_time` changes every frame — cache logically dead during speaking. TextPainter leak in `PlayerBubbleComponent` (missing `dispose()`).
- PR #411: `_maxReconnectAttempts` coupled to array length (latent `RangeError`). Auth-abort showed generic message. Test mock had counter-reset bug that silently passed while testing nothing.
- PR #405: Both reviewers caught `resultIndex > 0` off-by-one and `multiLine` + `(^|\n)` regex redundancy. Demanded adversarial injection tests — 4 added.
- PR #404: Kelvin found orphaned test calling deleted `onTapDown` — build-breaking compile error.
- PR #357: Two depth-sort bugs found during review.
- PR #392: Unused import failing CI.
- PR #412: Round 1 — `batch.ops.first` crash on empty undo batch (multi-version peer scenario), hot-restart doubles sinks, `CodeSubmitted.result` was String not enum. Round 2 — PII in test data, missing tearDown in fire-all-events CLI, weak assertions (containsAll → exact key set).
- PR #413: `architect.tmp` scratch file leaked into commit. `_handleHeartbeatReceived` force-unwrap (`_liveKitService!`) — both reviewers caught. `ARCHITECTURE.md` still listed completed refactors as pending (Kelvin's historical-context lens). Kelvin's `setBotStatus` ordering concern verified as false positive — all 4 call paths already correct.

---

## What's Next: Phase 6 — Remaining

| # | Skill | What It Covers |
|---|-------|----------------|
| 16 | `/tw-category-sweep` | Categorical law verification: CRDT monoid (associativity, identity, commutativity), Stream functor (composition, identity), event-sink natural transformations. |

The event system from #412 provides the `WithEvents<T>` Writer monad structure, and `ARCHITECTURE.md` from the architecture sweep documents the module structure. `/tw-category-sweep` can verify algebraic laws on both.

### Deferred from architecture sweep
- **MapLoader extraction** (~400 lines from TechWorld) — `_loadMapComponents` has 10+ dependencies (terminal interaction callbacks, tileset registry, pathComponent, game reference, editor mode notifier). Extract when next touching map-loading code, not speculatively.

---

## Key Files

| File | Purpose |
|------|---------|
| `robin-docs/AUDIT_PLAN.md` | Master audit plan with all 25 skills + progress table |
| `robin-docs/phase1-design-patterns.md` | 13 patterns, 5 misuses, 4 anti-patterns |
| `robin-docs/phase1-protocol-audit.md` | 25 LiveKit topics mapped |
| `robin-docs/phase2-distributed-state.md` | Multiplayer consistency findings |
| `robin-docs/phase2-crdt-audit.md` | CRDT algebraic law verification |
| `robin-docs/phase2-state-machine-sweep.md` | 30 enums, 7 FSMs, 4 implicit machines |
| `robin-docs/phase2-challenge-audit.md` | 41 challenges verified |
| `robin-docs/phase3-sweep2-code-quality.md` | Sweep2 consolidated report |
| `robin-docs/phase3-flame-audit.md` | Flame engine audit (2 HIGH, 8 MED, 9 LOW) |
| `robin-docs/phase3-video-pipeline.md` | Video pipeline audit (2 HIGH, 5 MED, 10 LOW) |
| `robin-docs/phase4-sweep1-security.md` | Sweep1 security + deps + protocol (3.2/5) |
| `robin-docs/phase4b-bot-integration.md` | Bot integration (3 HIGH, 7 MED, 4 LOW) |
| `robin-docs/phase4b-platform-parity.md` | Platform parity (1 CRIT, 2 HIGH, 3 MED, 2 LOW) |
| `robin-docs/phase5-sweep3-operations.md` | Sweep3 operations (3 CRIT, 11 HIGH, 14 MED, 7 LOW) |
| `robin-docs/ARCHITECTURAL_REFACTOR1.md` | BubbleManager extraction plan |
| `robin-docs/ARCHITECTURAL_REFACTOR2.md` | RoomSession extraction plan |
| `robin-docs/IMPRESSIVE.md` | Technical showcase for employers |
| `robin-docs/blog-post-tech-world.md` | Blog post draft for enspyr.co |
| `robin-docs/LOGS.md` | Event logging catalogue — 34 types, dispatch sites, JSONL format |
| `robin-docs/E2E.md` | E2E test coverage — 77 tests, what's tested and what's not |
| `ARCHITECTURE.md` | Module depth table, Flame component tree, layer diagram, sequence diagram, remaining refactors |

## Git Setup

```
origin   → git@github.com:RaggedR/tech_world.git   (Robin's fork)
upstream → https://github.com/enspyrco/tech_world   (enspyrco — Nick's repo)
```

All PRs opened against upstream. None merged by Nick yet (as of 2026-05-09).

## Conventions

- Bundle trivial fixes from the same audit into one PR; separate PRs for design decisions
- Branch names: `audit/<slug>`
- Cage-match review for PRs with design decisions (new types, refactors, architectural extractions)
- Skip cage-match for mechanical changes (deletions, find-replace, trivial fixes)
- **Max 3-4 parallel agents** — more overwhelms context
- Use worktree isolation for parallel agents
- Run `flutter analyze --fatal-infos` + `flutter test` before every commit
- CLAUDE.md updated when architecture changes

## Worktree Cleanup

Worktrees cleaned up at end of Phase 5. Run `git worktree list` to verify before starting new parallel work.
