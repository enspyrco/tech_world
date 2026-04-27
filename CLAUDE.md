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

## Design Standards

### Stringly-typing is a smell

Closed sets of identifiers — words of power, schools, elements, avatars, room types, terminal modes — should be `enum` or `sealed class`, not `String`. Strings only appear at boundaries (Firestore on-disk format, STT transcripts, network payloads) and parse via `Type.parse(String)` at the seam.

Why: Dart's exhaustive `switch` over enums catches every consumer of a closed set the moment it grows. The bijection between two const sets reduces to one length assertion. Typos can't compile.

When you arrive in this codebase: sweep `lib/` for `String` fields whose values are drawn from a closed set. Each one is a refactoring opportunity. Examples already done:

- `WordId` (the spellbook 18 — `lib/spellbook/word_of_power.dart`).
- `PromptChallengeId` (the 18 prompt challenges — `lib/prompt/prompt_challenge.dart`).
- `CodeChallengeId` (the 23 code-editor challenges — `lib/editor/challenge.dart`).

Examples still pending: `AvatarId`, `MapId`, `TilesetId`, `RoomType`. Don't refactor speculatively — refactor when you're already touching the code for another reason.

When the wire format is multi-word (snake_case), use the **enhanced enum** form so the in-language identifier stays camelCase but the `wireName` is preserved verbatim:

```dart
enum PromptChallengeId {
  evocationFizzbuzz('evocation_fizzbuzz'),
  // …
  ;
  const PromptChallengeId(this.wireName);
  final String wireName;
  static PromptChallengeId? parse(String wire) { /* … */ }
}
```

`enum.name` only matches the wire when each value is a single token — for everything else, store the wire form explicitly.

When two typed-id namespaces share the same persistence boundary (here: `ProgressService.completedChallenges` mixes `CodeChallengeId.wireName` and `PromptChallengeId.wireName` in one Firestore array), keep wire forms **disjoint by construction** and pin the disjointness with a runtime test (see `test/editor/code_challenge_id_test.dart`).

### Use Dart 3 features

- **Switch expressions** (`switch (x) => ...,`) over switch statements when the body is `return X;` per arm.
- **Pattern matching** for tuple destructuring: `switch ((a, b)) { (X, Y) || (Y, X) => ... }` — perfect for order-independent lookups (Phase 3 spell algebra).
- **Sealed classes** for closed hierarchies where enum is too flat (e.g. cast results: `sealed class CastResult` → `Pass`, `Fail`, `Pending`).
- **Records** for ad-hoc tuples (`(Position, Velocity)`) instead of `Map<String, dynamic>`.

When reading legacy Dart-2-shaped code: don't refactor for its own sake, but if you're already changing the file, modernize.

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
