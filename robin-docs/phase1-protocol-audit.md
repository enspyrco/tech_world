# Tech World — LiveKit Data Channel Protocol Audit

**Phase 1 / Foundation | 2026-05-06**

## 1. Complete Topic Registry (25 topics)

| # | Topic | Direction | Reliability | Sender -> Receiver | Purpose |
|---|-------|-----------|------------|-------------------|---------|
| 1 | `position` | broadcast | **unreliable** | player -> all | Player movement path updates |
| 2 | `avatar` | broadcast | reliable | player -> all | Avatar sprite selection |
| 3 | `chat` | broadcast | reliable | player -> all | Group chat messages |
| 4 | `chat-response` | broadcast | reliable | bot-claude -> all | Bot chat replies |
| 5 | `dm` | targeted | reliable | player -> player | Private direct messages |
| 6 | `dm-response` | targeted | reliable | bot -> player | Bot DM replies |
| 7 | `help-request` | targeted | reliable | player -> bot-claude | Request hint for coding challenge |
| 8 | `help-response` | targeted | reliable | bot-claude -> player | Hint reply |
| 9 | `ping` | targeted | reliable | player -> bot-claude | Connectivity health check |
| 10 | `pong` | targeted | reliable | bot-claude -> player | Health check reply |
| 11 | `map-info-request` | broadcast | reliable | bot -> all | Bot requests map layout on join |
| 12 | `map-info` | targeted | reliable | player -> all bots | Map layout (barriers, terminals, spawn) |
| 13 | `terminal-activity` | targeted | reliable | player -> bot-claude | Open/close code editor notification |
| 14 | `speech-transcript` | broadcast | reliable | dreamfinder -> all | Voice conversation text for speech bubbles |
| 15 | `oracle-request` | targeted | reliable | player -> bot-claude | Free-form bot generation (spells, flavor) |
| 16 | `oracle-response` | targeted | reliable | bot-claude -> player | Oracle generated text |
| 17 | `map-edit` | broadcast | reliable | player -> all | CRDT collaborative map edit batches |
| 18 | `map-edit-sync` | broadcast/targeted | reliable | player -> player | CRDT full-state sync (request/response) |
| 19 | `door-unlock` | broadcast | reliable | player -> all | Door unlock event |
| 20 | `infra-health` | broadcast | reliable | dreamfinder -> all | Infrastructure health heartbeat (~10s) |
| 21 | `infra-heal` | broadcast | reliable | player -> dreamfinder | Request service restart |
| 22 | `infra-heal-result` | broadcast | reliable | dreamfinder -> all | Heal action result |
| 23 | `infra-boot` | broadcast | reliable | dreamfinder -> all | Boot sequence animation on agent join |
| 24 | `dreamfinder-audio` | broadcast | reliable | dreamfinder -> all | Raw PCM16 audio chunks for lip-sync |
| 25 | `dreamfinder-mood` | broadcast | reliable | dreamfinder -> all | Avatar mood/expression state |

---

## 2. Message Schemas

### `position` (unreliable, broadcast)
```json
{
  "playerId": "string",
  "points": [{"x": 0.0, "y": 0.0}, ...],
  "directions": ["down", "left", "up", "right", "none", ...]
}
```
Parsed by `_parsePlayerPath()` in `livekit_service.dart:166`. Missing fields -> silently returns null (message dropped).

### `avatar` (reliable, broadcast)
```json
{
  "playerId": "string",
  "avatarId": "string",
  "spriteAsset": "string"
}
```
Own messages filtered by matching `playerId == userId`.

### `chat` (reliable, broadcast)
```json
{
  "type": "chat",
  "id": "timestamp-millis",
  "text": "string",
  "senderName": "string",
  "timestamp": "ISO8601",
  "[optional-metadata-fields]": "..."
}
```

### `chat-response` (reliable, broadcast)
```json
{
  "id": "string (own message ID for dedup)",
  "messageId": "string (ID of message being replied to)",
  "text": "string",
  "senderName": "string",
  "senderId": "string",
  "challengeResult": "'pass'|'fail' (optional, for challenge evaluation)"
}
```

### `dm` / `dm-response`
Same shape as `chat` / `chat-response` but targeted.

### `help-request` (reliable, targeted -> bot-claude)
```json
{
  "type": "help-request",
  "id": "help-{timestamp}",
  "challengeId": "string (wire name)",
  "challengeTitle": "string",
  "challengeDescription": "string",
  "code": "string",
  "terminalX": "int",
  "terminalY": "int",
  "senderName": "string",
  "timestamp": "ISO8601"
}
```

### `help-response` (reliable, targeted -> requester)
```json
{
  "requestId": "string (echoes help-request.id)",
  "hint": "string"
}
```

### `ping` / `pong`
```json
// ping
{"type": "ping", "id": "timestamp-millis", "timestamp": "ISO8601"}
// pong
{"originalMessage": {"id": "string (echoes ping.id)"}}
```

### `map-info-request`
No body — topic presence alone triggers response.

