# Phase 3 — Video Pipeline Audit

**Date:** 2026-05-07  
**Scope:** Three video capture pipelines feeding circular video bubbles in the Flame canvas.  
**Files audited:**
- `macos/VideoFrameCapture/VideoFrameCapture.h` / `.m`
- `lib/native/video_frame_ffi.dart`
- `lib/native/video_frame_web_v2.dart` (DirectTrackCapture + VideoElementCapture)
- `lib/native/canvas_capture_web.dart`
- `lib/livekit/dreamfinder_avatar_bridge_web.dart`
- `lib/native/direct_track_capture.dart`
- `lib/flame/components/video_bubble_component.dart`
- `lib/native/video_frame_web.dart` (dead code — see §4)

---

## Pipeline Matrix

| Pipeline | Platform | Browser | Frame Rate | Memory Model | Disposal |
|----------|----------|---------|------------|--------------|---------|
| **FFI** | macOS only | N/A | 15 fps (ObjC throttle) + 20 fps Dart throttle (50ms min interval) | ObjC `calloc` buffer (header+pixels) owned by `VideoFrameStreamer`; Dart `TypedList` view into it | `video_frame_capture_destroy` via `VideoFrameCapture.dispose()` on `onRemove` |
| **Web V2** (DirectTrackCapture) | Web — Chrome main thread | Chrome only (MediaStreamTrackProcessor) | 66ms timer (~15 fps) | Offscreen `<canvas>` + `ImageData` + `ui.Image`; old frame disposed on next frame | `stopCapture` + `_currentFrame?.dispose()` in `dispose()` |
| **Web V2 fallback** (VideoElementCapture) | Web — all browsers | Any (video element) | 66ms timer (~15 fps) | Hidden `<video>` element + `ImageBitmap` + offscreen `<canvas>` + `ImageData` + `ui.Image` | `stopCapture` + element removed from DOM if owned + `_currentFrame?.dispose()` |
| **Iframe** (CanvasCapture / DreamfinderAvatarBridge) | Web only | Any | 66ms timer (~15 fps) | 256×256 px offscreen `<canvas>` + `ImageData` + `ui.Image`; old frame deferred microtask dispose | `stopCapture` + `_currentFrame?.dispose()` + iframe removed in bridge dispose |

---

## FFI Pipeline Issues

### MEDIUM — No `_frameInFlight` guard on `_processNativeFrame`

**File:** `lib/flame/components/video_bubble_component.dart`, lines 433–492

`_checkForNewNativeFrame` is called every `update(dt)` tick. It calls `_processNativeFrame()` which is `async` and is **not awaited**. There is no `_frameInFlight` flag (unlike both web paths which have `if (_frameInFlight) return`).

If frame decoding (`_decodeRgbaImage`) takes longer than one game tick (~16ms at 60fps), a second call to `_processNativeFrame` can start before the first completes. Both calls can write to `_currentFrame` and call `_currentFrame?.dispose()` on the previous value. This creates a window where one coroutine disposes an image the other is still encoding, or where both assign distinct new images — the second overwrites the first without disposal.

**Fix:** Add a `bool _nativeFrameInFlight = false` guard, mirroring the web paths.

### LOW — Race condition: `markConsumed` called before pixel copy

**File:** `lib/flame/components/video_bubble_component.dart`, line 472; `lib/native/video_frame_ffi.dart`, line 241–249

The sequence in `_processNativeFrame` is:
1. `bgraBytes = _capture!.getPixels()` — obtains a `TypedList` **pointer** into the ObjC buffer
2. `_capture!.markConsumed()` — sets `ready = 0` under `NSLock`, allowing the producer to write the next frame
3. `_bgraToRgba(bgraBytes)` — reads from the same buffer memory

After step 2, the ObjC `renderFrame` method is unblocked and may write new pixel data (under lock) before step 3 finishes reading. This is a torn-read race: the copy may interleave old and new pixel data.

**Fix:** Move `markConsumed()` to after `_bgraToRgba` completes (i.e., after `rgbaBytes` is obtained), or copy the bytes before calling `markConsumed`.

