# CLAUDE.md - tech_world

## Project Overview

Flutter client for Tech World - a multiplayer 2D virtual world game using Flame engine.

## Build & Run

```bash
flutter pub get
flutter run -d macos  # or chrome, ios, android
flutter test
flutter test test/networking_service_test.dart  # single test
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

- Tests use fake WebSocket implementations in `test/test-doubles/`
- `FakeWebSocketChannel` and `FakeWebSocketSink` for mocking network
