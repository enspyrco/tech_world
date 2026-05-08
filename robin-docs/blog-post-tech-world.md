# We Built a Game Engine Where the Lobby Is a World

**2026-05-08 | ~8 min read**
**Tags:** tech-world, flame, multiplayer, livekit, ai, imagineering

*By Nick Meinhold & Claude*

---

**TL;DR** — Tech World is a multiplayer game engine built in Flutter and Flame where players walk through a tile-based world, solve coding challenges in an embedded IDE, cast spells by speaking aloud, and see each other as live video bubbles rendered inside the game canvas. There's no game server — everything runs over WebRTC. We hold our [Imagineering](https://imagineering.cc) meetups here.

---

## The idea that wouldn't stay simple

Tech World started as a lobby. A place to hang out before the real thing happened. Then the lobby grew a code editor. Then the code editor got a language server. Then someone said "what if you could see each other's faces?" and suddenly we were writing GLSL shaders to composite four video streams in a single GPU pass.

That's the thing about building a world instead of an app. Worlds accrete. Every feature you add doesn't sit beside the others — it *inhabits* the same space. The code editor isn't a modal dialog that floats above the game. It's a terminal you walk up to. The AI tutor isn't a sidebar chatbot. It's a character standing next to you, watching what you type.

We hold our online [Imagineering](https://imagineering.cc) meetups inside Tech World. It's not a metaphor — we literally walk around a dungeon together, our video feeds bobbing above our sprites, while we pair-program on challenges and demo what we've built that week. The world *is* the meeting room.

## No game server

Every multiplayer game has a server. Ours doesn't.

All real-time communication — player positions, chat messages, video feeds, map edits, bot commands, spell casts — flows through LiveKit's WebRTC data channels. We defined a custom wire protocol with 17+ topics: `position` (unreliable delivery for speed), `chat`, `map-edit` (CRDT operations), `door-unlock`, `terminal-activity`, `dreamfinder-audio` (raw PCM16 for lip-sync), and more.

The client *is* the authority. When a player moves, their client publishes the new position. When someone edits the map, their client broadcasts the CRDT operation. Conflicts are resolved mathematically, not by a referee.

This isn't the easy path. You give up a lot of guarantees when there's no server to be the single source of truth. But you gain something important: the architecture scales to zero. No server to keep running. No infrastructure cost when nobody's playing. The world sleeps when the last player leaves, and wakes when the next one arrives.

## Putting video inside a game engine

This is the part that nearly broke us.

The obvious thing — "just render the video" — turns out to be deeply non-obvious when your renderer is a game engine, not a browser. Flame renders to a Skia canvas. WebRTC produces video frames. Getting one into the other requires bridging two rendering pipelines that were never designed to meet.

We built three capture architectures:

**On macOS**, a native plugin writes BGRA frames to shared memory via FFI. Dart reads the pixels through pointer arithmetic — a 40-byte struct header followed by raw pixel data. Zero copies. The BGRA-to-RGBA channel swap happens in Dart before handing the buffer to `ui.ImageDescriptor.raw`.

**On Chrome**, we use the WebCodecs API (`MediaStreamTrackProcessor`) to pull `VideoFrame` objects from the media stream, draw them to an offscreen canvas, and decode via `decodeImageFromPixels`. Not `createImageFromImageBitmap` — that renders black under CanvasKit due to a Skia bug (#14637) that cost us two days to diagnose.

**On Safari and older browsers**, we fall back to a hidden `<video>` element positioned at `top: -9999px` (not `display: none` — browsers won't decode invisible video elements). We reuse video elements that `flutter_webrtc` already created by matching track IDs.

All three paths produce the same `ui.Image` that Flame can render. Seven conditional import abstraction points keep `dart:ffi` and `dart:js_interop` out of each other's compilation units.

## Video bubbles that breathe

The video feeds don't just appear in circles. They're physics objects.

Each bubble breathes — a sinusoidal scale pulse at 2Hz. When a player speaks, the bubble boundary deforms along 64 angular segments with two overlapping sine waves at different frequencies, scaled by smoothed audio level. The result is an organic, voice-reactive wobble that makes it obvious who's talking without any UI indicator.

When two players stand close together, their bubbles push apart with spring-based repulsion — force proportional to overlap, damped at 0.85x per frame, frame-rate independent. Stand close enough and something stranger happens: a metaball field shader fills the gap between bubbles with a glowing energy bridge. Closer still, and the bubbles *merge* — a Voronoi fragment shader composites both video feeds into a single organic shape, blending at the boundary with `smoothstep` over a soft radius.

The merge detection runs every frame: BFS over all bubbles within 1.5x diameter finds connected components. Groups of two or more trigger the merged shader. Individual bubbles hide and the merged renderer takes over. It looks like magic. It's 197 lines of GLSL working within CanvasKit's restrictions — no dynamic array indexing, no loops with variable bounds, explicit `if/else if` chains for each video sampler.

## A CRDT that lets you undo other people's edits

Multiple players can edit the game world simultaneously. Terrain, walls, objects, structural elements — five independent layers, all converging without a central server.

The data structure is a Last-Writer-Wins register per cell. Each `(x, y, layer)` tracks a Lamport clock counter and player ID. Higher counter wins; ties broken lexicographically. Standard stuff for CRDTs.

The interesting part is undo.

In most collaborative editors, undo is a nightmare. Do you undo *your* last edit, or the last edit to *that cell*, which might have been someone else's? What if someone edits the cell between your original edit and your undo — does their work disappear?

Our answer: undo operations produce new inverse batches with fresh Lamport counters. Because the counter is higher than any previous edit, the undo *always wins*. This is the correct semantic: "I meant to undo that" beats "someone happened to edit that cell at the same time." The undo doesn't rewrite history — it creates new history that happens to restore the old state, and it does so with a timestamp that says "this is the most recent intention."

Terrain painting propagates to all 8 Moore neighbours (bitmask recomputation), and the batch includes both terrain-layer and floor-layer operations. Remote clients apply the full visual diff without recomputing bitmasks locally. Late-joining editors get a complete snapshot — all five layers, the full version map, and the current Lamport clock — via the `map-edit-sync` protocol.

## Three bots, three personalities

Tech World has three AI agents that exist as participants in the world — they show up in LiveKit, they have positions on the map, they move around.

**Clawd** is the coding tutor. When you walk up to a terminal and open the code editor, Clawd receives a `terminal-activity` message with your challenge context. Ask for help and it responds through the chat channel, seeing exactly what you see.

**Gremlin** is the chaotic hype creature. Pure atmosphere. Every world needs a character that exists just to make things feel alive.

**Dreamfinder** is the ambitious one. It's voice-interactive, runs an autonomous behaviour loop (surprise animation when a player arrives, walks over to greet them, then wanders between terminals with 5-12 second work pauses), and renders as a holographic 3D avatar. That avatar is a Three.js scene running inside a hidden iframe, captured at 15fps by reaching into `iframe.contentWindow.document.querySelector('canvas')` and pulling pixels through the same `decodeImageFromPixels` pipeline as the video bubbles. Audio arrives as base64 PCM16 for lip-sync. Mood data arrives as JSON for expression changes. The 42MB GLB model takes up to two minutes to download, during which a hologram boot scan-line effect fills the bubble from bottom to top.

Dreamfinder also monitors infrastructure health, broadcasting `infra-health` snapshots every 10 seconds and accepting `infra-heal` requests to restart services.

## Casting spells by speaking

Players earn Words of Power by completing prompt challenges — 18 words across six schools (evocation, divination, transmutation, illusion, enchantment, conjuration). To cast, you don't press a button. You walk to a runestone or a locked door, and you speak.

This is a deliberate design decision: the world is the listener, not the player. Casting is a public, witnessed act. Other players see it happen. A button makes each player cast privately. A runestone makes one player walk across the room, speak, and everyone turns to watch. The second is the game.

The spell algebra is a 2x2 confidence lattice. High-confidence known combination? Cast succeeds. Low-confidence known combination? The spell wavers — you spoke the words but didn't commit. Novel combination above the confidence threshold? Experimental cast — the system tells you it doesn't recognise the combo but acknowledges you tried. Below the noise floor of 0.3? Silence. Not even attempted.

Five predefined combinations — `ignis + lumen` creates Blazing Sight, `tempus + libera` creates Time Unbound — with combination keys that are order-independent (sorted alphabetically, validated on hydration from Firestore).

## The embedded IDE

Walk up to a terminal in the game world and a code editor opens with a live connection to a remote Dart Language Server over WebSocket. Full LSP: autocomplete, diagnostics, hover documentation. Each session gets a unique file URI (timestamped with the challenge wire name) to prevent concurrent session collisions.

23 code challenges with starter code. Submit your solution and Clawd evaluates it. The challenges, the editor, the language server, and the AI evaluator all exist *inside* the world — you never leave the game to learn to code.

## Where we meet

Every week, the [Imagineering](https://imagineering.cc) community meets inside Tech World. We're a group of developers in Melbourne exploring what's possible when you build with AI agents as first-class collaborators — humans and AIs shipping code together.

The meetup isn't a video call with screen sharing. It's a room in a dungeon. You walk your avatar to a terminal, open the editor, and start building. Other people's video bubbles float nearby. Clawd watches over your shoulder. Someone casts a spell at a locked door across the room and you hear the incantation through proximity-based audio that fades with distance.

We chose to meet inside the thing we're building because it forces us to feel every rough edge. When the CRDT desyncs, we notice — because someone's wall edit just vanished. When the video pipeline drops a frame, we see it — because someone's face flickered. The world is the most honest integration test we have.

If you want to join us, visit [imagineering.cc](https://imagineering.cc). The only limit is your imagination.

---

## The numbers

- ~15,000 lines of Dart across 80+ files
- 3 GLSL fragment shaders (368 lines) working within CanvasKit's WebGL restrictions
- 3 video capture architectures unified behind conditional imports
- 7 system boundaries (LiveKit, Firestore, Firebase Storage, Firebase Functions, Dreamfinder API, LSP WebSocket, Three.js iframe)
- 17+ wire protocol topics over WebRTC data channels
- 3 autonomous AI agents with distinct personalities
- 5-layer CRDT with Lamport clocks and conflict-winning undo
- 4 target platforms (web, macOS, iOS, Android)
- 3 procedural map generators (cave, dungeon, maze)
- 41 educational challenges with speech-based spell casting