### LOW — Formal data race: Dart reads header without lock

**File:** `lib/native/video_frame_ffi.dart` (`hasNewFrame`, `width`, `height` getters); `macos/VideoFrameCapture/VideoFrameCapture.m` (`renderFrame`)

The Dart side reads `buf.ready`, `buf.frameNumber`, `buf.width`, `buf.height` directly without acquiring `NSLock`. The ObjC side writes these fields under `NSLock`. There is no acquire/release pairing on the Dart side, so this is formally a C11 data race.

In practice: macOS/ARM64's memory model and NSLock's internal `os_unfair_lock` (which issues a store-release on unlock) make this safe as long as the Dart isolate runs on a separate thread with the right memory barriers — which is true for Apple Silicon but not guaranteed by the C standard.

**Fix:** Expose a `video_frame_capture_read_header` C function that acquires the lock and copies the header atomically. Dart calls that instead of reading the shared buffer directly.

### LOW — `DynamicLibrary.executable()` — no symbol-not-found handling

**File:** `lib/native/video_frame_ffi.dart`, line 23; `_ensureFunctionsLoaded` lines 89–108

`DynamicLibrary.executable()` succeeds unconditionally (it just opens the current process), but `lookupFunction` throws if the symbol is absent. There is no try/catch around the lookup calls. If the ObjC plugin is not linked (e.g., wrong Xcode configuration or running on an iOS simulator), all lookups throw and the error propagates uncaught.

**Fix:** Wrap `_ensureFunctionsLoaded` in a try/catch and set `_isSupported = false` on failure.

### LOW — Stride padding is correct now but silently assumed

**File:** `lib/native/video_frame_ffi.dart`, line 248; `macos/VideoFrameCapture/VideoFrameCapture.m`, line 135

`dataSize = buf.height * buf.bytesPerRow` is used to size the `TypedList`. The ObjC code hardcodes `bytesPerRow = width * 4` (no padding). But `_bgraToRgba` iterates `bgra.length` as if every 4 bytes is a pixel — which is only correct when `bytesPerRow == width * 4`. If future code adds row padding (e.g., for GPU alignment), the conversion would silently misinterpret padding bytes as pixels, corrupting the image.

The struct declares `bytesPerRow` as a separate field (indicating awareness of potential stride), but `_bgraToRgba` ignores it. The two facts are inconsistent.

**Fix:** Either document the invariant (`bytesPerRow == width * 4` always) or update `_bgraToRgba` to respect stride.

### INFO — `_decodeRgbaImage` uses `ImageDescriptor.raw` (not `decodeImageFromPixels`)

**File:** `lib/flame/components/video_bubble_component.dart`, lines 539–563

The FFI path uses `ui.ImageDescriptor.raw` → `instantiateCodec` → `getNextFrame` (macOS only). The web paths use `ui.decodeImageFromPixels`. The CLAUDE.md prohibition ("NEVER use `createImageFromImageBitmap`") applies specifically to the Skia issue 14637 which only affects CanvasKit (web). `ImageDescriptor.raw` is not banned and works correctly on macOS where the Skia backend is the native one. This is intentionally different and **correct**. No action needed, but the doc comment in `video_bubble_component.dart` (lines 34–38) still describes the old V1 web approach (createImageBitmap + createImageFromImageBitmap) — that text is stale and misleading.

---

## Web Pipeline Issues

### MEDIUM — `_captureInitializing` guard bypassed for async remote capture path

**File:** `lib/flame/components/video_bubble_component.dart`, lines 207–227, 292–324

`_initializeCapture` sets `_captureInitializing = true`, then its `finally` block sets it back to `false` **synchronously** — before the async `_initializeRemoteWebCaptureAsync` completes. During the async operation (which involves `await Future.delayed` + `await video.play()` + polling loop totalling up to 3 seconds), the guard is down. The retry timer fires every 500ms for up to 10 retries (`_maxCaptureRetries`). Each retry creates a new `VideoElementCapture` (with a new `<video>` element appended to the DOM), overwrites `_remoteWebCapture`, and leaves the previous capture — and its DOM element — orphaned (never disposed, never removed from DOM).