### `map-info` (reliable, targeted -> all bots)
```json
{
  "mapId": "string",
  "barriers": [[x, y], ...],
  "terminals": [[x, y], ...],
  "spawnPoint": [x, y],
  "gridSize": "int",
  "cellSize": "int"
}
```

### `terminal-activity` (reliable, targeted -> bot-claude)
```json
{
  "type": "terminal-activity",
  "action": "open" | "close",
  "playerId": "string",
  "playerName": "string",
  "timestamp": "ISO8601",
  "challengeId": "string (optional)",
  "challengeTitle": "string (optional)",
  "challengeDescription": "string (optional)",
  "terminalX": "int (optional)",
  "terminalY": "int (optional)"
}
```

### `speech-transcript` (reliable, broadcast)
```json
{"speaker": "dreamfinder" | "user", "text": "string"}
```

### `oracle-request` / `oracle-response`
```json
// request
{"requestId": "oracle-{microseconds}-{seq}", "kind": "cast_no_match|spell_combo|...", "context": {...}}
// response
{"requestId": "string (echoed)", "text": "string"}
```

### `map-edit` (reliable, broadcast)
```json
{
  "type": "edit",
  "playerId": "string",
  "counter": "int (Lamport clock)",
  "ops": [{
    "x": "int", "y": "int",
    "layer": "structure|floor|objects|terrain|walls",
    "old": "null|string|{tilesetId,tileIndex}",
    "new": "null|string|{tilesetId,tileIndex}"
  }]
}
```

### `map-edit-sync` (reliable, broadcast/targeted)
```json
// Request (broadcast)
{"type": "sync-request", "playerId": "string"}
// Response (targeted)
{
  "type": "sync-response",
  "structure": [{"x": int, "y": int, "v": "barrier|spawn|terminal"}, ...],
  "floor": [{"x": int, "y": int, "tilesetId": "string", "tileIndex": int}, ...],
  "objects": [...],
  "terrain": [{"x": int, "y": int, "t": "string"}, ...],
  "walls": [{"x": int, "y": int, "s": "string"}, ...],
  "versions": {"playerId": {"x,y,layer": int}, ...},
  "clock": "int"
}
```

### `door-unlock` (reliable, broadcast)
```json
{"type": "door-unlock", "doorX": "int", "doorY": "int"}
```

### `infra-health` / `infra-heal` / `infra-heal-result` / `infra-boot`
```json
// health heartbeat
{"ts": "ISO8601", "services": {"serviceId": {"s": "up|warn|down", "d": "detail"}, ...}}
// heal request
{"service": "string", "action": "restart"}
// heal result
{"service": "string", "ok": bool, "d": "detail"}
// boot sequence
{"sequence": [{"service": "string", "delay": int}, ...]}
```

### `dreamfinder-audio` (reliable, broadcast)
Raw PCM16 bytes (not JSON). Forwarded as base64 to iframe's `__onAudioChunk(base64)`.

### `dreamfinder-mood` (reliable, broadcast)
```json
{"mood": "string"}
// or interrupt:
{"type": "interrupt"}
```

---

## 3. Protocol Issues (Severity-Ranked)

### CRITICAL

**C1: `door-unlock` has no client-side subscriber**
- File: `lib/flame/tech_world.dart:1921`
- `unlockDoor()` broadcasts `door-unlock` but no Flutter client subscribes. Door state is purely local. Other players and late-joiners never see doors unlock.

**C2: No versioning on the wire protocol**
- No `version` field in any message. No handshake. No capability negotiation. Adding a required field breaks all deployed clients and bots.

**C3: `map-edit-sync` thundering herd**
- File: `lib/map_editor/map_sync_service.dart:554-565`, `660-668`
- Sync-request is broadcast. ALL editors respond with full snapshots. Joiner applies first, ignores rest. For N editors, N snapshots sent instead of one.

### HIGH

**H1: Message IDs use millisecond timestamps — collision risk**
- Files: `chat_service.dart:363`, `470`, `658`
- `DateTime.now().millisecondsSinceEpoch.toString()` — two rapid calls in same millisecond produce same ID, deduplicating the second message.

**H2: `oracle-response` not targeted — leaks to all participants**
- File: `oracle_service.dart:108-119`
- Request is targeted to bot, but response broadcasts to room. All participants receive all oracle responses.

**H3: `ping`/`pong` stream subscription leaks on publish failure**
- File: `livekit_service.dart:523-558`
- `pongFuture` subscription never drained if `publishJson` throws.

**H4: `infra-heal` is broadcast, not targeted to Dreamfinder**
- File: `infra_health_service.dart:112-115`
- Any bot receives heal requests. Only Dreamfinder should handle them.

**H5: `position` unreliable with no dead-reckoning fallback**
- File: `livekit_service.dart:476-481`
- Dropped packets leave remote players stuck mid-path with no timeout.

### MEDIUM

**M1: `map-info` sent to hardcoded bot identities, misses `agent-*` Dreamfinder**
- File: `livekit_service.dart:461`
- `allBotIdentities` is static. Dreamfinder joining as `agent-{jobId}` never receives map info.

