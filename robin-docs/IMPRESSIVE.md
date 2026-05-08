# Tech World — Technical Showcase

**A distributed multiplayer game engine with real-time video compositing, collaborative world editing, AI agents, and an embedded IDE — built from scratch in Flutter/Dart on the Flame engine.**

---

## The Game Engine

Tech World renders a 50×50 tile-based world using Flame's component tree, but the rendering pipeline goes well beyond what Flame provides out of the box.

**Depth-sorted occlusion without a z-buffer.** Every game object — players, furniture, walls, bots — is priority-sorted by its y-coordinate (`priority = y ~/ gridSquareSize`). Wall caps, doorway lintels, and object tiles participate in the same sort. The result: a player walking behind a wall disappears behind it; walking through a doorway, their head tucks under the overhang. This emergent occlusion comes from a single pure function (`computePriorityOverrides`) that analyses the barrier set and computes per-tile priority bumps — no per-frame raycasting, no z-buffer, no special-case rendering in the player component. Doorway lintels are rendered at half-height (21 of 32 pixels) using a clip rect, exposing the floor beneath.

**Terrain autotiling with 8-bit Wang Blob bitmasks.** When a terrain type is painted, 8 Moore neighbours are encoded into a single byte. Corner bits are masked when adjacent edges aren't both set, reducing 256 raw configurations to 47 unique tile selections. Wall tiles use a separate 4-bit cardinal bitmask (16 configurations) selecting face, body, and cap variants per wall style.

**Three procedural map generators:** cellular automata caves (B5/S4 rule with flood-fill connectivity), BSP dungeon rooms with L-corridors, and recursive-backtracker mazes with dead-end removal. All produce the same `GameMap` abstraction.

**Jump Point Search pathfinding** with Bresenham interpolation. JPS is ~5x faster than A* on uniform-cost grids by pruning symmetric paths. The sparse JPS waypoints are expanded via Bresenham's line algorithm into per-cell steps. The pathfinding grid is cloned per query (JPS mutates grid state during search) and invalidated in real-time when the collaborative map editor modifies barriers.

---

## The Video Pipeline — Three Capture Architectures

Every player appears in the game world as a circular video bubble rendered inside the Flame canvas. Getting live video frames from WebRTC into Flame's rendering pipeline required building three entirely different capture paths, all converging to the same `ui.Image` output.

**macOS: zero-copy FFI shared memory.** A native plugin registers as an `RTCVideoRenderer` and writes BGRA frames to a shared memory buffer. Dart reads the pixel data via FFI pointer arithmetic — a 40-byte struct header (width, height, bytesPerRow, format, timestamp, frame number, ready flag) followed by raw pixels accessed as a `Uint8List` view from `Pointer<Uint8>.fromAddress()`. Genuinely zero-copy: no serialization, no message passing, no copies. BGRA-to-RGBA channel swap happens in Dart before handing off to `ui.ImageDescriptor.raw`.

**Web: MediaStreamTrackProcessor (WebCodecs API).** Creates a `ReadableStream` of `VideoFrame` objects directly from the `MediaStreamTrack`. Each frame is drawn to an offscreen canvas, extracted via `getImageData()`, and decoded through `decodeImageFromPixels()`. The critical detail: `createImageFromImageBitmap` — the obvious API — renders black under CanvasKit due to Skia issue #14637. This was diagnosed and worked around with the alternative `decodeImageFromPixels` path, which takes a different internal route through `SkImage.MakeRasterData`. Remote tracks start muted (RTP not yet flowing), so initialization polls for the `unmute` event with a 5-second timeout.

**Web fallback: hidden video element capture.** When `MediaStreamTrackProcessor` isn't available (Safari, older Chrome), a hidden `<video>` element is created at `top: -9999px` (not `display: none` — browsers don't decode hidden video elements). The implementation reuses existing `<video>` elements created by `flutter_webrtc` by matching track ID. Captures via `createImageBitmap(videoElement)` -> offscreen canvas -> `getImageData` -> `decodeImageFromPixels`.

**Dreamfinder 3D avatar: iframe canvas capture.** The Dreamfinder bot doesn't have a webcam — it has a Three.js holographic avatar loaded from a 42MB GLB model inside a same-origin `<iframe>`. The iframe posts `renderer-ready` when the model downloads (up to 120s timeout), with progress messages driving a hologram boot scan-line effect in the bubble. Once ready, Dart reaches into `iframe.contentWindow.document.querySelector('canvas')` and captures the Three.js render at 15fps via `drawImage` -> `getImageData` -> `decodeImageFromPixels`. Audio is forwarded as base64 PCM16 for lip-sync, mood data as JSON for expression changes.

