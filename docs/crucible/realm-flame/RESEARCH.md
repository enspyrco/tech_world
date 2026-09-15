# RESEARCH — `packages/realm_flame` (Heat)

**Movement:** Heat · **Date:** 2026-08-20
**Status:** internal audit COMPLETE · external prior-art PENDING (researcher in flight)

Heat's first job was the falsifier named in `CRUCIBLE.md`:

> *If the ~7,150 "generic" lines are shot through with Tech-World assumptions, this ore
> is slag.*

**Verdict: the falsifier does NOT fire — but it forced two corrections, and it exposed a
second axis the ore claim had blurred.**

---

## 0. Two instrument failures, recorded because the numbers changed

Both were mine, both would have shipped a wrong premise into Cast.

**(a) `package:` grep missed relative imports.** The first coupling pass grepped for
`package:tech_world` only. `video_bubble_component.dart` (1,045 LOC) scored "zero
coupling" — while actually importing seven app modules by *relative* path
(`../../events/dispatch.dart`, `../../utils/locator.dart`, `../../native/frame_source.dart`,
…). The initial "1,546 lines already dependency-free" claim was wrong; the true figure for
that sub-pile is ~502.

**(b) Filename-and-size classification is not evidence.** `CRUCIBLE.md`'s ~7,150-line
estimate was produced by reading a file listing, not code. The corrected number is
different in both directions (see §1) and the *shape* is entirely different.

Fix: `scratchpad/audit.py` resolves **every** import — `package:` and relative — to a repo
path and classifies it INTERNAL (inside `lib/flame`) / ESCAPES (elsewhere in `lib/`) /
EXTERNAL (pub or `dart:`). All numbers below come from that.

---

## 1. The corrected coupling picture

```
lib/flame:  74 files, 14,700 LOC
  ZERO escapes : 58 files,  6,703 LOC
  HAS escapes  : 16 files,  7,997 LOC
```

**Escapes are concentrated in five files holding ~49 of ~62 total escapes:**

| Escapes | LOC | File | Role |
|---:|---:|---|---|
| 18 | 1638 | `tech_world.dart` | the world / god object |
| 9 | 343 | `livekit_game_bridge.dart` | orchestrator |
| 8 | 1237 | `bubble_manager.dart` | orchestrator |
| 7 | 1045 | `components/video_bubble_component.dart` | **leaf, but heavily coupled** |
| 7 | 183 | `door_manager.dart` | Tech World vocabulary |

The remaining eleven coupled files carry **1–2 escapes each** — `map_preview` 2,
`countdown_clock` 1, `dreamfinder_component` 1, `path_component` 1, `player_component` 1,
`door_data` 1, `game_map` 1. Several are one-symbol fixes.

**What `lib/flame` reaches out to** (escape-target histogram, top entries):

```
5x events/dispatch.dart        5x events/types.dart
5x map_editor/map_editor_state.dart
4x livekit/livekit_service.dart  4x utils/locator.dart
4x prompt/prompt_challenge.dart  3x bots/bot_config.dart
3x auth/auth_user.dart           2x device/web_safe_mode.dart
2x diagnostics/diagnostics_service.dart
2x livekit/data_topic.dart       2x livekit/livekit_topic.dart
2x progress/progress_service.dart  2x avatar/avatar.dart
```

### THE KEY STRUCTURAL FINDING

**Coupling maps almost exactly onto the orchestrator-vs-leaf boundary.** The things that
*coordinate* (world, bridge, bubble manager, door manager) reach outward; the things that
*draw* mostly do not. The seam this candidate needs is not one that must be cut — it is
one that already exists and can be followed.

`video_bubble_component` is the sharp exception: a leaf renderer with 7 escapes. It is the
single most valuable extraction target (1,045 LOC of genuinely generic
video-bubble rendering) **and** the hardest. It is the crux of the whole candidate.

---

## 2. The second axis the ore claim blurred — this must reach Cast

**"Zero escapes" measures EXTRACTABILITY. It does not measure GENERICNESS.** These are
orthogonal, and `CRUCIBLE.md` conflated them.

Counter-examples, all zero-escape and all unmistakably Tech World vocabulary:

- `components/dreamfinder_component.dart` (420) — Dreamfinder is a Tech World character
- `components/bot_bubble_component.dart` (188) — Clawd
- `components/bot_character_component.dart` (120) — Clawd
- `tech_world_game.dart` (151) — the game class itself
- `mention/mention_world_controller.dart` (174), `components/mention_beacon_component.dart`
  (213) — arguably generic (mentions are a presence/chat primitive), arguably not

