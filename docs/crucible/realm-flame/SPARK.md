# SPARK — the out-breath

**Movement:** Spark (movement 3) · **Date:** 2026-08-20 ~23:10 AEST
**Cast:** Maxwell (Claude), Carnot (Codex/GPT), Kelvin (Gemini) — **Tesla (Grok) pending**
**Thrown:** in parallel, blind to each other, generative prompt (no critique, no feasibility
filter). Maxwell's was written and saved *before* reading any sibling.

**Withheld from the throw, deliberately:** Heat's solution space — specifically Flame's
`bridge_packages` convention. Handing the cast the existing answer produces a recombination
of the cached default. They got the problem, the measured coupling, the real constraints and
the observed failure modes only.

---

## The three sparks, verbatim

### MAXWELL (Claude)

> **The engine should not own rendering. It should own the PHYSICS OF ATTENTION — and
> rendering is merely one projection of that field.**
>
> Look at what the 1,237-line "bubble manager" actually computes: proximity between
> inhabitants, a repulsion force that keeps them from overlapping, a merge field that fuses
> them when they get close enough, and an audio enable/disable decision that follows the same
> geometry. Not one line of that is graphics. It is a continuous, spatial model of **who is
> attending to whom, and how strongly.** The metaball shader is just the visible shadow of a
> scalar field that already exists in the math.
>
> The engine already claims presence — but it models presence as a *set*: who is in this
> room. That is presence with the geometry thrown away. The thing sitting misfiled up in the
> game is **presence with a geometry**: a continuous attention field over inhabitants, where
> "near" is a gradient rather than a boolean, and voice, video, merge and repulsion are all
> just thresholds read off the same field.
>
> So the thing to move down into the pure-Dart core is not the rendering. It is
> `AttentionField` — positions, a distance kernel, and the derived quantities (audibility,
> mergeability, repulsion vectors). Pure math. Zero Flutter. It satisfies the headless
> constraint not awkwardly but *naturally*: a text-mode bot asks the same field "who is near
> me and how loudly can I hear them" and gets a real answer with no pixels involved. A server
> can run it to decide who receives whose audio track. Flame becomes one renderer that
> happens to *draw* the field as circles with a shader.
>
> And it dissolves the hardcoded cast. Bots and Dreamfinder are not special kinds of
> *bubble*; they are inhabitants with positions, contributing to the same field like everyone
> else. The taxonomy vanishes because the field never needed to know what kind of thing
> something is — only where it is and how much of it there is.
>
> The one-consumer objection weakens too. "A reusable video-bubble widget" has one plausible
> user. "A spatial model of attention in a shared room" is obviously wanted by the imagined
> second world, by a headless server deciding audio routing, and by any bot that needs to
> know whether it is being spoken to.
>
> The rendering extraction was the wrong altitude. The prize was never the circles. It was
> the field underneath them.

### CARNOT (Codex / GPT)

> Make the engine own a pure-Dart "apparition layer": every inhabitant emits a sensory field,
> and Flame merely paints the resulting weather.
>
> Why it is alive: it stops treating rendering as "components" and turns it into world law. A
> player, bot, door, terminal, Dreamfinder, or future git-commit-body does not request UI. It
> radiates presence: silhouette, voice pressure, attention, proximity charge, merge affinity,
> gesture phase, sprite species, interaction gravity.
>
> The 1,237-line bubble manager becomes the first apparition ecology. Not "video bubbles for
> Tech World," but a social-fluid simulation where identities create soft bodies, repel, fuse,
> mute, brighten, and composite according to declared fields. Dreamfinder is no longer a
> hardcoded special case; Dreamfinder is the first mythic role: an entity whose nearness flips
> the local world into a different perceptual regime.
>
> The engine core stays headless because apparition is not pixels. It is a stream of
> render-intent facts:
>
> ```
> body A has aura radius 96
> body B emits voice heat 0.72
> A and B share merge membrane 0.41
> entity C uses sprite sheet species wanderer.wave
> local observer is inside mythic field dreamfinder.near
> ```
>
> A server can run it and describe the room. A bot can reason over it. Flame becomes one
> possible retina: it consumes apparition facts and paints metaballs, sprite frames, video
> surfaces, doors, terminal glow, and camera pull.
>
> The wild move is that "rendering in the engine" means the engine owns how a world becomes
> sensible, not which Flutter widget or Flame component draws it. Tech World then becomes a
> bestiary of apparitions instead of a pile of scene logic.