**M2: `map-edit` op `old`/`new` fields ambiguous (absent vs null)**
- File: `map_edit_op.dart:74-81`
- `toJson()` omits null fields. `fromJson` treats absent and null identically. Fine internally, ambiguous for external observers.

**M3: Late bot response after chat timeout creates double message**
- File: `chat_service.dart:420-437`
- After 30s timeout message, a late bot response appears as an additional message.

**M4: `dreamfinder-audio` no early return for zero-length data**
- File: `dreamfinder_avatar_bridge_web.dart:233-243`
- Empty audio encoded and sent to iframe, may cause glitches.

**M5: `door-unlock` + no subscriber = late-joiners never see unlocked doors**
- Reinforces C1 — no sync mechanism for door state.

### LOW

**L1: `DataChannelMessage.json` swallows all parse errors silently**
- File: `livekit_service.dart:705-710`
- `catch (_)` returns null. No logging. Very hard to debug wire format issues.

**L2: `map-info-request` body undefined/ignored**
- File: `livekit_service.dart:134-135`
- Any payload triggers response. Minor spoofing concern.

**L3: `speech-transcript` unknown speaker values silently dropped**
- File: `tech_world.dart:1076-1079`
- No log for unrecognized speaker types.

**L4: `oracle-request` counter resets on service reconstruction**
- File: `oracle_service.dart:153-156`
- `_seq` resets to 0. Combined with microsecond timestamp, collisions extremely unlikely but possible.

---

## 4. Backward Compatibility Assessment

**No versioning exists.** The only implicit protection is `if (json == null) return;` null checks.

- **Adding a required field:** partial handling via `as String?`
- **Removing a field:** silent degradation via `?.`
- **Renaming a topic:** hard break, no fallback

**Critical crash risk:** `OpLayer.values.byName(json['layer'] as String)` in `map_edit_op.dart:65` throws `ArgumentError` on unrecognized layer names. This propagates uncaught through the CRDT sync stream listener, silently killing the sync loop.

---

## 5. Request-Response Correlation

| Pair | Correlation Key | Timeout | Leak on failure |
|------|----------------|---------|-----------------|
| `ping` / `pong` | `ping.id` == `pong.originalMessage.id` | 5s | Yes (stream sub) |
| `chat` / `chat-response` | `chat.id` == `chat-response.messageId` | 30s | No |
| `help-request` / `help-response` | `help-request.id` == `help-response.requestId` | 60s | No |
| `oracle-request` / `oracle-response` | `requestId` echo | 5s | No |
| `map-edit-sync` req / resp | `playerId` discriminator | 5s | Buffer may accumulate |

---

## 6. Race Conditions

| # | Condition | Handled? | Notes |
|---|-----------|----------|-------|
| RC1 | Dreamfinder joins before `onLoad` | Yes | `_pendingDreamfinderParticipant` deferred processing |
| RC2 | Bot `position` before `participant-joined` | Partial | PlayerComponent created with raw ID as display name, never updated |
| RC3 | Sync thundering herd | Functional | First response wins, but O(N) network waste |
| RC4 | Avatar update before `participant-joined` | Yes | Stored in `_pendingAvatars` |
| RC5 | Disconnect during pending chat | Functional | 30s timeout fires, leaves "thinking" state |
| RC6 | `map-edit` during sync buffering | Mostly | CRDT LWW may reject buffered edit if snapshot predates it |

---

## 7. Key File Locations

| File | Role |
|------|------|
| `lib/livekit/livekit_service.dart` | Central publish/subscribe hub, `DataChannelMessage`, all `publishX()` methods |
| `lib/flame/tech_world.dart` | Game world, subscribes to position, avatar, map-info-request, speech-transcript |
| `lib/chat/chat_service.dart` | chat, chat-response, dm, dm-response, help-request, help-response |
| `lib/map_editor/map_sync_service.dart` | map-edit, map-edit-sync CRDT protocol |
| `lib/infra/infra_health_service.dart` | infra-health, infra-heal, infra-heal-result, infra-boot |
| `lib/spellbook/oracle_service.dart` | oracle-request, oracle-response |
| `lib/livekit/dreamfinder_avatar_bridge_web.dart` | dreamfinder-audio, dreamfinder-mood (web only) |
| `lib/map_editor/crdt/map_edit_op.dart` | Wire schema for map-edit ops |
| `lib/bots/bot_config.dart` | Bot identity registry |

---

## 8. Top Priorities

1. **`door-unlock` has no subscriber** (C1) — door state never synchronizes
2. **No protocol versioning** (C2) — any schema change is a breaking deployment
3. **`map-edit-sync` thundering herd** (C3) — O(N) snapshots per sync request
4. **`OpLayer.values.byName` throws on unknown layer** — uncaught exception kills CRDT sync loop
5. **`map-info` misses `agent-*` Dreamfinder identity** (M1) — Dreamfinder may never receive map layout
6. **Message ID millisecond collisions** (H1) — deduplication eats rapid messages
