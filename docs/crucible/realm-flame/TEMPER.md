# TEMPER — round 1

**Movement:** Temper (movement 6) · **Date:** 2026-08-20 ~23:25–23:40 AEST
**Cast:** Maxwell (Claude, separate instance), Kelvin (Gemini), Tesla (Grok), Carnot (Codex — **did not return**)
**Struck:** the full bundle — `CRUCIBLE.md` + `RESEARCH.md` + `SPARK.md` + `DESIGN.md`

---

## Verdicts

| Family | Verdict | One line |
|---|---|---|
| **Tesla** (Grok) | **DISSOLVE** | "A compiler-for-presence design hung on a 1,237-line file that already has a dead extraction of the same idea; answers a different question than Nick asked; the incremental story is a big-bang refactor in costume." |
| **Maxwell** (Claude) | **RECAST** | "The centrepiece already exists as `lib/proximity/proximity_service.dart`, registered, preference-driven, contract-tested, with zero callers; Step 1 rebuilds an abstraction the codebase already ran and lost." |
| **Kelvin** (Gemini) | **RECAST** | "Correctly splits the problem space but substitutes an elegant abstraction for the user's concrete request, and `SubjectArchetype` reintroduces the bestiary the field was meant to dissolve." |
| **Carnot** (Codex) | — | Did not return before the round closed. **The strike is 3/4, not 4/4.** |

**Round outcome: the design as cast is DEAD.** One DISSOLVE + two RECAST. Below the DISSOLVE
threshold (≥2), so the *candidate* is not invalidated by vote — but see the premise failure, which
invalidates the design more decisively than the vote did.

---

## THE PREMISE FAILURE — found after the strike, by Nick

Every family struck a design whose foundation was:

> *"The engine core must stay pure Dart with zero Flutter dependency."*

**That constraint does not exist.** `packages/realm/DESIGN.md:1042` (Open Question #2, marked
**Resolved**):

> *"The engine package's `pubspec.yaml` whitelist (**Flutter SDK**, **`livekit_client`**, `http`,
> branded-type support utilities) is enforced by a `dart pub deps` check in CI"*

The author read the *current* `packages/realm/pubspec.yaml` (`deps: sdk, test` — which merely
reflects that nothing has needed Flutter yet), canonised that accident into an architectural law,
wrote it into `DESIGN.md` as inviolable, designed a CI guard to enforce it, and used it to argue
against Nick's stated intent **four separate times**.

The CI check the design doc actually prescribes is a **crypto denylist** (no `crypto`,
`cryptography`, `pointycastle` in the engine — so secret-bearing code cannot drift in). **It was
never a Flutter ban.** The author was guarding the wrong thing with a mechanism Maxwell then proved
does not work.

**Consequence for this round:** the strategic verdicts were rendered against a proposition nobody
was actually making. The concrete defects are unaffected. The split is recorded below and must not
be blurred — "the premise was wrong" is not a licence to discard findings that still apply.

---

## FINDINGS THAT SURVIVE THE PREMISE CORRECTION (unconditional)

### T1 — `ProximityService` is dark, and the user's preference is dead *(Maxwell + Tesla + Kelvin, independently)*

> **DISCHARGED 2026-08-21.** Resolved by deletion, not by wiring: `BubbleManager.proximityRadius`
> is now the single owner and every gate derives from it. `lib/proximity/proximity_service.dart`
> is gone. The recast inherits *"proximity is one owner with three derived thresholds"* as a
> settled fact, not an open constraint — the paragraphs below are kept as the record of how it was
> found. The engine-side question T1 raised is still live in a different form: whether a
> `PresenceField` primitive belongs in `realm_core`, now with a working implementation to
> generalise from rather than a dead one.

`lib/proximity/proximity_service.dart` is, feature for feature, the `PresenceField` the design
proposed to build: viewer-relative, Chebyshev (`:112`), threshold-gated, emitting enter/exit edges
(`:65-92`), pure Dart. Constructed per-room from a **user preference**
(`room_session.dart:197-202`), registered (`:208`), disposed in order (`:475`), with a full contract
test suite.

```
checkProximity()  — 39 call sites, ALL in test/.  ZERO in lib/.
proximityEvents   — 12 listeners,  ALL in test/.  ZERO in lib/.
```

**Live user-facing bug:** `bubble_manager.dart:155` hardcodes `_visualThreshold = 5`, while
`ProximityService` takes the user's "Proximity range". Two implementations, two thresholds, and only
the hardcoded one governs bubbles. `proximity_service.dart:29-35` documents `proximityThreshold == 0`
as *"no player ever becomes nearby, so video bubbles never form"* — **set the slider to 0 today and
bubbles still form at ≤5 squares.** The preference does nothing.

