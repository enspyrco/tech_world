# Tech World Sweep 1 — Contracts & Security

**Phase 4 | 2026-05-08**

---

## Pattern Vocabulary (Updated)

13 GOF patterns identified in Phase 1 remain valid. Key updates since Phase 1:
- **God Object partially decomposed:** BubbleManager (-730 lines) and RoomSession (-10 nullable fields) extracted. TechWorld still large but structurally healthier.
- **DataTopic enum added but NOT wired in** — the Type Object refactor was created but never connected. Every `publishJson` and topic filter still uses raw strings.
- **Dead code cleaned:** ~2,849 lines of dead LiveKit scaffolding removed, ProximityService deleted.

New anti-pattern identified: **Trust boundary inconsistency** — the codebase has good internal patterns (Strategy, Command+Memento, Facade) but the security perimeter is porous. Firestore rules trust clients, LiveKit messages trust payloads, and sender identity comes from JSON rather than transport.

---

## Scorecard

| Audit | Score /5 | Critical Gaps |
|-------|----------|---------------|
| Security | 3.0 | 3 HIGH: Firestore private-room read, editor self-promotion, Dreamfinder key hardcoded default |
| Dependencies | 3.0 | 16 outdated deps, 2 supply-chain risks (re_highlight, code_forge_web), 1 abandoned (pathfinding) |
| LiveKit Protocol | 3.5 | DataTopic enum unused (dead abstraction), map-edit fromJson throws in stream listener |

**Composite: 3.2 / 5**

---

## Findings by Priority

### Critical

**C1: DataTopic enum is a dead abstraction**
`lib/livekit/data_topic.dart` defines 24 typed constants but is never imported or referenced outside its own file. Every `publishJson` call and every `.where((msg) => msg.topic == ...)` filter uses raw string literals. The enum adds zero type safety. Two active topics (`position-heartbeat`, `map-switch`) are missing from it entirely.

*Pattern diagnosis:* Intended Type Object refactor was created but never connected. Completing the wiring fixes C1, and is a prerequisite for MessageEnvelope and ValidationStrategy patterns below.

### High

| # | Finding | File | Risk | Pattern Gap |
|---|---------|------|------|-------------|
| H-1 | Dreamfinder API key hardcoded `defaultValue` | `room_session.dart:135-139` | Key in web bundle readable by anyone | Survived RoomSession extraction — same 48-char hex key from Phase 3 |
| H-2 | Any authenticated user reads ALL private rooms | `firestore.rules:19-20` | Private rooms provide no actual privacy | Missing Authorization Proxy |
| H-3 | Editor can promote self to owner | `firestore.rules:27-30` | Room ownership theft via `.update({ownerId: myUid})` | Missing field-level Proxy constraint |
| H-4 | `infra-heal` broadcast, not targeted | `infra_health_service.dart:112` | Any participant receives/injects restart commands | Missing targeted routing |
| H-5 | `map-edit` fromJson throws in stream listener | `map_sync_service.dart:581` | One malformed packet permanently kills collab editing | Missing Null Object / Exception Barrier |

### Medium

| # | Finding | File | Risk |
|---|---------|------|------|
| M-1 | Unvalidated `spriteAsset` from remote participants | `livekit_service.dart:842` | Crash sprite rendering via unknown cache key |
| M-2 | Position coordinates not bounds-checked | `livekit_service.dart:203-233` | Off-screen ghosts, potential overflow at extreme values |
| M-3 | DM sender identity from payload, not transport | `chat_service.dart:231` | Identity spoofing in DMs — payload `senderId` used for routing |
| M-4 | DM regex bypass on conversationId | `firestore.rules:43-44` | Legacy DMs readable by unintended participants (open since Phase 1) |
| M-5 | `door-unlock` spoofable by any participant | `tech_world.dart` | Any player can unlock any door for everyone |
| M-6 | `dreamfinder-audio` raw PCM16, no size constraint | LiveKit data channel | Flood attack via rogue participant |
| M-7 | `help-request` code payload has no size cap | LiveKit data channel | Oversized payloads silently truncated/dropped |

### Low / Info

| # | Finding | File |
|---|---------|------|
| L-1 | Firebase API keys in `firebase_options.dart` in VCS | By design — low risk, restricted by rules |
| L-2 | FFI `error` field unchecked on VideoFrameBuffer | `video_frame_ffi.dart:242-255` |
| L-3 | FFI `height * bytesPerRow` can overflow on extreme inputs | `video_frame_ffi.dart:254` |
| L-4 | No XSS risk — Flutter `Text` widget, no HTML rendering | `chat_panel.dart` — resolved |
| L-5 | `speech-transcript` has no documented schema or tryParse | `tech_world.dart:775` |
| L-6 | Unrecognised topics silently dropped (no logging) | All receive paths |
| L-7 | No protocol version field on any message | All topics |

### Dependency Findings