**A file can be perfectly decoupled and still belong to the game.** If Cast scores only
the coupling axis, `realm_flame` ships with Clawd inside it. Every candidate file needs
BOTH scores: *does it escape?* and *would a second, non-Tech-World World want it?*

### Provisional two-axis read (judgement, flagged as such — not measured)

**Generic AND zero-escape — the clean core:**
`maps/tmx_importer` 768 · `maps/barrier_occlusion` 375 · `tiles/wall_style_def` 285 ·
`components/speech_bubble_component` 222 · `components/tile_floor_component` 203 ·
`components/tile_object_layer_component` 191 · `maps/generators/*` ~487 ·
`tiles/tileset_registry` 171 · `components/merged_video_bubble_component` 155 ·
`shared/keyboard_movement` 149 · `tiles/tile_layer_data` 135 ·
`components/bubble_field_component` 128 · `tiles/tileset_analyzer` 128 ·
`tiles/tile_animations` 126 · `components/test_shader_bubble` 188
→ **≈3,711 LOC, movable with little or no work.**

**Generic but coupled — needs surgery, high value:**
`bubble_manager` 1237 (8 escapes) — **see §2a, initially mis-scored** ·
`components/video_bubble_component` 1045 (7 escapes) ·
`components/player_component` 298 (1) · `components/map_preview_component` 152 (2) ·
`components/path_component` 189 (1) · `tiles/tileset` 216 (1 symbol)
→ **≈3,100 LOC, the real work.**

**Tech World vocabulary — stays in the game regardless of coupling:**
`tech_world.dart` 1638 · `dreamfinder_component` 420 ·
`livekit_game_bridge` 343 · `tiles/predefined_tilesets` 1216 · `maps/predefined_maps` 482 ·
`door_manager` 183 + doors · bots · DF territory · `countdown_clock` 158
→ **≈4,800+ LOC.**

### 2a. `bubble_manager` was mis-scored — the coupling metric misled the classifier

Caught by Nick asking *"why would bubble_manager import bots and shit?"* — a question the
audit's own metric could not have raised, because 8 escapes made the file *look* like an
orchestrator that belongs to the game.

It is not. Its 1,237 lines — proximity detection, physics repulsion, metaball field,
merged-video compositing, audio enable/disable, bubble creation and removal — are
**entirely generic**. What makes it non-generic is that it **hardcodes the cast of
characters**, because each kind of inhabitant renders differently:

```dart
required Map<String, BotCharacterComponent> bots,   // ctor param
DreamfinderComponent? dreamfinderComponent;         // a named character
String dreamfinderIdentity = dreamfinderBot.identity;
bool _wasNearDreamfinder = false;                   // DF-specific proximity latch
…
bubble = _createDreamfinderVideoBubble(dfParticipant);
bubble = BotBubbleComponent(botStatus: _botStatus);
```

The generic concept is **"a thing in the world with a position that can show a bubble"** —
one interface. `BubbleManager` should iterate `Iterable<BubbleSubject>`, each subject
supplying its position, identity and a factory for its own bubble; bots and Dreamfinder
then become *Tech World's* implementations of that interface and the imports vanish.

**This is a distinct flavour of the session's recurring class:** not a thing *filed* in the
wrong layer (`ActiveLayer`, `LiveKitTokenEndpoint`, `World`), but a **generic mechanism
with specific vocabulary compiled into it**. Fifth instance.

**Consequence for the design:** `bubble_manager` moves from "stays" to "high-value
extraction", and its coupling is *one conceptual fix* (introduce `BubbleSubject`) rather
than seven separate ones — which arguably makes it a **better** first hard target than
`video_bubble_component`.

**Methodological warning for Cast and Temper:** an escape count cannot distinguish "this
file orchestrates game-specific things" from "this generic engine has a hardcoded cast".
Both look identical to the metric. Every file in the coupled tier must be read, not
scored. At least one was mis-scored; assume there are others.

**So the honest extraction estimate is ~3,700 LOC easy + ~1,900 LOC hard ≈ 5,600**, not
7,150 — and roughly 6,000 lines stay in the game. `CRUCIBLE.md`'s number was ~28% high and,
more importantly, the wrong *shape*.

---

## 3. Named smells found in passing (each is real, each is small)

1. **`tiles/tileset.dart` imports `map_editor/map_editor_state.dart` `show ActiveLayer`.**
   A tileset *definition* depending on the map *editor*. `ActiveLayer` is a tiles concept
   filed in the editor. Moving the enum down removes the dependency entirely. **This is
   the fourth instance tonight of the "filed one layer from where it belongs" class** —
   after `LiveKitTokenEndpoint`, `World`, and the rendering substrate itself.