In a session with a slow remote track, this can create up to ~6 orphaned `<video>` elements per remote participant.

**Fix:** Check `_captureInitialized` at the start of `_initializeRemoteWebCaptureAsync` after each `await`, and keep a separate `_asyncInitInFlight` flag that is set before the async launch and cleared at the end of the async function.

### MEDIUM — `_pendingUnmute` static singleton: multi-participant collision

**File:** `lib/native/video_frame_web_v2.dart`, lines 103, 128, 171, 179–181

`_pendingUnmute` is a `static Completer<bool>?` on `DirectTrackCapture`. If two remote participants join simultaneously and both tracks are muted, `createAsync()` is called for each. The second call overwrites `_pendingUnmute`, so `cancelPendingUnmute()` only cancels the second completer. The first completer's `Timer.periodic` poll continues running until the first track unmutes. There is no way to cancel it from outside.

In a room with 3+ remote participants joining at once (e.g., room reconnect), up to N−1 polling timers can leak, each firing every 100ms and calling `_isTrackMuted` until the track unmutes or the page navigates away.

**Fix:** Change `_pendingUnmute` to an instance field, or use a `Set<Completer>` that each instance registers with.

### LOW — V1 web file with banned API is dead code but still compiled on web

**File:** `lib/native/video_frame_web.dart`, line 260

`video_frame_web.dart` contains `await ui_web.createImageFromImageBitmap(...)` — the banned API (Skia issue 14637). The file is re-exported by `lib/native/web_video_capture.dart`, but nothing in `lib/` imports `web_video_capture.dart`. The class `WebVideoFrameCapture` is unreachable from `video_bubble_component.dart`.

However, the file **is compiled** when building for web (the `if (dart.library.js_interop)` conditional export means it is included in web builds). The tree-shaker will eliminate it at link time, but it remains a latent hazard: if anyone adds an import of `web_video_capture.dart`, the banned API immediately becomes live.

**Fix:** Delete `lib/native/video_frame_web.dart` and `lib/native/web_video_capture.dart`. Both are superseded by V2.

### LOW — `createAsync` synchronous path uses fixed `initialDelay` of 500ms

**File:** `lib/native/video_frame_web_v2.dart`, lines 246–253

When a track is already unmuted (common for local tracks), `createAsync` adds a 500ms delay "to let the video decoder start producing frames." This delay is unconditional and adds half a second of latency before the first frame appears, even if the decoder is already producing frames. The local video bubble stays in the loading spinner state for 500ms longer than necessary.

This was `initialDelay = const Duration(milliseconds: 500)` as a default. The caller `_initializeLocalWebCapture` uses `DirectTrackCapture.create()` (synchronous, no delay), so `createAsync` is only called via a code path that is no longer exercised in `video_bubble_component.dart` (the component calls `DirectTrackCapture.create`, not `createAsync`). However `createAsync` is a public API and could be called by future code.

**Fix:** Reduce `initialDelay` default to 50–100ms, or add a fast path that probes the stream before waiting the full delay.

### LOW — Browser compatibility: `MediaStreamTrackProcessor` is Chrome-only

**File:** `lib/native/video_frame_web_v2.dart`, lines 43–44, 74–76; `lib/flame/components/video_bubble_component.dart`, lines 260–268

`MediaStreamTrackProcessor` is not available in Firefox (main thread) or Safari (any thread as of mid-2025). The code correctly falls back to `VideoElementCapture` when `isMediaStreamTrackProcessorSupported` is false. However:

1. The fallback path (`_initializeRemoteWebCapture`) is always used for remote tracks even on Chrome, because `_initializeLocalWebCapture` is called for ALL tracks but the docstring says "DirectTrackCapture for ALL tracks." This means Chrome remote participants also use the `VideoElementCapture` fallback path if `DirectTrackCapture.create` returns null (which it currently can — it returns null if the cast to `web.MediaStreamTrack` fails).

