# CLAUDE.md - tech_world

## Project Overview

Flutter client for Tech World - an educational multiplayer game where players solve coding challenges together. Uses Flame engine for the game world, LiveKit for proximity video chat, and includes an AI tutor bot powered by Claude.

## Build & Run

```bash
flutter pub get
flutter run -d macos  # or chrome, ios, android
flutter test
flutter test test/networking_service_test.dart  # single test
```

## Git Hooks

Enable the pre-commit hook (runs `flutter analyze --fatal-infos`):
```bash
git config core.hooksPath .githooks
```

## Key Files

- `lib/main.dart`: App entry point, initializes Firebase and services, registers with `Locator`
- `lib/flame/tech_world.dart`: Main game world component
- `lib/flame/components/player_component.dart`: Player sprite with animation and movement
- `lib/flame/components/path_component.dart`: A* pathfinding logic
- `lib/networking/networking_service.dart`: WebSocket connection to game server
- `lib/auth/auth_service.dart`: Firebase Auth wrapper
- `lib/utils/locator.dart`: Service locator - use `Locator.add<T>()` and `locate<T>()`

## Architecture Notes

### Service Locator Pattern
Services are registered in `main.dart` using:
```dart
Locator.add<AuthService>(authService);
Locator.add<NetworkingService>(networkingService);
Locator.add<TechWorld>(techWorld);
```

Access services via `locate<T>()`.

### Networking
- Uses `NetworkingService` to connect to WebSocket game server
- Switches between dev and production URLs based on `kReleaseMode`
- Message types from `tech_world_networking_types` package

### Game Engine
- Flame engine handles rendering and game loop
- `TechWorld` is the main world component
- Players use A* pathfinding via `a_star_algorithm` package

## Configuration Required

Create `lib/firebase/firebase_config.dart`:
```dart
const firebaseWebApiKey = '<your_web_api_key>';
const firebaseProjectId = '<your_project_id>';
```

## Testing

```bash
flutter test                          # run all tests
flutter test --coverage               # with coverage
flutter analyze --fatal-infos         # static analysis
```

### Test Structure
- `test/networking_service_test.dart` - NetworkingService unit tests
- `test/utils/locator_test.dart` - Service locator tests
- `test/proximity/proximity_service_test.dart` - Proximity detection tests
- `test/livekit/widgets/bot_bubble_test.dart` - BotBubble widget tests
- `test/test-doubles/` - Fake WebSocket implementations for mocking

### CI/CD

GitHub Actions run on PRs and pushes to main:
1. `flutter analyze --fatal-infos` - Static analysis
2. `flutter test --coverage` - Run tests with coverage
3. Coverage reported on PRs via `github-actions-report-lcov`
4. Deploy to Firebase Hosting (50% coverage threshold)

Workflows: `.github/workflows/firebase-hosting-*.yml`

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
