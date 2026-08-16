# HEAT — Runtime local sprite compositing for the player-authored character-maker

Research movement of the /crucible forge. One load-bearing question: **is cheap local
runtime compositing of layered PNGs into one `ui.Image` feasible on WASM/web + native, so
that only enum-ids cross the wire?** If it isn't, the whole `AvatarSpec` design collapses.

Environment verified in-repo: **Flame `^1.18.0`** (resolved 1.34/1.37 in pub-cache), **Flutter
3.44.0 stable**, CanvasKit/Skia on web. The app already ships production code that uses
`PictureRecorder`, `Picture.toImageSync`, and `decodeImageFromPixels` and carries hard-won
comments about the exact WASM black-render bug this question circles.

---

## Q1 — Options to composite N layered 384×64 PNGs into one 384×64 `ui.Image`

### (a) `PictureRecorder` + `Canvas.drawImage(Rect)` + `picture.toImage()` / `toImageSync()`
**VERDICT: This is the blessed path. WASM-safe. Use it (via Flame's `ImageComposition`, which is exactly this).**

- Mechanism: record a `Picture` that draws each layer image with `srcOver` blend, then
  rasterize with `picture.toImage(w,h)` (async) or `picture.toImageSync(w,h)` (sync, GPU).
- `Picture.toImage` / `Scene.toImage` on CanvasKit was flutter/flutter#42767 — **implemented and
  closed years ago**; it is a supported first-class web API.
  https://github.com/flutter/flutter/issues/42767
- `Picture.toImageSync` was flutter/flutter#77289 — implemented; rasterizes into GPU context and
  was added specifically to improve CanvasKit performance.
  https://github.com/flutter/flutter/issues/77289
  https://api.flutter.dev/flutter/dart-ui/Picture/toImageSync.html
- **Why it does NOT hit Skia 14637:** the black-render bug is about creating a `ui.Image` *from an
  external texture source* (`createImageFromImageBitmap` → Skia `MakeLazyImageFromTextureSource`;
  same for `ImageDescriptor.raw`). Our layer PNGs are loaded through the normal Flutter/Flame
  asset codec, producing genuine Skia raster/GPU images; drawing those into a `Picture` and
  rasterizing is an entirely different path. The repo's own comment documents the distinction
  (`lib/native/canvas_capture_web.dart:146`): "ImageDescriptor.raw and createImageFromImageBitmap
  both render black in CanvasKit WASM. decodeImageFromPixels uses a different internal path
  (SkImage.MakeRasterData)." Compositing decoded images is not the texture-source path.
- **In-repo proof it works:** `merged_video_bubble_component.dart:152` and `map_preview_component.dart`
  and `tile_floor_component.dart` already call `PictureRecorder` + `toImageSync` in shipping code.
- Sync vs async: `toImageSync` returns immediately (may briefly be GPU-resident/uploading);
  `toImage` is a `Future`. For a one-shot character build either is fine.
- Cost: one `Picture` with ~4 `drawImageRect` calls over a 384×64 surface is trivial — sub-millisecond
  of record time plus one rasterize. This is a demo-tier operation, not a per-tick concern.

### (b) Flame `ImageComposition` — **exists, and it IS option (a) wrapped**
**VERDICT: Use this. Don't hand-roll the recorder.**

- Source read directly: `flame-1.34.0/lib/src/image_composition.dart`. `add(image, position, {source, blendMode…})`
  accumulates fragments; `_composeCore()` builds a `PictureRecorder`+`Canvas`, `drawImageRect`s each
  fragment with its blend mode, `endRecording()`.
- Two outputs: **`compose()`** → `Future<Image>` via `picture.toImageSafe(...)` (async, `toImage` under
  the hood); **`composeSync()`** → `Image` via `picture.toImageSync(...)`.
- Official doc explicitly: composeSync "rasterize[s] the image into GPU context using the benefits of
  the `Picture.toImageSync` function," added "to improve web rendering performance on CanvasKit."
  https://docs.flame-engine.org/latest/flame/rendering/images.html
  (source: https://github.com/flame-engine/flame/blob/main/doc/flame/rendering/images.md)
- Doc's own guidance matches our design: *"Composing images is expensive, we do not recommend you run
  this every tick… have your compositions pre-rendered so you can just reuse the output image."* →
  composite once, cache (see Q4). `source:` param lets you even crop sub-rects if needed.

### (c) Manual pixel blend: `Image.toByteData` → CPU alpha-composite bytes → `decodeImageFromPixels`
**VERDICT: Works and is guaranteed-safe, but slower and carries its OWN web caveat. Fallback only.**

- Fully avoids GPU rasterize; `decodeImageFromPixels` is the known-good WASM path (SkImage.MakeRasterData).
- **But `Image.toByteData` on CanvasKit has its own bug: flutter/flutter#121758 — reading pixels back
  loses/corrupts WebGL context state.** So the read-back step is not free of web risk either.
  https://github.com/flutter/flutter/issues/121758
- Cost for our contract: 384×64×4 = ~98 KB per layer; ~4 layers = a few hundred KB of `srcOver` math in
  Dart. Milliseconds, one-shot — acceptable as a fallback, but pointless unless (a)/(b) somehow fail.

---

## Q2 — Is `drawImage`→`toImage` "black on WASM" like `createImageFromImageBitmap`?

**VERDICT: NO. `Canvas.drawImage`→`toImage`/`toImageSync` on already-decoded images is WASM-safe and
is a distinct code path from the 14637 black-render bug. No fallback needed for the compositing step.**

- Skia 14637 / the repo's black-render failures are specific to **texture-source image creation**
  (ImageBitmap, VideoFrame, `ImageDescriptor.raw`) → `MakeLazyImageFromTextureSource`. Our sources are
  PNG-decoded raster images, not texture sources.
- If it *were* unsafe, Flame would not have shipped `composeSync` as a CanvasKit performance win, and this
  app's existing `toImageSync` call sites would already render black (they don't).
- The only nearby real hazard is on the **byte-readback** path (`toByteData`, #121758) — which is method
  (c), the fallback we're NOT choosing. The chosen path (a/b) never reads bytes back.
- `decodeImageFromPixels` remains the correct tool only for the *source* side if a layer ever originates
  from a texture/canvas rather than an asset — not needed for static PNG layers.

---

## Q3 — LPC (Liberated Pixel Cup) standard: layer model, licensing, layout fit

**VERDICT: Borrow LPC's LAYER MODEL and draw-order discipline wholesale. Do NOT expect its sprite
sheets to be a pixel-drop-in — LPC is 64×64/frame with 9-frame walk cycles; our contract is
32×64/frame × 3 frames. The modularity transfers; the exact geometry does not.**

- **Layer model:** modular characters = separate, same-size PNG layers (body, hair, clothes, hats,
  weapons, accessories) stacked in a fixed draw order. This is exactly the `AvatarSpec` = record-of-enums
  shape; LPC is the canonical proof the approach works at scale.
- **Geometry:** LPC standardized on **64×64 px frames**, 4 cardinal directions, with animation rows
  (walk, thrust, slash, cast, shoot, hurt; walk = 9 frames/direction). Our render contract is
  **32×64/frame, 3 frames/direction, 4 direction strips [down|left|up|right] = 384×64**. So:
  - The **[down|left|up|right] direction ordering and per-direction strip idea maps cleanly.**
  - LPC's frame *size* (64×64) and *frame count* (9-frame walk) differ. LPC art would need cropping/
    re-authoring to our 32×64×3 cell, OR we author our own art to the LPC layer discipline. The layer
    model adapts; the assets are not a free drop-in.
- **Licensing (matters — we need art):** all LPC submissions are **dual-licensed GNU GPL 3.0 AND
  CC-BY-SA 3.0**; derivative work in the repo inherits the same terms. CC-BY-SA is share-alike +
  attribution — usable, but **copyleft/attribution obligations attach to the art assets** (not to our
  app code). Worth a deliberate license decision before shipping LPC-derived art in a grant submission.
  https://github.com/liberatedpixelcup/Universal-LPC-Spritesheet-Character-Generator
  https://opengameart.org/content/liberated-pixel-cup-lpc-base-assets-sprites-map-tiles
- **Existing generator to borrow the layer model from:** the **Universal LPC Spritesheet Character
  Generator** (LiberatedPixelCup org) is a live, maintained web tool whose data model is a JSON catalog
  of layers each carrying a **z-position** and per-variant sheet paths — precisely the enum→layer→z-order
  mapping our design needs. Read its layer JSON as the reference schema for our closed enums.
  https://liberatedpixelcup.github.io/Universal-LPC-Spritesheet-Character-Generator/

---

## Q4 — When to composite: once-and-cache vs per-frame

**VERDICT: Composite ONCE per distinct `AvatarSpec`, cache the resulting `ui.Image`, feed it to the
existing `_buildAnimations()` slicer. Never per-frame. This is Flame's own explicit recommendation.**

- A peer's `AvatarSpec` arrives once over the wire and rarely changes, so the composite is amortized to
  ~once per participant per session.
- Flame doc, verbatim: *"we do not recommend you run this every tick as it affects performance badly…
  have your compositions pre-rendered so you can just reuse the output image."*
- **Cache key shape:** the `AvatarSpec` record itself — `(body, hair, outfit, accessory)` of closed enums.
  Because it's a value record of enums it has stable value-equality and is a natural `Map` key
  (`Map<AvatarSpec, ui.Image>` or a small LRU). Two peers with identical specs share one cached image.
- Lifecycle: build lazily on first sighting of a spec; `dispose()` the `ui.Image` when its last referent
  leaves (mirror the deferred-dispose pattern already in `canvas_capture_web.dart`). Rebuild only on a
  spec change (rare), keyed by the new record.

---

## Q5 — Draw order / layering correctness

**VERDICT: A single fixed z-order — body → outfit → hair → accessory — is correct for all four LPC
facings for the common case. The one real gotcha is "behind-body" accessories (cape/quiver/wings),
which need a sub-layer beneath the body; encode that in the enum's z-position, don't reorder per-facing.**

- Base order, back-to-front: **body (bottom) → outfit/clothes → hair → accessory (top)**. Matches LPC's
  z-position convention (body low, hair above head, hats/held items highest).
- **Back-of-head is handled by the ART, not by reordering.** LPC authors each layer with all 4 facings
  drawn into the same sheet; when facing **up** the hair sheet simply shows the back of the head in the
  up-strip. So the *same* draw order works for down/left/up/right — you do not swap hair in front/behind
  by direction for basic body+hair. This keeps our compositor a single fixed-order pass.
- **Gotcha 1 — behind-body accessories:** capes, quivers, wings, tails must render *beneath* the body
  (they sit behind the torso). LPC solves this with a lower z-position for those variants. If our
  `accessory` enum includes any such item, it needs its own z slot below `body`, i.e. z-order is a
  property of the enum VALUE, not a global constant. Cleanest: give each layer enum a `zPos:int` and sort.
- **Gotcha 2 — recolor/palette:** LPC ships many color variants as separate sheets rather than runtime
  tinting; if our enums encode color, prefer pre-authored per-color PNGs (still just a layer) over
  runtime palette-swapping to keep the compositor a pure `srcOver` stack.
- **Gotcha 3 — pixel registration:** every layer PNG must share the identical 384×64 canvas and frame
  grid so `drawImageRect` at (0,0) aligns perfectly. This is LPC's whole discipline; enforce it as an
  asset-import invariant (assert every layer sheet is exactly 384×64).

---

## Q6 — Transport of an edited 384×64 raster to peers

**VERDICT: Do NOT stream the raster over the LiveKit data channel. Upload the PNG to Firebase
Storage under a content-addressed key (hash of the pixels), send only `hash` + `spec` over the
wire; receivers fetch-once, dimension-validate, and cache. Model (ii) wins for small-N rooms.**

### (a) LiveKit data-channel size limits
- LiveKit **recommends ≤16 KiB per reliable message** (SCTP compatibility ceiling); **lossy is far
  smaller, ~1300 bytes** to stay under the ~1400-byte MTU. Larger reliable messages are fragmented
  into multiple SCTP chunks and **if any one fragment is lost the whole message is lost**.
  https://docs.livekit.io/transport/data/packets/
- Real, filed failure modes above threshold: server-crashing payloads around **~64 KB**
  (livekit/rust-sdks#554) and historical `publishData` failures at ≥2 KB / on rapid sequential sends
  (client-sdk-flutter#571). Treat 16 KiB as a hard design ceiling, not a soft guide.
  https://github.com/livekit/rust-sdks/issues/554
  https://github.com/livekit/client-sdk-flutter/issues/571
- **96 KB raw RGBA is ~6× the reliable ceiling** → would require app-level chunking + reassembly +
  loss handling. That is real complexity we should avoid.

### (b) PNG-compressed size of this raster
- 384×64 = 24,576 px. Pixel art (flat colors, few palette entries, large transparent regions) is the
  **best case for PNG's DEFLATE + paletted (PLTE/tRNS) encoding**. Expect roughly **3–15 KB** for a
  typical character sheet (mostly transparent, <64 colors); a busy full-color edit tops out ~20–30 KB.
- So a PNG *might* fit under 16 KiB in the common case — but the worst case (busy edit) still breaches
  it, meaning data-channel transport needs chunking anyway to be correct. That alone favors model (ii).

### (c) Two transport models
- **(i) Compress + send over LiveKit data channel (chunked):** self-contained, no extra infra, but you
  own chunking, reassembly, per-fragment-loss recovery, and late-joiner replay (a peer who joins after
  the broadcast never saw it — you'd need to re-request). Breaches the 16 KiB ceiling on busy edits.
- **(ii) Upload to Firebase Storage, send content-addressed hash/URL, receiver fetches + caches:**
  wire payload shrinks to a ~32-byte hash + the enum `spec`; well under any limit, no chunking. Firebase
  Storage handles CDN, caching, and **late joiners fetch on demand** (they just resolve the hash). The
  app already uses Firebase (Auth + config in-repo), so this adds no new dependency class.
  Content-addressing (key = SHA-256 of the canonical RGBA bytes) gives free dedup and an integrity check.
- **Recommendation: (ii).** For a small-N-per-room game the round-trip is one HTTPS GET per distinct
  edited avatar, cached by `Map<hash, ui.Image>` exactly like the preset path (Q4). Cleaner, correct for
  late joiners, no chunking state machine.
- **Trust implication (applies to BOTH models):** the wire only ever carries a **hash + enum spec**, never
  trusted pixels — but a fetched blob is attacker-influenced (a peer can upload any bytes under their own
  storage path). **The receiver MUST enforce exactly 384×64 RGBA before the image reaches the renderer**,
  and (see Q7) the dimension check is necessary-but-not-sufficient. Store per-user uploads under
  auth-scoped paths so the uploader is attributable, and treat the fetched image as untrusted input.

## Q7 — Is dimension-locked structural validation sufficient security for an incoming raster?

**VERDICT: NO — a post-decode 384×64 check does not neutralize the threat, because the dangerous work
(decompression bomb, decoder memory bug) happens DURING decode, before you can inspect dimensions.
Transport RAW RGBA and reconstruct with `decodeImageFromPixels` on a FIXED buffer — that IS strictly
safer than accepting a PNG, and it collapses the residual attack surface to near-zero.**

- **What the dimension-lock DOES neutralize** (vs the current whitelist): path-traversal (no filename/
  asset-path is ever consulted — the image is bytes, not a lookup key) and "wrong-shape" logic errors
  (a 4000×4000 or 1×1 image is rejected before rendering). Good, but that's the post-decode layer.
- **What it does NOT neutralize — the decode step itself:** to learn an image's dimensions you must first
  hand attacker-controlled bytes to a decoder. That is where the real CVEs live:
  - **Decompression bomb:** a tiny PNG whose DEFLATE/ancillary chunks expand to gigabytes exhausts
    memory *during* decode — dimensions are never reached (classic libpng CVE-2010-0205 shape).
    https://www.cvedetails.com/vulnerability-list/vendor_id-7294/Libpng.html
  - **Skia/codec memory bugs are a live, recurring stream:** e.g. Skia heap-overflow CVE-2025-32318,
    Chrome/Skia CVE-2026-3931, and FreeType-via-Skia CVE-2025-27363 tracked directly in the Flutter
    engine (flutter/flutter#181492). Flutter's decode path wraps Skia's codecs, so it inherits these.
    https://github.com/flutter/flutter/issues/181492
    https://zeropath.com/blog/android-skia-cve-2025-32318-summary
  - A dimension check reads the header AFTER the decoder has already parsed attacker structure — too late
    for bomb/overflow classes.
- **Raw-RGBA transport removes the decoder from the trust path entirely.** If the wire/blob carries **raw
  384×64 RGBA bytes**, the receiver: (1) asserts `byteLength == 384*64*4 == 98304` — a pure integer check,
  no parsing; (2) reconstructs via `decodeImageFromPixels(bytes, 384, 64, rgba8888, …)`, which does a
  straight memcpy into a Skia raster image (`SkImage.MakeRasterData`) with **no DEFLATE, no chunk parser,
  no codec**. There is no compression to bomb and no format parser to overflow. This is the same known-good
  WASM path the app already relies on (Q1/Q2).
- **Trade-off:** raw RGBA is 96 KB — which is exactly why we upload-and-fetch (Q6 model ii) rather than
  data-channel it. You *can* PNG-compress the Storage blob to save bandwidth, but then the receiver is back
  to decoding attacker PNG. **Cleanest: store the canonical artifact as raw RGBA (or gzip-at-transport via
  HTTPS, which the browser/Dart inflates safely into a bounded 98304-byte buffer you then length-check),
  and reconstruct with `decodeImageFromPixels` — never `instantiateImageCodec` on peer bytes.** If PNG
  storage is required for size, gate it behind a server-side (Cloud Function) re-encode to a canonical
  384×64 raster so clients only ever fetch pre-validated bytes.

---

## Bottom line for the design

**Cheap local runtime compositing IS feasible on WASM/web + native. The falsifier is KILLED.**

- **Method:** Flame `ImageComposition` (`composeSync()` for the GPU/CanvasKit fast path, or `compose()`
  async) — which is `PictureRecorder` + `Canvas.drawImageRect(srcOver)` + `Picture.toImageSync/toImage`
  under the hood. This is a supported, first-class CanvasKit path (flutter#42767, #77289 both implemented),
  already used in this app's shipping code, and **structurally distinct from the Skia-14637 black-render
  bug**, which only affects *texture-source* image creation (`createImageFromImageBitmap`/`ImageDescriptor.raw`),
  not compositing of PNG-decoded images.
- **No byte-level fallback needed.** The manual `toByteData`→`decodeImageFromPixels` path works but carries
  its own web caveat (flutter#121758 WebGL-context corruption on readback) and is strictly a break-glass
  option. The chosen path never reads bytes back.
- **Cost:** one-shot, ~4 `drawImageRect`s over 384×64, sub-millisecond record + one rasterize. Composite
  **once per distinct `AvatarSpec`**, cache `Map<AvatarSpec, ui.Image>` keyed by the enum record, hand the
  cached 384×64 image straight into the existing `_buildAnimations()` slicer. Wire stays pure enum-ids.
- **Art:** borrow LPC's modular layer model + z-position discipline (Universal LPC Generator's layer JSON
  is the reference schema). Its 64×64/9-frame geometry is NOT a drop-in for the 32×64×3 contract — author
  or crop to our grid. Watch the **CC-BY-SA / GPL-3.0 dual license** on any LPC-derived art before it
  ships in the grant build.
- **Layering:** fixed order body → outfit → hair → accessory works across all four facings (LPC art bakes
  back-of-head into the up-strip). Make `zPos` a property of each layer enum value so a behind-body
  accessory (cape/wings) can drop beneath the body without per-facing reordering.
- **Transport (pixel-edit tier):** do NOT push the 96 KB raster over LiveKit — it is ~6× the 16 KiB
  reliable data-channel ceiling and would need a chunk/reassembly/loss state machine. **Upload to Firebase
  Storage under a content-addressed key (SHA-256 of the canonical RGBA), send only `hash` + enum `spec`
  over the wire; receivers fetch-once and cache** `Map<hash, ui.Image>` just like the preset path. Handles
  late joiners for free; adds no new dependency class (Firebase already in-repo).
- **Validation claim — PARTIALLY holds, so tighten it:** hard-locking incoming avatars to exactly
  384×64 RGBA kills path-traversal and wrong-shape errors, but a *post-decode* dimension check does NOT
  neutralize decompression-bomb / Skia-codec-CVE threats, which fire *during* PNG decode before dimensions
  are known. **Fix: transport/store the artifact as raw RGBA and reconstruct with `decodeImageFromPixels`
  after a pure `byteLength == 98304` integer check — no codec, no DEFLATE, no parser on peer bytes.** That
  reconstruction path (SkImage.MakeRasterData) is the same WASM-safe route the app already trusts, and it
  makes the dimension-lock claim actually sufficient. If PNG storage is needed for size, re-encode
  server-side (Cloud Function) so clients only ever fetch pre-validated canonical rasters.
