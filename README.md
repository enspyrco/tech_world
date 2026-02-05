# Tech World

An educational multiplayer 2D virtual world game where players solve coding challenges together. Built with Flutter and the Flame game engine, Tech World combines real-time collaboration, proximity-based video chat, and an AI tutor to create an engaging learn-to-code experience.

## Features

- Real-time multiplayer movement using WebSocket connections
- **Room-aware multiplayer** - Players only see others in the same room/map
- Jump Point Search (JPS) pathfinding for fast player navigation
- **Predefined maps** - Multiple map layouts (Open Arena, L-Room, Four Corners, Simple Maze)
- Firebase Authentication for user management
- LiveKit integration for proximity-based video chat
- **In-game video bubbles** - Render video feeds directly in the Flame game world using zero-copy FFI frame capture (macOS, web)
- Cross-platform support (macOS, web, etc.)

## Prerequisites

- Flutter SDK 3.0.0+
- Firebase project configured
- Game server running (see `tech_world_game_server`)

## Setup

1. Install dependencies:

   ```bash
   flutter pub get
   ```

2. Create Firebase configuration file at `lib/firebase/firebase_config.dart`:

   ```dart
   const firebaseWebApiKey = '<your_web_api_key>';
   const firebaseProjectId = '<your_project_id>';
   ```

   Both values can be found in the Project Settings page in the Firebase Console.

3. Configure Firebase options via FlutterFire CLI or manually create `lib/firebase_options.dart`.

## Running

```bash
flutter run -d macos  # or chrome, ios, android, etc.
```

## Testing

```bash
flutter test                                    # Run all tests
flutter test test/networking_service_test.dart  # Run specific test
```

## Architecture

- **auth/**: Firebase Auth integration (`AuthService`, `AuthGate`, `AuthUser`)
- **flame/**: Flame game engine components
  - `TechWorld`: Main world component, handles taps and player movement
  - `PlayerComponent`: Animated player sprites with pathfinding
  - `PathComponent`: Jump Point Search (JPS) pathfinding calculations
  - `maps/`: Predefined map definitions (`GameMap`, `predefined_maps.dart`)
- **networking/**: WebSocket connection management (`NetworkingService`)
- **livekit/**: Video chat integration for proximity-based calls
- **native/**: FFI bindings for native video frame capture
- **utils/locator.dart**: Simple service locator pattern

## Dependencies

- `flame`: Game engine
- `livekit_client`: Video chat
- `firebase_core`, `firebase_auth`, `cloud_firestore`: Firebase integration
- `jump_point_search`: Fast pathfinding for uniform-cost grids
- `web_socket_channel`: WebSocket communication
- `tech_world_networking_types`: Shared message types

## Claude Bot (AI Tutor)

Tech World includes an AI tutor bot powered by Claude that helps players learn to code.

### Current State

- Bot appears in the game world as a player named "Claude"
- Shows a blue bubble with "C" when players are nearby (proximity detection)
- Bot files: `lib/livekit/widgets/bot_bubble.dart`, server-side in `bot_user.dart`

### Planned Features

**Core Tutoring:**

- Hint system - Players approach Claude when stuck, describe their problem, get guided hints (not solutions)
- Code review - Players paste their solution, Claude gives feedback on style, edge cases, efficiency
- Concept explainer - Answer questions like "What's recursion?" or "How do promises work?"

**Challenge Integration:**

- Challenge stations - Different areas of the map have coding terminals with themed challenges (e.g., "Array Alley", "Recursion Ridge")
- Difficulty scaling - Claude adapts challenge difficulty based on player history
- Collaborative mode - When 2+ players are near a challenge, Claude facilitates pair programming

**Multiplayer Synergy:**

- Matchmaking by skill - Claude notices players struggling with similar concepts and suggests they team up
- Code battles - Claude referees live coding competitions between nearby players

**Voice Integration:**

- Browser speech-to-text (SpeechRecognition API) for voice input to Clawd
- Browser text-to-speech (speechSynthesis API) for Clawd's spoken responses
- Leverage existing LiveKit infrastructure for future voice conversations

**In-Game Code Editor:**

- Coding challenges at themed map locations (e.g., "Array Alley", "Recursion Ridge")
- Full Dart editor with real-time diagnostics, completions, and hover docs
- Uses [`code_forge_web`](https://pub.dev/packages/code_forge_web) for the editor widget
- Dart analysis server connected over WebSocket via [`lsp-ws-proxy`](https://github.com/nickmeinhold/lsp-ws-proxy)
- Clawd reviews submitted code and gives feedback

## In-Game Code Editor (Planned)

### Architecture

```
Browser (Flutter web)
  └─ code_forge_web widget (CodeForgeWeb)
       └─ WebSocket connection (LspSocketConfig)
            └─ lsp-ws-proxy (on server)
                 └─ dart language-server --protocol=lsp
```

Players approach a coding terminal in the game world, which opens the editor as an overlay or panel. The editor connects to a remote Dart analysis server via WebSocket, providing real-time diagnostics, completions, hover docs, and code actions - a VS Code-like experience in the browser.

### Key Packages

| Package | Version | Purpose |
|---------|---------|---------|
| [`code_forge_web`](https://pub.dev/packages/code_forge_web) | 1.0.0 | Flutter web code editor widget with LSP support |
| [`code_forge`](https://pub.dev/packages/code_forge) | 8.1.1 | Native platforms (macOS, etc.) - same API, uses `dart:io` |
| `lsp-ws-proxy` | - | Bridges WebSocket to stdio for the analysis server |

### LSP Features Available

- Intelligent code completions with auto-import
- Hover documentation with rich markdown tooltips
- Real-time diagnostics (errors and warnings)
- Semantic token-based highlighting
- Function signature help
- Code actions and quick fixes
- Inlay hints for type and parameter information
- Go-to-definition and symbol renaming

### Server-Side Setup

```bash
# Run the Dart analysis server behind a WebSocket proxy
lsp-ws-proxy --listen 0.0.0.0:9000 -- dart language-server --protocol=lsp
```

Each connected user gets their own analysis server process. The server needs the Dart SDK installed.

### Client-Side Integration

```dart
final controller = CodeForgeWebController(
  lspConfig: LspSocketConfig(
    workspacePath: 'file:///workspace',
    languageId: 'dart',
    serverUrl: 'ws://your-server:9000',
  ),
);

CodeForgeWeb(
  fileUrl: challengeFileUrl,
  controller: controller,
);
```

### Open Questions

- Where to host the LSP proxy (existing GCP instance vs. dedicated)
- How to sandbox user code execution (if we want to run code, not just analyze)
- Session lifecycle - spin up/tear down analysis server per challenge or per user session
- Could Clawd evaluate code via Claude API instead of (or in addition to) running it

## Future Work

- When you come in proximity to a person you can send them an emoji