2. **`components/path_component.dart` has `setGridFromEditor(MapEditorState)`** — one
   method causing the whole dependency. Invert it to accept a grid.
3. **`map_editor/map_editor_state.dart` is escaped-to 5×** — the joint-highest target
   alongside the event system. The map editor is acting as a de-facto shared module while
   living in a feature directory.
4. **`utils/locator.dart` escaped-to 4×** — components reaching into the service locator
   directly. Any extracted package must take dependencies by constructor injection
   instead; a package that calls `locate<T>()` is not a library, it is app code in a
   folder.

---

## 4. What this means for the candidate

**SURVIVES the falsifier**, with three amendments Cast must carry:

1. The extractable substrate is **~5,600 LOC**, not ~7,150, split into a genuinely easy
   tier (~3,700) and a hard tier (~1,900).
2. **Extractability and genericness are separate axes.** Score both, per file, or Clawd
   ends up in the engine.
3. **`video_bubble_component` is the crux.** It is the highest-value single file
   (1,045 LOC, genuinely generic video-bubble rendering that any multiplayer world would
   want) and it is coupled to the app's event system, service locator and native FFI
   layer. If the design cannot cleanly decouple this one file, the candidate loses most
   of its value — the tile stack alone does not justify a package.

**Sequencing implication:** the easy tier is real and independently useful, which means
the build order can be core-first and incremental. But a plan that ships only the easy
tier has shipped a tilemap library, not a rendering engine.

---

## 5. External prior art

Researcher briefed that the most valuable thing it could return was **evidence this is a
bad idea**. It found some. Sources fetched directly are marked VERIFIED; the researcher
flagged its own inferences separately, and those flags are preserved here.

### 5a. THE STRONGEST ARGUMENT AGAINST — one consumer

**VERIFIED, primary source:** Sandi Metz, *"The Wrong Abstraction"* (sandimetz.com).
Thesis, quoted: **"duplication is far cheaper than the wrong abstraction."**

The failure pattern she describes maps onto this candidate almost exactly: someone extracts
shared code; a second requirement arrives that is *almost* but not quite what the
abstraction handles; rather than fork, the team adds a parameter or conditional to avoid
"wasting" the extraction; each near-fit compounds the distortion until the abstraction
fights every new caller. Her prescribed remedy — **"the fastest way forward is back"**,
i.e. inline it into its sole caller and start over.

**`realm_flame` would have exactly ONE consumer: Tech World.** The "rule of three" says
two instances cannot distinguish *genuinely the same thing* from *coincidentally similar*,
and we have **one**. The generality is **speculative, not observed**.

**Partial rebuttal (mine, and it is only partial):** `packages/realm/DESIGN.md:115`
already names an intended second World — *"a github repo rendered as a body, an org
rendered as a city of bodies."* So a second consumer is *planned*. But planned is not
existing, and Metz's whole point is that the second real instance is the thing that tells
you where the seam actually goes. **This is the single strongest reason to defer, and
Temper must be allowed to kill the candidate on it.**

### 5b. THE STRONGEST ARGUMENT FOR — and it reframes the proposal

**VERIFIED:** Flame ships an entire documented category of first-party
**`bridge_packages`** (`docs.flame-engine.org/latest/bridge_packages/`):

- **`flame_forge2d`** — Box2D physics adapted into Flame components (`BodyComponent`,
  `Forge2DGame`)
- **`flame_tiled`** — Tiled tilemap rendering as Flame components
- **`flame_audio`**

Flame's own maintainers already split "engine core" from "first-party package that adapts
an external concern into Flame components," published separately, each coupled to
`FlameGame`/`Component` but decoupled from one another.

**This changes what the candidate IS.** `realm_flame` is not "a swappable renderer
abstraction" — it is a **bridge package**, structurally identical to `flame_tiled`. That
distinction matters enormously, because it sidesteps the entire body of evidence in §5c.
**Cast should adopt the bridge-package framing explicitly and drop the
renderer-abstraction framing.**

### 5c. Evidence against the framing we are NOT using (renderer-swap)

Preserved because `CRUCIBLE.md` reached for the renderer-neutrality framing, and Temper
should be able to check that we actually dropped it.

- **Godot** (VERIFIED, `godotengine.org/article/godot-3-renderer-design-explained`):
  abstracts rendering behind `RenderingServer` — but its architects **deliberately rejected
  a low-level swap boundary** in favour of a high-level one, because backends need
  structurally different techniques (GLES3 UBOs/VAOs vs GLES2 uniforms/pointers, different
  particle systems). Also documents that **"retrieving data from VisualServer is slow, as
  it may need synchronization."**