**This is the single most valuable output of the entire forge**, and three families found it
independently while the author, four sparks and a research pass did not.

### T2 — "The three loops are one loop" is FALSE *(Maxwell, with a table)*

`DESIGN.md §1` claimed identical geometry, thresholds and derived quantities. Reading `update()`:

| | bubble | opacity | audio | far-branch | network edge |
|---|---|---|---|---|---|
| remote players `:226-250` | ✓ | ✓ `:244` | ✓ `:245` **and `:248`** | ✓ | — |
| Dreamfinder `:253-284` | ✓ (3-way `:265`) | ✗ | ✓ via `_updateDreamfinderAudio` `:283` | ✓ | ✓ `:320` |
| bots `:287-303` | ✓ | ✗ | ✗ | ✗ | — |

Thresholds differ too: visual `5` (`:155`), audio hysteresis `4/5` (`:162-163`) with a volume ramp
(`:759-763`), DF-edge hysteresis `4/5` (`:776-779`).

**And the difference is the hard-won part.** Three sites encode one invariant — *gate state only
advances when the effect actually landed*: `:702-703` (no service ⇒ don't mutate the gate, else it
sticks once the service comes up), `:781-783` (no service ⇒ don't latch `_wasNearDreamfinder`, the
"signal lost forever" bug fixed in PR #481's cage match), `:745-751` (cache volume only if
`setParticipantAudioVolume` returned true, else a late track sticks at default volume). **Any field
that emits levels and edges cannot know whether the send landed.** Move edge ownership away from the
gate and all three regress.

**Plus:** `:814-819` fans the DF audio gate over `{dreamfinderIdentity, ...dreamfinderIdentities()}`
— `agent-*` LiveKit identities with **no components and no grid position**, added because "any
identity outside the gate is ungoverned audio (half of the 2026-07-18 silence failure)". A model of
*positioned inhabitants* cannot represent a positionless identity, so its audio goes ungoverned
again.

**Binding on the recast:** the audio gate (state + send-confirmation) stays with the thing that
sends. A proximity source supplies distance; it does not own the gate.

### T3 — `video_bubble_component` needs a federated FFI plugin, not a file move *(Maxwell)*

Three of its seven escapes are the native capture stack. `lib/native/video_frame_ffi.dart:24` does
`DynamicLibrary.executable()`, resolving symbols from `macos/VideoFrameCapture/VideoFrameCapture.m`,
compiled into the **Runner target** (`macos/Runner.xcodeproj/project.pbxproj:460`). Any package
containing this component would look up symbols that only exist if every consuming app hand-adds an
ObjC file to its own Xcode target — RESEARCH §5d's `flame_ui` failure one layer lower, reaching up
into the host *binary* rather than the host widget tree.

**Still true under the corrected premise.** It is now engine work (engines are allowed platform
plugins) but it is a real sub-project: podspec + per-platform variants, not "inject a sink".

### T4 — the proposed CI guard does not work, and the right one is specified but unbuilt *(Maxwell, verified by running it)*

`DESIGN.md:73-76` claimed `dart analyze packages/realm` hard-fails on a `package:flutter` import.
Maxwell ran it: `packages/realm/pubspec.yaml:18` is `resolution: workspace`, so the shared
`package_config.json` resolves `package:flutter` fine. Result: **exit 0**, one info-severity lint
(`depend_on_referenced_packages`). CI would go green.

The guard that matters — and that the recast needs — is the one `DESIGN.md:606` and migration step 4
already prescribe and **which has never been built**: a `dart pub deps --json` check on the resolved
transitive graph. Verified absent: no workflow references `pub deps`.

### T5 — opacity was deliberately moved OUT of the proximity layer *(Maxwell)*

`bubble_manager.dart:681-683`: *"Moved here from ProximityService — opacity is presentation, not
proximity logic."* The struck design put opacity back into the pure-Dart layer, contradicting both
that prior refactor and FOLD-1's own world-space/render-space principle. Also `:671-678`: only
`VideoBubbleComponent`/`PlayerBubbleComponent` accept opacity; bot bubbles ignore it.

### T6 — the incremental story was false *(all three)*

Verified step by step by Maxwell: only Steps 2 and 5 were independently useful; Step 2 was gated on
blocked task #1, and Step 5 — the cheapest, most decisive falsification — was scheduled **last**,
after everything it could have falsified was already built. **Binding on the recast: order the
falsifying step first.**

