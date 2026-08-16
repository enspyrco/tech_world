# 🜂 CRUCIBLE — Player-authored character-maker (Realm engine)

**Task:** #14 · **Selected & consented:** Nick named the target and the two core decisions explicitly.

## The pick (ore)

A player-authored character-maker in the **Realm engine** (the reusable substrate, not the grant-deadline game). Players compose a character from **preset parts** *and* can **edit at the pixel level**. The character is a typed `AvatarSpec` that composites **locally** on each peer into the game's rigid sprite-sheet render contract.

## Decisions already made (do not re-open — build on these)

1. **Authoring surface = a private authoring menu/UI**, NOT an in-world "forge" entity. The "world is the listener" doctrine is scoped to *casting/magic affordances only* and does not govern character creation. (An earlier framing wrongly imported it; corrected.)
2. **Format = procedural parts + pixel-level editing** (two-tier). Presets are closed part-enums; on top of any preset composition the player can paint at the pixel level. Both resolve locally to one 384×64 sheet.

## The render contract (the constraint everything resolves to)

From `lib/flame/components/player_component.dart` `_buildAnimations()`:
a **384×64** sprite sheet — 32×64 px per frame, **3 frames/direction**, **4 horizontal direction-strips** in order `down | left | up | right`; left/right strips reused for the diagonals. Sliced via `SpriteAnimation.fromFrameData` / `SpriteAnimationData.sequenced`.

## The crux (what Cast must resolve)

How does a typed `AvatarSpec` hold **open, user-authored** content (combinatorial presets **and** freehand pixels) AND flow through to the LiveKit avatar bubble **both peers see**?

Capability invariant, in verbs — grade the design against these, not "the type compiles":
- a user can **MAKE** a character (presets + pixel edits),
- **SEE** it (locally composited into the 384×64 sheet),
- **HAVE OTHERS SEE** it (survives the peer's parse gate and renders identically).

## The villain (peer-sync terminal where designs die)

`lib/livekit/livekit_service.dart:1197` — `AvatarUpdate.tryParse` whitelists incoming `spriteAsset` against `predefinedAvatarSpriteAssets` (the 3 known sprites) to stop path-traversal / decompression / cache-miss crashes from a hostile peer. A player-authored character must survive this gate **on the other peer's machine**.

## The two-tier resolution (proposed shape — pressure-test in Fold/Temper)

- **`CompositeAvatar(parts: {body, hair, outfit, accessory})`** — all closed enums. Only enum-ids cross the wire; the whitelist gate generalizes to "are all part-ids known?" = pure enum parse. Cheap, safe, closed.
- **`EditedAvatar(base, pixelLayer)`** — a **validated, content-addressed 384×64 RGBA raster**. The gate generalizes from *set-membership* to *structural validation*: **dimension-lock to exactly 384×64 RGBA** kills path-traversal (no filename), decompression bombs (fixed output size), and cache-miss crashes (always a valid texture). The rigid render contract is what makes accepting arbitrary pixels safe.

## Claims to falsify (carried to Fold + Temper)

1. **Local runtime compositing of preset parts into a 384×64 `ui.Image` is feasible and cheap on WASM/CanvasKit** (no `createImageFromImageBitmap`; Skia #14637). — *If false, the whole "composite locally, sync ids" argument collapses and bytes must cross for presets too.* (Heat is killing/confirming this.)
2. **Dimension-locked structural validation is a sufficient security substitute for the whitelist** for the edited-raster path. — *If a 384×64 RGBA raster can still carry an attack (renderer exploit, palette abuse), the gate isn't actually generalized, just relaxed.*
3. **An edited raster can be transported to peers within real constraints** (LiveKit data-channel size limits vs Firebase Storage hosting + content-addressing). 96KB raw / a few KB PNG. — *If neither transport is clean, the "others see it" verb fails for edited characters.*

## Rejected alternatives (carried to Temper)

- **Recolor/palette-swap only** (option A) — too thin; "customize" not "create." Rejected on aliveness.
- **Full arbitrary sprite-sheet upload as the *only* path** (pure option C) — heaviest, breaks typing discipline, worst peer-sync. Folded IN as the *edited* tier behind the preset tier, not adopted as the whole design.
- **In-world "forge" authoring entity** — rested on a mis-applied casting rule; character creation is legitimately private. Rejected.

## Content dependency (name in plan)

Preset parts need art (body/hair/outfit/accessory sets). Robin is already animating `dreamfinder_bot_sheet.png` — this closes that pipeline loop rather than opening a new one. LPC (Liberated Pixel Cup) layered-sprite standard is candidate prior art for the part model + open-licensed assets (Heat is assessing licensing + layout fit).
