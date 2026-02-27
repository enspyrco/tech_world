# Tech World

An educational multiplayer 2D virtual world where players solve coding challenges together. Built with Flutter and the Flame game engine, Tech World combines real-time collaboration, proximity-based video chat, an AI tutor (Clawd), and an in-game code editor to create an engaging learn-to-code experience.

## Features

### Multiplayer & Social
- **Room browser / lobby** — Browse and join public rooms or create your own, with animated join progress and owner/editor permissions
- **Player-to-player DMs** — Private direct messages delivered via targeted LiveKit data channels and persisted to Firestore
- **Proximity-based video chat** — LiveKit video/audio streams rendered as in-game bubbles when players are nearby
- **User profiles** — Set a display name and upload a profile picture, stored in Firestore and Firebase Storage

### Game World
- **6 predefined maps** — Open Arena, The L-Room, Four Corners, Simple Maze, The Library, The Workshop — with runtime switching
- **Animated tiles** — Water and other terrain tiles animate via shared tickers while static tiles stay in a cached `Picture`
- **Wall occlusion** — Characters walk behind walls and object tiles using y-priority sprite overlays
- **Cross-platform** — macOS, web, iOS, Android

### Map Editor
- **Paint custom maps** — Place tiles on a 50×50 grid with layer-aware palette (floor, structure, objects)
- **Auto-barriers** — Painting solid object tiles automatically places movement barriers
- **Automapping rules engine** — Declarative rules auto-place decorative tiles (shadows, transitions) based on neighbors
- **TMX import** — Import maps from the Tiled map editor (`.tmx` format)
- **Save / load / delete** — Persist custom maps to Firestore, browse them in the lobby
- **Procedural generation** — Generate maps using BSP dungeon, recursive-backtracker maze, or cellular-automata cave algorithms

### Coding & AI
- **23 coding challenges** — Beginner (10), Intermediate (7), and Advanced (6) tiers with LSP-powered code completion and hover docs
- **AI tutor (Clawd)** — Claude-powered bot that reviews code submissions and answers questions
- **Voice input/output** — Browser Speech-to-Text and Text-to-Speech for hands-free interaction with Clawd (web only)

## Prerequisites

- Flutter SDK ^3.6.0
- Firebase project configured (Auth, Hosting, Cloud Functions)

## Setup

1. Install dependencies:

   ```bash
   flutter pub get
   ```

2. Create Firebase configuration at `lib/firebase/firebase_config.dart`:

   ```dart
   const firebaseWebApiKey = '<your_web_api_key>';
   const firebaseProjectId = '<your_project_id>';
   ```

3. Configure Firebase options via FlutterFire CLI or manually create `lib/firebase_options.dart`.

## Running

```bash
flutter run -d macos   # or chrome, ios, android
```

## Testing

```bash
flutter test                          # Run all tests
flutter analyze --fatal-infos         # Static analysis (CI requirement)
```

CI runs analysis then tests with coverage. The merge-to-main threshold is 45%. See `CLAUDE.md` for details.

## Architecture

The app uses a service locator pattern (`Locator`) and Flame's component system. Real-time communication (player positions, chat, video/audio) goes through LiveKit. Persistent data (rooms, maps, DM history, user profiles) lives in Firestore and Firebase Storage. There is no separate game server.

For detailed architecture, component descriptions, and development notes, see [`CLAUDE.md`](CLAUDE.md).

## Related Projects

| Project | Description |
|---------|-------------|
| `tech_world_bot/` | AI tutor (Clawd) — Node.js using `@livekit/agents` + Claude API |
| `tech_world_firebase_functions/` | Firebase Cloud Functions for LiveKit token generation |

## Demo / Screenshots

<!-- TODO: Add screenshots and demo video for grant assessors -->

## Grant Application

Application materials for the Screen Australia Games Production Fund are in [`docs/grant-application/`](docs/grant-application/).

## License

See repository root.