2. Firefox users get `VideoElementCapture` with `createImageBitmap` in the intermediate step (line 797–799). `createImageBitmap` is available in Firefox, so the fallback works there, but it uses a `ImageBitmap`-to-canvas intermediate that adds one extra GPU→CPU→GPU round-trip versus the Chrome path.

### LOW — `VideoElementCapture` DOM element leak when `ownsElement = false`

**File:** `lib/native/video_frame_web_v2.dart`, lines 873–884

When `ownsElement = false` (i.e., a pre-existing LiveKit `<video>` element was found), `dispose()` skips DOM removal and `srcObject` nulling. This is correct — the element belongs to LiveKit. However, `_jsLoadedMetadata` event listener registered in `startCapture()` (line 729) is removed in `stopCapture()`. If `dispose()` is called without a prior `stopCapture()`, the event listener is cleaned up via `stopCapture()` being called in `dispose()` — this is fine.

The concern is the `_readbackCanvas` and `_readbackCtx`: these are never explicitly destroyed (no `remove()` call). They are not in the DOM (never appended), so they will be GC'd. No DOM leak, but the browser's GPU memory for the offscreen canvas bitmap (~width×height×4 bytes) is not freed until GC runs. Timing is non-deterministic.

**Fix:** Null out `_readbackCanvas` and `_readbackCtx` in `dispose()` to allow earlier GC.

---

## Iframe Pipeline Issues

### MEDIUM — No timeout for `renderer-ready` after canvas access failure

**File:** `lib/livekit/dreamfinder_avatar_bridge_web.dart`, lines 96–133

If `renderer-ready` arrives but `_findIframeCanvas()` returns null (e.g., the Three.js canvas wasn't yet created in the DOM when the message fired, or it's inside a shadow root), `initialize()` logs a `severe` error and returns. The bridge is left in `_isReady = false` state with the iframe loaded but no capture running and no retry logic. The 120-second timeout only guards the wait for `renderer-ready`; there is no retry after canvas lookup failure.

In practice: if Three.js is using a shadow DOM or a canvas created after the `renderer-ready` signal, the bridge silently fails.

**Fix:** Add a retry loop (e.g., 3 attempts × 500ms) for the `_findIframeCanvas()` call after `renderer-ready`.

### MEDIUM — Silent failure of iframe function calls (wrong log level)

**File:** `lib/livekit/dreamfinder_avatar_bridge_web.dart`, lines 261–277

`_callIframeFunction` catches all exceptions and logs at `_log.fine` (debug level). If `contentWindow` returns null after the iframe navigates away, or if `__onAudioChunk`/`__setMood`/`__interruptPlayback` don't exist on the window (e.g., the avatar JS failed to initialize), all audio and mood forwarding silently stops. In production (where log level is INFO+), this is completely invisible.

**Fix:** Log at `warning` level when `contentWindow` is null (iframe lifecycle issue) or when the JS call throws. Use `fine` only for the steady-state "everything working" path.

### LOW — `json['mood'] as String` unsafe cast

**File:** `lib/livekit/dreamfinder_avatar_bridge_web.dart`, line 254

```dart
_callIframeFunction('__setMood', json['mood'] as String);
```

If the bot sends `json['mood']` as a non-String JSON value (integer, null, or map), the `as String` cast throws a `TypeError`. The enclosing try/catch catches it at `_log.fine`, silently eating the mood update. This is defensive but opaque.

**Fix:** Use `json['mood']?.toString()` or add an explicit type check with a warning log on mismatch.

### LOW — postMessage listener not origin-checked

**File:** `lib/livekit/dreamfinder_avatar_bridge_web.dart`, lines 66–87

The `window.addEventListener('message', ...)` handler processes any `renderer-ready` or `avatar-progress` postMessage regardless of origin. If a third-party iframe or cross-origin script sends a spoofed `{ type: 'renderer-ready' }` message before the avatar loads, `readyCompleter.complete()` fires early, `_findIframeCanvas` is called on an empty iframe, and the bridge initializes against a blank canvas.

