# The Orchestration Pivot

**TL;DR:** Tech World evolves from "learn to code" to "learn to orchestrate AI agents." The game world stays. Terminals become orchestration stations with two modes: **Blueprint Mode** (visual pipeline builder for Tier 1-2) and **Code Mode** (Dart orchestration code for Tier 3-4).

## Why

Writing code is a solved educational problem — there are hundreds of apps that teach it. But orchestrating AI agents is the defining skill of 2026: defining goals and constraints for non-deterministic collaborators, managing unreliable systems, optimizing for cost/quality/speed tradeoffs.

Nobody has gamified this yet.

## The Learning Arc: Blueprint → Code

| Tier | Mode | What Players Do |
|------|------|----------------|
| 1-2 | **Blueprint** | Visual pipeline builder — drag agents, draw connections, write system prompts |
| 3-4 | **Code** | Dart code editor with LSP — write real orchestration code against an SDK |

Players graduate from visual concepts to programmatic implementation. This mirrors how professional tools evolve (Zapier → code, AWS Step Functions visual → CDK).

## Documents

| Document | What It Covers |
|----------|---------------|
| [Game Design](game-design.md) | Vision, dual-mode design, 23 scenarios across 4 tiers, scoring, progression, maps, Clawd's new role, multiplayer dynamics, open questions, phased rollout |
| [Architecture](architecture.md) | Data models, orchestration SDK, Firestore schema, pipeline execution, UI widget tree, service changes, migration path, Cloud Function design, testing strategy |

## What Changes vs. What Stays

### Changes
- Terminal stations → Orchestration stations (Blueprint or Code mode)
- 23 Dart challenges → 23 orchestration scenarios
- `ProgressService` → `ScoreService` + `LeaderboardService`
- Clawd: code tutor → orchestration advisor

### Extends (Reused)
- `CodeEditorPanel` — reused for Code Mode (Tier 3-4)
- LSP server — retained, workspace updated with orchestration SDK
- `lsp_config.dart` — unchanged

### Stays (Everything Else)
- Flame game engine, all maps, movement, pathfinding
- LiveKit multiplayer, proximity video, data channels
- Firebase Auth, Firestore, Cloud Functions, Hosting
- Map editor (retained fully)
- Chat service + Clawd bot infrastructure
- Service locator architecture
- All deployment infrastructure

## Phased Rollout

| Phase | Duration | Deliverable |
|-------|----------|-------------|
| 1: Foundation | 4 weeks | Scenario model, 5 Tier 1 (Blueprint, simulated), basic blueprint panel, Clawd as advisor |
| 2: Pipelines + Code | 4 weeks | Multi-agent blueprints, 7 Tier 2 (Blueprint), Code Mode + SDK, 2 Tier 3 (Code), real API execution, leaderboards |
| 3: Full Complexity | 4 weeks | 4 remaining Tier 3 (Code — retries, circuit breakers), full scoring, progression, map re-theming |
| 4: Community | 4 weeks | 5 Tier 4 (Code — adversarial, creative), community challenges, pipeline/code sharing, group challenges |

## Open Questions

See [Game Design — Open Questions](game-design.md#open-questions) for the 6 key decisions that need resolution before Phase 1 begins.