- **Bevy** (VERIFIED, GitHub discussion #2265): first-party admission that a dynamic
  render-backend abstraction required `bevy_id → backend_id` mapping with extra `RwLock`
  synchronisation and hashing, and **measurably hurt performance** (~8,000 sprites before
  dropping below 60fps, described by their own team as uncompetitive).
- **No source found** for a renderer abstraction being built and then torn out. The
  honest state is "costly, done carefully, at a high level" — not "abandoned."

**Team's original worry — validated but redirected.** The worry ("rendering is stateful,
per-frame, owns the component tree, unlike a narrow auth/storage port") is confirmed by
both Godot and Bevy *for multi-backend renderer abstraction*. It applies with much less
force to a single-implementation bridge package.

### 5d. A warning shot from the closest analogue

**VERIFIED:** `flame_ui` (pub.dev / github.com/chenasraf/flame_ui) is a reusable Flame
component library. Its components extend `PositionComponent` and are standalone —
**except `TextFieldComponent`, which requires `game.buildContext`**, so it only works
inside a `GameWidget` inside a `MaterialApp`.

**Even a deliberately-generic Flame component library had a component that reached back up
into the host app's Flutter tree.** That is precisely the failure mode to expect from
`video_bubble_component` (which already imports `utils/locator.dart` and
`diagnostics_service`). Adoption is also thin — 6 GitHub stars, 22 commits — so it is weak
evidence of the pattern *succeeding*, and better read as a caution.

### 5e. Mechanics to design around (all VERIFIED)

1. **`extends`, not `implements`, for evolvable ports.** Flutter's federated-plugin docs
   prescribe platform implementations `extends` the interface, because with `implements`
   **every added method breaks every implementer simultaneously**.
   **Direct tension with this repo:** `realm`'s `World` is an `abstract interface class`
   — which *forces* `implements`. The repo already knows: `world.dart:23` says **"Never add
   an abstract method to this interface after v1.0"** and prescribes sibling interfaces
   (`WorldFederationHooks`) for additive evolution. Consistent, but it means **any new
   `realm_flame` port must choose the same discipline deliberately, up front.**
2. **Dart workspaces share ONE lockfile.** `dart.dev/tools/pub/workspaces` warns
   explicitly: *"Using a single shared dependency resolution for all your packages
   increases the risks of dependency conflicts, because Dart doesn't allow multiple
   versions of the same package."* With `realm` (pure Dart) + `realm_firebase` +
   `realm_flame` (Flutter, and `realm_flame` would pull Flame, `flutter_webrtc`,
   `livekit_client`), **any transitive clash becomes a whole-workspace failure.** Given this
   repo was broken for a week by exactly a transitive version cascade (`6cbf90e7`), this is
   a live risk, not a theoretical one.
   Also: stray package-level `pubspec.lock` / `package_config.json` must be removed on
   migration, and an unlisted intermediate `pubspec.yaml` breaks `pub get` outright.
3. **Enforcing "`realm` never imports Flutter" has no off-the-shelf tool.**
   `dependency_validator` is a hygiene linter, not a direction enforcer. `import_lint`
   (Dart 3.10+) could plausibly be configured but the researcher found no published recipe.
   **The practical mechanism is a CI job running `dart analyze` (NOT `flutter analyze`)
   against `packages/realm/`** — a pure-Dart analysis context has no Flutter SDK, so any
   `package:flutter` import hard-fails. Researcher flagged this as common practice /
   inference, not a cited endorsement. It is cheap and it is a real guard; the design
   should include it.
4. **The proposed shape is the federated-plugin shape minus the app-facing package** —
   `realm` = interface, `realm_firebase` / `realm_flame` = implementations, consumed
   directly. Flutter's docs give **no** guidance on coordinating version numbers across
   split packages, and **do not enumerate failure modes** of splitting. That absence is a
   gap in the source material, not evidence of safety.

### 5f. Net read going into Cast

- **Adopt the bridge-package framing** (§5b). It is Flame's own convention and it dodges
  §5c entirely.
- **The one-consumer objection (§5a) is the real threat and has no clean answer.** It must
  survive to Temper unweakened, and should shape the build order: prefer steps that are
  *independently useful to Tech World even if `realm_flame` is never adopted by a second
  World*, so a wrong bet degrades to "we tidied our rendering layer" rather than "we built
  a library nobody used."
- **`video_bubble_component`'s locator/diagnostics reach-up is the `flame_ui`
  `TextFieldComponent` failure mode** (§5d), already present, already measurable.
