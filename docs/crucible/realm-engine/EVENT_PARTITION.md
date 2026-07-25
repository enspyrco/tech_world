# Event partition — the falsifier test (inline Heat finding)

**Falsifier (from CRUCIBLE.md):** if >~30% of the `AppEvent` subtypes are irreducibly bi-valent, the event system is NOT the clean first cut.

**Result: ORE SURVIVES.** 46 concrete subtypes partition as 61% engine / 33% game / 6.5% ambiguous. The ambiguity is one coherent subsystem (chat), not scattered bi-valence.

**Payload check (stronger than name-level):** borderline "engine" events carry PRIMITIVES, not game types — `PlayerMoved{int destX,destY}`, `AvatarSelected{String avatarId}` (NOT the `AvatarId` enum), `BotJoined{String identity}`, `UserSignedIn{String userId,displayName}`. The event layer is already game-agnostic in its payloads; extraction drags zero game types across. Only typed field on an engine event is `AvBubbleType` (a render-mode enum = infrastructure).

## ENGINE (28) — travel with the machinery

Movement/presence: `PlayerMoved`, `PlayerEnteredProximity`, `PlayerLeftProximity`
Room lifecycle: `RoomJoined`, `RoomLeft`, `RoomCreated`, `RoomDeleted`
Auth/identity presence: `UserSignedIn`, `UserSignedOut`, `ProfileUpdated`
Participant presence: `BotJoined`, `BotLeft`
Media/LiveKit infra: `LiveKitConnected`, `LiveKitDisconnected`, `MediaEnabled`, `ScreenShareToggled`
AV pipeline (11): `AvPipelineSnapshot`, `AvTrackSubscribed`, `AvTrackUnsubscribed`, `AvCaptureInitialized`, `AvCaptureInitFailed`, `AvBubbleCreated`, `AvBubbleRemoved`, `AvAudioGateChanged`, `AvVideoGateChanged`, `AvFrameDecodeError`, `AvSpeakingChanged`
Observability: `AppLogRecord`

## GAME (15) — stay in tech_world

Spellbook: `WordLearned`, `SpellCastFailed`
Challenges: `ChallengeCompleted`, `CodeSubmitted`
Doors: `DoorUnlocked`, `RemoteDoorUnlocked`
Terminals: `TerminalOpened`, `TerminalClosed`
Map editor: `MapEdited`, `MapEditorEntered`, `MapEditorExited`, `RoomMapSaved`
Avatar content: `AvatarSelected`
Bot personality: `BotSpoke`
Tutoring: `HelpRequested`

## AMBIGUOUS (3) — all chat; ONE design call

`PlayersMentioned`, `GroupMessageSent`, `DmSent`

These are the only bi-valent events, and they're all messaging. Not scattered ambiguity — a single subsystem question: **is chat engine or game?** Author lean: chat is a *feature* → game-side. tech_world keeps its chat events; the engine ships a messaging-agnostic core. Cage-match should strike this: a "generic multiplayer engine" arguably WANTS a chat primitive, so the counter-case is real.

## Design consequence

The engine event set is NOT "all 46 minus game" — it's a curated 28 that the extracted sinks already route on (`file_sink._isAvEvent`/`_isErrorEvent` switch over exactly the `Av*` + `LiveKit*` + `AppLogRecord` categories). This means the sinks come along as engine cleanly, because they route on the engine stratum. The game events become consumers of the engine's `AppEvent` contract via `abstract` (not `sealed`) — see CRUCIBLE.md crack #1.
