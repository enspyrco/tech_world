# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Documentation

- **Flame Engine**: https://docs.flame-engine.org/ — Component lifecycle, rendering, game loop

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

Enable the pre-commit hook (runs `flutter analyze --fatal-infos`):

```bash
git config core.hooksPath .githooks
```

## Architecture

### Service Locator Pattern

Services are registered with `Locator` and accessed via `locate<T>()`:

- `AuthService` — registered at startup in `_initializeApp()`
- `TechWorld` — registered at startup
- `TechWorldGame` — registered at startup
- `LiveKitService` — registered dynamically on sign-in, removed on sign-out
- `ChatService` — registered dynamically on sign-in, removed on sign-out
- `ProximityService` — registered dynamically on sign-in, removed on sign-out

Use `Locator.maybeLocate<T>()` for services that may not be registered yet.

### App Flow

1. **Initialization**: `_initializeApp()` creates Firebase, `AuthService`, `TechWorld`, and `TechWorldGame`. Shows `LoadingScreen` with progress bar during startup.
2. **Auth**: `AuthGate` handles sign-in (email, Google, Apple, anonymous) with friendly error messages for `FirebaseAuthException` codes.
3. **Sign-in**: `_onAuthStateChanged()` creates `LiveKitService`, `ChatService`, `ProximityService`, registers them with `Locator`, connects to LiveKit, enables camera/mic.
4. **Game**: `GameWidget` renders the Flame world. `ProximityVideoOverlay` renders video feeds as Flutter widgets on top of the game.
5. **Sign-out**: `_onAuthStateChanged()` disposes and removes all dynamic services from `Locator`.

### Key Classes

- **`TechWorldGame`** (`lib/flame/tech_world_game.dart`) — extends `FlameGame`, wraps the `TechWorld` world component, loads sprite images on startup.
- **`TechWorld`** (`lib/flame/tech_world.dart`) — extends `World`, manages all game components (players, barriers, terminals, video bubbles, wall occlusion), handles taps for pathfinding movement, subscribes to LiveKit events.

### Communication (All via LiveKit)

- **Video/Audio**: LiveKit tracks for proximity-based video chat
- **Data channels**: Player positions and chat messages
- **Bot (Clawd)**: Runs on GCP Compute Engine, joins room as participant `bot-claude`

**LiveKit room name**: Hardcoded as `'tech-world'` in `main.dart` (not the map ID).

**Data Channel Topics:**

| Topic | Direction | Purpose |
|-------|-----------|---------|
| `position` | broadcast | Player position updates |
| `chat` | broadcast | User chat messages |
| `chat-response` | broadcast | Bot responses |
| `ping` / `pong` | targeted | Connectivity testing |

### UI Layout

**Side panel priority** (only one shown at a time): map editor > code editor > chat panel.

**Toolbar** (top-right when authenticated): `MapSelector` + map editor button + `AuthMenu`.

**Responsive breakpoints:**
- `>= 1200`: Welcome panel shown on left
- `>= 800`: Side panels 480px (editor) / 320px (chat); below 800: 360px / 280px

**Connection failure**: Orange banner at bottom-left when LiveKit connection fails.

### Maps

6 predefined maps defined in `lib/flame/maps/predefined_maps.dart`:

| Map | ID | Terminals | Notes |
|-----|----|-----------|-------|
| Open Arena | `open_arena` | 0 | No barriers |
| The L-Room | `l_room` | 2 | Default map, has background image |
| Four Corners | `four_corners` | 0 | 5x5 barrier blocks in each corner |
| Simple Maze | `simple_maze` | 0 | Outer walls + internal maze |
| The Library | `the_library` | 4 | ASCII-parsed, bookshelf layout |
| The Workshop | `the_workshop` | 2 | ASCII-parsed, maker space |

- `GameMap` class (`lib/flame/maps/game_map.dart`): `id`, `name`, `barriers`, `spawnPoint`, `terminals`, `backgroundImage`
- `map_parser.dart`: Parses ASCII format (`.` open, `#` barrier, `S` spawn, `T` terminal) into `GameMap`
- Grid size: 50x50, cell size: 16x16 pixels
- **Runtime map switching**: `MapSelector` widget calls `TechWorld.loadMap()`, which tears down old components and creates new ones. Auto-exits editor mode and closes code editor on switch.