| Priority | Finding | Package |
|----------|---------|---------|
| P1 | Supply chain risk — low popularity, no adoption | `re_highlight` 0.0.3 |
| P1 | Abandoned since 2021, no maintenance signal | `pathfinding` 3.0.1 |
| P1 | Git-pinned to personal repo, no license, no pub.dev | `code_forge_web` |
| P2 | 3 major versions behind | `sign_in_with_apple` (7→8), `file_picker` (8→11) |
| P2 | WebRTC chain outdated (security fixes flow through this) | `livekit_client`, `dart_webrtc`, `flutter_webrtc` |
| P3 | 16 deps behind latest (all minor/patch) | Firebase suite, Flame, ffi, shared_preferences, etc. |

---

## Pattern-Based Remediation

### R1: Wire `DataTopic` enum (completes intended Type Object)
**Fixes: C1, M-1 (partial), M-5 (partial), L-5, L-6**
Replace all `topic: 'string'` literals with `topic: DataTopic.X.wireName` and all `.where((m) => m.topic == 'string')` with `DataTopic.parse`. Add `positionHeartbeat` and `mapSwitch` to the enum first. This is the single highest-leverage change — prerequisite for R2 and R3.

### R2: `MessageEnvelope<T>` — Verified Value Object / Decorator
**Fixes: M-3, H-4, M-5, H-5**
Immutable envelope `{topic: DataTopic, sender: VerifiedIdentity, payload: T, timestamp}` where `VerifiedIdentity` comes from LiveKit transport, never the JSON payload. Factory returns `Result<MessageEnvelope, ParseError>` — simultaneously fixes throwing `fromJson`. Every stream listener becomes `envelope.map(handler)`.

### R3: `ValidationStrategy` registry keyed on `DataTopic`
**Fixes: M-1, M-2, M-6, M-7**
Map from `DataTopic → Validator<T>`. Bounds-check for positions, size cap for audio, sprite-asset whitelist, code-size limit — all become entries in one registry. The registry doubles as protocol documentation.

### R4: Firestore Authorization Proxy (rule-level)
**Fixes: H-2, H-3, M-4**
Server-side Proxy with invariant guards:
- H-2: `allow read: if resource.data.isPublic || uid == ownerId || uid in editorIds`
- H-3: `allow update: if uid == ownerId || (uid in editorIds && !affectedKeys.hasAny(['ownerId','editorIds']))`
- M-4: Remove legacy regex fallback, migrate old DMs with Cloud Function

### R5: Adapter interfaces for risky dependencies
**Fixes: pathfinding P1, re_highlight P1, code_forge_web P1**
`IPathfinder` wrapping JPS, `ISyntaxHighlighter` wrapping re_highlight. Swap cost drops to single-file changes. `code_forge_web` should be vendored or published to pub.dev.

### R6: Hardcoded key removal
**Fixes: H-1**
Change `defaultValue: ''` in `room_session.dart:135-139`. Add startup assertion. This was prescribed in Phase 3 (HI-3) but survived the RoomSession refactor.

---

## Recommended PR Sequence

| # | Branch | What | Effort |
|---|--------|------|--------|
| 1 | `audit/fix-dreamfinder-key-default` | H-1: defaultValue → '' + assertion | Trivial |
| 2 | `audit/wire-data-topic-enum` | C1: Replace all string literals with DataTopic.X.wireName | Small |
| 3 | `audit/fix-map-edit-try-catch` | H-5: Wrap MapEditBatch.fromJson in try/catch | Trivial |
| 4 | `audit/fix-infra-heal-targeting` | H-4: Add destinationIdentities to infra-heal | Trivial |
| 5 | `audit/fix-dm-sender-trust` | M-3: Use transport senderId, not payload | Small |
| 6 | `audit/fix-spriteasset-whitelist` | M-1: Validate against known asset filenames | Small |
| 7 | `audit/fix-position-bounds` | M-2: Clamp coordinates at parse boundary | Small |
| 8 | `audit/fix-door-unlock-sender` | M-5: Verify door-unlock sender identity | Small |

Firestore rule changes (H-2, H-3, M-4) require coordination with Nick — they live in the Firebase console or a separate rules repo, not in this Flutter client.

Dependency updates (WebRTC chain, Firebase suite, re_highlight replacement) are best batched into 2-3 dedicated PRs after the security fixes land.

---

## Previous Finding Status

| Phase | Finding | Status |
|-------|---------|--------|
| 1 | Hardcoded Dreamfinder API key | Partially fixed — removed from main.dart, **reappeared in room_session.dart** |
| 1 | Firestore DM regex bypass | **Still open** (M-4) |
| 1 | Storage rules gap (tileset uploads) | By design — admin SDK, not a bug |
| 1 | Unversioned protocol | **Still open** (L-7) |
| 1 | Stringly-typed topics | DataTopic enum created but **not wired in** (C1) |
| 3 | God Object TechWorld | Partially fixed — BubbleManager + RoomSession extracted |
