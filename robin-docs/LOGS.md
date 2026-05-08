# Event Logging — Quick Reference

## What Gets Logged

### Domain events (34 types, 40 dispatch sites across 10 files)

#### Cast / Spellbook (3 types)
| Event | Trigger | Data |
|-------|---------|------|
| `WordLearned` | Player completes a prompt challenge | word ID, challenge ID |
| `ChallengeCompleted` | Player completes any challenge | challenge ID (wire format) |
| `SpellCastFailed` | Voice-cast at a door fails | reason (noMatch/notLearned/wrongDoor), transcript |

#### Game World (7 types)
| Event | Trigger | Data |
|-------|---------|------|
| `DoorUnlocked` | All required challenges satisfied | door coordinates |
| `RemoteDoorUnlocked` | Another player unlocked a door (via LiveKit) | door coordinates |
| `PlayerMoved` | Player clicks to move | destination grid coordinates |
| `TerminalOpened` | Player opens a code or prompt terminal | challenge ID, terminal position |
| `TerminalClosed` | Player closes the terminal editor | — |
| `AvatarSelected` | Player picks an avatar | avatar ID |
| `MediaEnabled` | Camera and mic enabled for room | — |

#### Room Lifecycle (5 types)
| Event | Trigger | Data |
|-------|---------|------|
| `RoomJoined` | Player joins a room (all wires complete) | room ID, room name |
| `RoomLeft` | Player leaves a room | room ID |
| `RoomCreated` | New room saved to Firestore | room ID, room name |
| `RoomMapSaved` | Existing room map updated in Firestore | room ID, room name |
| `RoomDeleted` | Owner deletes a room | room ID, room name |

#### Authentication (3 types)
| Event | Trigger | Data |
|-------|---------|------|
| `UserSignedIn` | Firebase auth completes | user ID, display name |
| `UserSignedOut` | User signs out | — |
| `ProfileUpdated` | User saves profile in edit dialog | display name |

#### Code Editor (1 type)
| Event | Trigger | Data |
|-------|---------|------|
| `CodeSubmitted` | Player submits code for bot evaluation | challenge ID, result (pass/fail/timeout) |

#### Map Editor (3 types)
| Event | Trigger | Data |
|-------|---------|------|
| `MapEditorEntered` | Player enters map editor mode | map ID, map name |
| `MapEditorExited` | Player exits map editor mode | applied (bool) |
| `MapEdited` | Any CRDT map edit operation | action (8 variants), coordinates |

#### Multiplayer (7 types)
| Event | Trigger | Data |
|-------|---------|------|
| `PlayerEnteredProximity` | Another player enters Chebyshev range | player ID |
| `PlayerLeftProximity` | Another player leaves range (or disconnects) | player ID |
| `BotJoined` | Bot participant joins the room | identity |
| `BotLeft` | All bots leave the room | — |
| `ScreenShareToggled` | Player starts or stops screen sharing | started (bool) |
| `LiveKitConnected` | WebRTC connection established | room name |
| `LiveKitDisconnected` | WebRTC connection lost | reason |

#### Chat (4 types)
| Event | Trigger | Data |
|-------|---------|------|
| `GroupMessageSent` | Player sends a group chat message | message ID, challenge ID (if submission) |
| `DmSent` | Player sends a DM | peer ID, conversation ID |
| `HelpRequested` | Player asks Clawd for a hint | challenge ID |
| `BotSpoke` | Clawd sends a chat response or help hint | text, context (group/help) |

#### Log Bridge (1 type)
| Event | Trigger | Data |
|-------|---------|------|
| `AppLogRecord` | Any `_log.info/warning/severe/fine` call (~80 sites) | logger name, severity, message, error, stack trace |

## Dispatch Sites

