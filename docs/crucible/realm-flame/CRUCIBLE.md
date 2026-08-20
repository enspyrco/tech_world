# CRUCIBLE — `packages/realm_flame`

**Forged:** 2026-08-20, ~22:58 AEST
**Movement:** Ore (selected, consent given)
**Bundle:** `docs/crucible/realm-flame/`

---

## The pick

**Lift the generic rendering substrate out of Tech World and into a first-party engine
adapter package, `packages/realm_flame` — mirroring the `packages/realm_firebase`
pattern that already exists.**

BYO backend *and* BYO renderer, with a first-party option for each.

---

## How the scout got here (including the wrong turn)

This candidate is **not** the one Ore first selected. The path matters, because two
premises were falsified on the way and the record should show it.

**Nick's ask:** "I want to do a crucible on flame."

**My first framing (WRONG):** I aimed the forge at *"is Realm deliberately
renderer-agnostic, or is that an accident? `packages/realm/DESIGN.md` never says."*

**Refuted in Ore, by reading the artifact.** `DESIGN.md` says it repeatedly and
deliberately:

- `DESIGN.md:742-744` — *"**No Flutter types in the return value** — the consuming
  renderer wraps RoomPreview in its own rendering stack. This keeps the engine portable
  across rendering stacks (Flame, raw CustomPainter, future 3D, text-mode bots, etc.)."*
- `DESIGN.md:716` / `world.dart:13-19` — engine `World` is an `abstract interface class`
  **specifically because** `TechWorld` already `extends flame.World`, and Dart is
  single-inheritance. The Flame constraint was designed *around*, not ignored.
- `DESIGN.md:223` — the Flame/Realm `World` name collision has a stated resolution
  (import prefix).
- `RoomPreview` is a **sealed** class so renderer-neutrality is enforced by the type
  system rather than by prose discipline.

So the question was already answered, in writing, on purpose. My candidate was slag; a
four-family strike would have burned a research pass re-deriving a decision already made.

**Second framing (also superseded):** *"the engine's `World` interface has zero real
implementers"* — true and still relevant (see Open Threads), but it is a **step inside**
this candidate, not a rival to it.

**Nick's correction, which is the actual ore:** *"but I want the rendering stuff to live
in the engine."*

That inverts the design decision rather than discovering it — and it turns out not to
require overturning anything.

---

## The case (why this thrills me AND what it changes)

### The "oh, of course"

`packages/realm` core depends on **`sdk` and `test`. That is the entire dependency list.**
Pure Dart, zero Flutter. `packages/realm_firebase` depends on `realm` +
`firebase_auth` + `cloud_firestore` + `firebase_storage` — it is a **first-party adapter**:
one concrete implementation of the core's ports, shipped alongside, carrying the heavy
dependencies so the core doesn't have to.

`DESIGN.md:3` — *"BYO backend: Firebase, self-hosted, or anything that satisfies the
interfaces."*

The shape Nick wants **already exists in this repo, once**. `realm_flame` is that same
shape a second time, for rendering instead of persistence.

- Rendering lives *in the engine* — shipped by it, versioned with it, maintained as
  engine code. Nick's ask, satisfied literally.
- Core `realm` stays pure Dart and renderer-neutral. `DESIGN.md`'s stated commitment
  survives **intact**, not overturned.
- The Flame-vs-raw-Flutter question dissolves: Flame becomes an engine-level choice
  isolated behind one package boundary, so replacing it later is a *package swap*, not a
  29-file migration.

### What it changes

The engine is currently 1,334 lines — and that always looked small for "the durable
investment." The explanation is that **it is the ports layer**. The mass was always meant
to live in adapters: `realm_firebase` is 568 lines, and `realm_flame` would be
**~7,150 lines currently misfiled up in `lib/flame/`**.

Measured split of `lib/flame` (14,626 LOC / 74 files) — **by filename and size only, NOT
by reading the code; see the falsifier**:

| Plausibly generic substrate | Tech World vocabulary |
|---|---|
| `bubble_manager` 1236 | `tech_world.dart` 1637 |
| `video_bubble_component` 1044 | `predefined_tilesets` 1216 |
| `tmx_importer` 767 | `predefined_maps` 482 |
| `barrier_occlusion` 374 | `dreamfinder_component` 419 |
| `player_component` 297 | `door_manager` 182 + doors |
| `speech_bubble_component` 221 | terminals, bots, DF territory |
| `merged_video_bubble` 154, `bubble_field` 127 | |
| tile/tileset stack ~1,256 | |
| `map_preview_component` 151 | |
| map generators ~484 | |
| **≈7,150** | |

### The pattern this closes

**The engine owns voice but not the bubble that renders voice. It owns presence but not
the avatar that shows presence. It owns rooms but not the tilemap that makes a room feel
like a place.**

Each is a split concern, and it is the **same drift found three times in one session**:

1. `LiveKitTokenEndpoint` — port defined in `packages/realm`, its two-hop driver living
   up in `lib/livekit/realm_token_source.dart`.
2. `World` — interface defined in the engine, **zero** real implementers; the only
   `implements World` in the repo is `_StubWorld` in the engine's own test, with every
   method body empty.
3. The rendering substrate — this candidate.

Three instances is a class, not three incidents. Fixing the class is worth more than
fixing any one of them.

---

## Scoring

