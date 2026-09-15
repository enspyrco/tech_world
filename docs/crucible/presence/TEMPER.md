# TEMPER.md — presence ownership (who is in a room, and who may say so)

**Overall verdict:** RECAST
**Struck:** `dt-presence-1`, 2026-09-15. Families seated: **Maxwell + Kelvin + Carnot + Tesla (4/4)**. Wu disabled.
**Design struck:** `DESIGN.md` at the version recommending option (b).

> Bundle note: there is no `CRUCIBLE.md` / `SPARK.md` for this candidate — it came from a
> cage-match finding, not a crucible run. So the "catch what the enthusiasm smuggled in" angle
> had nothing to bite on, and the strike is correspondingly weaker on origin-assumptions.

## Per-family verdicts

| Family | Verdict | One-line |
|---|---|---|
| Maxwell (Claude) | RECAST | The option-frame never asks what the occupancy list is FOR, and the anti-(a) argument is guilt by vocabulary. |
| Kelvin (Gemini) | RECAST | False dichotomy — a periodic server-side reconciliation job is a third option that keeps graceful degradation. |
| Carnot (GPT) | RECAST | Right direction, but no replacement contract: auth boundary, cache semantics, degraded states, consumer audit all unspecified. |
| Tesla (Grok) | RECAST | `/presence` was a CHANNEL, not a store; replacing a push stream with a point query re-creates the reverted sweep as a cache. |

**No DISSOLVE.** The diagnosis (LiveKit owns connectedness; a client-written mirror cannot be
patched into truth) survived all four strikes. What failed is the *specification*, not the
direction.

## Fatal flaws (deduped, most-severe first)

1. **`/presence` is a CHANNEL, not only a store — and the design replaced a push stream with a point query without noticing.** — Tesla; confirmed by audit (`room_browser.dart:71` is `watchAll().listen(...)`, a live subscription). `listRooms`/`listParticipants` are strikes of a bell, not a sustained tone, so the first implementer polls or caches — **and a cache at 30s is the reverted TTL sweep in a new body**: people who are there hidden, people who left still glowing. **DISPOSITION: fold.** The design must specify a PROTOCOL (hydrate + live edge + server metronome), not "an endpoint", and name the ghost window as `max(hydrate interval, push delay)` in product terms.

2. **The anti-(a) argument is a category error.** — Maxwell, Kelvin, Tesla (3 families, independently). The cage-match condemned a *client-local clock* and a *filter with no metronome*. It did not condemn "compare LiveKit's roster to something, on a server timer". The note smuggled "the reverted implementation was bad" into "any TTL is bad". **DISPOSITION: fold.** Rewrite as: two stores plus a missed webhook is a ghost factory; the only clock we own is LiveKit's roster, evaluated server-side.

3. **A server-side reconciliation job is a third option the note never considered.** — Kelvin. Webhook for low-latency eviction + periodic reconcile against the LiveKit roster + Firestore retained as a *cache* gives the exit signal of (a), the authority of (b), and graceful degradation neither has alone. **DISPOSITION: fold as option (c); it is the leading candidate.**

4. **Option (b) puts `LIVEKIT_API_KEY` on a foyer read path.** — Tesla, sharpening Carnot. That key can list every participant in every room; the token-server's auth path is "mint a join", not "panopticon". **DISPOSITION: fold.** A roster ACL is required: which rooms, which fields (count vs identity vs displayName vs metadata). Partially answered already — `firestore.rules:22` states "presence is public in a shared world" — but a Firestore-scoped public and a LiveKit-god-key public are not the same blast radius.

5. **Empty ≠ unknown.** — all four. A LiveKit outage rendering every room empty is a product lie, and "the product looks dead" is a worse failure than a stale list. **DISPOSITION: fold.** The API returns explicit states (`available` / `unavailable` / `unauthorized` / `empty`) and the foyer renders unknown distinctly.

6. **Cost is `1+N`, not 1.** — Tesla. `listRooms` yields counts; WHO needs `listParticipants` per room. Latency, partial failure and throttling all live on that N, and a per-room timeout must not empty the whole foyer. **DISPOSITION: fold.** Split "is this room alive" (counts, cheap) from "who is in it" (roster, per-room).

7. **Occupancy has no schema, and names live in the wrong place.** — Tesla. `/presence` docs carry displayName/photo; `ParticipantInfo` carries them only if the token mint stamped them. Delete the collection without folding name-stamping into the token path and the foyer renders raw disposable guest ids (#3160). **DISPOSITION: fold** — and note this makes claude-tasks#2835 (thread displayName through the mint) a PREREQUISITE, not a nicety.

8. **Premise 4 was an assumption supporting a deletion.** — all four. **DISPOSITION: RESOLVED during this strike, not folded as open.** Audited 2026-09-15: readers = `room_browser.dart:71` only; writers = `room_session.dart` only; rules = `firestore.rules:22`; no analytics, jobs or other surfaces in-repo. Old deployed clients remain the only unaudited consumer.

9. **The option-frame never establishes what the foyer is FOR.** — Maxwell. Premise 1 ("must show occupancy for rooms the viewer has not joined") is load-bearing, sourced to nothing, and is the sole reason both options need a server. If the job is "help me pick a room that isn't empty", a coarse activity signal dissolves the roster query entirely. **DISPOSITION: fold as the FIRST question**, ahead of the option choice.

10. **The motivating evidence is engineer-only.** — Maxwell. "Three ghosts six hours later" was found by reading Firestore; no player has reported that the foyer lied. **DISPOSITION: named tradeoff.** Owner: Nick. This does not block the direction, but it caps how much machinery is proportionate — and it argues for the cheapest option that removes the mirror, not the most complete one.

11. **No behaviour-first acceptance criteria, and no deletion sequence.** — Carnot. **DISPOSITION: fold.** Criteria: ungraceful exit vanishes via LiveKit state; a LiveKit outage does not display false emptiness; duplicate sessions counted intentionally; guest churn grows no stored state; `/presence` writes stop entirely. Sequence: ship endpoint → client reads it → disable heartbeat → delete collection, rules and indexes.

## What holds

- **The diagnosis.** A client-written mirror ghosts without a clock and hides the living with a client clock. Unanimous; this is load-bearing and correct.
- **Option (a) as a DESTINATION is slag** (Tesla) — two stores plus a missed webhook still needs a reaper. It survives only as the *eviction edge* of option (c).
- **The premise-verification move.** Checking that `realm-token-server` already carries `livekit-server-sdk` and the credentials — rather than restating the ticket — is the fact that changed the calculus, and all four families accepted it.
- **The success criterion**: collection AND heartbeat deleted, not bypassed.

## Disposition

**RECAST toward option (c)** — server-owned occupancy projection: LiveKit as authority, webhook
as the live edge, a server metronome as anti-entropy, Firestore (or an in-memory cache) as a
*declared* cache with a named staleness window rather than a second source of truth.

Before re-striking, `DESIGN.md` must answer, in order: (1) what the foyer is for and at what
fidelity; (2) the protocol, not the endpoint; (3) the roster ACL; (4) the explicit state
vocabulary including unknown; (5) the `1+N` cost split; (6) where displayName is stamped.

Round 1 of ≤3.