| File | Events dispatched | Count |
|------|-------------------|-------|
| `lib/main.dart` | UserSignedIn, UserSignedOut, RoomJoined, RoomLeft, RoomCreated, RoomMapSaved, RoomDeleted, AvatarSelected, CodeSubmitted, ScreenShareToggled, AppLogRecord | 12 |
| `lib/flame/tech_world.dart` | PlayerMoved, TerminalOpened (×2), TerminalClosed, DoorUnlocked, RemoteDoorUnlocked, MapEditorEntered, MapEditorExited | 8 |
| `lib/chat/chat_service.dart` | BotJoined, BotLeft, BotSpoke (×2), GroupMessageSent, DmSent, HelpRequested | 7 |
| `lib/map_editor/map_sync_service.dart` | MapEdited (via _pushAndPublish + undo + redo) | 3 |
| `lib/proximity/proximity_service.dart` | PlayerEnteredProximity, PlayerLeftProximity (×3) | 3 |
| `lib/spellbook/speech_cast_overlay.dart` | SpellCastFailed (×3 failure variants) | 3 |
| `lib/livekit/livekit_service.dart` | LiveKitConnected, LiveKitDisconnected | 2 |
| `lib/rooms/room_session.dart` | MediaEnabled | 1 |
| `lib/spellbook/cast_effects.dart` | WordLearned, ChallengeCompleted (via dispatch) | 1 |
| `lib/widgets/edit_profile_dialog.dart` | ProfileUpdated | 1 |
| **Total** | | **40** |

## Where They Go

| Sink | Platforms | Condition | Format |
|------|-----------|-----------|--------|
| Console (`debugPrint`) | All | `kDebugMode` only | `[event] PlayerMoved: → (12, 8)` |
| File (`events.log`) | macOS, iOS, Android | Always (not web) | JSONL — one JSON object per line |
| `developer.log` | All | Always | DevTools / debug console (existing, unchanged) |

### File location

- **macOS:** `~/Library/Application Support/tech_world_logs/events.log`
- **iOS/Android:** app documents directory (via `path_provider`)
- **Web:** no file sink — console only

### Tailing the log (macOS)

```bash
# All events
tail -f ~/Library/Application\ Support/tech_world_logs/events.log | python3 -m json.tool

# Domain events only (skip log bridge)
tail -f ~/Library/Application\ Support/tech_world_logs/events.log | grep -v '"type":"log"' | python3 -m json.tool

# Warnings and errors only
tail -f ~/Library/Application\ Support/tech_world_logs/events.log | grep -E '"severity":"(warning|severe)"' | python3 -m json.tool

# Specific event types
tail -f ~/Library/Application\ Support/tech_world_logs/events.log | grep '"type":"map_edited"'
tail -f ~/Library/Application\ Support/tech_world_logs/events.log | grep '"type":"code_submitted"'
tail -f ~/Library/Application\ Support/tech_world_logs/events.log | grep '"type":"spell_cast_failed"'
```

### Example session log

