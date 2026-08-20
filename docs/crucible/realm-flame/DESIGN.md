# DESIGN — the field, the costumes, and one deleted god object

**Movement:** Cast · **Date:** 2026-08-20 ~23:22 AEST
**Status:** cast, pre-Fold-writeup, pre-Temper. **Not yet struck by a cross-family adversary.**

---

## 1. The problem

Nick: *"I want the rendering stuff to live in the engine."*

`packages/realm` (1,334 LOC, pure Dart, deps `sdk`+`test`) owns identity, presence, rooms,
voice transport, blob storage — as **ports**. `lib/flame` (74 files, 14,700 LOC) owns
everything that makes a room feel like a *place*. The engine owns voice but not the bubble
that renders voice; owns presence but not the avatar that shows presence; owns rooms but not
the tilemap.

Heat measured the seam (RESEARCH §1): **58 of 74 files (6,703 LOC) never import outside
`lib/flame`**, and ~49 of ~62 escapes sit in five files — four of which are orchestrators that
should never move. **Coupling maps onto the orchestrator-vs-leaf boundary.** The seam exists.

But the real find is one file. `bubble_manager.dart` (1,237 LOC) runs the *same loop three
times* — once for remote players, once for Dreamfinder, once for bots:

```dart
final distance = chebyshevDistance(playerGrid, X.miniGridPosition);
if (distance <= _visualThreshold) { …create bubble… setOpacity(distance); gateAudio(distance); }
```

Identical geometry, identical thresholds, identical derived quantities. The only differences:
which bubble is constructed, what the audio policy is, and whether an enter/exit edge is
published to the network. **It is a generic proximity engine with the cast of characters
compiled into it.**

---

## 2. The shape

Three layers, one direction of dependency, no upward path.

```
packages/realm            PURE DART. deps: sdk, test. No Flutter. Ever.
  Metric                  a world supplies distance(a, b) — evaluated ONLY
                          viewer-to-subject, so asymmetry is harmless (FOLD-2)
  PresenceField           viewer-relative, O(n): for each subject, distance ->
                          visible?, opacity, audibility  + enter/exit EDGES
  KernelFrame             per-subject WORLD-SPACE intent: position, opacity,
                          audibility, gait phase.
                          NOT merge weight, NOT repulsion — those are render-space (FOLD-1)
  SubjectArchetype        per-kind policy: audio gate, costume class, whether
                          enter/exit edges are published to the network

packages/realm_flame      Flame costumes. deps: realm, flame, flutter.
  depends DOWNWARD on realm only. NEVER imports the app.
  Consumes KernelFrames and paints. Video bubbles, speech bubbles, tile
  rendering — AND owns all render-space physics: pairwise repulsion in pixel
  space, the metaball merge field, merged video. These are functions of how
  large the costume is drawn, so they cannot live in a pure-Dart core (FOLD-1).

lib/  (Tech World)        supplies the Metric (Chebyshev on tiles) and its
                          Archetypes; keeps its vocabulary — doors, terminals,
                          Dreamfinder, its art, its maps.
```

**Why the dependency direction is safe.** RESEARCH §5d found `flame_ui`'s
`TextFieldComponent` re-coupled to its host app by needing `game.buildContext` — a component
reaching **up**. Tesla's rule ("costumes are write-only from the field") defends against
exactly that. But depending **down** on a pure-Dart engine is the opposite direction and
carries none of that risk. Tesla drew the boundary one package too conservatively; the
topology survives with the package intact.

**Why `realm` cannot acquire Flutter.** Enforced by CI, not by prose: a job runs
`dart analyze` (NOT `flutter analyze`) against `packages/realm/`. A pure-Dart analysis
context has no Flutter SDK, so any `package:flutter` import hard-fails (RESEARCH §5e.3 — no
off-the-shelf Dart tool does this; the CI job is the mechanism).

### The three things Fold established that neither spark had

1. **A bare Metric is insufficient — `SubjectArchetype` is required.** Bots get no audio gate;
   Dreamfinder gets a *different* one (`_updateDreamfinderAudio`); players get the standard
   one. That is per-kind policy, not geometry. Tesla's metric is necessary, Kelvin's archetype
   is required, and the code adjudicates it.