### T7 — `SubjectArchetype` reintroduces what the field was meant to dissolve *(Kelvin)*

> *"If the field needs a bestiary of archetypes to function, it's not a pure field; it's a policy
> engine with extra steps."*

The Spark's whole claim was that a metric dissolves the hardcoded cast. FOLD-1 conceded a bare
metric is insufficient and reintroduced per-kind policy. Kelvin is right that this eats the
abstraction's justification. **The recast must not claim "the cast dissolves" — it does not. It
becomes data instead of code, which is a smaller and more honest claim.**

### T8 — `ViewerContext` is an unowned complexity bomb *(Kelvin)*

Invented during Fold, one hour old, no definition, no owner, no plumbing story. The author had
already flagged it as the most likely thing to be wrong; Kelvin independently agreed.

---

## FINDINGS CONDITIONED ON THE FALSE PREMISE (superseded)

Recorded so a later reader does not resurrect them as if unanswered.

- **"One consumer / Metz / don't build a package."** Aimed at a *speculative feature extraction*.
  Under the corrected premise, rendering is the engine's **designed scope** (Flutter SDK and
  `livekit_client` are whitelisted), and the shape is an **endorsed implementation** — which
  `DESIGN.md` itself says is "real from day one… because their shape is known". The Metz discipline
  still binds **feature** plugins; it does not bind provider implementations.
- **"It answers a different question than Nick asked."** Correct at the time, and resolved by Nick
  directly: rendering ships *with* Realm.
- **"Keep it in `lib/flame`" / "move it to `worlds/tech_world/lib/flame`."** Rejected by Nick
  explicitly — Flame is a substrate choice, not world vocabulary, and burying it in a World means
  every future world inherits a rendering stack through a game.
- **The `DESIGN.md:902` non-goal conflict** ("Animation/render systems… all Tech World"). Real, and
  **deliberately overturned by Nick** on 2026-08-20. Must be edited in `packages/realm/DESIGN.md`,
  not left to contradict the new direction silently.

---

## WHAT THE DESIGN GOT RIGHT (calibration, not politeness)

- **FOLD-1 is real, not a rescue** — Maxwell verified independently: `_applyBubbleRepulsion`
  (`:894-935`) never touches `chebyshevDistance`; `delta.length` is Euclidean on rendered `center`,
  thresholded on `_bubbleDiameter = 64.0` (`:168`), damped (`:927`) and tether-capped (`:929`). Same
  for `_findMergeGroup` (`:1038`, `_mergeThreshold = 96.0`). The author correctly refuted his own
  spark against the code.
- **FOLD-3 verified** — `entries.length < 2` (`:896`), `dist > 0.01` (`:908`), `removeWhere` prune
  (`:898`) all present as described.
- **RESEARCH §1's headline held** — Maxwell's independent import resolver: 74 files, 58 zero-escape
  (6,645 LOC vs the author's 6,703), same top-five coupled files. That instrument did not break.
- **The core observation is genuine** — `BubbleManager` hardcodes the cast (`:50`, `:106-107`,
  `:119`, `:270`, `:298`). It is what Nick pointed at, and unifying the loops is the right fix.

---

## ROUND OUTCOME

**Design DEAD as cast. Candidate NOT invalidated** — it was struck on a premise the author invented,
and the corrected premise (rendering is engine scope) is materially different and verified against
`DESIGN.md:1042`.

**Recast round 1 of 3 consumed.**

Recast direction agreed with Nick 2026-08-20 ~23:39, four-package shape:

```
realm_core      protocols + vocabulary types. Slow, strictly versioned.
realm_flame     endorsed implementations — rendering (incl. video bubbles),
realm_firebase  persistence, transport. Each independently swappable.
realm_livekit
realm           APP-FACING package: depends on core + endorsed defaults,
                re-exports them. What a game actually puts in its pubspec.
```

This closes the gap RESEARCH §5e.4 identified — the current structure is the Flutter federated
pattern **minus its app-facing package**, and Flutter's own term for implementations wired into that
package is **"endorsed"**.

**Binding constraints carried into the recast:** T1 (wire or delete `ProximityService`; fix the dead
preference), T2 (the gate owns its own send-confirmed state; positionless identities must remain
governable), T3 (video bubble needs a real federated FFI plugin), T4 (`dart pub deps --json` on
`realm_core`, not `dart analyze`), T5 (opacity is presentation), T6 (order the falsifying step
first), T7 (do not claim the cast dissolves).

**Carnot never returned — the next strike must be 4/4.**
