# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Documentation

- **Flame Engine**: https://docs.flame-engine.org/ - Game engine documentation (component lifecycle, rendering, etc.)

## Project Overview

Flutter client for Tech World - an educational multiplayer game where players solve coding challenges together. Uses Flame engine for the game world and LiveKit for video chat, positions, and AI tutor chat.

## Build & Run

```bash
flutter pub get
flutter run -d macos  # or chrome, ios, android
flutter test
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
Locator.add<LiveKitService>(liveKitService);
Locator.add<ChatService>(chatService);
Locator.add<TechWorld>(techWorld);
```

Access anywhere via `locate<T>()`.

### App Flow

1. **Auth**: User authenticates via `AuthGate` using Firebase Auth
2. **LiveKit**: On sign-in, `LiveKitService` connects to LiveKit room with token from Firebase Function
3. **Game**: Flame game world renders with video bubbles and chat panel

### Communication (All via LiveKit)

- **Video/Audio**: LiveKit tracks for proximity-based video chat
- **Positions**: Data channel broadcasts player positions (`topic: 'position'`)
- **Chat**: Data channel for shared chat (`topic: 'chat'`, `topic: 'chat-response'`)
- **Bot (Clawd)**: Runs on GCP Compute Engine, joins room as participant `bot-claude`

### Maps

Predefined maps are defined in `lib/flame/maps/`:

- `game_map.dart`: `GameMap` class with id, name, barriers (mini-grid coordinates), and spawn point
- `predefined_maps.dart`: Available maps including:
  - `openArena` - No barriers, free movement
  - `lRoom` - L-shaped walls (default map)
  - `fourCorners` - Barriers in each corner
  - `simpleMaze` - Basic maze pattern

The default map (`lRoom`) is used in `main.dart` and its `id` is used as the LiveKit room name.

### Proximity Detection

`ProximityService` emits events when players enter/exit proximity range:

- Uses Chebyshev distance (accounts for diagonal movement)
- Default threshold: 3 grid squares
- Stream-based: subscribe to `proximityEvents` for enter/exit notifications

### LiveKit Integration

- `LiveKitService` (`lib/livekit/livekit_service.dart`) manages room connection, participants, and data channels
- Token retrieved from Firebase Function `retrieveLiveKitToken`
- Data channels used for positions and chat (replaces old WebSocket game server)

### Video Bubble Component (In-Game Video Rendering)

Renders LiveKit video feeds as circular bubbles inside the Flame game world using zero-copy FFI frame capture.

**Architecture:**

```
LiveKit VideoTrack → Native RTCVideoRenderer → Shared Memory Buffer → Dart FFI → ui.Image → Flame Canvas
```

**Key Files:**

- `lib/flame/components/video_bubble_component.dart` - Flame component that renders video as circular bubble
- `lib/native/video_frame_ffi.dart` - Dart FFI bindings for native frame capture
- `macos/Runner/VideoFrameCapture.h` - Native C API header
- `macos/Runner/VideoFrameCapture.m` - Native Objective-C implementation using `FlutterWebRTCPlugin`

**Platform Support:** macOS uses FFI capture, web uses ImageBitmap, other platforms show placeholder with initial.

### Chat Service

- `ChatService` manages shared chat via LiveKit data channels
- All participants see all messages (questions and responses)
- Bot responses come from `bot-claude` participant running on GCP Compute Engine
- `ChatPanel` widget renders the chat UI

## Testing

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

## Claude Bot (Clawd - AI Tutor)

### Current Implementation

- **Bot Service**: Node.js service on GCP Compute Engine (`tech-world-bot` instance)
- **Joins LiveKit**: As participant `bot-claude`, listens for `chat` topic messages
- **Claude API**: Calls Claude API, broadcasts response on `chat-response` topic
- **Shared Chat**: All participants see all questions and answers

### Bot Management

```bash
# Check status
gcloud compute ssh tech-world-bot --zone=us-central1-a --project=adventures-in-tech-world-0 --command="pm2 status"

# View logs
gcloud compute ssh tech-world-bot --zone=us-central1-a --project=adventures-in-tech-world-0 --command="pm2 logs --lines 50"

# Update and restart
gcloud compute ssh tech-world-bot --zone=us-central1-a --project=adventures-in-tech-world-0 --command="cd ~/tech_world_bot_service && git pull && pm2 restart tech-world-bot"
```

### Planned Features

**Core Tutoring:**
- Hint system for stuck players (guided hints, not solutions)
- Code review with feedback on style, edge cases, efficiency
- Concept explainer for programming questions

**Voice Integration:**
- Pipeline: microphone → speech-to-text → Claude API → text-to-speech → bot audio track

## LiveKit Self-Hosting Migration

### Current Setup (LiveKit Cloud)

```dart
// lib/livekit/livekit_service.dart
static const _serverUrl = 'wss://testing-g5wrpk39.livekit.cloud';
```

- Free tier: 500 participant-minutes/month
- Token generation via Firebase Cloud Function

### Migration Steps

1. **Update server URL** in `lib/livekit/livekit_service.dart`
2. **Update Firebase Functions env vars** with self-hosted credentials

### Server Requirements

For ~50 concurrent users:

| Resource | Minimum |
|----------|---------|
| CPU | 4 cores |
| RAM | 4-8 GB |
| Ports | 443, 7881, UDP 50000-60000 |

ARM64 compatible - can run on OCI free tier (4 OCPU / 24 GB Ampere).