### Map Editor

Paint custom maps on the 50x50 grid with live preview in the game canvas.

**Key files:**
- `lib/map_editor/map_editor_panel.dart` — Sidebar UI with paintable grid, toolbar, import/export
- `lib/map_editor/map_editor_state.dart` — Grid state model (extends `ChangeNotifier`), paint tools
- `lib/flame/components/map_preview_component.dart` — Renders editor state on game canvas, caches as `Picture` for performance

**Paint tools:** barrier, spawn, terminal, eraser. Single spawn point enforced.

**Workflow:** Enter via toolbar button → `TechWorld.enterEditorMode()` shows `MapPreviewComponent`, hides barriers and wall occlusion → edit grid → export as ASCII or load existing maps → exit via button or map switch.

### Wall Occlusion

`WallOcclusionComponent` (`lib/flame/components/wall_occlusion_component.dart`) creates sprite overlays from the background PNG for walls. Each overlay extends 1 cell above a barrier and uses y-priority so characters walking behind walls are occluded. Only active for maps with a `backgroundImage`. Hidden during editor mode.

### Proximity Detection

`ProximityService` emits stream events when players enter/exit proximity range:

- Uses Chebyshev distance (accounts for diagonal movement)
- Default threshold: 3 grid squares
- Stream-based: subscribe to `proximityEvents` for enter/exit notifications

### Video Bubble Component (In-Game Video Rendering)

Renders LiveKit video feeds as circular bubbles inside the Flame game world using zero-copy FFI frame capture.

**Architecture:**

```
LiveKit VideoTrack → Native RTCVideoRenderer → Shared Memory Buffer → Dart FFI → ui.Image → Flame Canvas
```

**Key Files:**

- `lib/flame/components/video_bubble_component.dart` — Flame component rendering video as circular bubble
- `lib/native/video_frame_ffi.dart` — Dart FFI bindings for native frame capture
- `macos/Runner/VideoFrameCapture.h` / `.m` — Native Objective-C implementation

**Platform Support:** macOS uses FFI capture, web uses ImageBitmap, other platforms show placeholder with initial.

**Bubble lifecycle:** When a remote participant joins, a `PlayerBubbleComponent` placeholder is created. When `TrackSubscribedEvent` fires, it's upgraded to `VideoBubbleComponent`. `ProximityVideoOverlay` provides a Flutter widget alternative using LiveKit's native `VideoTrackRenderer`.

**Debugging Notes:** See `docs/video-capture-debugging.md` for detailed notes on PRs #71–#77.

**Testing Multi-Participant Video:**
```bash
brew install livekit-cli
LIVEKIT_URL=wss://testing-g5wrpk39.livekit.cloud \
LIVEKIT_API_KEY=<key> \
LIVEKIT_API_SECRET=<secret> \
lk room join --identity video-test-user --publish-demo l_room
```

### Voice Services (Browser Web Speech API)

- **TTS**: `lib/services/tts_service.dart` (conditional export) — Clawd speaks responses via `speechSynthesis`
  - Web: `tts_service_web.dart` uses `package:web` for typed API access
  - Native: `tts_service_stub.dart` no-op
- **STT**: `lib/services/stt_service.dart` (conditional export) — Voice input via `SpeechRecognition`
  - Web: `stt_service_web.dart` uses `dart:js_interop_unsafe` with `globalContext`
  - Native: `stt_service_stub.dart` no-op
- Pattern: `export 'stub.dart' if (dart.library.js_interop) 'web.dart'`

### Chat Service

- `ChatService` manages shared chat via LiveKit data channels
- All participants see all messages (questions and responses)
- Bot responses come from `bot-claude` participant on GCP Compute Engine
- `ChatPanel` renders chat UI with mic button (STT) and auto-spoken responses (TTS)

### In-Game Code Editor

Coding terminal stations on the map. Tap a terminal (within 2 grid squares) to open the editor panel replacing the chat sidebar.

**23 challenges** across 3 difficulty tiers:
- **Beginner (10):** Hello Dart, Sum a List, FizzBuzz, String Reversal, Even Numbers, Palindrome Check, Word Counter, Temperature Converter, Find Maximum, Remove Duplicates
- **Intermediate (7):** Binary Search, Fibonacci Sequence, Caesar Cipher, Anagram Checker, Flatten List, Matrix Sum, Bracket Matching
- **Advanced (6):** Merge Sort, Stack Implementation, Roman Numerals, Run Length Encoding, Longest Common Subsequence, Async Data Pipeline