2. **The frame factory needs a viewer.** `hideVideoBubbles` and `_isMobileWeb` decide which
   bubble is built — properties of the **viewer's device and preferences**, not of the
   inhabitant. Signature is `(Archetype, ViewerContext) -> Costume`, not `Archetype -> Costume`.
   Neither spark contained a viewer.
3. **The field must emit EDGES, not just levels.** `_updateDreamfinderProximity` publishes a
   LiveKit message on enter/exit. A level-only field cannot express that without every
   consumer re-deriving edges and getting it subtly wrong.

### Evidence the framing prevents a real bug class

From `bubble_manager.dart`'s own comment: a previous optimisation skipped recompute when the
**local** player hadn't moved, so a peer who walked back into range **stayed inaudible until
the local player happened to move** — the "can't hear you until I move" bug. It existed
because proximity was modelled as local-player-driven rather than field-driven. Under a
field, that bug is not a bug you fix; it is **unrepresentable**.

---

## 2a. FOLD — what the author's own pass changed

Fold ran after the first cast and **materially changed the shape**. Recorded rather than
silently absorbed, so Temper can see what was corrected and by what evidence.

### FOLD-1 (major): the field splits in two — I had `KernelFrame` wrong

The first cast listed **merge weight** as a field quantity and my own spark claimed
**repulsion vectors** as a derived quantity of the `AttentionField`. **Both are wrong.**
Reading `_applyBubbleRepulsion`:

```dart
final ci = entries[i].value.center;              // RENDERED bubble centre, pixels
final dist = (ci - cj).length;                   // EUCLIDEAN, not the world metric
if (dist < _bubbleDiameter && dist > 0.01) { …}  // _bubbleDiameter is a RENDER constant
…
disp = disp * _repulsionDamping;                 // STATEFUL across frames
if (disp.length > _maxTetherDistance) …          // and tether-capped
```

Repulsion never touches `chebyshevDistance` or grid coordinates. It is pairwise O(n²)
Euclidean distance between **rendered bubble centres in pixel space**, thresholded on **how
big we chose to draw the circle**, accumulating displacement across frames.

**Therefore:**

| Quantity | Space | Home |
|---|---|---|
| proximity, audibility, opacity, enter/exit edges | **world** (metric, grid) | `packages/realm` — pure Dart |
| repulsion, metaball field, merged video | **render** (pixels, diameter) | `packages/realm_flame` — costumes |

A git-city with blame-distance has no bubble diameter and no pixel space; the repulsion does
not transfer. **The pure-Dart field is smaller than cast**: proximity + audibility + opacity
+ edges. The physics stays with the costumes, where it already was and already worked.

This is a correction to **Maxwell's own spark** — the author's, found by the author's pass.
It is exactly what Fold exists for, and it makes the engine surface smaller, not larger.

### FOLD-2: the "field" is viewer-centred and O(n), not global and O(n²)

Every proximity computation in `update()` measures **from the local player only**. There is
no global pairwise proximity anywhere; `closestDistance` is a min-reduction over
subject-to-viewer distances. Designing a *global* field would add cost and generality nothing
uses. **`PresenceField` is a viewer-relative radial evaluation**, and the design should say so
rather than implying an O(n²) world model.

Corollary: a non-symmetric metric (Tesla proposed **blame-distance**, which need not be
symmetric) is harmless for this use, because only one direction is ever evaluated. That is
luck, not design — record it before someone "fixes" the field to be global.

### FOLD-3: degenerate states were already handled

The states I went hunting for are guarded in the existing code: `dist > 0.01` covers
coincident positions (divide-by-zero on `normalized()`); `if (entries.length < 2) return`
covers n=0 and n=1; `_bubbleDisplacements.removeWhere` prunes departed subjects each frame.
**Any rewrite must preserve all three**, and they should become explicit tests in Step 1
rather than being re-derived by accident.

### FOLD-4: a latent identity-as-mutable-key hazard

