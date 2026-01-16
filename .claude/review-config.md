# Review Configuration

## Project Context
Tech World - Educational multiplayer game where players solve coding challenges together. Uses Flame engine for the game world and LiveKit for proximity video chat.

## Tech Stack
- **Flutter/Dart**: Flame game engine, LiveKit client
- **Firebase**: Auth, Cloud Functions (LiveKit token generation)
- **WebSocket**: Real-time multiplayer via tech_world_game_server

## Review Focus Areas
- Flame component lifecycle and performance
- WebSocket message handling and error cases
- LiveKit integration and proximity detection
- Firebase security and auth patterns
- State management via service locator pattern

## Code Standards
- Dart: Follow flutter_lints rules
- Run `flutter analyze --fatal-infos` before committing
- Pre-commit hook enforces analyzer

## Required Checks
- CI must pass (Test and Deploy to Firebase Hosting)
- No analyzer warnings (--fatal-infos)
- Minimum 50% test coverage
