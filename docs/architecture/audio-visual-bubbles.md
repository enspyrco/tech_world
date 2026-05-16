# Audio-Visual Bubble System

When two players walk near each other, video/audio bubbles appear above their heads.
This document maps every component involved.

## System Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              TechWorld (Flame World)                            │
│                                                                                 │
│  update(dt) ──► BubbleManager.update(dt)  ◄── called every frame               │
│                                                                                 │
│  connectToLiveKit() ──► creates LiveKitGameBridge (14 stream subscriptions)     │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Full Pipeline

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  1. SESSION SETUP                                                            │
│                                                                              │
│  RoomSession.create()                                                        │
│    ├── LiveKitService    (WebRTC room, streams, data channels)               │
│    ├── ProximityService  (event dispatch only — NOT used for bubbles)        │
│    └── ChatService                                                           │
│                                                                              │
│  RoomSession.connect()                                                       │
│    └── LiveKitService.connect()                                              │
│          └── Firebase httpsCallable('retrieveLiveKitToken')                  │
│                └── Room(adaptiveStream: false)  ◄── CRITICAL: Flame needs    │
│                                                     raw frames, not widget   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  2. LIVEKIT ──► FLAME BRIDGE                                                 │
│                                                                              │
│  LiveKitGameBridge (plain Dart, no Flame dependency)                         │
│  Translates LiveKit events into game-world mutations via callbacks:          │
│                                                                              │
│  LiveKitService stream            Callback target                            │
│  ─────────────────────────        ───────────────────────────────────        │
│  speakingChanged ──────────────► BubbleManager.updateSpeakingState()         │
│  trackSubscribed (VIDEO) ──────► BubbleManager.refreshBubbleForPlayer()      │
│  trackUnsubscribed (VIDEO) ────► BubbleManager.downgradeVideoBubble()        │
│  localTrackPublished (VIDEO) ──► BubbleManager.refreshLocalPlayerBubble()    │
│  participantJoined ────────────► TechWorld._handleParticipantJoined()        │
│  participantLeft ──────────────► TechWorld._handleParticipantLeft()           │
│  positionReceived ─────────────► TechWorld._handlePositionReceived()         │
│  heartbeatReceived ────────────► corrects stale positions                    │
│  connectionLost ───────────────► TechWorld.disconnectFromLiveKit()           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  3. PROXIMITY DETECTION (inside BubbleManager.update)                        │
│                                                                              │
│  Uses Chebyshev distance: max(|dx|, |dy|) in grid squares                   │
│                                                                              │
│       ┌──────────────────────────────────────────────┐                       │
│       │                                              │                       │
│       │          5 squares ─── VISUAL THRESHOLD      │                       │
│       │       ┌──────────────────────────┐           │                       │
│       │       │                          │           │                       │
│       │       │    2 squares ─── AUDIO   │           │                       │
│       │       │   ┌──────────────┐       │           │                       │
│       │       │   │              │       │           │                       │
│       │       │   │   Player A   │       │           │                       │
│       │       │   │              │       │           │                       │
│       │       │   └──────────────┘       │           │                       │
│       │       │   audio enabled          │           │                       │
│       │       │   full opacity           │           │                       │
│       │       └──────────────────────────┘           │                       │
│       │       bubbles visible, fading with distance  │                       │
│       │                                              │                       │
│       └──────────────────────────────────────────────┘                       │
│       no bubbles, no audio                                                   │
│                                                                              │
│  NOTE: This is separate from ProximityService (threshold=3, events only).    │
│  BubbleManager does its own inline Chebyshev check each frame.              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  4. BUBBLE CREATION                                                          │
│                                                                              │
│  BubbleManager._createBubbleForPlayer(identity)                              │
│                                                                              │
│           ┌─────────────────────────┐                                        │
│           │  Has video track?       │                                        │
│           │  hideVideoBubbles=false? │                                        │
│           └────────┬────────────────┘                                        │
│              yes ╱    ╲ no                                                    │
│                ╱        ╲                                                     │
│    ┌──────────▼──┐   ┌───▼──────────────┐                                    │
│    │ VideoBubble │   │ PlayerBubble      │                                    │
│    │ Component   │   │ Component         │                                    │
│    │             │   │ (initial letter,  │                                    │
│    │ - shader    │   │  dark circle)     │                                    │
│    │ - capture   │   └──────────────────-┘                                    │
│    │ - glow      │                                                            │
│    │ - ripple    │   ┌───────────────────┐                                    │
│    └─────────────┘   │ BotBubble         │  (for bot characters)             │
│                      │ Component         │                                    │
│                      └───────────────────┘                                    │
│                                                                              │
│  Special case: Dreamfinder gets VideoBubbleComponent with gold glow +        │
│  externalVideoCapture (CanvasCapture from Three.js iframe, not WebRTC).      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  5. VIDEO FRAME CAPTURE (platform-specific)                                  │
│                                                                              │
│  Three parallel paths, all producing ui.Image at ~15fps:                     │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────┐         │
│  │ macOS (FFI)                                                     │         │
│  │                                                                 │         │
│  │ VideoFrameCapture ──► native ObjC RTCVideoRenderer              │         │
│  │   ├── shared memory buffer (40-byte header + pixels)            │         │
│  │   ├── getPixels() → zero-copy asTypedList                      │         │
│  │   ├── BGRA → RGBA conversion                                   │         │
│  │   └── ImageDescriptor.raw → codec → ui.Image                   │         │
│  └─────────────────────────────────────────────────────────────────┘         │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────┐         │
│  │ Web — Chrome (MediaStreamTrackProcessor)                        │         │
│  │                                                                 │         │
│  │ DirectTrackCapture                                              │         │
│  │   ├── jsTrack → MediaStreamTrackProcessor → readable stream     │         │
│  │   ├── reader.read() → VideoFrame                                │         │
│  │   ├── draw to offscreen canvas → getImageData                   │         │
│  │   └── decodeImageFromPixels → ui.Image                          │         │
│  │                                                                 │         │
│  │   ⚠ Never createImageFromImageBitmap (Skia #14637 = black)     │         │
│  └─────────────────────────────────────────────────────────────────┘         │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────┐         │
│  │ Web — Fallback (HTMLVideoElement)                               │         │
│  │                                                                 │         │
│  │ VideoElementCapture                                             │         │
│  │   ├── hidden <video> at top:-9999px (NOT display:none)          │         │
│  │   │   └── mobile browsers won't decode hidden elements          │         │
│  │   ├── createImageBitmap(video) → draw to canvas → getImageData  │         │
│  │   └── decodeImageFromPixels → ui.Image                          │         │
│  └─────────────────────────────────────────────────────────────────┘         │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────┐         │
│  │ Dreamfinder only (Three.js iframe)                              │         │
│  │                                                                 │         │
│  │ DreamfinderAvatarBridge                                         │         │
│  │   ├── hidden iframe → /avatar (Three.js TalkingHead, 42MB GLB) │         │
│  │   ├── postMessage 'renderer-ready' (up to 120s)                 │         │
│  │   ├── CanvasCapture.create(iframe canvas, fps: 15)              │         │
│  │   │                                                             │         │
│  │   │  Data channel → iframe:                                     │         │
│  │   │  dreamfinder-audio (PCM16→base64) → __onAudioChunk()       │         │
│  │   │  dreamfinder-mood (JSON)           → __setMood()            │         │
│  │   │                                                             │         │
│  │   └── CanvasCapture exposes FrameSource → VideoBubbleComponent  │         │
│  └─────────────────────────────────────────────────────────────────┘         │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  6. BUBBLE RENDERING                                                         │
│                                                                              │
│  VideoBubbleComponent.render(Canvas)                                         │
│                                                                              │
│         ┌─────────────────────────────────────┐                              │
│         │           ╭─────────╮               │                              │
│         │         ╱~ ~ ~ ~ ~ ~ ╲  ◄── radial glow (pulses when speaking)    │
│         │        │  ┌────────┐  │                                            │
│         │        │  │ video  │  │ ◄── circle-clipped drawImageRect           │
│         │        │  │ frame  │  │                                            │
│         │        │  └────────┘  │                                            │
│         │         ╲  ╰─╮╭─╯   ╱  ◄── voice ripple (sinusoidal lobes)       │
│         │           ╰──╯╰───╯     ◄── proportional to audioLevel            │
│         │         ─── border ───  ◄── thin ring (glowColor or white)        │
│         └─────────────────────────────────────┘                              │
│                                                                              │
│  Animation layers:                                                           │
│    1. Breathing scale: 1.0 ± 2.5% × sin(t × 2.0)                           │
│    2. Opacity layer (fades with proximity distance)                          │
│    3. Shadow / glow halo                                                     │
│    4. Glow pulse: radius + 8 × intensity × (1 + 0.15 × sin(t × 2.5))      │
│    5. Video frame (circle-clipped)  — or dark bg + initial if no frame      │
│    6. Voice ripple path (when audioLevel > 0.01)                             │
│    7. Border ring                                                            │
│    All animation skipped when reduceMotion = true.                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  7. BUBBLE PHYSICS & MERGING                                                 │
│                                                                              │
│  BubbleManager._updateBubblePositions(dt):                                   │
│                                                                              │
│  ┌─── Anchoring ──────────────────────────────────────────────────┐          │
│  │  Each bubble anchored to character world pos + offset(16, -20) │          │
│  └────────────────────────────────────────────────────────────────┘          │
│                                                                              │
│  ┌─── Repulsion (O(n²) pairwise) ────────────────────────────────┐          │
│  │                                                                │          │
│  │   ○ ◄──── 64px ────► ○     collision diameter                 │          │
│  │    ╲                ╱                                          │          │
│  │     ╲   overlap    ╱       force = overlap × 31.25            │          │
│  │      ╲            ╱        damping = 0.85× per frame          │          │
│  │       ╲──────────╱         max displacement = 24px (tether)   │          │
│  │                            dt clamped to 50ms (stability)     │          │
│  └────────────────────────────────────────────────────────────────┘          │
│                                                                              │
│  ┌─── Metaball Field (≥2 bubbles) ────────────────────────────────┐         │
│  │                                                                 │         │
│  │  BubbleFieldComponent (GLSL shader quad, BlendMode.plus)        │         │
│  │  Uniforms: time, count, colour, radius, up to 8 positions      │         │
│  │  Renders additive energy field below all bubbles                │         │
│  └─────────────────────────────────────────────────────────────────┘         │
│                                                                              │
│  ┌─── Merge (≥2 video bubbles < 96px apart) ─────────────────────┐          │
│  │                                                                │          │
│  │  BFS finds connected groups → largest group (max 4)            │          │
│  │                                                                │          │
│  │  MergedVideoBubbleComponent (GLSL shader quad)                 │          │
│  │    ├── up to 4 image samplers (reads currentFrame from each)   │          │
│  │    ├── Voronoi metaball boundary between videos                │          │
│  │    └── source bubbles: hiddenForMerge=true                     │          │
│  │         (keep capturing frames, skip individual render)        │          │
│  └────────────────────────────────────────────────────────────────┘          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  8. SPEAKER DETECTION (two independent signal paths)                         │
│                                                                              │
│  Path A — Binary speaking state (event-driven):                              │
│                                                                              │
│    LiveKit ActiveSpeakersChangedEvent                                        │
│      └── LiveKitService diffs _previousSpeakerIds vs new set                │
│            └── emits (participant, true/false) on speakingChanged            │
│                  └── LiveKitGameBridge                                       │
│                        └── BubbleManager.updateSpeakingState()              │
│                              └── VideoBubbleComponent.speakingLevel = 1│0   │
│                                                                              │
│  Path B — Continuous audio level (polled per frame):                         │
│                                                                              │
│    VideoBubbleComponent.update(dt)                                           │
│      └── reads participant.audioLevel (0.0–1.0)                             │
│            └── lerps into _smoothedAudioLevel                               │
│                  └── drives voice ripple amplitude in render()              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘


## File Index

| File | Role |
|------|------|
| `lib/rooms/room_session.dart` | Session factory — creates LiveKitService, connects |
| `lib/livekit/livekit_service.dart` | WebRTC room wrapper, typed event streams |
| `lib/flame/livekit_game_bridge.dart` | 14 subscriptions translating LiveKit → game world |
| `lib/flame/bubble_manager.dart` | Core orchestrator — proximity, lifecycle, physics, merging |
| `lib/flame/tech_world.dart` | Flame World, calls BubbleManager.update(dt) each frame |
| `lib/flame/components/video_bubble_component.dart` | Per-player video bubble rendering + frame capture |
| `lib/flame/components/player_bubble_component.dart` | Fallback bubble (no video, shows initial) |
| `lib/flame/components/bot_bubble_component.dart` | Bot character bubbles |
| `lib/flame/components/bubble_field_component.dart` | Metaball energy field (GLSL shader) |
| `lib/flame/components/merged_video_bubble_component.dart` | Merged multi-video shader (up to 4) |
| `lib/native/video_frame_ffi.dart` | macOS FFI capture (shared memory, BGRA→RGBA) |
| `lib/native/video_frame_web_v2.dart` | Web capture (DirectTrackCapture + VideoElementCapture) |
| `lib/native/canvas_capture_web.dart` | Dreamfinder Three.js canvas capture |
| `lib/livekit/dreamfinder_avatar_bridge_web.dart` | Dreamfinder iframe + audio/mood forwarding |
| `lib/proximity/proximity_service.dart` | Event-only proximity (separate from bubble system) |
| `lib/flame/shared/speaker_role.dart` | Speech transcript attribution enum |
| `lib/preferences/user_preferences.dart` | hideVideoBubbles / reduceMotion prefs |

## Key Constraints

1. **`adaptiveStream: false`** — Flame renders to canvas, not `VideoTrackRenderer` widget. Without this the SFU stops forwarding video.
2. **Never `createImageFromImageBitmap`** — Skia bug #14637 renders black in CanvasKit WASM.
3. **Hidden elements at `top: -9999px`**, not `display:none` — mobile browsers won't decode hidden video elements.
4. **Two separate proximity systems** — `ProximityService` (threshold=3, events only) vs `BubbleManager` (visual=5, audio=2, owns bubbles). They don't talk to each other.
5. **GLSL limits** — no array initializers or dynamic loop bounds (CanvasKit rejects them).
6. **`hiddenForMerge`** — merged bubbles keep capturing but skip render; the merged component samples their `currentFrame` directly.