All four paths are wired through Dart's conditional import system (7 abstraction points, each with web/native/stub variants), keeping `dart:js_interop` and `dart:ffi` out of each other's compilation units.

---

## Video Bubble Physics and Shaders

Video feeds don't just appear in circles — they're living, breathing, physically-interacting game objects.

**Spring-based repulsion.** O(n^2) pairwise physics: when two bubbles are closer than 64px, they push apart with force proportional to overlap. Displacements persist across frames (spring simulation, not impulse), are damped at 0.85x per frame, and clamped to 24px maximum tether distance. Frame-rate independent via `clampedDt / 0.016` normalization.

**Breathing animation.** Sinusoidal scale pulse: `1.0 + 0.025 * sin(time * 2.0)` applied via canvas save/translate/scale/restore.

**Voice ripple borders.** When a player is speaking, the bubble boundary deforms along 64 angular segments with two overlapping sinusoidal waves at different frequencies (`sin(angle * 8 + time * 6)` and `sin(angle * 11 - time * 4) * 0.4`) scaled by smoothed audio level. The result is an organic, voice-reactive boundary.

**Metaball merge field (GLSL fragment shader).** When bubbles are close enough, a metaball field (`r^2 / (d^2 + 1)`) fills the gap between them with a glowing energy bridge. Uses `BlendMode.plus` (additive blending). Up to 8 bubbles via explicit `#define BALL(b)` macros — CanvasKit's WebGL compiler forbids dynamic array indexing and loops with variable bounds.

**Merged video compositing (GLSL fragment shader — 197 lines).** The most complex shader: Voronoi-based multi-video blending. Each pixel samples from the nearest bubble's video feed. At boundaries, `smoothstep(secondDist - nearestDist)` over a `radius * 0.3` blend width creates smooth transitions. Aspect-correct UV mapping in cover mode. Four video streams composited in a single GPU pass, with explicit `if/else if` chains replacing the forbidden dynamic sampler indexing.

**BFS merge group detection.** Every frame, a BFS over `VideoBubbleComponent` instances finds connected components within 96px (1.5x bubble diameter). Groups of 2+ trigger the merged video shader; individual bubbles hide and the merged renderer takes over.

---

## CRDT Collaborative Map Editor

Multiple players can simultaneously edit the game world's terrain, walls, objects, and structure. Edits converge without a central server.

**Last-Writer-Wins registers per cell.** Each `(x, y, layer)` position tracks a `(counter, playerId)` version. Higher counter wins; ties broken lexicographically by player ID. Five independent layers: structure (barriers/spawn/terminals), floor tiles, object tiles, terrain IDs, and wall styles.

**Lamport clock synchronization.** Each player maintains a monotonically increasing counter. On receiving a remote edit: `local = max(local, remote)`. This ensures causal ordering across the distributed system without wall-clock synchronization.

**Undo that wins conflicts.** Undo operations don't replay history — they produce new inverse batches with fresh (higher) Lamport counters. This means an undo always beats concurrent edits from other players, which is the correct semantic: "I meant to undo that" should override "someone else edited that cell at the same time."

**Terrain paint propagation.** Painting a terrain type affects the target cell plus its 8 Moore neighbours (bitmask recomputation). The batch includes both terrain-layer and floor-layer operations, so remote clients apply the full visual diff without recomputing bitmasks locally.

**Late-join sync protocol.** A joining editor publishes a `sync-request` on the `map-edit-sync` LiveKit topic. Existing editors respond with a complete snapshot: all five layers, the full version map, and the current Lamport clock value. Incoming edits are buffered during sync to prevent races.

**Real-time pathfinding integration.** CRDT edits (local or remote) trigger `editorState.notifyRemoteChange()` -> `TechWorld._onEditorStateChanged()` -> `pathComponent.setGridFromEditor()`. The pathfinding grid stays consistent with the visual map at all times.

---

## LiveKit Wire Protocol — 17+ Data Channel Topics

All multiplayer communication runs over LiveKit's WebRTC data channels — there is no game server. The client manages a custom wire protocol with 17+ topics:

| Category | Topics |
|----------|--------|
| **Player state** | `position` (unreliable), `avatar`, `speech-transcript` |
| **Chat** | `chat`, `chat-response` |
| **CRDT** | `map-edit`, `map-edit-sync` |
| **Game events** | `door-unlock`, `terminal-activity` |
| **Bot coordination** | `ping`/`pong`, `map-info`, `map-info-request` |
| **Dreamfinder** | `dreamfinder-audio` (PCM16), `dreamfinder-mood`, `infra-boot` |
| **Infrastructure** | `infra-health`, `infra-heal`, `infra-heal-result` |