### KELVIN (Gemini)

> The rendering engine becomes a "social physics compiler" that translates a high-level
> description of inhabitants and their interaction rules into a visual and physical
> simulation.
>
> This idea is alive because it reframes the goal from "drawing sprites" to "embodying
> relationships." It treats the "hardcoded" logic in the bubble manager not as a flaw, but as
> the primordial soup of a domain-specific language (DSL) for social agents. The engine's new
> responsibility is to render a *Realm*, which is defined by the way its inhabitants perceive
> and react to one another.
>
> Instead of the game telling a generic renderer what to draw, it provides the rendering
> engine with declarative `Archetypes`. The game defines a `Player` archetype, a `WanderingAI`
> archetype, and a `Bot` archetype. Each definition bundles the "what" (sprite sheets,
> shaders) with the "how" (repulsion force, merge-field sensitivity, audio activation
> distance). The hardcoded map of characters becomes a registry of these behavioral
> blueprints.
>
> The new rendering package (`packages/realm_flame`) is not a library of components but a
> runtime for this system. It consumes the stream of raw presence data from the pure-Dart core
> (`Player X is at Y`), looks up the corresponding archetype, and executes its rules. The
> metaball physics, video compositing, and repulsion forces become emergent properties of the
> social graph, not bespoke features of one game.
>
> This creates a powerful, non-obvious abstraction. To build the next game — a git repository
> rendered as a city — one does not write new rendering code. One simply defines `Commit` and
> `Author` archetypes with their own unique social physics, plugging them into the compiler to
> get a living, walkable world for free. The engine provides a grammar for creating embodied
> social spaces, not just a canvas to paint on.

### TESLA (Grok)

*(Note: Tesla's raw output contains one truncated fragment — a line beginning "ng for
enter/exit edges on the local player's isosurface." — evidently a lost prefix. Reproduced
verbatim including the damage; nothing was reconstructed.)*

> The engine does not own sprites, cameras, or Flame. It owns the smear: a pure-Dart scalar
> field over the map that records, at every point, how completely the beings there have
> stopped being separate.
>
> Open the 1,237-line bubble manager and the game is not in the physics. Proximity, repulsion,
> the metaball, who can hear whom: that is climate. The game is the playbill stapled to the
> front of it. A map of bots. A wandering AI with a proper name. An identity string. A boolean
> latch for whether you are standing next to that one character. Plot. Costume. Cast.
>
> Identity in the engine is currently a point: a presence, a room, a voice track. The smear is
> identity becoming a region. Two video bubbles melt because the engine believes presence is
> not discrete. The shader is only the first witness that happens to speak in photons. A
> headless bot is a second witness: it never paints the metaball, it feels the chorus. The
> git-city does not need a new renderer. Two contributors standing on the same file are
> already a smear; a city block is what that field looks like when the beings are departments.
>
> The leaves that draw can live anywhere. They sample. The orchestrator that currently reaches
> into the service locator and the FFI frame-capture is trying to *be* the field while also
> dressing it. Split them there.
>
> Then "rendering lives in the engine" is already true, and Flutter never enters
> `packages/realm`. The engine renders by computing togetherness. Photons are a costume the
> field sometimes wears.
>
> ng for enter/exit edges on the local player's isosurface.
>
> Worlds do not draw. They supply the **metric**. Tech World: Chebyshev on tiles. The
> git-body: blame-distance. The org-city: org-chart hops. Same field, different distance. Git
> merge and metaball merge are the same algebra at different zoom.
>
> The 58 isolated Flame files stay in the one game that has pixels, as **costumes**. They
> receive a `KernelFrame` — position, 16-beat gait phase, merge-weight, voice amplitude — and
> they never import the engine. That is how the published Flame-library trap is refused: the
> one component that needed host UI context never gets a path upward, because costumes are
> write-only from the field. No new Flutter package, no lockfile poison.
>
> The 16-cell sheet (12 walk, 4 wave) is the engine's only pixel opinion: a metronome. Wave is
> the beat you play when fields brush without merging. Every world in this universe walks in
> 16. The second game is not a second consumer of a widget library. It is a second metric
> wearing the same gait.
>
> The bubble manager is deleted when Dreamfinder is data.

