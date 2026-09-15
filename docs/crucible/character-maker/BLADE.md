# BLADE — Character-maker: ordered implementation plan

The tempered design (`DESIGN.md` v2, SOUND after 2 Temper rounds) translated into ordered, buildable
steps. Each step is independently shippable; the trust boundary is last and gets a code cage-match.

Locked decisions: ship **presets + all-three pixel edit** (pure / OverlayEdit / CanvasEdit); **blob
store abstracted into the engine**; authoring is a **private menu** (not an in-world entity).

---

## Step 0 — Art-viability spike (GATE) — ✅ **PASSED 2026-08-20** (see `step0/FINDINGS.md`)

Parts read clearly at true display scale. Measured against the SHIPPING sprites (NPC11/12/13)
rather than generated placeholders, so a negative result couldn't be blamed on bad programmer-art.
All four proposed slots — body / hair / outfit / accessory — are demonstrably legible at 32×64;
NPC13 already carries a cane, so the accessory slot is native to the house style. **The gate is
cleared: Step 1 may commit the enum surface.** OV2 (art source + licence) remains open and still
blocks real preset *content*, not the Step-1 scaffolding.

<details><summary>Original step-0 brief</summary>
Before committing the enum surface, prove modular parts read at 32px wide.
- Author ONE real modular character at the render contract: `body + hair + outfit + accessory`, each a
  512×64 PNG, composited. **The sheet is sixteen 32×64 cells** — 12 walk (4 direction strips × 3
  frames) **plus a 4-cell wave strip**, per `DESIGN.md:25` and
  `player_component.dart:_buildAnimations`. "3-frame / 4-strip" describes the walk portion only and
  is 384 wide; a part authored to it costs every character built from it the wave emote.
- Eyeball legibility at game scale. **If parts are muddy/misaligned at 32px → shrink scope (fewer slots
  / recolor-leaning) before building the type surface.** This is the C5/flaw-13 kill-or-confirm.
- Decide **OV2 (art source + license)**: LPC-derived (dual CC-BY-SA/GPL — attribution attaches to art,
  decide before grant build) vs Robin-authored to our grid. Robin is already in the sprite pipeline.

</details>

## Step 1 — Typed spec + preset compositing (no network attack surface) — *independently shippable*
1. **Slot enums** (`lib/avatar/parts/`): `BodyId` (no `none`), `HairId`/`OutfitId`/`AccessoryId` (with
   `none`), enhanced enums carrying `wireName`, `asset`, `zPos`; `parse(wire)`. Start minimal (OV1).
2. **Types** (`lib/avatar/avatar_spec.dart`): `CompositeAvatar` (value-equality), `AvatarSpec {parts,
   edit?}` (value-equality over `parts` + `edit?.hash` + edit runtime-type), sealed `PixelEdit` →
   `OverlayEdit`/`CanvasEdit` (defined now; only `parts` exercised until step 3).
3. **Compositor** (`lib/avatar/avatar_composer.dart`): Flame `ImageComposition.composeSync()` over parts
   in `zPos` order → one 512×64 `ui.Image`; **refcounted LRU cache** keyed by `AvatarSpec`; feed to the
   existing `_buildAnimations()`. Assert `width==512 && height==64` on every part-asset load (F7).
4. **Gate**: replace `AvatarUpdate.tryParse` (`livekit_service.dart:1197`) with total `AvatarSpec.parse`:
   parts path + `assetPackVersion` (same-major required; unknown `body`/major-miss ⇒ `defaultAvatar`;
   optional slots degrade to `none`) + **legacy `avatarId`→`CompositeAvatar` migration (F5)**.
5. **Swap call sites** off the String `Avatar`/`predefinedAvatars`: `player_component` (spriteAsset →
   composed image), `presence_entry`, `user_profile_service`, `livekit_service` publish/subscribe.
6. **Per-peer avatar-update throttle** (trailing-edge / flush-on-save) + bounded LRU cache.
7. **Tests**: enum wireName round-trip + cross-namespace disjointness; refcount dispose (2 peers, 1
   leaves → image survives); legacy migration; unknown-id fail-closed; composite cache hit by value-equality.
→ Ships: characters built from typed parts; peers see them. **Blocks on Step 0's art.**

## Step 2 — Authoring UI: preset picker — *independently shippable (a complete character-maker)*
1. Replace/extend `avatar_selection_screen.dart`: per-slot selection grid + **live composited preview**.
2. Persist `AvatarSpec` to the Firestore profile (**OV3** schema, wire form reused); broadcast on change.
3. Tests: preview matches broadcast; persistence round-trip.
→ Ships: the beloved Mii/Picrew-style pick-and-customize maker.

## Step 3 — Pixel edit tier (TRUST BOUNDARY → code cage-match on the diff)
1. **Engine blob port** (`packages/realm/`): `abstract interface class BlobStore { put(uid,hash,bytes);
   get(uid,hash) }`. **Tech World `FirebaseBlobStore`** adapter. Storage rules: *write* = `auth.uid==uid`
   + `size==131072` + content-type; *read* = get-by-**exact-path** for any authed user (no prefix list).
2. **Editor** (`lib/avatar/editor/`): CPU `Uint8List(131072)` source-of-truth; preview via
   `decodeImageFromPixels`; **never `toByteData`** (flutter#121758). **Decal start**: paint one facing →
   engine stamps 12 cells (+ L/R mirror). **Decorate mode** → `OverlayEdit` (delta bytes, parts NOT baked
   in, `basePartsHash` recorded). **Erase / "make it mine"** promotes → `CanvasEdit` (full sheet, one
   confirm "locks your parts"). SHA-256 the buffer; `put` to blob store.
3. **Wire + profile** carry `edit:{kind,uid,hash,basePartsHash?}`. **Receive verify** (§3.4): denylist →
   `get` → `length==131072` → `sha256(bytes)==hash` → `decodeImageFromPixels`; fail ⇒ render `parts`.
   Render branch: `OverlayEdit` = srcOver on live parts; `CanvasEdit` = raster direct.
4. **Moderation** (`moderated_avatar_hashes` Firestore collection): session-synced in-memory denylist,
   checked before fetch; a moderator hash **evicts the composite LRU** (not just the fetch gate); report UI.
5. **GC** (Cloud Function): time-based LRU (~90d since last profile-ref or access); **current-profile blob
   immune** (OV4).
6. **Tests + `/cage-match` on the diff** (trust boundary by law): malformed length, random bytes, wrong
   hash, moderated-mid-session eviction, overlay→canvas promotion, mixed assetPackVersion, n=0 overlay.
→ Ships: all-three pixel authoring.

---

## Dependencies & residual watch-items
- Order: **0 → 1 → 2 → 3.** Art (Step 0/OV2) gates real preset content, not the Step-1 scaffolding.
- **Verify in build, not on paper:** the `OverlayEdit`→`CanvasEdit` promotion path (C4 residual); that a
  satisfying static mark lands in a short sitting (C5 playtest); `decodeImageFromPixels(131072)` safe on
  web/macOS/iOS/Android (C2 residual).
- Open (non-blocking): OV6 color variants (deferred).

## Suggested first PR
Step 1.1–1.3 (enums + types + compositor + cache) behind the existing 3 presets, no UI change — pure
substrate, fully testable, zero user-visible risk. Then Step 2 lights it up.
