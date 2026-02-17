# Tech World

An educational multiplayer 2D virtual world where players solve coding challenges together. Built with Flutter and the Flame game engine, Tech World combines real-time collaboration, proximity-based video chat, an AI tutor (Clawd), and an in-game code editor to create an engaging learn-to-code experience.

## Features

- **Multiplayer** — Real-time player positions and chat via LiveKit data channels
- **6 maps with runtime switching** — Open Arena, The L-Room, Four Corners, Simple Maze, The Library, The Workshop
- **Map editor** — Paint barriers, spawn points, and terminals on a 50x50 grid; import/export ASCII format
- **23 coding challenges** — Beginner (10), Intermediate (7), and Advanced (6) tiers with Dart syntax-highlighted editor
- **AI tutor (Clawd)** — Claude-powered bot that reviews code submissions and answers questions
- **Voice input/output** — Browser Speech-to-Text and Text-to-Speech for hands-free interaction with Clawd (web only)
- **Proximity-based video chat** — LiveKit video/audio streams rendered as in-game bubbles when players are nearby
- **Wall occlusion** — Characters walk behind walls using y-priority sprite overlays
- **Cross-platform** — macOS, web, iOS, Android

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

The app uses a service locator pattern (`Locator`) and Flame's component system. All real-time communication goes through LiveKit (data channels for positions/chat, tracks for video/audio). There is no separate game server.

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
