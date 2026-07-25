# Realm Engine Extraction — Heat (research pass)

Ground-truth research for extracting a reusable Flutter/Flame/LiveKit multiplayer
framework ("Realm engine") from `tech_world`. First cut = the event-sink + PII
system in `lib/events/`. This feeds the design doc + cage-match, so it surfaces
**constraints and failure modes**, not cheerleading.

Date: 2026-07-25. Read-only pass.

---

## 0. TL;DR — the three decision-relevant findings

1. **The `code_forge_web` precedent DOES NOT EXIST.** It is a third-party MIT
   package by GitHub user `heckmon`, pulled from pub.dev — *not* an enspyrco
   extraction from this workspace. There is **no internal precedent** to copy;
   the design must invent the extraction pattern, not template it. (§1)
2. **Native Dart pub workspaces are available and free here** — SDK constraint is
   already `^3.6.0` (installed Dart 3.12.0), the exact minimum. No Melos in the
   repo. An in-repo `packages/realm_engine` workspace member is the
   lowest-friction path; a separate repo buys pub.dev publishing at the cost of
   version-lockstep pain. (§2)
3. **`sealed AppEvent` → `abstract AppEvent` is the load-bearing tension.** Making
   the base extensible by downstream apps *destroys* the compile-time exhaustive
   `switch` that three call sites (`console_sink`, `file_sink`, and the
   `pii_marker_test` gate) depend on. The abstract `PiiPolicy get piiPolicy`
   getter survives the boundary and still forces every subtype to classify
   itself — but the *sink-side exhaustiveness* does not. (§3)

---

## 1. PRECEDENT — `code_forge_web` is NOT an internal extraction ⚠️

**The task premise is false.** Verified against `pubspec.lock` and pub.dev:

- `pubspec.yaml`: `code_forge_web: ^2.9.0` — a normal hosted dependency, not a
  path dep.
- `pubspec.lock`: `source: hosted`, `url: https://pub.dev`,
  `sha256: 1b6b5a61…`, `version: "2.9.0"`.
- pub.dev page: publisher = **"Unverified uploader"** (not enspyrco /
  nickmeinhold), **license = MIT**, repo = `https://github.com/heckmon/code_forge_web`,
  described as "the web version of the powerful `code_forge` package."

So `code_forge_web` is a **third-party dependency tech_world consumes**, never
something extracted *from* this workspace. Grepping the two relevant CLAUDE.md
files finds no mention of it as a local package. No sibling under
`adventures-in/` or `~/git/orgs/enspyrco/` is a published-package extraction of
tech_world code (`crowdleague`, `engram`, `loom`, `domain_visualiser` carry no
`publish_to`/`homepage` package metadata indicating a pub.dev extraction).

**Implication for the design:** there is no house style to inherit. The realm-engine
extraction is the *first* package split out of this workspace, so the crucible
must specify the packaging shape from scratch (name, `publish_to`, LICENSE,
workspace wiring). Do not anchor the design on a "we did this with code_forge_web"
story — that story does not exist.

---

## 2. WORKSPACE / MONOREPO PACKAGING

### Current state
- `tech_world/pubspec.yaml`: `publish_to: "none"`, `environment: sdk: ^3.6.0`.
- **No `resolution: workspace`** anywhere in the pubspec. **No `melos.yaml`** in
  `tech_world` or anywhere under `adventures-in/`. tech_world is today a
  single standalone package.
- Installed toolchain: **Dart SDK 3.12.0 / Flutter** (`dart --version`).