**Fix:** Check `event.origin == window.location.origin` before processing the message.

### LOW — 42MB GLB: 120-second timeout may be insufficient on mobile/slow connections

**File:** `lib/livekit/dreamfinder_avatar_bridge_web.dart`, lines 97–100

At 1 Mbps (mobile 4G with overhead), 42MB takes ~336 seconds. The 120-second timeout is calibrated for a fast connection (~4 Mbps). On slow connections the bridge will log `severe: Avatar renderer did not signal ready within 120 seconds` and return without starting capture, and there is no user-facing message (the bubble stays in loading spinner state forever after that point, since `_isReady` remains false and no retry is attempted).

**Fix:** Expose the `avatarLoadProgress` to the `VideoBubbleComponent` so the progress percentage is shown in the spinner (this is already wired: `loadingProgress` field on `VideoBubbleComponent` exists and renders the hologram boot). Also consider extending timeout to 300s or making it configurable.

### INFO — Same-origin requirement is implicit, not enforced

**File:** `lib/livekit/dreamfinder_avatar_bridge_web.dart`, line 7–14 (library docstring)

The docstring correctly documents the same-origin requirement (Caddy/nginx must serve `/avatar` from the same domain). The code relies on cross-origin access throwing an exception, which `_findIframeCanvas` wraps in a catch. The failure message is "Cannot access iframe canvas (cross-origin?)" at `severe` level. This is adequate for debugging. No code fix needed, but the deployment configuration is a single point of failure with no in-app warning to the user.

---

## Memory Concerns

### Per-bubble estimates (640×480 baseline)

| Pipeline | Native buffer | Dart copy | GPU texture | Peak (processing) | Steady state |
|----------|--------------|-----------|-------------|-------------------|--------------|
| FFI (macOS) | 1.17 MB (ObjC calloc) | 1.17 MB (`_bgraToRgba`) | ~1.17 MB | ~3.5 MB | ~2.3 MB |
| Web V2 DirectTrack (Canvas 640×480) | — | — (view, no copy) | ~1.17 MB | ~2.3 MB | ~1.2 MB |
| Web V2 VideoElement (640×480) | — | — (view) | ~1.17 MB | ~3.5 MB (+ ImageBitmap) | ~2.3 MB |
| Iframe CanvasCapture (256×256) | — | — | ~0.25 MB | ~0.75 MB | ~0.5 MB |

For a room with 5 active video participants + 1 Dreamfinder avatar: estimated steady-state GPU texture memory ~7 MB; peak during simultaneous frame decoding ~15 MB.

### MEDIUM — `_currentFrame` not disposed when video track stops (FFI path)

**File:** `lib/flame/components/video_bubble_component.dart`, lines 433–491

If the remote participant's video track ends (track terminated, not just paused), `_capture!.hasNewFrame` returns false indefinitely. The last decoded `_currentFrame` is held in memory until the component is removed from the Flame tree (`onRemove`). If the bubble component stays alive (participant still present but video track ended — e.g., they disabled camera), the last video frame is retained as a GPU texture indefinitely.

This is a deliberate UX choice (show last frame instead of blank), but it should be documented. If video is disabled for long periods (minutes), the GPU texture accumulates without ever being refreshed.

### LOW — Deferred microtask disposal in `CanvasCapture` vs synchronous disposal in web V2

**File:** `lib/native/canvas_capture_web.dart`, lines 147–149; `lib/native/video_frame_web_v2.dart`, line 403

`CanvasCapture` defers old frame disposal: `Future.microtask(() => oldFrame.dispose())`. `DirectTrackCapture` disposes synchronously: `oldFrame?.dispose()`. Both patterns are defensible, but the microtask approach in `CanvasCapture` was motivated by "CanvasKit can finish rendering it." The web V2 path uses `Future.microtask` in `_processWebFrame` (in the component, line 423–425) for web frames. The FFI path in `_processNativeFrame` (line 481) disposes synchronously without a microtask. This inconsistency means the GPU usage pattern differs between paths.

No leak in either case, but worth documenting the rationale per-path.