```json
{"type":"user_signed_in","userId":"abc123","displayName":"Robin","timestamp":"2026-05-08T14:30:00.000"}
{"type":"avatar_selected","avatarId":"wizard_blue","timestamp":"2026-05-08T14:30:02.000"}
{"type":"room_joined","roomId":"wiz_tower_01","roomName":"The Wizard's Tower","timestamp":"2026-05-08T14:30:05.123"}
{"type":"livekit_connected","roomName":"l_room","timestamp":"2026-05-08T14:30:06.000"}
{"type":"media_enabled","timestamp":"2026-05-08T14:30:06.500"}
{"type":"bot_joined","identity":"bot-claude","timestamp":"2026-05-08T14:30:07.000"}
{"type":"player_moved","destX":12,"destY":8,"timestamp":"2026-05-08T14:30:10.789"}
{"type":"player_entered_proximity","playerId":"user_456","timestamp":"2026-05-08T14:30:12.000"}
{"type":"terminal_opened","challengeId":"evocation_fizzbuzz","terminalX":15,"terminalY":10,"timestamp":"2026-05-08T14:31:00.000"}
{"type":"code_submitted","challengeId":"evocation_fizzbuzz","result":"pass","timestamp":"2026-05-08T14:31:45.000"}
{"type":"terminal_closed","timestamp":"2026-05-08T14:31:46.000"}
{"type":"word_learned","wordId":"ignis","challengeId":"evocation_fizzbuzz","timestamp":"2026-05-08T14:32:30.000"}
{"type":"challenge_completed","challengeId":"evocation_fizzbuzz","timestamp":"2026-05-08T14:32:30.100"}
{"type":"door_unlocked","doorX":20,"doorY":5,"timestamp":"2026-05-08T14:32:31.000"}
{"type":"remote_door_unlocked","doorX":30,"doorY":15,"timestamp":"2026-05-08T14:32:45.000"}
{"type":"spell_cast_failed","reason":"noMatch","transcript":"flambe","timestamp":"2026-05-08T14:33:00.000"}
{"type":"group_message_sent","messageId":"1715178785123456","timestamp":"2026-05-08T14:33:01.000"}
{"type":"bot_spoke","text":"Welcome, wizard!","context":"group","timestamp":"2026-05-08T14:33:05.000"}
{"type":"help_requested","challengeId":"evocation_countdown","timestamp":"2026-05-08T14:33:20.000"}
{"type":"dm_sent","peerId":"user_456","conversationId":"abc123_user_456","timestamp":"2026-05-08T14:33:30.000"}
{"type":"map_editor_entered","mapId":"wizards_tower","mapName":"The Wizard's Tower","timestamp":"2026-05-08T14:34:00.000"}
{"type":"map_edited","action":"paintWall","x":25,"y":12,"timestamp":"2026-05-08T14:34:15.000"}
{"type":"map_edited","action":"undo","x":25,"y":12,"timestamp":"2026-05-08T14:34:17.000"}
{"type":"room_map_saved","roomId":"wiz_tower_01","roomName":"The Wizard's Tower","timestamp":"2026-05-08T14:34:30.000"}
{"type":"map_editor_exited","applied":true,"timestamp":"2026-05-08T14:34:31.000"}
{"type":"profile_updated","displayName":"Robin the Magnificent","timestamp":"2026-05-08T14:35:00.000"}
{"type":"screen_share_toggled","started":true,"timestamp":"2026-05-08T14:36:00.000"}
{"type":"screen_share_toggled","started":false,"timestamp":"2026-05-08T14:36:30.000"}
{"type":"player_left_proximity","playerId":"user_456","timestamp":"2026-05-08T14:37:00.000"}
{"type":"bot_left","timestamp":"2026-05-08T14:37:30.000"}
{"type":"livekit_disconnected","timestamp":"2026-05-08T14:38:00.000"}
{"type":"room_left","roomId":"wiz_tower_01","timestamp":"2026-05-08T14:38:00.100"}
{"type":"room_created","roomId":"new_room_02","roomName":"Robin's Lab","timestamp":"2026-05-08T14:39:00.000"}
{"type":"room_deleted","roomId":"new_room_02","roomName":"Robin's Lab","timestamp":"2026-05-08T14:40:00.000"}
{"type":"user_signed_out","timestamp":"2026-05-08T14:41:00.000"}
```

## Architecture

```
_log.info(...)  ──→ Logger.root.onRecord ──→ developer.log (DevTools)
                                           └→ AppLogRecord ──→ dispatch()
                                                                  │
Business logic  ──→ dispatch([WordLearned, ...]) ─────────────────┤
Game world      ──→ dispatch([PlayerMoved, DoorUnlocked, ...]) ───┤
Room lifecycle  ──→ dispatch([RoomJoined, RoomCreated, ...]) ─────┤
Map editor      ──→ dispatch([MapEdited, MapEditorEntered, ...]) ─┤
Multiplayer     ──→ dispatch([BotJoined, LiveKitConnected, ...]) ─┤
Chat            ──→ dispatch([GroupMessageSent, DmSent, ...]) ────┤
Auth            ──→ dispatch([UserSignedIn, AvatarSelected, ...]) ┤
                                                                  │
                                                           registered sinks
                                                            ├─ consoleSink (dev)
                                                            └─ fileSink (native)
```

## Not Yet Included

- **Crashlytics sink** — ready to add once `firebase_crashlytics` is in pubspec.
- **Free casting** — Phase 3 not yet wired. When it is, `FreeCastResult` outcomes should dispatch events.
- **Spell slot consumption/regen** — internal timer mechanics, excluded to reduce noise.
- **Log rotation** — not implemented. App storage is OS-managed.
- **Room browser** — lobby browsing/searching not logged (low value).

## Key Files

| File | Purpose |
|------|---------|
| `lib/events/types.dart` | Sealed `AppEvent` class + 34 event types + `toJson()` |
| `lib/events/dispatch.dart` | `registerSink()`, `dispatch()`, `clearSinks()` |
| `lib/events/sinks/console_sink.dart` | Dev console sink (31-arm exhaustive switch) |
| `lib/events/sinks/file_sink.dart` | JSONL file sink (native) |
| `lib/events/sinks/file_sink_stub.dart` | Web no-op stub |