---

## Did they collapse onto one axis?

**No — and the way they failed to collapse is the finding.**

The skill's degenerate case is all families landing on the same axis, leaving bisociation
nothing to work with. Two of three (Maxwell, Carnot) *did* converge on "the engine owns
something field-shaped and pure, rendering is a projection." But they are not the same layer,
and Kelvin is on a third:

| Family | Layer | Owns |
|---|---|---|
| **Kelvin** | INPUT language | `Archetypes` the game *declares* — what an inhabitant is, and how it behaves socially |
| **Tesla** | INPUT, minimised | the **metric** only. A world supplies a distance function, nothing else |
| **Maxwell** | COMPUTATION | the field — positions + kernels → audibility, mergeability, repulsion. Pure Dart, headless |
| **Carnot** | OUTPUT contract | apparition *facts* — renderer-neutral render-intent a "retina" consumes |

Blind to each other, four families **tiled a pipeline** rather than duplicating a layer:
*declare → compute → emit → paint.*

All four converged on "the engine owns something field-shaped and pure; drawing is a
projection." That convergence is weak evidence *for* the split — they could not copy each
other — but it is equally **correlated-error risk across four models with a shared training
prior**, and Temper must treat it as the latter rather than as corroboration. Four models
agreeing is not four observations.

### Tesla is on Kelvin's axis but strictly smaller — and that matters

Kelvin: a world declares `Archetypes` bundling sprites, shaders, repulsion force, merge
sensitivity, audio distance. Tesla: a world supplies **a distance function**. Everything else
is derived.

Tesla's is the more radical reduction and the more testable claim. It is also directly
falsifiable — if Tech World's real behaviour cannot be reconstructed from Chebyshev-distance
plus a handful of kernels, Tesla is wrong and Kelvin's richer archetype is needed. **Fold
should test exactly this against `bubble_manager`'s actual logic.**

### Two things Tesla contributed that nothing else did

1. **It structurally refuses the `flame_ui` trap** (RESEARCH §5d) — without having seen that
   research. "Costumes are write-only from the field": components receive a `KernelFrame` and
   **never import the engine**, so the upward path that re-coupled `TextFieldComponent` to its
   host app *does not exist to be taken*. That is stronger than a convention; it is a
   topology.
2. **It dissolves the packaging problem, and with it two named risks.** The 58 zero-escape
   Flame files **stay in the game** as costumes. No new Flutter package ⇒ no shared-lockfile
   exposure (RESEARCH §5e.2), and the one-consumer objection (§5a) shrinks dramatically
   because no rendering *library* is being built at all — only a pure-Dart field with three
   already-wanted witnesses (Flame retina, headless bot, audio-routing server).

**This is the "simpler alternative that dissolves the problem" arriving three movements early,
inside the out-breath. Fold must take it seriously as a rival to the fusion, not fold it in
automatically.**

---

## The fusion — the third object no single spark contained

**`realm` is a compiler for embodied social space — and its source language is a metric.**

- **Source** — a World supplies a **metric** (Tesla): Chebyshev on tiles for Tech World,
  blame-distance for a git-body, org-chart hops for an org-city. Plus, where the metric is not
  enough, a small set of `Archetype` declarations (Kelvin) binding an inhabitant kind to its
  kernel parameters.
- **IR** — the **field** (Maxwell). Metric + positions + kernels, evaluated in pure Dart into
  continuous derived quantities: audibility, merge-weight, repulsion vector, gait phase.
