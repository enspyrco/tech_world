# CAST — Player-authored character-maker: design (v2, post-Temper recast)

Bundle: `docs/crucible/character-maker/` · reads `CRUCIBLE.md` (ore) + `RESEARCH.md` (heat) + `TEMPER.md` (rounds 1–2).
Status: **SOUND → Blade-ready.** v1 sealed-XOR → stacked-AND; 13 round-1 flaws folded; round-2 (2 SOUND / 2 RECAST,
0 DISSOLVE) resolved — OV8 closed via the sealed `PixelEdit` union + 4 unanimous minors folded. No open soundness flaw.
Decisions locked by Nick: **ship presets + all-three pixel edit now** (pure / OverlayEdit / CanvasEdit); **blob store abstracted into the engine**.

---

## 1. Problem

Players want to author their own character — grab **preset parts** *and* **paint at the pixel
level on top** — and have **other players see it**. The codebase standard says a closed set is an
`enum`, never a `String`; but a player-authored character is open space. The design must let a
**typed `AvatarSpec`** hold open, user-authored content and flow through to the LiveKit avatar
bubble both peers render, without regressing the security boundary that protects the renderer.

**Capability invariant (grade against these verbs, not "it compiles"):** a user can **MAKE** a
character (presets + freehand pixels), **SEE** it (composited locally into the 512×64 sheet), and
**HAVE OTHERS SEE** it (survives the peer's gate and renders identically on their machine).

**The render contract everything resolves to** — verified against the ACTUAL asset
(`assets/images/NPC11.png`), not inferred from the code:

A **512×64** RGBA sprite sheet = **sixteen** 32×64 cells. `_buildAnimations()` reads only the
**first twelve** (`frameCount=3`, `sectionWidth = 3*32 = 96`, four strips at x=0/96/192/288):

| cells | x range | content |
|---|---|---|
| 0–2 | 0–96 | **down** (front) |
| 3–5 | 96–192 | **left** (side) |
| 6–8 | 192–288 | **up** (back) |
| 9–11 | 288–384 | **right** — pixel-identical opaque counts to 3–5, i.e. a mirror |
| 12–15 | 384–512 | **UNUSED** — an arms-raised wave/emote animation, drawn and shipped but never wired to any renderer |

Left/right are reused for the diagonals. **Assets are 512 wide; the renderer consumes 384 of them.**

⚠️ Both numbers matter and they are NOT interchangeable:
- **Asset/canvas invariant = 512×64** → a `width == 384` assert would reject every existing sprite.
- **Raw RGBA byte count = 512 × 64 × 4 = 131,072** (not 98,304) → this is the integrity constant in
  §3.4; the old value would have rejected every legitimate edit.

Corrected 2026-08-16 by opening the PNG during the Step-0 spike. The wrong constant survived
RESEARCH, the Fold self-pass, and BOTH four-family Temper rounds — everyone reasoned from
`frameCount * 32` in the code and nobody looked at the image.

The editor canvas is the full 512×64 (16 cells), so the unused emote frames stay authorable and the
wave animation can be wired up later without a spec-version bump. **Sixteen cells, not one canvas**
— the animation-consistency fact the editor must honor (§3.5).

---

## 2. The atypical element (the one surprising move)

**The rigid dimension is the security primitive.** Most custom-avatar systems pick one of two losing
ends: lock to presets (no freedom) or accept image uploads and fight decoder CVEs forever. This
design gets arbitrary-pixel freedom *and* a near-zero decoder attack surface by exploiting the fixed
512×64 contract: **peer-authored pixels travel as raw RGBA, never as an encoded image, so no codec
ever runs on peer-controlled bytes — on the way *out* (mint) OR the way *in* (render).** The
constraint that limits authoring is what makes accepting arbitrary pixels safe. That inversion is the
heart of the design — and it is only true if the *writer* is codec-free too (Temper flaw 3, §3.5).

---

## 3. Shape

### 3.1 The typed spec — **stacked, not sealed-or** (Temper flaw 1)

v1's fatal flaw: `CompositeAvatar` XOR `EditedAvatar` meant painting *flattened away* the semantic
parts, so a later part change forced "new hair OR your paint, never both." The ore was presets **AND**
pixels-on-top. So the spec is **one composite with an optional overlay**:

```dart
/// A player's character: semantic parts, plus an OPTIONAL pixel edit. The edit is a sealed
/// union of two flavours (Nick: "all three") — null=pure preset, OverlayEdit=decorate-on-top
/// (parts live), CanvasEdit=full custom sheet (parts frozen). One spec, one transport (§3.3),
/// one security path (§3.4); the ONLY divergence is a single render branch (§3.2).
final class AvatarSpec {
  const AvatarSpec({required this.parts, this.edit});
  final CompositeAvatar parts;   // ALWAYS present — closed enums, composited locally from the bundle
  final PixelEdit? edit;         // null ⇒ pure preset

  Map<String, dynamic> toWire();               // {parts:{…}, edit:{kind,uid,hash}?} — never pixels
  static AvatarSpec parse(Map<String, dynamic>? json); // total: always returns a renderable spec (§3.4)

  // AvatarSpec is the cache key (§3.2) → needs its OWN value-equality (Temper r2, Maxwell).
  @override bool operator ==(Object o) => o is AvatarSpec && o.parts == parts &&
      o.edit?.hash == edit?.hash && o.edit.runtimeType == edit.runtimeType;
  @override int get hashCode => Object.hash(parts, edit?.hash, edit.runtimeType);
}

/// Preset parts — pure closed enums. Only ids cross the wire; composited locally from bundled assets.
final class CompositeAvatar {
  const CompositeAvatar({
    required this.body,                  // MANDATORY — no `none` → never an invisible character (F1)
    this.hair = HairId.none,
    this.outfit = OutfitId.none,
    this.accessory = AccessoryId.none,
  });
  final BodyId body;
  final HairId hair;
  final OutfitId outfit;
  final AccessoryId accessory;
  @override bool operator ==(Object o) => o is CompositeAvatar && o.body == body &&
      o.hair == hair && o.outfit == outfit && o.accessory == accessory;
  @override int get hashCode => Object.hash(body, hair, outfit, accessory); // explicit value-equality → cache key
}

/// A pixel edit: a locator to raw-RGBA bytes in the engine's blob store (§3.3). Sealed — two
/// flavours that transmit identically ({kind,uid,hash}) and differ ONLY in how they render (§3.2).
/// The AUTHOR additionally holds the CPU Uint8List(131072) source-of-truth locally (§3.5);
/// peers only ever need {kind,uid,hash} to fetch, verify, and render.
sealed class PixelEdit {
  const PixelEdit({required this.uid, required this.hash});
  final String uid;   // owner — locator for the blob path `avatars/{uid}/{hash}` (Temper flaw 4)
  final String hash;  // SHA-256 of the canonical 131,072 RGBA bytes (integrity, Temper flaw 2)
}

/// Decorate-on-top: an additive delta (transparent except where painted), `srcOver` on the
/// LIVE composited parts. Parts stay swappable. Paint is pixel-absolute → a big mark may need a
/// touch-up after a part swap (named tradeoff, OV8); `basePartsHash` lets the editor flag it.
final class OverlayEdit extends PixelEdit {
  const OverlayEdit({required super.uid, required super.hash, required this.basePartsHash});
  final String basePartsHash; // parts fingerprint painted against (Temper r2, Carnot) — editor keep/clear assist
}

/// Full custom sheet: the bytes ARE the final 512×64. Rendered directly; `parts` retained only
/// as editor seed / provenance (frozen). Enables erase + destructive edits (Temper r2, Carnot).
final class CanvasEdit extends PixelEdit {
  const CanvasEdit({required super.uid, required super.hash});
}

/// Fallback before a peer's spec arrives, on parse failure, and on any overlay-fetch failure (F3).
const defaultAvatar = AvatarSpec(parts: CompositeAvatar(body: BodyId.explorer));
```

There is **no untrusted `base` on the wire** — `parts` *is* the semantic base, and it's closed enums
(this dissolves Kelvin's covert-channel flaw). Each slot is a closed **enhanced enum** carrying wire
name, bundled asset, and z-position:

```dart
enum HairId {
  none('none', null, 30),
  shortBrown('short_brown', 'parts/hair/short_brown.png', 30),
  ;
  const HairId(this.wireName, this.asset, this.zPos);
  final String wireName; final String? asset; final int zPos; // zPos on the VALUE (behind-body sorts < body)
  static HairId? parse(String wire) { /* wireName lookup, null if unknown */ }
}
```

**Part assets are app-bundled and closed** — every client ships every part sheet, so any receiver
composites any `CompositeAvatar` with zero fetch (claim C1).

### 3.2 Local compositing (parts → overlay → one cached `ui.Image`)

- **`parts`** → collect non-null part assets, `ImageComposition.add(image, Vector2.zero())` in ascending
  `zPos`, `composeSync()` (Flame CanvasKit GPU fast path; RESEARCH Q1/Q2 — WASM-safe, *not* the
  Skia-14637 texture-source bug).
- **`edit`** (if present) → one render branch, chosen by the sealed type:
  - `OverlayEdit` → `srcOver` the delta `ui.Image` on top of the composited parts, same `ImageComposition`
    pass. Parts stay live. An all-transparent delta is a no-op ⇒ render `parts` only (Temper flaw 12, n=0).
  - `CanvasEdit` → render the fetched raster **directly** (it IS the final sheet); parts are not drawn
    (frozen seed). Same 512×64, same slicer.
- Result cached keyed by the **whole `AvatarSpec`** (parts record + layer hash). Composite once per
  distinct spec, never per-frame (RESEARCH Q4). Hand the cached 512×64 image to the existing
  `_buildAnimations()` slicer — **the renderer does not change.**
- **Caches REFCOUNTED (F2).** Peers sharing a spec (or a layer hash — content-addressing dedups) share
  one cache entry; `dispose()` only when the refcount hits zero. Never dispose-on-first-leaver.
- **Bounded LRU + per-peer update throttle (Temper flaw 11).** A peer rapidly broadcasting distinct
  valid specs would otherwise thrash GPU composites; cap the cache (LRU) and rate-limit avatar updates
  per participant. The preset tier is **not** zero-attack-surface without this.
- **Overlay renders only after verify; until then, render `parts` (Temper flaw 1 + F4).** Because `parts`
  always composites locally with zero fetch, a peer sees a valid, *semantically-correct* character
  instantly; the overlay swaps in once fetched + verified. A permanently-failed / moderated / GC'd fetch
  simply stays on `parts` — graceful, and never a peer-controlled `base` (v1's mistake).

### 3.3 Transport, storage & persistence

- **Wire (LiveKit `avatar` topic):** `{parts:{body,hair,outfit,accessory, v:assetPackVersion},
  edit:{kind:'overlay'|'canvas', uid, hash, basePartsHash?}?}`. Enum wireName strings + an
  **`assetPackVersion`** (Temper flaw 8) so render-identical is verifiable across mixed clients. Never pixels.
- **Overlay bytes — engine blob PORT, not Firebase-in-the-engine (Temper flaw 6).** The Realm engine
  defines:
  ```dart
  abstract interface class BlobStore {           // content-addressed, engine-level
    Future<void> put(String uid, String hash, Uint8List bytes512x64); // exactly 131072 bytes
    Future<Uint8List?> get(String uid, String hash);                  // null = miss
  }
  ```
  **Tech World provides `FirebaseBlobStore`** (Storage under `avatars/{uid}/{hash}`); another World
  supplies its own. Mirrors the moderation-pluggable split.
- **Storage rules (Tech World adapter):** *write* = `request.auth.uid == uid` **and**
  `request.resource.size == 131072` **and** content-type locked. *read* = **get-by-exact-path for any
  authenticated user** (Temper flaw 7 + r2 Tesla: exact `avatars/{uid}/{hash}` GET, never a prefix
  **list** — a listable prefix collapses "room peer" into "any authed user can enumerate a user's blobs").
- **Profile persistence:** the player's `AvatarSpec` persists to their Firestore profile — **including
  `parts` AND `pixelLayer{uid,hash}`.** Because `parts` is always stored and the layer bytes live under
  the author's *own* uid path, **re-editing works cross-device** (fetch your own layer bytes back into
  the editor). Wire form == Firestore form (one codec).

### 3.4 The generalized gate (replacing the whitelist) — total, fail-closed

`AvatarUpdate.tryParse` (`livekit_service.dart:1197`) today whitelists `spriteAsset`. It becomes a
**total structural validator** that always yields a renderable `AvatarSpec`:

1. **`parts`** → parse each id via its enum `parse()`. **Same major `assetPackVersion` required for
   identity fidelity; do NOT silently default identity slots — `body` unknown ⇒ fall back to
   `defaultAvatar` (Temper flaw 8/Carnot).** Only explicitly-optional additive slots (hair/outfit/
   accessory) may degrade to `none` on an unknown id.
2. **`edit`** (optional, either variant — identical verify) → (a) well-formed `{kind,uid,sha256}`?
   (b) **hash NOT in the session-synced moderation denylist** (§5, an in-memory set subscribed once per
   session — NOT a per-sighting query; checked *before* any fetch — Temper flaw 5 + r2 Maxwell); (c)
   `BlobStore.get(uid, hash)`; (d) `bytes.length == 131072`; (e) **`sha256(bytes) == hash` else discard
   (Temper flaw 2 — integrity, not just length)**; (f) `decodeImageFromPixels` (no codec on peer bytes).
   Any step fails ⇒ **drop the edit, render `parts`** (always present, even for `CanvasEdit` — the frozen
   seed) — never a peer-controlled fallback. **A moderator hash landing mid-session must also evict the
   composite LRU entry, not just gate the next fetch (Temper r2, Tesla) — else takedown is fetch-time only.**
- **Legacy migration (F5).** Existing profiles hold the old String `avatarId` (`npc11/12/13`); `parse()`
  maps each to its equivalent `CompositeAvatar` so live users don't reset to default.
- **Fail-closed to a valid avatar** (`parts`, then `defaultAvatar`) — never a crash or hostile texture.

### 3.5 The freehand pixel editor (Nick: per-pixel now) — with the 12-cell honesty (Temper flaw 10)

The sheet is **twelve 32×64 cells** (3 frames × 4 directions). Freehand freedom is preserved, but the
editor must make animation-consistency *easy*, not the player's manual burden:

- **CPU source-of-truth (Temper flaw 3 — the writer path).** The editor owns a `Uint8List(131072)` in
  CPU memory. All painting mutates *that buffer*. Preview is `decodeImageFromPixels` on the buffer —
  **never GPU-composite-then-`toByteData`** (flutter#121758 WebGL readback corruption). The hash is
  computed over this buffer; the same bytes are uploaded. Codec-free out, codec-free in.
- **Decal start (Temper r2, Kelvin) then assists.** The first shippable editor collapses the 12-cell
  burden to **one**: paint freehand on a single canonical facing, the engine stamps it across all 12 cells
  (with L/R mirror). Richer per-frame control (onion-skinning, per-facing stamps, paint-through vs
  per-frame animated detail) layers on after. The player *can* reach every cell; the tools make the
  common want (a scar, a badge, a static mark) one action, not twelve.
- **Two modes → the sealed `PixelEdit` (Nick: all three).**
  - *Decorate* (default): paint sits on TOP of live parts. On save, the overlay bytes are the **delta the
    player added** (transparent elsewhere) — **parts are NEVER baked into these bytes** (Tesla r2: baking
    parts in silently restores v1's XOR). Produces `OverlayEdit{uid,hash,basePartsHash}`; parts stay
    swappable. A later part swap re-composites live; if `basePartsHash` no longer matches, the editor
    offers **keep / clear** (peers just render what the author broadcasts).
  - *Full canvas* (promote): the moment the player uses **erase** or picks "make it fully mine", the
    editor promotes to a full-sheet edit (one confirm: "this locks your parts"). Save writes the whole
    512×64 buffer ⇒ `CanvasEdit{uid,hash}`; parts kept only as re-edit seed.
- **Editor invariant (beside F7):** canvas is exactly 512×64; empty buffer ⇒ no `edit` (pure preset).

---

## 4. Build order (core-first, each step independently useful)

1. **Typed spec + preset compositing.** Slot enums + `AvatarSpec`/`CompositeAvatar` + `ImageComposition`
   compositor + refcounted LRU cache; replace String `Avatar`/`predefinedAvatars`; generalize `tryParse`
   (parts path + assetPackVersion + legacy migration). **Zero new *network* attack surface.**
   *Independently shippable.* **Includes the art-viability spike (Temper flaw 13):** author ONE real
   modular 32×64×3 character and confirm parts read at 32px *before* committing the enum surface.
2. **Authoring UI — preset picker.** Private menu (extends `avatar_selection_screen.dart`): per-slot
   selection, live composited preview, persist + broadcast. *A complete character-maker on its own.*
3. **Freehand pixel overlay tier.** The CPU-buffer editor (§3.5); `BlobStore` port + `FirebaseBlobStore`
   adapter; upload; `pixelLayer{uid,hash}` on wire + profile; receiver verify path (§3.4 step 2);
   moderation denylist (§5). **All network blast-radius lives here** — Storage rules, integrity verify,
   moderation, throttle built *with* this step. **This is a trust boundary → cage-match by law on the diff.**

Cage precedes monster: the untrusted-bytes surface is last, behind two safe milestones.

---

## 5. Blast-radius & consent spine

**New attack surface (step 3):** peer-influenced overlay bytes reaching the renderer; an authenticated
Storage write path; broadcast of arbitrary imagery.

| Threat | Mitigation (in the design) |
|---|---|
| Codec CVE / decompression bomb, in OR out | Raw RGBA only, **both writer and reader**; `length==131072`; `decodeImageFromPixels`; **no `toByteData` on the author path** (flaw 3). |
| Same-size malicious blob swap | **`sha256(bytes)==hash` recompute before render** (flaw 2) — content-addressing as integrity, not a folder name. |
| Unfetchable overlay | Wire carries `{uid,hash}` locator (flaw 4); read rule = any authed room peer (flaw 7). |
| Storage abuse / oversized | Rule: `auth.uid==uid` + `size==131072` + content-type; content-addressing dedups. |
| Quota exhaustion | Time-based LRU GC (~90d since last profile-ref OR access), **never the current-profile blob** (flaw 9, OV4). |
| Preset-update spam → GPU thrash | Per-peer avatar-update throttle + bounded LRU composite cache (flaw 11). **Throttle is trailing-edge / flush-on-save (Tesla r2)** — a committed avatar must not die inside the debounce window as if it were noise. |
| Mixed-version visual fork | `assetPackVersion` on wire; identity slots don't silently default (flaw 8). |
| **Offensive user imagery** | **Moderation designed IN (flaw 5):** a `moderated_avatar_hashes` collection; client checks a layer hash against it *before* fetch/render; a moderator adds a hash ⇒ real-time, non-destructive takedown (render `parts`, no 404). Report UI + attributable blobs (auth-scoped path). Automated pre-screen out of scope (named tradeoff). |

**Cost:** one blob (~96 KB) per distinct overlay; one GET per viewing peer, cached. Small-N rooms → negligible.

---

## 6. Claims to falsify (round 2 — for re-temper)

- **C1** — bundled parts ⇒ zero-fetch preset composite. Commit: parts bundled, closed, versioned with binary.
- **C2** — raw-RGBA **both directions** + length + `sha256` recompute + `decodeImageFromPixels` removes the
  codec surface end-to-end. Probe: is the *author's* CPU-buffer path truly free of any GPU readback on
  every target? Is `decodeImageFromPixels(131072)` itself safe on web/macOS/iOS/Android?
- **C3** — `assetPackVersion` + moderation-denylist-before-fetch + LRU GC + per-peer throttle is enough
  anti-abuse/anti-fork. Probe: denylist propagation latency; a hash re-uploaded under a new uid.
- **C4 — RESOLVED (Temper r2 + Nick):** the sealed `PixelEdit` union answers "presets AND pixels" with
  `OverlayEdit` (parts live, additive, keep/clear on mismatch) and `CanvasEdit` (frozen, full edit+erase).
  Both camps of the r2 panel were right about different modes. Residual watch: the `OverlayEdit`→`CanvasEdit`
  promotion path (erase triggers it) is the one *new* interaction — verify it in build, not on paper.
- **C5 — a step-3 PLAYTEST, not a design claim (Temper r2 unanimous).** Freehand at 32px×12-cells is a
  pixel-pusher; the decal-start + assists are the impedance match, and *presets* carry the beloved-ness.
  Measured by the same spike discipline as the art-viability spike (flaw 13). If a satisfying static mark
  can't land in a short sitting, shrink the *tools*, not the `AvatarSpec`.

---

## 7. Rejected alternatives

- **Recolor-only** — too thin. **Pure sheet-upload as the only path** — breaks typing; folded in as the
  overlay tier instead. **In-world forge** — mis-applied casting rule. **PNG over data channel** —
  breaches 16 KiB. **PNG storage + client decode** — reintroduces the codec on peer bytes.
  **Sealed-XOR two-tier (v1)** — repealed compose-ability; replaced by the stacked overlay (Temper flaw 1).
  **Per-slot detail-stamp edit model** — Nick chose freehand per-pixel; stamps become an *assist* (§3.5),
  not the model. **Firebase-direct in the engine** — Nick chose the `BlobStore` port abstraction.

---

## 8. Open variables (explicit)

- **OV1** — v1 slots: `body/hair/outfit/accessory` (additive-by-design). **OV2** — art source + license
  (LPC dual CC-BY-SA/GPL vs Robin-authored; blocking for real art, not for step-1 scaffolding).
  **OV3** — Firestore schema (wire form reused). **OV4** — GC: LRU 90d, current-profile blob immune.
  **OV6** — color variants (pre-authored PNGs vs runtime tint; deferred).
- **OV5 — RESOLVED:** identity slot (`body`) unknown ⇒ `defaultAvatar`, not silent default; optional
  slots degrade to `none` (Temper flaw 8).
- **OV7 — RESOLVED into §5:** moderation is designed in (denylist + report + non-destructive takedown),
  no longer deferred.
- **OV8 — RESOLVED (Nick: "all three"):** the sealed `PixelEdit` union gives both — `OverlayEdit`
  (pixel-absolute delta, parts stay live, keep/clear on `basePartsHash` mismatch) AND `CanvasEdit`
  (full sheet, parts frozen, enables erase). Pure preset = `edit:null`. No "third frozen type" beyond
  the two variants (Tesla: don't detune the spec) — `CanvasEdit` *is* the frozen case.

---

## 9. Grading against the invariant

- **MAKE** — steps 2 (presets) + 3 (freehand pixels, §3.5). ✅ by build order.
- **SEE** — local `ImageComposition` + overlay `srcOver` + CPU-buffer preview. ✅ (falsifier killed).
- **HAVE OTHERS SEE** — enum-ids + assetPackVersion (parts, always) + verified content-addressed overlay
  (integrity + moderation gate). Parts render *identically and instantly*; the overlay upgrades on verify.
  ✅ *if* C2–C4 survive round-2 Temper. Still the verb where the blast-radius concentrates.

---

## 10. Fold — author self-strike (v1, historical)

F1 mandatory body · F2 refcounted caches · F3 default-on-first-arrival · F4 base-first→now parts-first ·
F5 legacy migration · F6 moderation named→now designed-in · F7 512×64 asset invariant. (Full table in
git history of this file; kept short after the recast.)

## 11. Temper round-1 fold log (see TEMPER.md for the full strike)

All 13 deduped flaws folded above: **1** stacked-not-sealed (§3.1) · **2** sha256 integrity (§3.4) ·
**3** CPU-buffer writer, no toByteData (§3.5) · **4** {uid,hash} locator (§3.1/3.3) · **5** moderation
designed-in (§5) · **6** engine `BlobStore` port (§3.3) · **7** read=any-authed-peer (§3.3) · **8**
assetPackVersion + no-silent-identity-default (§3.3/3.4) · **9** LRU GC, current-blob immune (§5/OV4) ·
**10** 12-cell editor honesty + assists (§3.5) · **11** preset-update throttle + LRU (§3.2/5) · **12**
n=0 transparent overlay ⇒ parts-only (§3.2) · **13** art-viability spike in step 1 (§4).
Round-2 residuals for the re-strike: **C4/OV8** (overlay pixel-absolute vs part-locked) and **C5**
(freehand-at-32px is fun, not brutal).
