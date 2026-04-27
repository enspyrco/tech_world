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
- **Bot (Clawd)**: Runs on OCI, joins room as participant `bot-claude`

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

### Y-Based Depth Sorting (Occlusion)

All world-level components use the grid row (y index) as their Flame `priority`, so Flame's `World` sorts them back-to-front automatically:

| Component | Priority | Source |
|-----------|----------|--------|
| `TileObjectLayerComponent` sprites | `y` (grid row) | `tile_object_layer_component.dart:52` |
| `PlayerComponent` | `position.y.round() ~/ gridSquareSize` (updated per frame) | `player_component.dart:129` |
| `WallOcclusionComponent` overlays | `barrier.y` | `wall_occlusion_component.dart:57` |

**Result:** A player north of a wall (lower y) renders *behind* it; a player south (higher y) renders *in front*. Auto-barriers ensure the player can never occupy a wall cell, so there are no ambiguous same-cell ties.

**`TileObjectLayerComponent`** — Sprites are injected into the parent `World` (not as children of the component) so they participate in the World's global priority sort alongside players and occlusion overlays.

**`WallOcclusionComponent`** — Creates sprite overlays from the background PNG for walls. Each overlay extends 1 cell above a barrier. Only active for maps with a `backgroundImage`. Hidden during editor mode.

**`barrier_occlusion.dart`** — Pure functions computing priority overrides and object layer positions from barrier geometry:
- **Wall caps**: Tile above any north-facing barrier edge gets bumped to wall priority. Ensures the player is occluded by the wall top when walking above any wall (horizontal or vertical).
- **Vertical doorway lintels**: barrier → gap → barrier pattern (y direction). Bumped to `y+2`.
- **Horizontal doorway lintels**: barrier → gap → barrier pattern (x direction). Tiles above gap rendered half-height ("alpha punch") via `lintelOverlayPositions`.
- **Debug**: Set `debugPriorities: true` on `TileObjectLayerComponent` to see priority labels (green=default, red=overridden, magenta=lintel overlay).

**Edge case:** Multi-cell-tall objects would need height metadata, but the LimeZu tilesets avoid this by composing tall objects from multiple single-cell tiles, each with its own correct y-priority.

### Proximity Detection

`ProximityService` emits stream events when players enter/exit proximity range:

- Uses Chebyshev distance (accounts for diagonal movement)
- Default threshold: 3 grid squares
- Stream-based: subscribe to `proximityEvents` for enter/exit notifications

### Video Bubble Component (In-Game Video Rendering)

Renders LiveKit video feeds as circular bubbles inside the Flame game world.

**Architecture (per platform):**

```
macOS:  LiveKit VideoTrack → RTCVideoRenderer → FFI shared memory → BGRA→RGBA → ui.Image
Web:    LiveKit VideoTrack → MediaStreamTrackProcessor → VideoFrame → drawImage to canvas → getImageData → decodeImageFromPixels → ui.Image
Web DF: Three.js iframe canvas → CanvasCapture → drawImage to canvas → getImageData → decodeImageFromPixels → ui.Image
```

**Key Files:**

- `lib/flame/components/video_bubble_component.dart` — Flame component rendering video as circular bubble
- `lib/native/video_frame_ffi.dart` — Dart FFI bindings for native frame capture (macOS)
- `lib/native/video_frame_web_v2.dart` — Web frame capture: `DirectTrackCapture` (MediaStreamTrackProcessor) for all tracks
- `lib/native/canvas_capture_web.dart` — Web frame capture for Dreamfinder's 3D avatar iframe
- `lib/flame/components/bubble_field_component.dart` — Metaball glow field shader (additive blend between nearby bubbles)
- `lib/flame/components/merged_video_bubble_component.dart` — Merged video rendering via GLSL Voronoi shader (when bubbles are close)
- `shaders/metaball_field.frag` — Metaball energy field GLSL shader
- `shaders/merged_video_bubble.frag` — Multi-texture video merge GLSL shader

