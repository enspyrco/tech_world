# 🜂 CRUCIBLE — Realm engine extraction (event-sink + PII core)

**Ore selected:** 2026-07-25 · #1384 / #23 · seed-biased (Realm engine extraction), scout hand-verified against live code.

## The pick

Extract the reusable Flutter/Flame/LiveKit multiplayer framework's **event-sink + PII core** as the first cut of the Apache-2.0 "Realm engine":

- **Engine machinery** (~270 lines, pure infrastructure, zero game content): `AppEvent` base contract, `PiiPolicy`, `dispatch`, sink registration (`registerSink`/`registerRemoteSink`/async variants), `logger_bridge`.
- **Engine-flavored events** (~400 lines): the infrastructure-category events the sinks route on — `AvPipelineSnapshot`, `LiveKitConnected/Disconnected`, `AppLogRecord`, `PlayerMoved`, proximity, room-lifecycle.
- **First proving consumer:** `ProximityService` (120 lines, one file, zero game concepts, imports only `events/dispatch` + `events/types`).

**Stays in tech_world (game content, ~1000 lines):** `WordLearned`, `SpellCastFailed`, `DoorUnlocked`, `TerminalOpened`, `MapEdited`, `BotSpoke`, challenge events, plus the exhaustive `sealed`-switch PII marker test.

## Why this one (aliveness × impact)

- **Aliveness 3** — the most defensible "framework" claim in the repo: pure infrastructure discipline, an analyzer-enforced PII topology, zero game content. The thing another builder who's "noticing" could adopt directly.
- **Impact 3** — removes a real thing: the PII gate's rigor is currently trapped in tech_world; extracted, it becomes a reusable topology any LiveKit-Flame multiplayer app inherits. Also the *dependency root* — proximity (and later bridges) can't extract until the event bus does.

## The falsifier (what proves this ore is slag)

The engine/game **event partition cannot be drawn cleanly**. If >~30% of the 48 `AppEvent` subtypes are irreducibly bi-valent (`PlayerMoved` — engine-generic multiplayer position, or tech_world-specific movement? `RoomJoined`? `CodeSubmitted`?), the extracted engine either drags game vocabulary across the boundary or leaves the game with a crippled event set. If so, the event system is NOT the clean first cut — proximity-alone or the LiveKit bridge wins. **Temper strikes this directly.**

## The two known cracks (topology, not find-replace)

1. **`sealed` cannot cross a package boundary.** `AppEvent` must become `abstract` in the engine (Dart requires sealed subtypes in the same library). The PII gate survives because its teeth are the **abstract `piiPolicy` getter**, not `sealed` — verified: the runtime gate (`registerRemoteSink`) switches on `PiiPolicy`, never on `AppEvent` subtypes. `sealed` only bought the test's exhaustive switch, which stays in tech_world with the game events.
2. **The engine/game event partition is a judgment call**, not a mechanical boundary — and it IS the falsifier above.

## Settled — do NOT re-litigate

- Licensing: AGPL v3 game / Apache-2.0 framework (#7/#23/#1059/#1384).
- Precedent: `code_forge_web` already extracted this way.
- Pluggable PII policy interface (scope #3): **do NOT build speculatively.** `PiiPolicy{none, pii}` is a sane default a second consumer inherits fine. Add the interface only when a real consumer chafes (`remove-the-coupling` / ship-simple-pick-before-next-abstraction).

## GRANT FIREWALL (hold the whole time)

Engineering only. Must stay **rhetorically invisible** in the Screen Australia GPF application (#44, closes 5pm AEST Thu 27 Aug 2026). SA flags "learning project whose scope evolved into an engine" as an eligibility RISK. Build it real; pitch only the game. This document and everything downstream of it is ⊗ from the grant narrative.

## Blast radius

23 files import `events/types.dart` — mechanical import-path rewrite (`package:tech_world/events/...` → `package:realm_engine/events/...`), not topology. Shared-type change → workspace-wide verification required.
