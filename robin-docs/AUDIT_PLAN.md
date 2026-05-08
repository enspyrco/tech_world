# Tech World Audit Plan

## What This Is

A comprehensive audit of [Tech World](https://github.com/enspyrco/tech_world) — a distributed multiplayer educational game built with Flutter/Dart, Flame engine, LiveKit, and Firebase. This is NOT a web app. It's a game engine with real-time communication, autonomous AI agents, collaborative CRDT editing, 3 video capture pipelines, and a built-in IDE with LSP.

## Fork Setup

```
origin   → git@github.com:RaggedR/tech_world.git   (Robin's fork)
upstream → https://github.com/enspyrco/tech_world   (enspyrco — Nick's repo)
```

## Skills Inventory (25 tw- skills)

### Layer 1 — Adapted Generic Skills (17)

| Skill | What It Audits |
|-------|---------------|
| `/tw-design-patterns` | GOF patterns with Flame Component/ECS, Service Locator, ValueNotifier Observer |
| `/tw-tech-debt` | Coupling, god widgets, stringly-typing, missing const, dead code |
| `/tw-style-review` | Dart idioms, CLAUDE.md conventions (enum over String), Dart 3 features |
| `/tw-add-events` | Event-sink with Dart records, LiveKit/Firestore side effects |
| `/tw-architecture-sweep` | Ousterhout's principles + Flame component depth, flutter_test contracts |
| `/tw-category-sweep` | Writer monad (WithEvents), CRDT monoid, Stream functor, flutter_test laws |
| `/tw-test-health-audit` | Flutter test pyramid, flame_test, fake_cloud_firestore, coverage gaps |
| `/tw-state-machine-sweep` | 10 enums + _MyAppState implicit machine, random walk invariants |
| `/tw-performance-profile` | Widget rebuilds, Flame render loop, video frame processing, memory |
| `/tw-production-ready` | Flutter client 6-dimension audit (Crashlytics, LiveKit resilience, CRDT) |
| `/tw-read-logs` | Flutter process/device/build logs, analyzer output |
| `/tw-security-audit` | Hardcoded API keys, Firestore rules bypass, LiveKit spoofing, FFI safety |
| `/tw-fuzz-sweep` | LiveKit message parsing, Firestore deserialization, map/tileset parsing |
| `/tw-production-sinks` | FileSink (path_provider), CrashlyticsSink, ConsoleSink (dev only) |
| `/tw-sweep1` | Orchestrator: /tw-design-patterns → /tw-security-audit + /dependency-audit → synthesis |
| `/tw-sweep2` | Orchestrator: /tw-design-patterns → /tw-tech-debt + /tw-style-review + /tw-test-health-audit → synthesis |
| `/tw-sweep3` | Orchestrator: /tw-design-patterns → /tw-performance-profile + /dependency-audit + /tw-production-ready → synthesis |

### Layer 2 — Game-Specific Skills (8)

| Skill | What It Audits |
|-------|---------------|
| `/tw-protocol-audit` | 22-topic LiveKit wire protocol — schemas, reliability, backward compat |
| `/tw-distributed-state` | Multiplayer consistency — concurrent doors, position sync, CRDT divergence |
| `/tw-flame-audit` | Game engine — depth sorting, pathfinding, bubble physics, shaders, disposal |
| `/tw-video-pipeline` | 3 capture pipelines (FFI, JS interop, iframe) — buffer safety, Skia constraints |
| `/tw-challenge-audit` | 41 challenges, spell bijection, door gating, evaluation reliability |
| `/tw-crdt-audit` | LWW merge laws, Lamport clocks, late-join sync, undo interaction |
| `/tw-platform-parity` | 4 platforms, 6 conditional imports, WASM constraints, feature matrix |
| `/tw-bot-integration` | 3 AI agents — evaluation parsing, oracle timeouts, health monitoring |

---

## Audit Execution Order

### Phase 1: Foundation (understand what we have) — DONE

1. `/tw-design-patterns` — establish pattern vocabulary
2. `/tw-protocol-audit` — map the 22-topic wire protocol

### Phase 2: Correctness (does it work right?) — DONE

3. `/tw-distributed-state` — multiplayer state consistency
4. `/tw-crdt-audit` — collaborative editing algebraic laws
5. `/tw-state-machine-sweep` — formalize the implicit state machine
6. `/tw-challenge-audit` — educational content integrity

### Phase 3: Quality (is the code healthy?) — DONE

7. `/tw-sweep2` — tech-debt + style + test-health (orchestrated)
8. `/tw-flame-audit` — game engine health
9. `/tw-video-pipeline` — video capture correctness

### Phase 4: Security — DONE

10. `/tw-sweep1` — security + dependencies (orchestrated)
11. `/tw-bot-integration` — AI agent testing
12. `/tw-platform-parity` — cross-platform feature matrix

### Phase 5: Operations — DONE

13. `/tw-sweep3` — performance + dependencies + production-ready (orchestrated)

### Phase 6: Structural (deep) — IN PROGRESS

14. `/tw-add-events` — **DONE** — refactor side effects to pure event returns
    - Also ran `/tw-production-sinks` — console + JSONL file sinks
    - 34 event types, 40 dispatch sites, 10 files, 77 E2E tests
15. `/tw-architecture-sweep` — module depth + contract tests
16. `/tw-category-sweep` — categorical law verification

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    TECH WORLD — Architecture                     │
└─────────────────────────────────────────────────────────────────┘

7 System Boundaries:
  1. LiveKit Data Channels  — WebRTC, 22+ topics, custom wire protocol
  2. Firestore              — 4 collections (users, rooms, messages, conversations)
  3. Firebase Storage       — profile pics + tilesets
  4. Firebase Functions     — 1 callable (retrieveLiveKitToken)
  5. Dreamfinder API        — HTTPS POST /api/game/event (fire-and-forget)
  6. LSP Server             — WebSocket wss://lsp.adventures-in-tech.world
  7. Three.js Avatar        — postMessage iframe (42MB GLB model)

3 Bots:
  - bot-claude (Clawd)       — code tutor, evaluation, help hints
  - bot-gremlin (Gremlin)    — hype creature
  - bot-dreamfinder          — voice interactive, infra health, 3D avatar

4 Platforms:
  - Web (Chrome full, Safari/Firefox partial)
  - macOS (FFI video, Apple Sign-In)
  - iOS (limited)
  - Android (limited)

Game Systems:
  - 50×50 grid world, 32px tiles
  - JPS pathfinding with Bresenham expansion
  - Depth-sorted tile rendering with occlusion
  - Video bubbles with metaball shader + merge shader
  - CRDT collaborative map editor (LWW, Lamport clock)
  - 23 code challenges + 18 prompt challenges + 18 words of power + 5 spell combos
  - Speech-to-text spell casting with confidence lattice
  - 3 procedural map generators (cave, dungeon, maze)
```

## Audit Progress

| # | Phase | Skill | Status | Report |
|---|-------|-------|--------|--------|
| 1 | Foundation | `/tw-design-patterns` | **Done** | 13 patterns, 5 misuses, 4 anti-patterns → `phase1-design-patterns.md` |
| 2 | Foundation | `/tw-protocol-audit` | **Done** | 25 topics, 3 CRIT / 5 HIGH / 5 MED / 4 LOW → `phase1-protocol-audit.md` |
| 3 | Correctness | `/tw-distributed-state` | **Done** | 2 CRIT / 4 HIGH / 3 MED / 1 LOW → `phase2-distributed-state.md` |
| 4 | Correctness | `/tw-crdt-audit` | **Done** | All 3 algebraic laws hold. 1 P1 / 3 P2 / 5 P3 / 1 P4 → `phase2-crdt-audit.md` |
| 5 | Correctness | `/tw-state-machine-sweep` | **Done** | 30 enums, 7 FSMs, 4 implicit machines → `phase2-state-machine-sweep.md` |
| 6 | Correctness | `/tw-challenge-audit` | **Done** | 41 challenges verified, bijection holds → `phase2-challenge-audit.md` |
| 7 | Quality | `/tw-sweep2` | **Done** | Tech Debt 2.5/5, Style 3.5/5, Test Health 3.4/5 → `phase3-sweep2-code-quality.md` |
| 8 | Quality | `/tw-flame-audit` | **Done** | 2 HIGH / 8 MED / 9 LOW → `phase3-flame-audit.md` |
| 9 | Quality | `/tw-video-pipeline` | **Done** | 2 HIGH / 5 MED / 10 LOW → `phase3-video-pipeline.md` |
| 10 | Security | `/tw-sweep1` | **Done** | Composite 3.2/5 → `phase4-sweep1-security.md` |
| 11 | Security | `/tw-bot-integration` | **Done** | 3 HIGH / 7 MED / 4 LOW → `phase4b-bot-integration.md` |
| 12 | Security | `/tw-platform-parity` | **Done** | 1 CRIT / 2 HIGH / 3 MED / 2 LOW → `phase4b-platform-parity.md` |
| 13 | Operations | `/tw-sweep3` | **Done** | Perf 3.2/5, Deps 3.2/5, Prod 3.25/5 → `phase5-sweep3-operations.md` |
| 14 | Structural | `/tw-add-events` | **Done** | 34 events, 40 dispatch sites, console + JSONL sinks, 77 E2E tests → PR #412 |
| 15 | Structural | `/tw-architecture-sweep` | **Done** | LiveKitTopic enum, SpeakerRole enum, DI injection, LiveKitGameBridge, DoorManager, botStatusNotifier eliminated, applyCodeSubmitEffects, 108 contract tests, ARCHITECTURE.md → PR #413 |
| 16 | Structural | `/tw-category-sweep` | **Done** | Sealed AuthUser, .whereMap Kleisli extension, sealed _TokenResult Either, derived CastResult.passed, 165 law + FSM tests, CATEGORY_THEORY.md → PR #414 |

## PR Summary

| Phase | PRs | Range | Cage-matches |
|-------|-----|-------|-------------|
| 3a: Sweep2 fixes | 14 | unnumbered–#337 | 5 (DataTopic, BotResponse, Dreamfinder, BubbleManager, RoomSession) |
| 3b: Flame + Video | 13 | #351–#363 | 4 (door pathfinding, spawn safety, bubble physics, player priority) |
| 4a: Security | 14 | #381–#394 | 4 (protocol version, DM sender, position bounds, door unlock) |
| 4 follow-ups | 5 | #395–#396 | — |
| 4b: Bot + Platform | 9 | #397–#405 | 2 (bot tap toggle, eval parsing) |
| 5: Operations | 6 | #406–#411 | 2 (Paint cache, reconnect backoff) |
| 6: Structural | 3 | #412–#414 | 4 (event system, E2E tests, architecture-sweep, category-sweep) |
| **Total** | **64** | | **21** |

## Known Issues Resolved

These were identified in Phase 1 and fixed across subsequent phases:

| Issue | Fixed In |
|-------|----------|
| Hardcoded API key (DreamfinderClient) | Phase 3a (#382) |
| Firestore rules regex bypass | Phase 4a (#384, #386) |
| Unversioned protocol | Phase 4a (#388) |
| God widget `_MyAppState` | Phase 3a (#337 — RoomSession extraction) |
| God component `TechWorld` | Phase 3a (#320 — BubbleManager extraction) |
| Dead LiveKit scaffolding (2,849 lines) | Phase 3a (delete-dead-livekit) |
| No crash reporting | Phase 5 (#407 — Crashlytics) |
| Single reconnection attempt | Phase 5 (#411 — exponential backoff) |
| Per-frame Paint allocations | Phase 5 (#410 — Flyweight caching) |
| Non-atomic Firestore writes | Phase 5 (#408 — WriteBatch) |
| No structured event logging | Phase 6 (#412 — 34 event types, JSONL file sink) |
| No E2E event tests | Phase 6 (#412 — 77 tests, capture-sink pattern) |
| Scattered topic string literals | Phase 6 (#413 — LiveKitTopic enum, 26 values across 10 files) |
| Locator calls inside widgets | Phase 6 (#413 — DI injection for MapSyncService, ProgressService) |
| No architecture contract tests | Phase 6 (#413 — 108 tests in test/architecture/) |
| Global mutable `botStatusNotifier` | Phase 6 (#413 — ChatService owns `_botStatus`, exposes `ValueListenable`) |
| 14 subscription fields in TechWorld | Phase 6 (#413 — LiveKitGameBridge extraction, 260 lines) |
| Door logic scattered in TechWorld | Phase 6 (#413 — DoorManager extraction, 152 lines) |
| Duplicated challenge-completion logic | Phase 6 (#413 — `_persistCompletion` + `applyCodeSubmitEffects`) |

## Items Deferred to Nick

| Item | Why |
|------|-----|
| Android release signing | Requires production keystore |
| Firebase API key rotation | Keys in repo history; needs `.gitignore` + rotation |
| `[skip-tests]` deploy bypass | Deploy pipeline governance decision |
| Staging environment | Infrastructure: separate LiveKit + Firebase project |
| `code_forge_web` fork → pub.dev | Nick's fork; upstream macOS patch or migrate to 2.9.0 |
| Dreamfinder API key default | Key in repo history; needs rotation |
| iOS/Android video gap | Platform feature decision |
| Firefox STT gap | Browser API limitation |
| Firestore rules deploy | Security rules need deployment |
| Legacy DM migration | Data migration decision |
