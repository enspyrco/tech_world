# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Flutter client for Tech World - an educational multiplayer game where players solve coding challenges together. Uses Flame engine for the game world and LiveKit for proximity video chat.

## Build & Run

```bash
flutter pub get
flutter run -d macos  # or chrome, ios, android
flutter test
flutter test test/networking_service_test.dart  # single test
flutter analyze --fatal-infos                   # static analysis (CI requirement)
```

## Git Hooks

Enable the pre-commit hook (runs `flutter analyze --fatal-infos`):

```bash
git config core.hooksPath .githooks
```

## Architecture

### Service Locator Pattern

Services are created in `main.dart` and registered with `Locator`:

```dart
Locator.add<AuthService>(authService);
Locator.add<NetworkingService>(networkingService);
Locator.add<TechWorld>(techWorld);
```

Access anywhere via `locate<T>()`.

### App Flow

1. **Auth**: User authenticates via `AuthGate` using Firebase Auth
2. **Connect**: `ConnectPage` retrieves LiveKit token from Firebase Function, shows connection UI
3. **Video**: `PreJoinPage` → `RoomPage` handles LiveKit room connection and video/audio

Note: The Flame game world (`TechWorldGame`/`TechWorld`) is currently commented out in `main.dart`. The app goes directly to LiveKit connection after auth.

### Networking

- `NetworkingService` connects to WebSocket game server
- Dev: `ws://127.0.0.1:8080`, Prod: `wss://adventures-in-tech.world` (auto-selects via `kReleaseMode`)
- Message types from `tech_world_networking_types` package (external Git dependency)

### Proximity Detection

`ProximityService` emits events when players enter/exit proximity range:

- Uses Chebyshev distance (accounts for diagonal movement)
- Default threshold: 3 grid squares
- Stream-based: subscribe to `proximityEvents` for enter/exit notifications

### LiveKit Integration

- `ConnectPage` calls Firebase Function `retrieveLiveKitToken` to get auth token
- Token generated in `functions/src/index.ts` using `livekit-server-sdk`
- Requires `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` in Firebase Functions environment

### Firebase Functions

Located in `functions/` (Node.js TypeScript):

```bash
cd functions
npm install
firebase deploy --only functions
```

## Testing

Test doubles in `test/test-doubles/` provide fake WebSocket implementations for mocking server connections.

CI runs: `flutter analyze --fatal-infos` then `flutter test --coverage` with 50% coverage threshold.

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

## Claude Bot (AI Tutor)

### Current Implementation

- **Server**: `bot_user.dart` defines the bot (`id: 'bot-claude'`, `displayName: 'Claude'`)
- **Server**: `client_connections_service.dart` includes bot in `OtherUsersMessage` and sends bot position on player connect
- **Client**: `lib/livekit/widgets/bot_bubble.dart` - UI widget showing blue bubble with initial
- **Client**: `lib/livekit/widgets/proximity_video_overlay.dart` - renders `BotBubble` when player is near bot

Bot position is set in server's `bot_user.dart`:

```dart
final botPosition = Double2(x: 200.0, y: 200.0);  // Pixel coordinates
```

### Planned Features

**MVP - Text Chat:**

1. Add tap handler to `BotBubble` that opens a chat dialog
2. Create `ChatService` to manage conversation with Claude API
3. Display responses in speech bubbles or chat panel

**Core Tutoring:**

- Hint system for stuck players (guided hints, not solutions)
- Code review with feedback on style, edge cases, efficiency
- Concept explainer for programming questions

**Challenge System:**

- Challenge stations at different map locations with themed challenges
- Difficulty scaling based on player history
- Collaborative mode for pair programming when 2+ players are nearby

**Voice Integration:**

- Use existing LiveKit audio infrastructure
- Pipeline: microphone → speech-to-text → Claude API → text-to-speech → bot audio track

**Multiplayer:**

- Matchmaking - suggest players team up when struggling with similar concepts
- Code battles - Claude referees live coding competitions
