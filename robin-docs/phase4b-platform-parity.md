# Phase 4b: Platform Parity Audit

**Date:** 2026-05-08
**Skill:** `/tw-platform-parity`

## Conditional Import Map (7 files)

| Router file | Web implementation | Native implementation | Stub |
|---|---|---|---|
| `native/video_frame_capture.dart` | `video_frame_ffi_stub.dart` | `video_frame_ffi.dart` (macOS FFI) | `video_frame_ffi_stub.dart` |
| `native/direct_track_capture.dart` | `video_frame_web_v2.dart` (JS interop) | `video_frame_web_v2_stub.dart` | `video_frame_web_v2_stub.dart` |
| `native/canvas_capture.dart` | `canvas_capture_web.dart` | `canvas_capture_stub.dart` | `canvas_capture_stub.dart` |
| `livekit/dreamfinder_avatar_bridge.dart` | `dreamfinder_avatar_bridge_web.dart` | `dreamfinder_avatar_bridge_stub.dart` | `dreamfinder_avatar_bridge_stub.dart` |
| `services/stt_service.dart` | `stt_service_web.dart` | `stt_service_stub.dart` | `stt_service_stub.dart` |
| `services/tts_service.dart` | `tts_service_web.dart` | `tts_service_stub.dart` | `tts_service_stub.dart` |
| `flame/tiles/tileset_cache_provider.dart` | `tileset_cache_provider_stub.dart` | `tileset_cache_provider_native.dart` | `tileset_cache_provider_stub.dart` |

## Feature Parity Matrix

| Feature | Web (Chrome) | Web (Safari) | Web (Firefox) | macOS | iOS | Android |
|---|---|---|---|---|---|---|
| Video capture (FFI) | stub | stub | stub | **full** | no-op | no-op |
| Video capture (web — DirectTrack) | **full** | partial (Safari 18+) | partial (VideoElement fallback) | stub | stub | stub |
| Video capture (Dreamfinder canvas) | **full** | full | full | stub | stub | stub |
| LiveKit audio/video | **full** | partial | full | **full** | partial | full |
| Firebase Auth — Google | **full** | full | full | full | full | full |
| Firebase Auth — Apple | — | — | — | **full** | full | — |
| Speech-to-text (spell casting) | **full** | partial (privacy prompts) | **none** | stub | stub | stub |
| TTS (bot voice) | **full** | full | full | stub | stub | stub |
| Code editor with LSP | **full** | full | full | full | untested | untested |
| Map editor with CRDT | **full** | full | full | full | untested | untested |
| Dreamfinder 3D avatar | **full** | full | full | stub | stub | stub |
| Tileset disk cache | no (browser cache) | no | no | **yes** | yes | yes |
| Procedural map generation | **full** | full | full | full | full | full |

## WASM Compliance

- **`adaptiveStream: false`** in `RoomSession` — CORRECT
- **No `createImageFromImageBitmap`** — all paths use `decodeImageFromPixels` — COMPLIANT
- **No `dart:html`/`dart:js`** — all web code uses `dart:js_interop` + `package:web` — COMPLIANT
- **GLSL shaders** — no array initializers, no dynamic loops — COMPLIANT
- **One `dynamic` parameter** in `VideoElementCapture.createFromVideoElement` — WASM smell but safe (immediate typed cast)

## Stub Quality Assessment

| Stub | Throws? | Graceful? | Grade |
|---|---|---|---|
| `video_frame_ffi_stub.dart` | No | Yes — null/0/false | **A** |
| `video_frame_web_v2_stub.dart` | No | Yes — null/false/no-op | **A** |
| `canvas_capture_stub.dart` | No | Yes — false/null/no-op | **A** |
| `dreamfinder_avatar_bridge_stub.dart` | No | Yes — isReady:false | **A** |
| `stt_service_stub.dart` | No | Yes — isSupported:false | **A** |
| `tts_service_stub.dart` | No | Yes — isReady:false | **A** |
| `tileset_cache_provider_stub.dart` | No | Yes — passthrough | **A** |

All stubs grade A. Zero `UnimplementedError` throws. All expose support flags.

## Issues Found

### CRITICAL

**C1: iOS and Android have no video bubble rendering**
- **File:** `lib/native/video_frame_ffi.dart`, `lib/flame/components/video_bubble_component.dart`
- **Issue:** FFI path checks `Platform.isMacOS` → false on iOS/Android. Web path not selected on native. Result: no video frame source for remote participants on mobile. Players see spinner placeholders indefinitely.
- **Fix:** Wire up `RTCVideoRenderer` pixel-readback via platform channels for iOS/Android, or adopt a `TextureRenderer` approach. The `_initializeCapture()` already has an else branch for this.

### HIGH

**H1: `adaptiveStream: true` default in developer connect page**
- **File:** `lib/livekit/pages/connect.dart:38,93`
- **Issue:** Dev/debug connect page defaults `adaptiveStream` to `true`. CLAUDE.md says it must be `false`. Video bubbles stop receiving frames if connected through this page.
- **Fix:** Hardcode `adaptiveStream: false` or change default.

**H2: STT unavailable on Firefox**
- **File:** `lib/services/stt_service_web.dart`
- **Issue:** Firefox doesn't implement `SpeechRecognition` API. Spell-casting mechanic entirely absent. Overlay hides gracefully (no crash) but core game interaction missing.
- **Fix:** Document Firefox limitation + add keyboard fallback for spell words.

### MEDIUM

**M1: `code_forge_web` imported unconditionally on native**
- **File:** `lib/editor/code_editor_panel.dart`
- **Issue:** Package named "web" imported without platform guard. May fail silently on iOS/Android if it doesn't provide a native WebView fallback internally.
- **Fix:** Verify cross-platform support or add `kIsWeb` guard.

**M2: `dreamfinder_client.dart` catches `SocketException` (dead on web)**
- **File:** `lib/services/dreamfinder_client.dart`
- **Issue:** `dart:io` `SocketException` never thrown by `package:http` on web. Web HTTP errors come as `ClientException`. The `on http.ClientException` catch after `SocketException` likely covers it, but order-dependent.
- **Fix:** Remove `SocketException` catch or combine with `ClientException`.

**M3: Firebase options throw `UnsupportedError` for Windows/Linux**
- **File:** `lib/firebase/firebase_options.dart`
- **Issue:** Latent hazard if Flutter desktop targets expand. Not a current platform.

### LOW

**L1: `dynamic` parameter in `createFromVideoElement`**
- **File:** `lib/native/video_frame_web_v2.dart:647`
- **Issue:** WASM code smell. Immediate typed cast is safe but parameter should be `Object`.

**L2: Platform checks (`kIsWeb`) scattered in business logic**
- **File:** `lib/flame/components/video_bubble_component.dart` (5×), others
- **Issue:** `_initializeCapture()` manually re-tests platform despite conditional import system existing. Architectural smell, not a bug.
- **Fix:** Long-term: move dispatch fully into conditional-import layer.

## What's Already Good

- **Conditional import architecture** — 7-file system is clean, idiomatic Dart
- **All stubs grade A** — no UnimplementedError, all expose support flags
- **WASM-aware JS interop** — zero use of deprecated `dart:html`/`dart:js`
- **Skia 14637 avoidance** — all capture paths use `decodeImageFromPixels` with issue number cited
- **GLSL CanvasKit compliance** — no arrays, no dynamic loops, explicit comments
- **`adaptiveStream: false`** in production `RoomSession` path
- **FFI macOS fallback** — try/catch around native symbol lookup, graceful `_isSupported = false`
- **Tileset cache split** — browser HTTP cache on web, disk cache on native via `dart.library.io`