**CRITICAL — WASM Compatibility:**
- **NEVER use `dynamic` dispatch to access JS interop properties.** `(track as dynamic).jsTrack` compiles but fails silently in WASM. Always use typed casts: `(track as MediaStreamTrackWeb).jsTrack`.
- **NEVER use `createImageFromImageBitmap`** — renders black due to Skia issue 14637. Use `decodeImageFromPixels` (SkImage.MakeRasterData path) instead.
- **NEVER use array initializers or dynamic loop bounds in GLSL** — CanvasKit's WebGL compiler rejects them. Use explicit `if` branches.
- Remote tracks start **muted**. Use `DirectTrackCapture.createAsync()` (not `.create()`) for remote tracks — it waits for the track to unmute before creating the MediaStreamTrackProcessor.

**Bubble visual effects (PRs #287–#291):**
- Breathing animation (±2.5% sinusoidal scale pulsing)
- Radial glow (gold for Dreamfinder, configurable per-bubble)
- Voice ripples (border undulates with `participant.audioLevel`)
- Physics repulsion (bubbles push apart, don't overlap)
- Metaball merge field (glow bridges between nearby bubbles)
- Merged video rendering (video content flows into single organic blob when close)

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
- Bot responses come from `bot-claude` participant on OCI
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

**LSP Integration (Code Completion & Hover Docs):**

```
Browser (Flutter web)
  └─ CodeForgeWeb widget
       └─ WebSocket (WSS via LspSocketConfig)
            └─ nginx (SSL termination + limit_conn 5/IP)
                 └─ lsp-ws-proxy (localhost:9999)
                      └─ dart language-server --protocol=lsp
                           (one process per WebSocket connection)
```

- **Server URL**: `wss://lsp.adventures-in-tech.world` → `104.154.170.222` (static IP)
- **Workspace**: `/opt/lsp-workspace` — shared pubspec.yaml + analysis_options.yaml
- **Config**: `lib/editor/lsp_config.dart` — constants for server URL, workspace path, language ID
- **Capabilities enabled**: completion, hover, signature help (others disabled for performance)
- **Graceful fallback**: If the LSP server is unreachable, the editor works as plain text

**Server management:**
```bash
# SSH into OCI instance, then:
pm2 status
pm2 logs lsp-proxy --lines 50

# nginx config
# /etc/nginx/sites-available/lsp-proxy
```

### Auth

`AuthGate` (`lib/auth/auth_gate.dart`) supports email/password, Google Sign-In, Apple Sign-In (iOS/macOS), and anonymous guest login. Catches `FirebaseAuthException` and shows friendly error messages (e.g. "No account found with that email", "Too many attempts. Please wait a moment and try again.").

## Testing

**CI** (`.github/workflows/`):
1. Docs-only changes (`.md`, `.txt`, `LICENSE`, `CHANGELOG`) skip tests and deploy.
2. `flutter analyze --fatal-infos`
3. `flutter test --coverage` with **45% coverage threshold** on merge to main.

**Excluded from coverage:** `video_frame_ffi.dart`, `video_frame_web_stub.dart`, `video_frame_web_v2_stub.dart`, `video_bubble_component.dart`, `auth_service.dart`, `predefined_tilesets.dart`.

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

- **Source Code**: `../tech_world_bot/` — Node.js using `@livekit/agents` framework (v1.0+)
- **Deployment**: OCI (Oracle Cloud Infrastructure), managed by PM2
- **Joins LiveKit**: As participant `bot-claude`, listens for `chat` topic messages
- **Claude API**: Uses Claude Haiku 4.5 for fast, cost-effective responses
- **Shared Chat**: All participants see all questions and answers

### Agent Dispatch

The bot uses the `@livekit/agents` SDK to register as a worker with the self-hosted LiveKit server. LiveKit dispatches the bot to rooms via **token-based dispatch**: the Firebase Cloud Function (`retrieveLiveKitToken`) embeds a `RoomAgentDispatch` in every user's access token. When a user joins a room, LiveKit automatically dispatches the bot.

**Why token-based dispatch?** LiveKit's automatic dispatch only fires for *new* rooms. The `tech-world` room has a 5-minute `empty_timeout`, so if users sign out and back in quickly, the room persists and automatic dispatch never triggers. Token-based dispatch ensures the bot is dispatched every time any user connects, regardless of room age.

**If the bot disappears:** Check these in order:
1. `pm2 logs tech-world-bot` — Is the worker registered? Look for `"registered worker"`.
2. Room exists? Use LiveKit API: `POST /twirp/livekit.RoomService/ListRooms`
3. Dispatch happening? Look for `"received job request"` and `"[Bot] Connected to room"` in logs.
4. If worker registers but no dispatch, the `@livekit/agents` SDK version may be incompatible with the LiveKit server. Check `npm outdated @livekit/agents`.
5. Manual dispatch (emergency): `POST /twirp/livekit.AgentDispatchService/CreateDispatch {"room": "tech-world"}`

### Bot Presence Indicator

`ChatService` tracks bot presence via LiveKit participant events (`participantJoined`/`participantLeft` for identity `bot-claude`). The `botStatusNotifier` (`ValueNotifier<BotStatus>`) drives UI state:

- `BotStatus.absent` — Bot not in room. Chat panel shows "Clawd is offline" banner, input disabled.
- `BotStatus.idle` — Bot connected, ready for messages.
- `BotStatus.thinking` — Bot is processing a message (set on send, cleared on response).

`sendMessage()` has a fast guard: if bot is absent, it immediately shows a system message instead of waiting for the 30-second timeout.

```bash
# SSH into the OCI instance, then:
pm2 status
pm2 logs --lines 50
cd ~/tech_world_bot && git pull && npm install && npm run build && pm2 restart tech-world-bot
```

## Grant Application

Screen Australia Games Production Fund application materials are in `docs/grant-application/`.

## LiveKit Server

Self-hosted LiveKit v1.11.0 at `livekit.imagineering.cc` on OCI VPS (ARM64 Ampere).

```dart
// lib/livekit/livekit_service.dart
static const _serverUrl = 'wss://livekit.imagineering.cc';
```

- Caddy handles TLS termination, Redis on port 6389 for agent dispatch
- Token generation via Firebase Cloud Function (credentials must match server)
- Config at `/home/nick/apps/livekit/livekit.yaml` on OCI VPS
- TURN: UDP 3478 + TLS 5349 (cert from Caddy, mounted at `/certs/` in container)
- **iptables on OCI**: Rules added for UDP 3478, 7882-7892, 30000-40000 and TCP 5349, 7881. Without these, only Tailscale connections work (OCI's default iptables REJECT blocks all non-listed ports).
- Container runs in `--network host` mode with config + certs bind-mounted

## TODO

- Delete stale `functions/` directory (real Firebase functions live in `tech_world_firebase_functions/` sibling repo)

## Current Work

### Recently completed

**Animated tile rendering (#150, #153)** — Native animated tile rendering using shared `AnimationTicker`s. Water tiles in `ext_terrains` animate while static tiles stay in a cached `Picture`.

**Auto-terrain brush (#151)** — Wang blob tileset brush for the map editor. Paint "water" and the brush auto-selects the correct edge/corner/transition tile using 8-bit bitmask neighbor lookup (Moore neighborhood → simplify corners → 47-tile blob pattern). Implemented with `TerrainDef`, `TerrainGrid` (parallel semantic grid for editor round-trips), and `terrain_bitmask.dart` utilities. Water terrain in `ext_terrains` rows 60–67 fully mapped.

**Automapping rules engine (#152, #163)** — Declarative, priority-ordered rules that auto-place decorative tiles (shadows, transitions) based on structural neighbors, re-evaluated on every paint stroke.

**Key files (auto-terrain):**
- `lib/flame/tiles/terrain_bitmask.dart` — `computeBitmask()`, `simplifyBitmask()`, `Bitmask` constants
- `lib/flame/tiles/terrain_def.dart` — `TerrainDef` with `bitmaskToTileIndex` map (47 entries)
- `lib/flame/tiles/predefined_terrains.dart` — `waterTerrain` definition, `lookupTerrain()`
- `lib/map_editor/terrain_grid.dart` — Parallel 50×50 grid storing terrain IDs per cell (sparse JSON serialization)