| Axis | Score | Evidence (concrete, not affect) |
|---|---|---|
| Aliveness | 3 | It is what Nick actually asked for; it *resolves* rather than overturns a recorded design; it reuses a pattern already proven in-repo; and it dissolves the Flame-migration question rather than answering it. |
| Impact | 3 | ~7,150 lines currently unreusable become the reusable core of the stated durable investment. Closes a 3-instance drift class. Directly answers open task #3148 ("Character-maker in the Realm engine") — the character-maker compositor **is** rendering substrate, so `realm_flame` is its natural home. |
| **Product** | **9** | |

**Rejected alternatives at Ore:**

- **Re-home the two-hop token flow into `realm_firebase`** (aliveness 2 × impact 2 = 4).
  Real, and the same drift class — but a subset of this candidate's problem.
- **Decompose `main.dart`** (aliveness 1 × impact 3 = 3). Genuine debt, genuinely dull.
  Needs an afternoon, not a forge. Tracked as task #5.
- **Migrate Tech World off Flame to raw Flutter.** Argued against on measured evidence
  (see Attackable Claims) — and this candidate makes it moot either way.

---

## THE FALSIFIER — Heat must attack this first

**If the ~7,150 "generic" lines are shot through with Tech-World assumptions, this ore is
slag.**

Concretely, the classification above was done **by filename and file size, not by reading
the code**. That is exactly the cheap-proxy failure this session already committed twice.
The things that would falsify it:

- `bubble_manager` / `video_bubble_component` physics tuned to Tech World's specific grid
  size, or reaching into `TechWorld` directly.
- `player_component` hard-assuming the 512×64 / 16-cell sprite contract (it does at least
  partly — the wave strip logic is sheet-shape-aware).
- the tileset stack coupled to `predefined_tilesets` (Tech World's own art) rather than
  being format-generic.
- `map_preview_component` depending on Tech World map types rather than the engine's
  `RoomPreview`.
- anything in the "generic" pile importing `package:tech_world/...`.

If most of the pile fails this, the extraction produces a package with exactly **one
possible consumer** — which is not an engine, it is Tech World's rendering with
generic-sounding filenames. **Heat's first job is to read these files and report the
coupling honestly, including if it kills the candidate.**

---

## Attackable claims (carried forward to Temper — do NOT treat as premises)

1. **"~7,150 lines are generic substrate."** Filename-and-size classification only. Weakest
   claim in the bundle; the falsifier above targets it directly.
2. **"Don't migrate Tech World off Flame to raw Flutter."** *I* argued this earlier tonight
   on the grounds that (i) shallow usage means Flame is cheap to KEEP not cheap to LEAVE —
   you would rebuild component lifecycle, render ordering/priority, the animation ticker
   and effects by hand; (ii) `BLADE.md`'s character-maker compositor depends on Flame's
   `ImageComposition.composeSync()`, so rewriting the substrate immediately before building
   on it is bad sequencing; (iii) none of the repo's real architectural problems are
   Flame's fault. **I chose the route to that conclusion, so it is not independent. Attack
   it properly.**
3. **"The adapter pattern generalizes from persistence to rendering."** `realm_firebase`
   swaps a *backend* behind narrow ports (auth, storage, config). Rendering is not
   obviously the same shape — it is stateful, per-frame, and owns the component tree. The
   analogy may be prettier than it is true.
4. **"Core `realm` staying pure Dart is worth preserving."** Asserted from its dependency
   list plus `DESIGN.md`'s text-mode-bot claim. Nobody has ever run the engine headless.

---

## Open threads this candidate must face (not dodge)

- **The singleton/per-room mismatch.** `world.dart:6` says *"One room's worth of meaning"*
  and `:41` *"The room this world instance is hosting"* — the interface assumes **one World
  per room**. But `TechWorld` is an **app-lifetime singleton** constructed once at
  `main.dart:302` and reused across rooms (verified 2026-08-20; not disposing it on leave
  is *correct* for that reason). Making `TechWorld implements World` forces this
  contradiction into the open. `_StubWorld` can never surface it — it takes a `descriptor`
  in its constructor, so it is born per-room and of course fits.
- **`DESIGN.md:1030` step 6 ("the TechWorld wrap PR")** already prescribes
  `class TechWorld extends flame.World with TapCallbacks implements World` and a move to
  `worlds/tech_world/lib/`. `worlds/` does not exist; step 6 is unstarted. Per the
  scout-memory rule, a prior design's **prescribed shape binds** — this candidate must
  reconcile with it, not quietly replace it.
- **Do not make existing debt worse:** `lib/flame/tech_world.dart` is 1,637 lines and has
  regrown *past* its pre-refactor size (1613 → 1317 after PR #438 → 1637 now).
  `lib/main.dart` is 2,101 lines with zero dedicated tests.
- **`docs/crucible/realm-engine/`** holds `CRUCIBLE.md` + `RESEARCH.md` +
  `EVENT_PARTITION.md` but **no `DESIGN.md` and no `TEMPER.md`** — that forge stalled at
  Heat and never cast. Read it before casting this one.

---

## Stakes / context

No deadline. The Screen Australia grant was dropped 2026-08-20. Realm is explicitly the
durable engineering investment; Tech World is the first-party World that consumes it. The
next planned build is `BLADE.md` Step 1 (character maker: typed slot enums + preset
compositor), which is Flame-dependent and which task #3148 says belongs *in the engine* —
making this candidate directly upstream of it.