### Native pub workspaces are viable with zero new tooling
Dart pub workspaces (docs: <https://dart.dev/tools/pub/workspaces>) require
**Dart ≥ 3.6.0**, and *every workspace member* must have `sdk: ^3.6.0` or higher.
tech_world already satisfies this exactly. Shape:

```yaml
# root pubspec.yaml (tech_world becomes/stays the root, or a new root wraps both)
workspace:
  - .                      # tech_world app
  - packages/realm_engine  # the extracted package
```
```yaml
# packages/realm_engine/pubspec.yaml
name: realm_engine
resolution: workspace
environment: { sdk: ^3.6.0 }
# publish_to omitted (or a pub.dev target) — see tradeoff below
```

A single shared lockfile/resolution covers both; the app depends on the package
via a plain `realm_engine:` (path resolved by the workspace). A workspace member
*can* be separately published to pub.dev while siblings stay `publish_to: none` —
publication target and workspace resolution are orthogonal (per docs; the member
consumes hosted versions when consumed externally).

### In-repo workspace member vs. separate repo — concretely for THIS repo

| Axis | `packages/realm_engine` (in-repo workspace) | Separate git repo + pub.dev |
|---|---|---|
| Tooling cost | **Zero** — native, no Melos | Melos or manual version dance |
| Change latency | Edit + run, one tree, one PR | Publish → bump → repoint every change |
| Grant firewall | Weak — code sits in the AGPL app repo | **Strong** — Apache code physically separate |
| Open-source story | "a folder" | A real published package |
| CI | Existing `flutter analyze`/`test` covers it | New repo needs its own CI |
| Blast radius | Shared lockfile — a realm_engine dep bump can move the app's resolution | Isolated |

**Read for the design:** start in-repo as a workspace member (cheapest, keeps
the tight edit loop while the API churns), with the package **structured as if it
were already standalone** (own LICENSE, no `package:tech_world/...` imports) so a
later lift to a separate repo is a `git filter-repo`, not a rewrite. The grant
firewall (Apache-vs-AGPL separation — flagged in project memory) is the one force
that argues for a separate repo *now*; weigh that explicitly, it is a real fork.

⚠️ **Shared-lockfile caveat** (workspace-wide verification, per global CLAUDE.md):
once realm_engine is a workspace member, changing its deps changes the *app's*
resolution too. Verification surface = the whole workspace, not just the package.

---

## 3. `sealed` ACROSS PACKAGE BOUNDARIES — the central constraint

### 3a. `sealed` subtypes are library-confined (VERIFIED)
Dart language docs (<https://dart.dev/language/class-modifiers>):
> "The compiler is aware of any possible direct subtypes because they can only
> exist in the same library."

`sealed` also implies `abstract` and prevents extension/implementation outside
its own library. **Therefore a `sealed AppEvent` in `package:realm_engine`
cannot be extended by an event subtype in `package:tech_world`.** The moment the
base is `sealed` and lives in the engine, the app cannot add `WordLearned`,
`DoorUnlocked`, etc. This is a hard compiler wall, not a style choice.

### 3b. What `sealed` currently buys — and what breaks when you drop it
The current `sealed AppEvent` is load-bearing for **compile-time exhaustive
`switch`** at three sites, all verified in-tree:
- `lib/events/sinks/console_sink.dart` — `switch (event) { WordLearned(...) => …, … }`
  over ~46 arms, **no `default`**. Adding a subtype without an arm is a build
  error today.
- `lib/events/sinks/file_sink.dart` — same pattern (JSONL serialization).
- `test/events/pii_marker_test.dart` — the **PII gate's dual control**: an
  exhaustive `switch` whose own comment states "Adding a new `AppEvent` subtype
  WITHOUT an arm … makes this file a compile error."

If the extraction turns `sealed` → `abstract` (so downstream apps can subclass),
**all three exhaustive switches stop compiling as exhaustive** — the analyzer will
demand a `default`/wildcard arm because the subtype set is now open. Consequences:
- `console_sink`/`file_sink` lose the "new event ⇒ compile error until you handle
  it" property. A new app event silently falls into `default`.
- The `pii_marker_test` compile-time exhaustiveness guarantee is **gone** — the
  test can only check representatives it happens to list (it already documents it
  cannot enumerate subtypes at runtime; Dart sealed classes expose no reflection
  over subtypes). Open hierarchy makes this strictly weaker.

This is the failure mode the cage-match will hammer: **you cannot have BOTH an
extensible-across-packages `AppEvent` AND compiler-enforced exhaustive
sink/PII switches in one type.** Design must pick a reconciliation, e.g.:
- Keep the engine's *own* infra events sealed; give the app a separate open
  extension point (a `custom` payload event, or a generic
  `AppEvent`-implements-interface where the app owns its own sealed family and
  the engine only sees the interface).
- Or accept an open base and replace exhaustiveness with a *runtime* registry +
  a lint/test that fails on an unclassified type (weaker; codegen needed for true
  exhaustiveness).

### 3c. The abstract getter DOES survive the boundary (VERIFIED, load-bearing)
An `abstract class AppEvent` with `PiiPolicy get piiPolicy;` (no body) forces every
**concrete** subclass — in any package — to override it. A concrete class that
inherits an unimplemented abstract member is an analyzer error
(`non_abstract_class_inherits_abstract_member` / "Missing concrete implementation
of 'getter piiPolicy'"). So the **PII self-classification gate is preserved** by
the `sealed → abstract` change: `registerRemoteSink`'s
`_shouldDropForRemote(event.piiPolicy)` still runs on every event, and a new
downstream event that forgets to classify itself won't compile.

**Net:** the PII *producer-side* gate (abstract getter) survives extraction
cleanly. The *sink-side* exhaustiveness (sealed switch) does not. Keep these two
guarantees mentally separate — the design note conflates them at your peril, and
the existing `pii_marker_test` comment explicitly warns against exactly that
conflation.

### 3d. Domain coupling — most of `types.dart` is NOT reusable
`lib/events/types.dart` (40KB, **46 `AppEvent` subtypes**) imports
`package:tech_world/editor/challenge.dart`, `.../prompt/prompt_challenge.dart`,
`.../spellbook/word_of_power.dart`. The subtypes are overwhelmingly
game-specific: `WordLearned`, `ChallengeCompleted`, `SpellCastFailed`,
`DoorUnlocked`, `TerminalOpened`, `MapEditorEntered`, `AvBubbleCreated`, …

**Only the machinery is generic:** `AppEvent` base + `PiiPolicy`
(`pii_policy.dart`) + `dispatch.dart` (register/remote/async/clear + fan-out with
try-catch isolation) + the sink *framework* (`console_sink`, `file_sink`,
`rotating_file_sink`, stubs) + `logger_bridge`. The extraction boundary is
**machinery-out, event-catalogue-stays** — you cannot lift `types.dart` wholesale
because it drags the whole game domain and violates the reusability goal. This
directly forces the 3b decision: the engine ships the base + gate + dispatch +
sink registration; the app keeps its own (sealed, if it wants exhaustiveness)
event family that plugs into the engine's open base.

---

## 4. LICENSING MECHANICS (Apache-2.0 pkg inside AGPL app)

Choice is settled (Apache-2.0); mechanics only:
- **`LICENSE` file at the package root** (`packages/realm_engine/LICENSE`) is
  **required** to publish to pub.dev, and pub renders it. Full Apache-2.0 text
  verbatim. (dart.dev publishing docs; package-layout conventions.)
- Apache-2.0 pkg consumed by an AGPL-v3 app is fine — Apache-2.0 is permissive
  and GPLv3/AGPLv3-compatible; the aggregate app remains AGPL, the package stays
  Apache. Keeping the `LICENSE` files distinct at each package root is what
  documents the boundary. (Not re-litigating the choice per task scope.)
- **Per-file headers**: optional but the Apache convention (Appendix boilerplate
  in `//` comment syntax at the top of each `.dart` file). pub.dev does not
  require them; the LICENSE file is the hard requirement. Recommend headers on
  engine `.dart` files for provenance clarity given the grant firewall.
- Add a `NOTICE` file only if attribution is needed (optional).

Sources: <https://dart.dev/tools/pub/publishing>,
<https://dart.dev/tools/pub/package-layout>.

---

## 5. PRIOR ART (external, brief)

- **Flame itself is a Melos monorepo** of 12+ packages (`flame`,
  `flame_network_assets`, `flame_audio`, `flame_forge2d`, bridge packages …),
  some depending on each other, in one repo published to pub.dev. It is the
  canonical "engine split into core + optional bridge packages" example, and it
  uses **Melos**, not native pub workspaces (Melos predates workspaces). Takeaway:
  a mature engine ends up multi-package (core + per-integration bridges) — plan
  the name/boundary so `realm_engine` (events/observability core) can later gain
  siblings like `realm_engine_livekit` without a rename.
  (melos.invertase.dev lists Flame among Melos adopters alongside FlutterFire,
  Amplify, Plus Plugins.)
- **Observability/event-bus extracted from an app**: the common pub.dev shape is a
  tiny zero-Flutter-dependency `*_events` / `*_logging` core package (pure Dart,
  `sdk` only, no `flutter` dep) that the app and other packages both import — which
  matches realm-engine's event core: `dispatch.dart`/`pii_policy.dart` have **no
  Flutter dependency** except `debugPrint` (from `flutter/foundation`), so the
  core could even be a pure-Dart package if that one call is abstracted. Worth a
  design note: dropping the `flutter/foundation` import widens reuse to server-side
  Dart.

Sources: <https://melos.invertase.dev/>,
<https://medium.com/@davidLegend47/part-1-flutter-monorepos-the-why-and-how-melos-can-help-9032f22513de>.

---

## 6. FAILURE-MODE CHECKLIST for the cage-match

- [ ] **Ghost precedent** — do NOT design "like code_forge_web"; it was never
      extracted from here (§1). Any plan citing it as the template is built on a
      false premise.
- [ ] **sealed/abstract fork** — the plan MUST state how it reconciles
      cross-package extensibility with the three exhaustive switches (§3b). "Turn
      sealed into abstract" without addressing sink-side exhaustiveness silently
      deletes a compile-time guarantee and weakens the PII gate test.
- [ ] **PII gate split** — producer gate (abstract getter) survives; sink-side
      exhaustiveness does not. Don't claim "the PII gate is preserved" as if both
      halves survive (§3c). `pii_marker_test` already warns against this exact
      conflation.
- [ ] **Domain drag** — `types.dart`'s 46 subtypes + 3 game-domain imports can't
      move to the engine (§3d). Confirm the boundary is machinery-only.
- [ ] **Shared-lockfile blast radius** — a workspace member's dep change moves the
      app's resolution; verification is workspace-wide (§2).
- [ ] **flutter/foundation dep** — `debugPrint` is the only Flutter coupling in the
      core; decide keep-as-Flutter-pkg vs abstract-to-pure-Dart (§5).
- [ ] **Grant firewall** — in-repo folder gives weak Apache/AGPL separation;
      separate repo gives strong. This is a real fork, name it (§2).