`_bubbleDisplacements` is keyed by subject id and carries accumulated physics state across
frames. If a subject id is ever **reused** for a different inhabitant (a reconnecting peer
issued the same identity, an `agent-*` id recycled), the newcomer inherits the departed one's
displacement. Pruning is by absence, not by a freshness watermark. Small, real, pre-existing.

### FOLD-5: the boring alternative, tested and rejected

Extracting only the clean tier leaves `bubble_manager` at 1,237 lines with three duplicated
loops and the hardcoded cast intact. It tidies *around* the mess without touching it — and
the mess is precisely what Nick pointed at. Rejected on those grounds, not on ambition.

### What Fold did NOT resolve

FOLD-1 shrinks the engine surface, which **weakens claim 4** (worth it with one consumer):
a smaller engine-side artifact is cheaper to be wrong about, but it is also *less* of the
"rendering in the engine" that was asked for. Steps 1–2 now deliver a **proximity field**,
and the rendering-in-a-package part is entirely Step 3 onward. **Temper should press on
whether Steps 1–2 alone answer the original request.**

---

## 3. Build order — core first, each step independently useful

Every step must be worth doing **even if the next step never happens**, so a wrong bet
degrades to "we tidied our rendering layer," never "we built a library nobody used."

- **Step 0 — the guard (hours).** CI job: `dart analyze packages/realm`. Locks the pure-Dart
  invariant *before* anything can violate it. Independently useful: protects the existing
  engine today.
- **Step 1 — `Metric` + `PresenceField` in `packages/realm`, pure Dart (small).** Chebyshev
  metric, threshold kernel, opacity kernel, enter/exit edge emission. Fully unit-testable with
  zero Flutter. Independently useful: the "can't hear you until I move" bug class becomes
  untypable, and it is testable in a way `_StubWorld` never made anything.
- **Step 2 — `bubble_manager` consumes the field (medium).** Delete the three duplicated
  loops; iterate subjects. Introduce `SubjectArchetype` so bots/DF/players supply their own
  audio policy and bubble factory. **`bubble_manager` stops knowing any character's name.**
  Independently useful even if no package is ever created: it is the single messiest file in
  the rendering layer and this is the fix Nick actually pointed at.
- **Step 3 — `packages/realm_flame`, seeded with the CLEAN tier (medium).** Move only
  zero-escape, unambiguously generic files first: `speech_bubble_component`,
  `bubble_field_component`, `merged_video_bubble_component`, the tile stack,
  `barrier_occlusion`, the map generators. ~2,000 LOC, no surgery required.
  **Explicitly NOT moved:** `dreamfinder_component`, `bot_bubble_component`,
  `bot_character_component`, `tech_world_game` — zero-escape but Tech World vocabulary
  (RESEARCH §2: extractability ≠ genericness).
- **Step 4 — `video_bubble_component` into `realm_flame` (the crux).** Fold established this
  is closer than its 7 escapes suggest: `DiagnosticsService` and `FrameSource` are **already
  constructor-injected** with locator lookups only as *defaults*. The one genuine coupling is
  `dispatch([AvCaptureInitialized(…)])` — the app's global event bus plus app-owned event
  types. Fix: inject a sink, or move the AV-capture telemetry events into `realm` (they are
  generic capture telemetry, arguably engine-owned already).
- **Step 5 — the second witness (small, and it is the proof).** A headless consumer of
  `PresenceField` that paints nothing: a text-mode describer or an audio-routing check. This
  is the **cheapest possible falsification of the whole design** — if a non-visual consumer
  can't use the field, the abstraction is fake. Do this EARLY if confidence dips.
- **Later, explicitly deferred:** `TechWorld implements World` (the `DESIGN.md:1030` wrap PR),
  the `worlds/` move, the character-maker compositor's home.

---

## 4. Blast radius & consent spine

- **No trust boundary is touched.** No auth, no token path, no network admission, no
  persistence rules. This is internal architecture.
- **Blast radius is the running game**, entirely: proximity, bubbles, and the audio gate are
  the most visible things in the product. A field bug is *"I can't hear anyone."*