Terminals cycle through challenges: `allChallenges[terminalIndex % allChallenges.length]`.

**Key files:**
- `lib/editor/challenge.dart` — `Challenge` data model with `Difficulty` enum
- `lib/editor/predefined_challenges.dart` — All 23 challenges, accessed via `allChallenges`
- `lib/editor/code_editor_panel.dart` — Flutter widget wrapping `CodeForgeWeb`
- `lib/flame/components/terminal_component.dart` — Flame component for terminal stations

**Workflow:** Terminal tap → proximity check → `TechWorld.activeChallenge` ValueNotifier → `main.dart` swaps `ChatPanel` for `CodeEditorPanel` → submit sends code to Clawd via `ChatService` → editor closes.

**Planned — LSP Integration:**

```
Browser (Flutter web)
  └─ code_forge_web widget
       └─ WebSocket (LspSocketConfig)
            └─ lsp-ws-proxy (server)
                 └─ dart language-server --protocol=lsp
```

`code_forge_web` already supports LSP via `CodeForgeWebController(lspConfig: LspSocketConfig(...))`.

### Auth

`AuthGate` (`lib/auth/auth_gate.dart`) supports email/password, Google Sign-In, Apple Sign-In (iOS/macOS), and anonymous guest login. Catches `FirebaseAuthException` and shows friendly error messages (e.g. "No account found with that email", "Too many attempts. Please wait a moment and try again.").

## Testing

**CI** (`.github/workflows/`):
1. Docs-only changes (`.md`, `.txt`, `LICENSE`, `CHANGELOG`) skip tests and deploy.
2. `flutter analyze --fatal-infos`
3. `flutter test --coverage` with **45% coverage threshold** on merge to main.

**Excluded from coverage:** `video_frame_ffi.dart`, `video_frame_web_stub.dart`, `video_frame_web_v2_stub.dart`, `video_bubble_component.dart`, `auth_service.dart`.

## Configuration Required

**Firebase config** (already exists, don't commit secrets):
`lib/firebase/firebase_config.dart`

**LiveKit** (Firebase Functions environment):

```bash
firebase functions:config:set livekit.api_key="<key>" livekit.api_secret="<secret>"
```

Or create `functions/.env`:

```
LIVEKIT_API_KEY=<key>
LIVEKIT_API_SECRET=<secret>
```

## Claude Bot (Clawd — AI Tutor)

- **Source Code**: `../tech_world_bot/` — Node.js using `@livekit/agents` framework
- **Deployment**: GCP Compute Engine (`tech-world-bot` instance)
- **Joins LiveKit**: As participant `bot-claude`, listens for `chat` topic messages
- **Claude API**: Uses Claude 3.5 Haiku for fast, cost-effective responses
- **Shared Chat**: All participants see all questions and answers

```bash
# Check status
gcloud compute ssh tech-world-bot --zone=us-central1-a --project=adventures-in-tech-world-0 --command="pm2 status"

# View logs
gcloud compute ssh tech-world-bot --zone=us-central1-a --project=adventures-in-tech-world-0 --command="pm2 logs --lines 50"

# Update and restart
gcloud compute ssh tech-world-bot --zone=us-central1-a --project=adventures-in-tech-world-0 --command="cd ~/tech_world_bot && git pull && npm install && npm run build && pm2 restart tech-world-bot"
```

## Grant Application

Screen Australia Games Production Fund application materials are in `docs/grant-application/`.

## LiveKit Self-Hosting Migration

### Current Setup (LiveKit Cloud)

```dart
// lib/livekit/livekit_service.dart
static const _serverUrl = 'wss://testing-g5wrpk39.livekit.cloud';
```

- Free tier: 500 participant-minutes/month
- Token generation via Firebase Cloud Function

### Server Requirements

For ~50 concurrent users:

| Resource | Minimum |
|----------|---------|
| CPU | 4 cores |
| RAM | 4-8 GB |
| Ports | 443, 7881, UDP 50000-60000 |

ARM64 compatible — can run on OCI free tier (4 OCPU / 24 GB Ampere).
