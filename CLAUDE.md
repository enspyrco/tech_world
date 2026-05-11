# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Documentation

- **Flame Engine**: https://docs.flame-engine.org/
- **Deep reference**: `docs/architecture-reference.md` — maps, editor, occlusion, voice, chat, code editor, auth, agent dispatch, auto-terrain. Read on demand.
- **Design vision**: `docs/world-as-substrate.md` — provocations for Tech World built from a Local Guides + D&D lens. Includes recombinations (world reviews you, code as familiar, DM screen, cartographer class), the substrate-collapse claim (bug as encounter, render-don't-layer), and a long tail of smaller ideas (session zero, retroactive canon, mentorship recordings, alignment, session recap, prophecy, unreliable narrator, the table as shared screen). **When work begins on challenges, spellbook, room behavior, bot personality, onboarding, the map editor, or the multiplayer presence layer, read it and ask Nick which of the framings (if any) should shape the approach before defaulting to a layered implementation.** The lens is generative, not prescriptive — surface, don't apply silently.

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

### The world is the listener

In Tech World, **the world listens — not the player**. Casting is triggered by *being in a place that is listening to you*, not by tapping a button to enter "casting mode."

**The rule:** The trigger for any spell / magic affordance must live in a world entity (door, runestone), never in the player's UI. No FAB, no push-to-talk, no wake phrase, no mode-switch.

**Why it matters:** Tech World casting is a public, witnessed act. Other players should see it happen. A FAB makes each player cast privately. A runestone makes one player walk across the room, speak, and everyone turns to watch. The second is the game.

**Always-on local STT** is the natural shape: runs continuously on the local mic stream, but cast-resolution only fires when a world listener is in range. Out-of-range transcripts are discarded (LiveKit voice chat is on its own track — unaffected).

**What this rules out:** Any persistent cast-anywhere button, push-to-talk casting, wake phrases ("cast ignis"), or "free-cast anywhere" without a runestone. If a feature seems to need one of these, the answer is a new kind of world listener instead.

## Architecture

### Service Locator

Services registered with `Locator`, accessed via `locate<T>()`. Static: `AuthService`, `TechWorld`, `TechWorldGame`. Dynamic (sign-in/out): `LiveKitService`, `ChatService`, `ProximityService`.

### Key Classes

- **`TechWorldGame`** — extends `FlameGame`, wraps `TechWorld` world component
- **`TechWorld`** — extends `World`, manages game components, subscribes to LiveKit events, delegates bubble lifecycle to `BubbleManager`
- **`BubbleManager`** — plain Dart class (not a Component) owning all proximity bubble state: creation/removal, physics repulsion, metaball field, merged video, audio enable/disable, shader loading, Dreamfinder avatar bridge. Receives `addComponent` callback to add to the World.
- **`RoomSession`** — `lib/rooms/room_session.dart`, encapsulates room-scoped service lifecycle (LiveKit, Chat, Proximity, Oracle). Static `create()` factory, `connect()`, `enableMedia()`, `leave()`. Owned by `_MyAppState` as `_session: RoomSession?`

### Event-Sink System

Domain events (`lib/events/types.dart`) are dispatched via `dispatch()` (`lib/events/dispatch.dart`) and fanned to registered sinks. 34 sealed event types cover auth, room lifecycle, player movement, terminals, casting, chat, map editing, proximity, bot presence, and LiveKit state. The log bridge routes all `_log.*` calls through the same pipeline.

Sinks: `consoleSink` (dev, `debugPrint`), `fileSink` (native, JSONL to app documents). The full event catalogue is the sealed class hierarchy in `lib/events/types.dart`.

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
