# TEMPER.md — Player-authored character-maker

**Overall verdict:** RECAST (candidate valid — no DISSOLVE; the *preset tier* is SOUND and Blade-ready, the *pixel/edited tier* needs a fold + re-strike before its build)
**Struck:** dt-1786839701 · families seated: **Maxwell + Kelvin + Carnot + Tesla** (4/4; Wu disabled)

## Per-family verdicts
| Family | Verdict | One-line |
|--------|---------|----------|
| Maxwell (Claude) | RECAST | Enthusiasm picked the elegant crux (type/security) over the real one (authoring UX); "pixel-edit the sheet" ignores that it's 12 animation frames. |
| Kelvin (Gemini)  | RECAST | `base`-on-the-wire is a covert channel / second source of truth; GC is distributed-state-blind; moderation is a vacuum, not a variable. |
| Carnot (GPT)     | RECAST | `hash` is not a locator; length-check ≠ integrity (no sha256 recompute); enum-render-identical assumes a pinned asset-pack version. |
| Tesla (Grok)     | RECAST | **Stacked-AND was recast as sealed-XOR** (flatten repeals compose-ability); the security thesis has no *writer* (mint-path hits the WebGL readback bug); the blob store is welded to Firebase inside the *engine*. |

## Fatal flaws (deduped, most-severe first)

1. **Sealed-XOR should be stacked-AND** — raised by **Tesla + Maxwell**. The ore is "presets PLUS pixels on top." The design made it `CompositeAvatar` XOR `EditedAvatar`: editing flattens and *loses* the semantic parts, so unlocking new hair later forces "new hair OR your painted scar, never both." **DISPOSITION: FOLD** → retype `AvatarSpec { parts: CompositeAvatar, pixelLayer: PixelLayer? }` — an optional overlay `srcOver` on the locally-composited parts. Peers always composite `parts` from the bundle (closed enums); the overlay rides on top and survives a part change. **This single retype also dissolves Kelvin's `base` covert-channel flaw (there is no untrusted `base` — `parts` is closed-enum) and fixes cross-device re-edit.**

2. **No integrity verification at the receiver** — **Carnot + Tesla**. Design validates `byteLength==98304` but never recomputes `sha256(bytes)==layerHash` before decode. Content-addressing without the compare is "naming theatre" — a same-size malicious blob under a plausible key renders. **DISPOSITION: FOLD** → receive gate: well-formed hash → fetch → `length==98304` → **`sha256(bytes)==hash` else discard** → `decodeImageFromPixels`.

3. **The security thesis has no WRITER** — **Tesla + Maxwell**. The *receive* path is codec-free and safe, but the editor must MINT the canonical bytes. The obvious flatten (GPU `ImageComposition` → `toByteData` → hash) hits **flutter#121758** — the exact WebGL-readback corruption RESEARCH Q1c flagged as break-glass. Author previews perfectly, uploads cursed bytes, peers decode a corpse. **DISPOSITION: FOLD** → editor source-of-truth is a CPU `Uint8List(98304)`; preview via `decodeImageFromPixels`; hash *that* buffer; **forbid `toByteData` on the authoring path.**

4. **`hash` is not a locator** — **Carnot + Tesla**. Wire sends `{hash}` but storage path is `avatars/{uid}/{sha256}`; a receiver can't fetch without the uid. **DISPOSITION: FOLD** → wire carries `{uid, layerHash}` (or hash + the named participant uid).

5. **Moderation is a vacuum, not a variable** — **Kelvin + Carnot**. For a broadcast-arbitrary-pixels feature, "no moderation story, deferred to OV7" is a fatal product/safety gap. **DISPOSITION: FOLD** → elevate to core: a `moderated_avatar_hashes` Firestore collection; client checks a layerHash against the denylist **before** fetch/render; a moderator adds a hash → real-time, non-destructive takedown (render `default`, no 404). *Named-tradeoff residue:* automated pre-screening is out of scope; the mechanism is report-and-takedown with instant propagation.

6. **The blob store is welded to Firebase inside the ENGINE** — **Tesla**. Realm is the reusable substrate; Firebase is Tech World's habit. `layerHash` with Firebase Storage assumed = next World has nowhere to resolve it. **DISPOSITION: FOLD (architecture — surfaced to Nick)** → a content-addressed blob *port* in the engine (`put(uid,hash,bytes) / get(uid,hash)→bytes|miss`); Firebase Storage is Tech World's adapter. Mirrors the moderation-pluggable split already in the design.

7. **Storage read rule undefined** — **Tesla**. Owner-only read → peers can't fetch → verb 3 dies; world-public → scrapers drink 96 KB × N. **DISPOSITION: FOLD** → read = any authenticated room peer.

8. **Enum render-identical assumes a pinned asset-pack version** — **Carnot**. Mixed client versions turn `unknown id → default slot` into a visual fork (author sees new part, old peer sees degraded), violating the "renders identically" invariant. **DISPOSITION: FOLD** → carry `assetPackVersion` in the composite wire spec; **do not silently default identity slots (body)** — require same major schema for identity fidelity, allow only explicitly-optional additive slots to degrade.