Proximity-based audio uses `RemoteTrackPublication.enable()`/`.disable()` to signal the SFU to start/stop forwarding audio for out-of-range players — bandwidth management at the infrastructure level.

---

## AI Agent Ecosystem — Three Bots

**Clawd** (`bot-claude`) — a coding tutor that receives `terminal-activity` messages when a player opens the code editor, sees the challenge context, and provides hints via the chat return channel.

**Gremlin** (`bot-gremlin`) — a chaotic hype creature for atmosphere.

**Dreamfinder** (`bot-dreamfinder`) — a voice-interactive autonomous agent with:
- An 8-direction state machine (`working` -> `surprised` -> walking -> `idle` -> wandering)
- Autonomous behaviour: notices new players (surprise animation -> walks toward them), then wanders between terminals (70% probability) and random positions with 5-12 second work pauses
- A holographic 3D avatar (Three.js, 42MB GLB model) captured via the iframe pipeline
- Infrastructure health monitoring with self-healing (`infra-heal` / `infra-heal-result`)

---

## Spell Casting — Speech Recognition Meets Game Design

Players earn Words of Power by completing prompt challenges. Casting is triggered by proximity to world listeners (doors, runestones) — never by a button.

**Speech-to-text** via the Web Speech API (`webkitSpeechRecognition`), returning transcripts with per-alternative confidence scores.

**Spell algebra — a 2x2 confidence lattice:**

|  | High confidence (>=0.7) | Low confidence (0.3-0.7) |
|--|------------------------|--------------------------|
| **Known combo** | `CastComboKnown` (success) | `CastComboKnownPartial` (wavering) |
| **Novel combo** | `CastComboNovel` (experiment) | `FreeCastNoMatch` (fail cheap) |

Below the noise floor (0.3) -> silence (null). `NaN` handled explicitly because `NaN < x` is always `false` in Dart. 18 words across 6 schools, 5 predefined combinations (e.g., `ignis + lumen` -> Blazing Sight). Combination keys are order-independent (sorted alphabetically, validated on hydration from Firestore).

---

## Embedded IDE with LSP

The in-game code editor connects to a remote Dart Language Server over WebSocket (`wss://lsp.adventures-in-tech.world`). Architecture: nginx SSL -> `lsp-ws-proxy` -> `dart language-server --protocol=lsp`. Each editor session gets a unique file URI (timestamped with challenge wire name) to prevent concurrent session collisions. 23 code challenges with starter code, evaluated by the bot service.

---

## Challenge System — 41 Challenges

23 code challenges and 18 prompt challenges, all typed as enums with wire names for Firestore persistence. Wire name disjointness is enforced by a runtime test. Prompt challenges span three evaluation tiers: `deterministic` (programmatic checks), `structural` (programmatic with LLM fallback), and `behavioral` (always LLM judge). Each prompt challenge maps bijectively to a Word of Power.

---

## The Numbers

- **~15,000 lines of Dart** across 80+ files
- **3 GLSL fragment shaders** (368 lines) working within CanvasKit's WebGL restrictions
- **3 video capture architectures** unified behind conditional imports
- **7 system boundaries** (LiveKit, Firestore, Firebase Storage, Firebase Functions, Dreamfinder API, LSP WebSocket, Three.js iframe)
- **17+ wire protocol topics** over WebRTC data channels
- **3 autonomous AI agents** with distinct personalities and capabilities
- **5-layer CRDT** with Lamport clocks and conflict-winning undo
- **4 target platforms** (web, macOS, iOS, Android) with 7 conditional import abstraction points
- **3 procedural map generators** (cave, dungeon, maze)
- **41 educational challenges** with a spell casting system built on speech recognition

---

## What Makes This Impressive

What makes this codebase remarkable isn't any single feature — it's the integration density. The video pipeline alone (3 capture architectures, BGRA-to-RGBA conversion, WASM compatibility workarounds, Skia bug avoidance) would be a significant project. The CRDT map editor with conflict-winning undo would be another. The metaball merge shader compositing multiple live video feeds in a single GPU pass is a third. But they all work together: a player walks through a CRDT-edited doorway, their video bubble merges with another player's via a Voronoi shader, while a Three.js holographic bot wanders autonomously nearby and a Lamport clock ticks forward on a remote map edit. That orchestration — across WebRTC, WebGL, FFI, iframe boundaries, and 4 platforms — is the real engineering achievement.
