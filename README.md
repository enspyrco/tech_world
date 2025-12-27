# Tech World

An educational multiplayer 2D virtual world game where players solve coding challenges together. Built with Flutter and the Flame game engine, Tech World combines real-time collaboration, proximity-based video chat, and an AI tutor to create an engaging learn-to-code experience.

## Features

- Real-time multiplayer movement using WebSocket connections
- A* pathfinding for player navigation
- Firebase Authentication for user management
- LiveKit integration for proximity-based video chat
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
  - `PathComponent`: A* pathfinding calculations
- **networking/**: WebSocket connection management (`NetworkingService`)
- **livekit/**: Video chat integration for proximity-based calls
- **utils/locator.dart**: Simple service locator pattern

## Dependencies

- `flame`: Game engine
- `livekit_client`: Video chat
- `firebase_core`, `firebase_auth`, `cloud_firestore`: Firebase integration
- `a_star_algorithm`: Pathfinding
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

- Leverage existing LiveKit infrastructure for voice conversations with Claude
- Speech-to-text → Claude API → text-to-speech pipeline

## Future Work

- When you come in proximity to a person you can send them an emoji