- **Object code** — a **`KernelFrame`** per inhabitant (Tesla) / apparition facts (Carnot):
  renderer-neutral render-intent, emitted downward only.
- **Witnesses** — the Flame components already in `lib/flame` **stay where they are** and
  become costumes that *sample* frames. They never import the engine; the coupling is
  physically one-way. A headless bot is a second witness. An audio-routing server is a third.

**The load-bearing change from the pre-Tesla fusion:** there is **no `realm_flame` package** in
the fused object. The thing that moves down is the field, not the rendering. `packages/realm`
gains pure-Dart maths and gains no Flutter dependency; `lib/flame` keeps its 58 clean files and
loses its orchestrator.

That is a much smaller build, and it is the version that survives §5a and §5e.2 rather than
arguing with them.

### Why this is the "oh, of course"

**A game engine as a compiler: worlds are programs written in archetypes, and renderers are
code generators.**

1. **The pure-Dart constraint stops being aspirational and becomes structural.** Front-end and
   IR are pure Dart *by construction*; only backends ever touch Flutter. The "headless
   text-mode bot" in `DESIGN.md` stops being a rhetorical flourish and becomes just another
   backend — the cheapest possible proof that the boundary is real.
2. **It gives the one-consumer objection (RESEARCH §5a) its first genuine answer.** The
   second consumer does not have to be a second *game*. A headless audio-routing server and a
   text-mode bot are both already wanted, and both consume the IR without a single pixel. The
   abstraction gets its second and third data points *without* waiting for the git-repo world
   to exist.
3. **The hardcoded cast becomes the feature.** Carnot's reframe is the best line any family
   produced: Dreamfinder is not a wart, it is *the first mythic role* — an entity whose
   nearness flips the local perceptual regime. That is a thing an engine for embodied social
   space should be able to express, not a special case to sand away.
4. **Every boundary is independently testable** — archetype parsing, field evaluation, fact
   emission, lowering — which is exactly what the current `_StubWorld`-only validation lacks.

### Honest assessment of the fusion

**Is it just Tesla with decoration?** Closest call of the four. Tesla supplies the metric, the
write-only costume topology and the package-dissolution; Maxwell supplies the field as an
explicit IR; Carnot supplies the fact-stream contract and the "Dreamfinder as first mythic
role" reframe; Kelvin supplies the archetype fallback for what a bare metric cannot express.
**The fusion is ~60% Tesla.** That is an honest number, not a modest one — and if Fold finds
the other 40% is decoration, the correct outcome is to say so and cast Tesla's version
straight.

**Now the dangers, loudly.** The crucible's own evidence file warns that the out-breath
reliably produces designs that are **more alive AND more wrong**, and that Fold hit the Spark
arms hardest — in one trial the central claim was refuted at the first directive tried. This
one has four candidate refutations already visible:

1. **It may not answer what Nick actually asked.** He said *"I want the rendering stuff to live
   in the engine."* The fusion's reply is that rendering *already* lives in the engine because
   the engine computes togetherness and photons are a costume. **That may be a genuine
   reframe, or it may be a redefinition that quietly declines the request.** This is the FIRST
   thing Fold must test, and it is not a technical question — it is a "did we answer the
   customer" question, and the customer is one message away.
2. **The metric claim is falsifiable and untested.** Can `bubble_manager`'s real behaviour be
   reconstructed from Chebyshev distance plus a few kernels? Nobody has checked. If not, Tesla
   is wrong and the richer archetype is required.
3. **Four models sharing a training prior converged.** Treat as correlated error, not
   corroboration.
4. **Nothing is costed.** No estimate exists for extracting even one kernel, and "the bubble
   manager is deleted when Dreamfinder is data" is a *lovely sentence*, not a plan.

**Fold must also try the boring alternative** — move the clean tier into a bridge package per
Flame's own `bridge_packages` convention (RESEARCH §5b), leave the physics where it is — and
see whether it dissolves the problem at a fraction of the cost. If it does, the sparks were
beautiful and the answer is still boring, and Fold should say so.
