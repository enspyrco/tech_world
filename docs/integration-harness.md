# Integration Harness — multi-peer audio/proximity, terminating in runtime

**Status:** spec / phase 0. No code yet. This document is the acceptance contract.

## Why this exists

Tech World's audio/proximity bugs have been caught by **live users complaining in
production meetups** — Robin saying "I can't hear you" *was* the bug tracker.
Cage-match (three LLMs reading a diff) is static analysis: it cannot catch a
browser-API race, a WASM load-fallback path, or a proximity gate that only
re-fires on *local* movement. Every one of the 2026-06-06 bugs slipped past
review and was found in production.

This harness exists to make a "this degrades gracefully" claim a **fact** instead
of an **assertion**, without shipping to prod first. Its design principle is the
through-line from that session:

> Every assertion must terminate in the thing that **actually happened at
> runtime** — the DOM property, the published SFU message, the audio-enable
> decision — not in the code path that *should* produce it.

**Acceptance criterion (Kelvin's test of success):** *if this harness had
existed, the df-proximity null-latch (#1) and the volume DOM-write (#2) bugs
would have been caught before cage-match, not during.* We build toward catching
the bugs we already know about; that earns trust for the ones we don't.

## Architecture — Playwright two-tab, black-box, real SFU

```
   playwright CLI  (~/.claude/cli-tools/playwright)
        │  drives two real Chromium tabs of the SERVED Flutter web app
        ├─ Tab A  (player-A, anonymous auth)  ─┐
        │                                       ├─ local livekit-server  (real SFU)
        └─ Tab B  (player-B / DF-identity)    ─┘   docker: livekit/livekit-server
        │
        └─ asserts on TERMINAL RUNTIME STATE:
             • Tab A DOM:  document.getElementById('livekit_audio_<cid>').volume
             • window.twHarness.dfProximityNear   (flag-gated observation object)
             • window.twHarness.audioEnabledCids  (set)
```

Two **real** Flutter web clients in real browser tabs, on a **real** SFU. The
only thing faked is the *driving* (Playwright moves avatars) and the *room*
(local server, throwaway room). Everything the bugs live in — DOM, LiveKit JS
client, BubbleManager, the data channel — is real.

### Test pyramid — the rig is for the boundary, not the logic (decided 2026-06-07)

The four bugs split by where their terminal layer lives, and they get **different
test tiers** accordingly (a hybrid, not "everything through Playwright"):

- **#1 (df-proximity publish) + #2 (volume DOM-write)** — terminal layer is the
  real SFU message / the real browser DOM. These NEED the Playwright two-tab rig.
- **#3 (remote-move gate) + #4 (hysteresis)** — terminal layer is BubbleManager's
  own audio-enable decision, pure in-process Dart. These are **fast hermetic
  `flutter test` unit tests** that drive `BubbleManager.update()` with synthetic
  participant positions — NO browser, NO SFU. Routing them through Playwright
  would make them slow + flaky for zero fidelity gain (violates the test pyramid).

Same terminal-layer discipline everywhere; the right tool per layer. The
expensive Playwright rig is reserved for the DOM/SFU boundary it alone can reach.

**Why black-box two-tab (the chosen shape):** maximal production fidelity; both
peers are identical real clients; reuses the existing `playwright` CLI. The cost
we accept: driving avatars through the canvas UI is brittle (mitigated below),
and two of four signals need a small observation seam.

### The three seams this requires (all small, all justified)

| Seam | Change | Why it's safe / independently good |
|---|---|---|
| **S1 — env LiveKit URL** | `_serverUrl` (livekit_service.dart:110) → `String.fromEnvironment('LIVEKIT_URL', defaultValue: 'wss://livekit.imagineering.cc')` | Already on the CLAUDE.md TODO ("LiveKit URL hardcoded… add --dart-define env selection"). Default unchanged ⇒ prod byte-identical. |
| **S2 — local token path** | In harness mode the app reads its join token from a **URL query param** (`?lk_token=…`) instead of calling the `retrieveLiveKitToken` Cloud Function (livekit_service.dart:827). The **harness orchestrator** mints the per-identity tokens (`lk token create` against the local server's dev key) and injects one per tab. | **Decided 2026-06-07 (revises the original client-side mint):** keeps ALL credential-generation logic OUT of the Dart client tree — no JWT-signing code or dev secret in the app bundle, even tree-shaken. The app-side seam is a ~5-line URL-param read, gated on the non-default URL. ⚠️ The committed `harness_token.dart` (client-side mint) is to be **replaced** by this at the smoke phase. |
| **S3 — observation object** | Under `bool.fromEnvironment('TW_HARNESS')`, populate `window.twHarness` with `{ dfProximityNear, audioEnabledCids, participantVolumes }` from existing internal state | Flag-gated; absent in every normal build. Reads a *published surface*, doesn't let the test reach into Dart internals (keeps it black-box). |

`window.twHarness` is updated at the same points the internal state already
changes: `dfProximityNear` from `publishDfProximity` (livekit_service.dart:690 /
bubble_manager.dart:744), `audioEnabledCids` + `participantVolumes` from the
BubbleManager audio gate (bubble_manager.dart:148+). DOM volume (#2) does **not**
need S3 — it's read straight from `livekit_audio_<cid>.volume`.

## Driving the avatar (the brittle part, made robust)

Movement is **tap-to-move** on the Flame canvas (tech_world.dart:1151), 1 grid
square = 32 px (`gridSquareSize`), Chebyshev distance for proximity. A Playwright
click at canvas pixel `(gridX*32, gridY*32)` (adjusted for camera/viewport
offset) walks the avatar there.

Robustness measures (so "brittle UI-driving" doesn't mean "flaky"):
- **Assert position, then act.** After a click, poll `window.twHarness` (or the
  published position) until the avatar reaches the target grid cell before
  asserting audio state — never sleep-and-hope.
- **Resolve the canvas→world transform once** at harness start (read camera
  offset/zoom via a `twHarness` field) rather than hardcoding pixel math.
- **Grid targets, not pixels, in test code.** Tests say "move B to 3 squares from
  A"; the driver converts to a click.

## The four bug scenarios → smallest two-tab scenario

Each scenario is an **ATDD acceptance test**: write it red against the
*reverted* fix, watch it fail, then confirm it passes against current `main`.

| # | Bug (2026-06-06) | Smallest scenario | Assertion terminates in |
|---|---|---|---|
| **1** | df-proximity null-latch — signal latched but never published when `_liveKitService` was null | Tab B joins as DF-identity; Tab A near | `window.twHarness.dfProximityNear === true` **and** a `df-proximity` data msg observed (Tab B subscribes) within N ms of join |
| **2** | volume cached before DOM write — `_audioVolumes` set but `HTMLAudioElement` absent ⇒ silence | Tab B joins with audio; Tab A in range | `document.getElementById('livekit_audio_<B-cid>').volume` in Tab A DOM equals the expected proximity-faded value (not just the cache) |
| **3** | Robin-stops-hearing — gate only re-fired on *local* movement | A and B in range; move **B** (remote) out, then back | Tab A `audioEnabledCids` flips off on B's move-out and on again on move-in — driven by the **remote** move, A stationary |
| **4** | hysteresis dead zone — see-but-can't-hear between audio≤? / visual≤5 | Sweep B across the hysteresis band (4→5→6 squares) | no distance where B's bubble is *visible* but `audioEnabledCids` excludes B (no see-but-can't-hear gap) |

## Build phases (ATDD; each phase ends green)

0. **This spec.** ✅ (acceptance contract above.)
1. **Seams.** S1 (env URL) ✅ + S3 (`window.twHarness`) ✅ done. **S2 rework:** replace the committed client-side `harness_token.dart` mint with the URL-param token read (app side) + `lk token create` in the harness orchestrator (decided 2026-06-07). `flutter analyze` + existing tests green; prod path unchanged.
2. **Pyramid base first (cheap, no infra): #3 + #4 as pure-Dart tests.** Make `BubbleManager.update()` drivable with synthetic positions; write the remote-move (#3) and hysteresis (#4) regressions as `flutter test` unit tests — red against the reverted fix, then green. This lands fast and de-risks (proves BubbleManager is testable headless).
3. **Green smoke (the rig).** Local livekit-server up; serve the web app with `--dart-define LIVEKIT_URL=ws://localhost:7880 TW_HARNESS=true`; harness mints two tokens (`lk token create`) and opens two Playwright tabs to one room; assert a data message crosses A→B. *Proves the rig before any browser bug scenario.*
4. **Port #2 then #1 through the rig** (the DOM/SFU-bound bugs). #2 (volume DOM-write) first — highest value, terminal layer (DOM `.volume`) directly readable. Each red-then-green.
5. **CI.** Pure-Dart #3/#4 run in the normal `flutter test` job (always on, cheap). The Playwright rig (#1/#2) runs on PRs touching `bubble_manager.dart`, `livekit_service.dart`, `set_track_volume_web.dart`, or `proximity_service.dart` — needs Chromium + a livekit-server container + the Playwright CLI. If that job's cost is prohibitive, gate it as label-triggered, but **log loudly** when skipped (no silent coverage gaps).

## Open questions (resolve as we build, not before)

- **S2 token minting** — simplest hermetic option: a ~30-line local token endpoint using the livekit-server's dev API key/secret, or a pre-minted long-TTL `--dart-define` token for a fixed test room. Decide at phase 1.
- **DF identity in Tab B** — DF is normally a server agent. For #1 we only need a participant whose identity matches `isDreamfinderIdentity()` (`bot-dreamfinder` / `agent-*`). Tab B joins with that identity; no real DF brain needed (and it's down on zero Anthropic credit anyway).
- **CI economics** — phase 5; measure wall-clock before deciding always-on vs label-gated.

## Non-goals

- Not replacing unit tests — `proximity_service` Chebyshev math etc. stay unit-tested.
- Not testing DF's STT/LLM/TTS — that's the bot repo's concern; this harness asserts only what the *client* does with proximity/audio.
- Not a load test — N is small (2–3 peers), enough to reproduce the bug classes.
