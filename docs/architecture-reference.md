# Architecture Reference

Deep reference for subsystems. Read on demand, not every session.

## Maps

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

## Map Editor

Paint custom maps on the 50x50 grid with live preview in the game canvas.

**Key files:**
- `lib/map_editor/map_editor_panel.dart` — Sidebar UI with paintable grid, toolbar, import/export
- `lib/map_editor/map_editor_state.dart` — Grid state model (extends `ChangeNotifier`), paint tools
- `lib/flame/components/map_preview_component.dart` — Renders editor state on game canvas, caches as `Picture` for performance

**Paint tools:** barrier, spawn, terminal, eraser. Single spawn point enforced.

**Workflow:** Enter via toolbar button → `TechWorld.enterEditorMode()` shows `MapPreviewComponent`, hides barriers and wall occlusion → edit grid → export as ASCII or load existing maps → exit via button or map switch.

## Y-Based Depth Sorting (Occlusion)

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
- **Wall caps**: Tile above any north-facing barrier edge gets bumped to wall priority.
- **Vertical doorway lintels**: barrier → gap → barrier pattern (y direction). Bumped to `y+2`.
- **Horizontal doorway lintels**: barrier → gap → barrier pattern (x direction). Tiles above gap rendered half-height ("alpha punch") via `lintelOverlayPositions`.
- **Debug**: Set `debugPriorities: true` on `TileObjectLayerComponent` to see priority labels (green=default, red=overridden, magenta=lintel overlay).

## Voice Services (Browser Web Speech API)

- **TTS**: `lib/services/tts_service.dart` (conditional export) — Clawd speaks responses via `speechSynthesis`
  - Web: `tts_service_web.dart` uses `package:web` for typed API access
  - Native: `tts_service_stub.dart` no-op
- **STT**: `lib/services/stt_service.dart` (conditional export) — Voice input via `SpeechRecognition`
  - Web: `stt_service_web.dart` uses `dart:js_interop_unsafe` with `globalContext`
  - Native: `stt_service_stub.dart` no-op
- Pattern: `export 'stub.dart' if (dart.library.js_interop) 'web.dart'`

## Chat Service

- `ChatService` manages shared chat via LiveKit data channels
- All participants see all messages (questions and responses)
- Bot responses come from `bot-claude` participant on OCI
- `ChatPanel` renders chat UI with mic button (STT) and auto-spoken responses (TTS)

## In-Game Code Editor

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
- **Graceful fallback**: If the LSP server is unreachable, the editor works as plain text

## Auth

`AuthGate` (`lib/auth/auth_gate.dart`) supports email/password, Google Sign-In, Apple Sign-In (iOS/macOS), and anonymous guest login. Catches `FirebaseAuthException` and shows friendly error messages.

## Agent Dispatch

The bot uses the `@livekit/agents` SDK to register as a worker with the self-hosted LiveKit server. LiveKit dispatches the bot to rooms via **token-based dispatch**: the Firebase Cloud Function (`retrieveLiveKitToken`) embeds a `RoomAgentDispatch` in every user's access token.

**Why token-based dispatch?** LiveKit's automatic dispatch only fires for *new* rooms. The `tech-world` room has a 5-minute `empty_timeout`, so if users sign out and back in quickly, the room persists and automatic dispatch never triggers.

**If the bot disappears:** Check these in order:
1. `pm2 logs tech-world-bot` — Is the worker registered? Look for `"registered worker"`.
2. Room exists? Use LiveKit API: `POST /twirp/livekit.RoomService/ListRooms`
3. Dispatch happening? Look for `"received job request"` and `"[Bot] Connected to room"` in logs.
4. If worker registers but no dispatch, check `npm outdated @livekit/agents`.
5. Manual dispatch (emergency): `POST /twirp/livekit.AgentDispatchService/CreateDispatch {"room": "tech-world"}`

## Bot Presence Indicator

`ChatService` tracks bot presence via LiveKit participant events (`participantJoined`/`participantLeft` for identity `bot-claude`). The `botStatusNotifier` (`ValueNotifier<BotStatus>`) drives UI state:

- `BotStatus.absent` — Bot not in room. Chat panel shows "Clawd is offline" banner, input disabled.
- `BotStatus.idle` — Bot connected, ready for messages.
- `BotStatus.thinking` — Bot is processing a message (set on send, cleared on response).

## Auto-Terrain (PRs #150-153)

Wang blob tileset brush for the map editor. 8-bit bitmask neighbor lookup (Moore neighborhood → simplify corners → 47-tile blob pattern).

**Key files:**
- `lib/flame/tiles/terrain_bitmask.dart` — `computeBitmask()`, `simplifyBitmask()`, `Bitmask` constants
- `lib/flame/tiles/terrain_def.dart` — `TerrainDef` with `bitmaskToTileIndex` map (47 entries)
- `lib/flame/tiles/predefined_terrains.dart` — `waterTerrain` definition, `lookupTerrain()`
- `lib/map_editor/terrain_grid.dart` — Parallel 50×50 grid storing terrain IDs per cell (sparse JSON serialization)