- **Therefore the gate is behavioural, not structural.** Step 2 must not merge until the
  two-client runtime pass (task #1) has actually been *watched* — the emote, the bubbles, and
  leave/rejoin. That pass is currently **blocked on identity** (two macOS clients share one
  Firebase session; web is dead on token CORS, task #7). **Unblocking task #1 is a
  precondition of Step 2, not a nicety.**
- **Steps 0, 1 and 5 are risk-free** (additive, no consumer changes) and can proceed regardless.
- **Reversibility:** Steps 0–2 are ordinary refactors, revertible by `git revert`. Step 3
  onward creates a package — reversible, but noisily. **The irreversible-ish step is 3**, and
  it should not be taken until Step 2 has run in front of a human.

---

## 5. Claims to falsify (carried to Temper — attack these)

1. **"The three loops really are one loop."** Established by reading `update()`. But `update()`
   is 130 lines and I read it once. There may be per-kind behaviour I skimmed.
2. **"`realm_flame` depending down on `realm` is safe."** Asserted from the direction of the
   `flame_ui` failure. Not demonstrated — no second component has been tried.
3. **"The clean tier is genuinely generic."** RESEARCH §2's two-axis split is *judgement*, not
   measurement. `bubble_field_component` and `test_shader_bubble` may encode Tech World's
   specific visual language.
4. **"Extraction is worth it with one consumer."** RESEARCH §5a (Metz) says no, loudly, and
   the answer here — that the headless bot and audio-router are consumers #2 and #3 — is
   *my* argument, made by the enthusiastic author, and both are hypothetical today.
5. **"A field is the right model for proximity."** Four models converged on it. Four models
   sharing a training prior is **correlated error, not corroboration**.
6. **"This answers what Nick asked."** He asked for rendering in the engine. Step 3 delivers
   that literally, but Steps 1–2 (the valuable part) deliver a *field*, not rendering. If the
   design is judged only on Steps 1–2 it has answered a different question.
7. **"`ViewerContext` is a clean concept."** Invented during Fold, one hour old, zero
   consumers. Most likely thing here to be wrong.

---

## 6. Rejected alternatives

- **Migrate Tech World off Flame to raw Flutter.** Rejected on measured evidence: shallow-but-
  wide usage (17 `PositionComponent` subclasses across 29 files), one Flame release in four
  months, both 1.38.0 breaking changes with zero usages here, and the character-maker
  compositor depends on `ImageComposition.composeSync()`. **Flagged: I chose the route to
  this conclusion; it is not independent.**
- **Move rendering into `packages/realm` core.** Rejected — kills the pure-Dart property that
  makes headless consumers possible, and `DESIGN.md:742-744` commits to renderer-neutrality
  with a sealed `RoomPreview` enforcing it.
- **The boring alternative: extract only the clean tier, leave the physics.** Tested in Fold
  and **rejected**: it leaves `bubble_manager` at 1,237 lines with three duplicated loops and
  the hardcoded cast intact. It tidies *around* the mess without touching it, and the mess is
  what Nick pointed at.
- **Tesla's pure dissolution: no package at all, costumes stay in the game.** Rejected as
  *strictly* stated — it declines Nick's literal request. Its topology rule is adopted; its
  package-abolition is not.
- **Do nothing until a second World exists.** The honest Metz-compliant option, and it stays
  live. Its cost: every engine feature added meanwhile (#3211 admission, #2850 visibility,
  #3262 API audit) is designed against `_StubWorld`.

---

## 7. Open variables (enumerated, not hidden)

- **Does the character-maker (#3148) go in `realm_flame`?** Its compositor is
  `ImageComposition.composeSync()` — Flame-dependent rendering substrate, so structurally yes.
  **Unresolved, and it is on the critical path of the work Nick actually wants to do next.**
- **Where does `AvCapture*` telemetry live** — app events, or engine events? Decides Step 4.
- **Is `mention_*` generic or Tech World vocabulary?** Zero-escape, genuinely ambiguous.
- **`ActiveLayer` must move from `map_editor` into the tiles layer** regardless — a tiles
  concept filed in the editor. Small, unrelated, do it anyway.
- **No step is costed in hours.** Sizes above are ordinal (small/medium), not estimates.
