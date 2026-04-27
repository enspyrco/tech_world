# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Documentation

- **Flame Engine**: https://docs.flame-engine.org/
- **Deep reference**: `docs/architecture-reference.md` — maps, editor, occlusion, voice, chat, code editor, auth, agent dispatch, auto-terrain. Read on demand.

## Project Overview

Flutter client for Tech World — an educational multiplayer game where players solve coding challenges together. Uses Flame engine for the game world and LiveKit for video chat, player positions, and AI tutor chat. All real-time communication goes through LiveKit; there is no separate game server.

## Build & Run

```bash
flutter pub get
flutter run -d macos  # or chrome, ios, android
flutter test
flutter analyze --fatal-infos                   # static analysis (CI requirement)
```

## Git Hooks

```bash
git config core.hooksPath .githooks   # pre-commit runs flutter analyze
```

## Architecture

### Service Locator

Services registered with `Locator`, accessed via `locate<T>()`. Static: `AuthService`, `TechWorld`, `TechWorldGame`. Dynamic (sign-in/out): `LiveKitService`, `ChatService`, `ProximityService`.

### Key Classes

- **`TechWorldGame`** — extends `FlameGame`, wraps `TechWorld` world component
- **`TechWorld`** — extends `World`, manages all game components, subscribes to LiveKit events

### Communication (All via LiveKit)

| Topic | Direction | Purpose |
|-------|-----------|---------|
| `position` | broadcast | Player position updates |
| `chat` | broadcast | User chat messages |
| `chat-response` | broadcast | Bot responses |
| `ping` / `pong` | targeted | Connectivity testing |

**Bot (Clawd)**: Runs on OCI as participant `bot-claude`. Source in `../tech_world_bot/`.

### UI Layout

Side panel priority: map editor > code editor > chat panel. Toolbar (top-right): `MapSelector` + editor button + `AuthMenu`. Responsive at 800px breakpoint.

### Video Bubble Component

Renders LiveKit video feeds as circular bubbles inside the Flame game world.

**Architecture (per platform):**
```
macOS:  LiveKit VideoTrack → RTCVideoRenderer → FFI shared memory → BGRA→RGBA → ui.Image
Web:    LiveKit VideoTrack → MediaStreamTrackProcessor → VideoFrame → canvas → decodeImageFromPixels → ui.Image
Web DF: Three.js iframe → CanvasCapture → canvas → decodeImageFromPixels → ui.Image
```

**CRITICAL — WASM Compatibility:**
- **NEVER use `dynamic` dispatch** for JS interop. Always typed casts.
- **NEVER use `createImageFromImageBitmap`** — Skia issue 14637. Use `decodeImageFromPixels`.
- **NEVER use array initializers or dynamic loop bounds in GLSL** — CanvasKit rejects them.
- **`adaptiveStream` must be `false`** — LiveKit's adaptive streaming requires `VideoTrackRenderer` widget. Flame canvas doesn't signal demand, so the SFU stops forwarding.

**Bubble effects:** Breathing animation, radial glow, voice ripples, physics repulsion, metaball merge field, merged video shader.

### Proximity Detection

`ProximityService`: Chebyshev distance, 3 grid squares threshold, stream-based enter/exit events.

## Testing

**CI** (`.github/workflows/`): docs-skip → `flutter analyze` → `flutter test --coverage` (45% threshold).

**Excluded from coverage:** `video_frame_ffi.dart`, `video_frame_web_stub.dart`, `video_frame_web_v2_stub.dart`, `video_bubble_component.dart`, `auth_service.dart`, `predefined_tilesets.dart`.

**Note:** `dart_webrtc` imports must stay behind conditional exports (`direct_track_capture.dart`) or native tests break.

## Configuration

**Firebase**: `lib/firebase/firebase_config.dart` (don't commit secrets)

**LiveKit**: `wss://livekit.imagineering.cc` — self-hosted v1.11.0 on OCI VPS (ARM64). Caddy TLS, Redis for dispatch. Config at `/home/nick/apps/livekit/livekit.yaml`.

**Testing multi-participant video:**
```bash
lk room join --identity video-test-user --publish-demo l_room
```

## TODO

- Delete stale `functions/` directory (real functions in `tech_world_firebase_functions/` sibling repo)

## Grant Application

Screen Australia Games Production Fund materials in `docs/grant-application/`.