### LOW — `_readbackCanvas` and `_readbackCtx` not explicitly nulled on dispose (web V2)

**File:** `lib/native/video_frame_web_v2.dart`, `VideoElementCapture.dispose` (lines 866–885) and `DirectTrackCapture.dispose` (lines 433–438)

Neither class nulls `_readbackCanvas` / `_readbackCtx` in `dispose()`. These hold a reference to an off-screen `HTMLCanvasElement` and its 2D context. The canvas holds GPU backing memory. Until the Dart object is GC'd (and the JS objects finalized), the GPU memory for the canvas bitmap is pinned. At 640×480, this is ~1.17 MB per disposed-but-not-GC'd capture.

**Fix:** Set `_readbackCanvas = null; _readbackCtx = null` in `dispose()`.

---

## Compatibility Concerns

### HIGH — Safari / Firefox receive `VideoElementCapture` only, no `MediaStreamTrackProcessor`

**File:** `lib/native/video_frame_web_v2.dart`, line 74; `lib/flame/components/video_bubble_component.dart`, line 263–268

`MediaStreamTrackProcessor` is not available in Firefox or Safari. The fallback path (`VideoElementCapture`) is correctly activated. However `VideoElementCapture` uses `createImageBitmap` internally (line 797), which IS available in Firefox and Safari — so the fallback works. No breakage, but the Firefox/Safari path is slower (one extra ImageBitmap allocation per frame vs the Chrome path).

### HIGH — WASM dart2wasm: `dynamic` dispatch in conditional paths

The CLAUDE.md prohibits `dynamic` dispatch for JS interop in WASM builds. `direct_track_capture.dart` and `canvas_capture_web.dart` both use typed casts throughout. One exception is `VideoElementCapture.createFromStream(dynamic jsStream, dynamic jsTrack)` (line 472) — both parameters are typed `dynamic`. The casts inside (`jsStream as web.MediaStream`, `jsTrack as web.MediaStreamTrack`) are safe in dart2js but could fail differently in dart2wasm if the types don't match the JS type hierarchy. This method is called from `_initializeRemoteWebCaptureAsync` with `jsTrack` being the result of `direct_capture.getJsTrack(mediaStreamTrack)` which is typed `Object?`. The cast `jsTrack as web.MediaStreamTrack` in `createFromStream` performs a runtime type check.

In dart2wasm, this type check is stricter — if `getJsTrack` returns a `JSObject` that is not statically a `web.MediaStreamTrack`, the cast fails. Given the implementation of `getJsTrack` returns `mediaStreamTrackWeb.jsTrack` (typed as `web.MediaStreamTrack`), this should be fine, but the `dynamic` parameter loses the compile-time guarantee.

**Fix:** Change `createFromStream(dynamic jsStream, dynamic jsTrack)` to `createFromStream(Object? jsStream, Object? jsTrack)`.

### MEDIUM — `adaptiveStream: false` must be set on all VideoTrack subscriptions

**File:** `lib/flame/components/video_bubble_component.dart`, lines 506–537 (`_getVideoTrack`)

The CLAUDE.md documents that `adaptiveStream` must be `false` because Flame's canvas doesn't signal demand. The audit did not find where subscription options are set; this belongs to `LiveKitService`. If any video track is subscribed with `adaptiveStream: true`, the SFU will stop forwarding once the track is not rendered in a `VideoTrackRenderer` widget — and the Flame bubble will freeze silently. This is a configuration concern rather than a code bug in the pipeline files, but it should be verified in `LiveKitService`.

---

## What's Already Good

**Skia issue 14637 avoidance is thorough.** All three active pipelines use `ui.decodeImageFromPixels` (web V2 and iframe) or `ImageDescriptor.raw` (macOS FFI, where CanvasKit is not used). The banned `createImageFromImageBitmap` path is fully quarantined in the dead-code file `video_frame_web.dart`.

**BGRA→RGBA conversion is correct.** The byte swap in `_bgraToRgba` correctly maps `I420ToARGB`'s little-endian output (BGRA in memory) to RGBA for `ui.Image`. The `format` field in the shared header correctly records `0 = BGRA`, making the intent explicit.

