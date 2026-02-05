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
- **Coding terminals** - In-game terminal stations with Dart code editor (`code_forge_web`) and challenge submission to Clawd
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
  - `TerminalComponent`: Coding terminal stations with proximity-gated interaction
  - `maps/`: Predefined map definitions (`GameMap`, `predefined_maps.dart`)
- **editor/**: In-game code editor
  - `CodeEditorPanel`: Flutter widget wrapping `code_forge_web` with challenge info and submit button
  - `Challenge`: Data model for coding challenges
  - `predefined_challenges.dart`: Starter challenges (Hello Dart, Sum a List, FizzBuzz)
- **networking/**: WebSocket connection management (`NetworkingService`)
- **livekit/**: Video chat integration for proximity-based calls
- **native/**: FFI bindings for native video frame capture
- **utils/locator.dart**: Simple service locator pattern

## Dependencies

- `flame`: Game engine
- `livekit_client`: Video chat
- `firebase_core`, `firebase_auth`, `cloud_firestore`: Firebase integration
- `jump_point_search`: Fast pathfinding for uniform-cost grids
- `code_forge_web`: In-game Dart code editor with syntax highlighting
- `re_highlight`: Dart syntax highlighting for the editor
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

**In-Game Code Editor (Implemented):**

- Coding terminal stations on the map - tap to open editor (proximity-gated)
- Dart syntax-highlighted editor using [`code_forge_web`](https://pub.dev/packages/code_forge_web)
- 3 starter challenges: Hello Dart, Sum a List, FizzBuzz
- Submit code to Clawd for review via chat

## In-Game Code Editor

### How It Works

Players walk to a coding terminal (green `>_` icon on the map) and tap it. If within 2 grid squares, a code editor panel replaces the chat sidebar with:
- Challenge title and description
- Dart code editor with syntax highlighting
- Submit button that sends code to Clawd for review

### Architecture

```
TerminalComponent (Flame) → tap + proximity check
  → TechWorld.activeChallenge (ValueNotifier)
    → main.dart swaps ChatPanel ↔ CodeEditorPanel
      → CodeForgeWeb (code_forge_web) with re_highlight for Dart syntax
        → Submit → ChatService.sendMessage() → Clawd reviews code
```

### Key Files

| File | Purpose |
|------|---------|
| `lib/editor/challenge.dart` | `Challenge` data model |
| `lib/editor/predefined_challenges.dart` | Starter challenges |
| `lib/editor/code_editor_panel.dart` | Editor panel widget |
| `lib/flame/components/terminal_component.dart` | Terminal Flame component |
| `lib/flame/maps/game_map.dart` | `GameMap.terminals` field |

### Planned - LSP Integration

Connect to a remote Dart analysis server for real-time diagnostics, completions, and hover docs:

```
Browser (Flutter web)
  └─ code_forge_web widget (CodeForgeWeb)
       └─ WebSocket connection (LspSocketConfig)
            └─ lsp-ws-proxy (on server)
                 └─ dart language-server --protocol=lsp
```

`code_forge_web` already supports LSP via `CodeForgeWebController(lspConfig: LspSocketConfig(...))`.

**Open Questions:**
- Where to host the LSP proxy (existing GCP instance vs. dedicated)
- How to sandbox user code execution (if we want to run code, not just analyze)
- Session lifecycle - spin up/tear down analysis server per challenge or per user session
- Could Clawd evaluate code via Claude API instead of (or in addition to) running it

## Future Work

- When you come in proximity to a person you can send them an emoji