9. **GC is distributed-state-blind** — **Kelvin + Carnot**. "Collect superseded blobs" ignores peer caches / replication lag. **DISPOSITION: FOLD** → time-based LRU (e.g. 90 days since last profile-reference OR download), never collect the blob the current profile points at (refines OV4).

10. **"Pixel-edit the sheet" ignores 12 animation frames** — **Maxwell + Tesla**. A brushstroke on `down/frame0` is absent from the other 11 cells → the character strobes when it moves. **DISPOSITION: FOLD** → editor invariant (beside F7): a stamp lands on *every* facing+frame it belongs to, or it's a design bug. Decide the edit model: per-slot detail-stamp re-composited across frames vs freehand-per-cell (brutal). Resolve before the pixel tier builds.

11. **Preset-tier avatar-update spam → composite/cache thrash** — **Maxwell**. A peer rapidly broadcasting distinct valid specs forces a GPU composite + cache entry each time; "zero attack surface" is false. **DISPOSITION: FOLD** → per-peer avatar-update throttle + bounded (LRU) composite cache.

12. **n=0 on the overlay** — **Tesla**. An all-transparent `pixelLayer` must be a no-op (stay on parts), not an invisible body — the raster window F1 didn't visit. **DISPOSITION: FOLD** → empty/all-transparent overlay ⇒ render `parts` only.

13. **Over-invested in the elegant 15%** — **Maxwell**. The doc grades against "type is beautiful, wire is safe," not "authoring is fun"; part-legibility at 32px wide is an untested premise. **DISPOSITION: FOLD** → art-viability spike (author ONE real modular 32×64×3 character, eyeball legibility) *before* committing the enum surface; re-weight authoring-UX + art pipeline as co-equal crux.

## What holds (survived all four strikes)
- **Local compositing** via Flame `ImageComposition`/`composeSync` on bundled parts (RESEARCH Q1/Q2 — not the Skia-14637 bug). C1 true *while parts stay in the binary*.
- **Codec-free raw-RGBA RECEIVE gate** (the §2 inversion) — the right *shape*, once a CPU writer feeds it and integrity-verify is added.
- **Two chambers, build order caged** — preset tier first (steps 1–2, independently shippable steel), risky tier last.
- The **Fold F1–F7 lattice** for the preset chamber rings clean.

## Disposition
- **Preset tier (steps 1–2): SOUND → hand to Blade now.** It is a complete character-maker on its own and every family blessed it.
- **Pixel/overlay tier (step 3): RECAST → fold flaws 1–13 into DESIGN.md, then re-strike (round 2 of ≤3) before its build.** The structural retype (flaw 1) + write-path (flaw 3) + blob port (flaw 6) are substantial enough to warrant a second temper on the recast.

---

# TEMPER round 2 — re-strike of the recast (dt-1786840570-r2)

**Verdict:** 2 SOUND (Maxwell, Tesla) / 2 RECAST (Kelvin, Carnot) / 0 DISSOLVE. **Not a re-architecture** — all four agree the stacked shape, the end-to-end codec-free security, the blob port, and all 13 round-1 folds HOLD. The entire disagreement is one unresolved decision: **OV8 — how a pixel-absolute overlay relates to swappable semantic parts** — plus Carnot's sharp adjacent point that a pure `srcOver` overlay is **additive-only** (can't erase/modify preset pixels), so "pixel-level editing" may be underpowered.

## The one open fork (families split 2–2)
- **Don't lock (Maxwell, Tesla):** overlay is a pixel-absolute delta, parts stay live; recompose on part-change so any mismatch is visible; one assist (keep/clear). Locking = v1's XOR sneaking back in.
- **Bind/lock (Kelvin, Carnot):** an edited creation is an indivisible `(parts, layer)` unit (Carnot: add `basePartsHash`; mismatch ⇒ drop overlay or editor-rebase). Enables destructive edits since the base is fixed.
- **Carnot's orthogonal point:** `srcOver` can only ADD. True pixel editing needs an **erase/alpha mask** OR a frozen flattened sheet. Additive-only ≠ "change any pixel."

→ **This is product intent (what "change at the pixel level" MEANS), not a soundness question — surfaced to Nick, not tie-broken.**

## Unanimous minor folds (fold regardless of the fork)
- `AvatarSpec` needs its own `==`/`hashCode` over `(parts, pixelLayer?.hash)` — it's the cache key now (Maxwell).
- Moderation denylist = a session-synced in-memory set, not a per-sighting Firestore query (Maxwell).
- **Tesla's 3 implementation resonances:** (1) a moderator hash must pierce the composite **LRU cache**, not only the fetch gate, or "real-time takedown" is a fetch-time courtesy; (2) Storage `read` = get-by-**exact-path**, not prefix-list, or "room peer" collapses to "any authed user"; (3) the update throttle must **trailing-edge / flush-on-save**, or a committed overlay dies inside the window.
- Kelvin's **decal model** as the step-3 editor *starting point*: paint one canonical frame, engine stamps to all 12 (collapses the 12-cell burden to 1) — a concrete C5 de-risk.

## Disposition
Resolve OV8 per Nick's intent + fold the unanimous minors ⇒ the design is SOUND (nothing else blocks it; a round-3 strike is optional since the split is product-intent, not soundness). Then Blade.