**FFI struct alignment matches.** The 40-byte header is correctly computed in both C (`VideoFrameBufferHeader`) and Dart (`VideoFrameBuffer extends Struct`) with no misalignment: `uint64_t timestamp` lands at offset 16 (4+4+4+4), which is 8-byte aligned, requiring no padding.

**`top: -9999px` instead of `display:none` for offscreen rendering.** Both `VideoElementCapture.createFromStream` and `DreamfinderAvatarBridge._createHiddenIframe` correctly use fixed+offscreen positioning. Using `display:none` would prevent Three.js and video decoders from running.

**VideoFrame.close() called immediately after drawImage (web V2 DirectTrackCapture).** Releasing the VideoFrame reference before the async `decodeImageFromPixels` returns is correct — it allows the video decoder to recycle the buffer.

**ObjC VideoFrameStreamer holds a strong reference to RTCVideoTrack** (`@property strong RTCVideoTrack* videoTrack`). This prevents ARC from deallocating the track while rendering is in progress.

**`video_frame_capture_destroy` is called on dispose** (`VideoFrameCapture.dispose` → `_destroy?.call(_handle)`), and the handle uses `__bridge_retained` / `__bridge_transfer` correctly for ARC ownership transfer.

**`cancelPendingUnmute` is a public API** that allows callers to interrupt the unmute wait when the component is disposed. It is correctly used where needed.

**Canvas offscreen sizing is dynamic.** All three web capture paths resize the offscreen canvas when the video dimensions change, avoiding stale-size pixel readback.

**`_captureInitialized` prevents re-entry for the synchronous paths** (FFI and local web capture). The guard is reliable for non-async initialization.

**FrameSource interface** cleanly decouples `CanvasCapture` from `VideoBubbleComponent`, allowing the iframe pipeline to plug in without component changes.

---

## Finding Summary

| # | Severity | Pipeline | Description |
|---|----------|----------|-------------|
| 1 | HIGH | Web | Firefox/Safari compatibility: VideoElementCapture only (functional but slower) |
| 2 | HIGH | Web | WASM: `dynamic` params in `createFromStream` lose compile-time type safety |
| 3 | MEDIUM | FFI | No `_frameInFlight` guard on `_processNativeFrame` — overlapping async frame processing possible |
| 4 | MEDIUM | Web | `_captureInitializing` guard bypassed for async remote capture — orphaned DOM elements |
| 5 | MEDIUM | Web | `_pendingUnmute` static singleton — multi-participant collision leaks poll timers |
| 6 | MEDIUM | Iframe | No retry after canvas lookup failure post `renderer-ready` |
| 7 | MEDIUM | Iframe | Iframe function call failures logged at `fine` (invisible in production) |
| 8 | LOW | FFI | Race: `markConsumed` before pixel copy — torn read possible |
| 9 | LOW | FFI | Formal data race: Dart reads header without lock |
| 10 | LOW | FFI | `DynamicLibrary.executable()` symbol lookup not wrapped in try/catch |
| 11 | LOW | FFI | Stride-padding assumption undocumented (bytesPerRow assumed == width×4) |
| 12 | LOW | Web | Dead V1 file (`video_frame_web.dart`) contains banned API, compiled on web |
| 13 | LOW | Web | `createAsync` 500ms delay on already-unmuted tracks (unused in practice) |
| 14 | LOW | Iframe | `json['mood'] as String` unsafe cast, error silently swallowed |
| 15 | LOW | Iframe | postMessage handler not origin-checked |
| 16 | LOW | Iframe | 42MB GLB: 120s timeout insufficient on slow mobile connections |
| 17 | LOW | Memory | `_currentFrame` retained when track stops (intentional but undocumented) |
| 18 | LOW | Memory | `_readbackCanvas` / `_readbackCtx` not nulled on dispose |
| 19 | INFO | FFI | `_decodeRgbaImage` uses `ImageDescriptor.raw` — correct for macOS, but component docstring describes old banned web approach |
