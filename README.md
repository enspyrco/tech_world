# Tech World

A multiplayer 2D virtual world game built with Flutter and the Flame game engine. Players can move around, see other players in real-time, and connect via LiveKit video chat.

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

## Future Work

- When you come in proximity to a person you can send them an emoji
