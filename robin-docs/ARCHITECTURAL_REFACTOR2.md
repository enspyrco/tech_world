# Architectural Refactor 2: Extract RoomSession from _MyAppState

**Branch:** `audit/extract-room-session`
**Effort:** Large
**Fixes:** CR-2 (god widget), ME-1 (duplicated connection), ME-3 (5× StreamBuilder), untestable orchestration

---

## Problem

`_MyAppState` (1734 lines, 20+ fields) manages the entire app lifecycle: Firebase init, auth, avatar selection, room join/leave/create/save/delete, LiveKit lifecycle, service registration, reconnect logic, 5 nested `StreamBuilder<AuthUser>`, and 6 overlay panels. The implicit state machine (unauthenticated → authenticated → joining → connected → reconnecting → leaving) is implemented as 12+ boolean flags and nullable fields.

The most extractable responsibility is **room session management** — the lifecycle of joining a room, creating services, connecting LiveKit, reconnecting on failure, and tearing down on leave. This is ~500 lines of `_MyAppState` that has clear entry/exit points and manages a well-defined set of services.

---

## Current Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                 _MyAppState (1734 lines)                      │
│                                                               │
│  Fields (20+):                                                │
│  ├─ _initialized, _loadingMessage, _progress                │
│  ├─ _liveKitService, _chatService, _proximityService        │
│  ├─ _progressService, _spellbookService                      │
│  ├─ _sttService, _speechCastService, _oracleService         │
│  ├─ _spellbookOpen, _mapEditorState, _chatCollapsed         │
│  ├─ _activeDmPeer, _chatMessageRepository, _spellSlotService│
│  ├─ _liveKitConnectionFailed, _connectionFailureMessage     │
│  ├─ _authSubscription, _connectionLostSubscription          │
│  ├─ _isReconnecting, _wireStates, _showJoinOverlay          │
│  ├─ _selectedAvatar, _avatarLoaded, _currentUserId          │
│  ├─ _isAnonymous, _currentDisplayName                       │
│  ├─ _currentProfilePictureUrl, _roomService, _myRooms       │
│  └─ _currentRoom                                             │
│                                                               │
│  Lifecycle Methods:                                           │
│  ├─ _initializeApp()           ← Firebase + service init     │
│  ├─ _onAuthStateChanged()      ← auth gate                  │
│  ├─ _joinRoom()                ← wire overlay join           │
│  ├─ _createServices()          ← service construction        │
│  ├─ _setupLiveKit()            ← non-overlay join            │
│  ├─ _leaveRoom()               ← teardown                   │
│  ├─ _listenForConnectionLoss() ← reconnect wiring           │
│  ├─ _handleConnectionLost()    ← reconnect logic            │
│  ├─ _failureMessageFor()       ← error messages             │
│  ├─ _onCreateRoom()            ← editor flow                │
│  ├─ _saveRoom()                ← persistence                │
│  ├─ _loadSavedRoom()           ← persistence                │
│  └─ _deleteSavedRoom()         ← persistence                │
│                                                               │
│  build() (~600 lines):                                       │
│  ├─ Loading screen                                            │
│  ├─ Auth gate                                                │
│  ├─ Avatar selection                                          │
│  ├─ Lobby (room browser)                                     │
│  ├─ GameWidget                                                │
│  ├─ StreamBuilder<AuthUser> ×5 (identical guards)            │
│  │   ├─ Map editor panel                                     │
│  │   ├─ Code editor panel                                    │
│  │   ├─ Prompt challenge panel                               │
│  │   ├─ Chat panel                                           │
│  │   └─ Spellbook panel                                      │
│  ├─ Toolbar (MapSelector, editor button, AuthMenu)           │
│  ├─ Join overlay                                              │
│  ├─ Screen share overlay                                      │
│  └─ Speech cast overlay                                       │
└─────────────────────────────────────────────────────────────┘

State machine (implicit in boolean flags):

  ┌──────────────────┐
  │  _initialized=F  │ Loading screen
  └────────┬─────────┘
           ▼
  ┌──────────────────┐
  │ _currentUserId   │ ← _onAuthStateChanged
  │   == null        │ Auth gate / sign-in
  └────────┬─────────┘
           ▼
  ┌──────────────────┐
  │ _avatarLoaded=F  │ Avatar picker
  └────────┬─────────┘
           ▼
  ┌──────────────────┐
  │ _currentRoom     │ Lobby (room browser)
  │   == null        │
  └────────┬─────────┘
           ▼
  ┌──────────────────┐   _showJoinOverlay=T
  │ _joinRoom()      │──────────────────────┐
  └────────┬─────────┘                      │
           ▼                                ▼
  ┌──────────────────┐         ┌──────────────────┐
  │ Connected        │         │ Join overlay      │
  │ _liveKitConn     │         │ (circuit board)   │
  │ Failed = F       │         └──────────────────┘
  └────────┬─────────┘
           │ connection lost
           ▼
  ┌──────────────────┐
  │ _isReconnecting  │ Banner + auto-retry
  │   = T            │
  └──────────────────┘
```

---

## Target Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              _MyAppState (~1100 lines)                        │
│              (renamed to _TechWorldAppState)                  │
│                                                               │
│  Fields:                                                      │
│  ├─ _initialized, _loadingMessage, _progress                │
│  ├─ _authSubscription                                        │
│  ├─ _selectedAvatar, _avatarLoaded                           │
│  ├─ _currentUserId, _isAnonymous, _currentDisplayName       │
│  ├─ _currentProfilePictureUrl                                │
│  ├─ _roomService, _myRooms                                   │
│  ├─ _progressService, _spellbookService                      │
│  ├─ _sttService, _speechCastService                         │
│  ├─ _spellbookOpen, _spellSlotService                       │
│  ├─ _mapEditorState                                          │
│  ├─ _chatCollapsed, _activeDmPeer                           │
│  └─ _session: RoomSession?      ← NEW: replaces 10+ fields │
│                                                               │
│  Methods:                                                     │
│  ├─ _initializeApp()                                         │
│  ├─ _onAuthStateChanged()                                    │
│  ├─ _joinRoom() → delegates to RoomSession.join()           │
│  ├─ _leaveRoom() → delegates to _session?.leave()           │
│  ├─ _onCreateRoom()                                          │
│  ├─ _saveRoom(), _loadSavedRoom(), _deleteSavedRoom()       │
│  └─ build() — single StreamBuilder, extracted child widgets  │
└────────────────────────────┬────────────────────────────────┘
                             │ owns
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                RoomSession (~350 lines)                       │
│                lib/rooms/room_session.dart                    │
│                                                               │
│  Final fields (set at construction):                          │
│  ├─ liveKitService: LiveKitService                           │
│  ├─ chatService: ChatService                                 │
│  ├─ chatMessageRepository: ChatMessageRepository             │
│  ├─ room: RoomData                                           │
│  ├─ userId: String                                           │
│  ├─ displayName: String                                      │
│                                                               │
│  Mutable state:                                               │
│  ├─ connectionFailed: ValueNotifier<bool>                    │
│  ├─ connectionMessage: ValueNotifier<String?>                │
│  ├─ isReconnecting: bool                                     │
│  ├─ _connectionLostSubscription: StreamSubscription?         │
│  └─ oracleService: OracleService?  (lazily created)          │
│                                                               │
│  Lifecycle:                                                   │
│  ├─ static join(room, userId, displayName) → RoomSession     │
│  │   Creates services, connects LiveKit, registers in Locator│
│  │   Returns a fully-connected session                       │
│  │                                                            │
│  ├─ reconnect() → Future<void>                               │
│  │   Auto-retry with 2s backoff                              │
│  │                                                            │
│  ├─ leave() → Future<void>                                   │
│  │   Disposal order: TechWorld subs → consumers → producers  │
│  │   Removes from Locator, nulls refs                        │
│  │                                                            │
│  └─ _failureMessageFor(ConnectionResult) → String            │
│      Centralised error message mapping                        │
│                                                               │
│  Testable in isolation:                                       │
│  ├─ Service creation with mock LiveKit                       │
│  ├─ Reconnection logic with simulated disconnect             │
│  ├─ Disposal order verification                               │
│  └─ State transitions (connected → lost → reconnecting)      │
└─────────────────────────────────────────────────────────────┘

State machine (now explicit in RoomSession lifecycle):

  _MyAppState                        RoomSession
  ──────────                        ───────────
  _session == null  ─── joinRoom() ──→  RoomSession.join()
                                         │
                                         ▼
                                    ┌──────────┐
                                    │ Connected │
                                    └─────┬────┘
                                          │ connectionLost
                                          ▼
                                    ┌──────────────┐
                                    │ Reconnecting │
                                    └─────┬────────┘
                                          │ success/fail
                                          ▼
                                    ┌──────────┐
  _session = null  ←── leave() ────│ Connected │
                                    └──────────┘
```

---

## What Moves

| From _MyAppState | To RoomSession | Notes |
|-----------------|----------------|-------|
| `_liveKitService` | `liveKitService` | Final, set at construction |
| `_chatService` | `chatService` | Final |
| `_chatMessageRepository` | `chatMessageRepository` | Final |
| `_liveKitConnectionFailed` | `connectionFailed` | ValueNotifier for UI |
| `_connectionFailureMessage` | `connectionMessage` | ValueNotifier for UI |
| `_isReconnecting` | `isReconnecting` | Internal state |
| `_connectionLostSubscription` | `_connectionLostSub` | Internal |
| `_oracleService` | `oracleService` | Lazily created per-room |
| `_wireStates` | (stays in _MyAppState) | UI concern, not session |
| `_showJoinOverlay` | (stays in _MyAppState) | UI concern |
| `_createServices()` | `RoomSession.join()` | Static factory |
| `_setupLiveKit()` | (merged into join) | Eliminated |
| `_listenForConnectionLoss()` | `_listenForLoss()` | Internal |
| `_handleConnectionLost()` | `reconnect()` | Public |
| `_failureMessageFor()` | `_failureMessageFor()` | Internal |
| `_leaveRoom()` (service teardown) | `leave()` | Public |

## What Stays in _MyAppState

- `_initialized`, `_loadingMessage`, `_progress` — app-level init
- `_authSubscription`, `_onAuthStateChanged()` — auth gate
- `_selectedAvatar`, `_avatarLoaded` — user profile
- `_currentUserId`, `_isAnonymous`, `_currentDisplayName` — user identity
- `_progressService`, `_spellbookService` — user-scoped (survive room changes)
- `_sttService`, `_speechCastService` — user-scoped
- `_roomService`, `_myRooms` — lobby
- `_mapEditorState` — editor (could move later)
- `_spellbookOpen`, `_chatCollapsed`, `_activeDmPeer` — UI state
- `_wireStates`, `_showJoinOverlay` — join overlay UI
- `_onCreateRoom()`, `_saveRoom()`, etc. — room persistence
- `build()` — widget tree

## Interface Between _MyAppState and RoomSession

```dart
// Joining:
Future<void> _joinRoom(RoomData room) async {
  final session = await RoomSession.join(
    room: room,
    userId: _currentUserId!,
    displayName: _currentDisplayName,
    onConnectionLost: (reason) => setState(() {}),  // trigger rebuild
  );
  setState(() {
    _session = session;
    _currentRoom = room;
  });
}

// Leaving:
Future<void> _leaveRoom() async {
  await _session?.leave();
  setState(() {
    _session = null;
    _currentRoom = null;
  });
}

// In build(), replace field access:
// OLD: _liveKitConnectionFailed
// NEW: _session?.connectionFailed.value ?? false
//
// OLD: _chatService
// NEW: _session?.chatService
//
// OLD: _oracleService
// NEW: _session?.oracleService
```

---

## Build Method Simplification

The 5 nested `StreamBuilder<AuthUser>` with identical guards become unnecessary. Currently each guards on `!snapshot.hasData || snapshot.data is SignedOutUser || _currentRoom == null`. With RoomSession, the guard becomes `_session != null`:

```dart
// BEFORE: 5 identical StreamBuilder<AuthUser> blocks
StreamBuilder<AuthUser>(
  stream: locate<AuthService>().authStateChanges,
  builder: (context, snapshot) {
    if (!snapshot.hasData || snapshot.data is SignedOutUser || 
        _currentRoom == null || _selectedAvatar == null) {
      return const SizedBox.shrink();
    }
    return MapEditorPanel(...);  // or ChatPanel, CodeEditorPanel, etc.
  },
)

// AFTER: simple null check, extracted widgets
if (_session != null) ...[
  _MapEditorSection(session: _session!, ...),
  _CodeEditorSection(session: _session!, ...),
  _ChatSection(session: _session!, ...),
  // etc.
]
```

---

## Migration Steps

1. Create `lib/rooms/room_session.dart` with the class shell
2. Move `_failureMessageFor()` first (already extracted in PR11, just relocate)
3. Add `RoomSession.join()` factory — initially just wraps `_createServices()`
4. Move service fields one at a time (`_liveKitService`, `_chatService`, etc.)
5. Move `_handleConnectionLost()` → `reconnect()`
6. Move teardown from `_leaveRoom()` → `leave()`
7. Replace `_liveKitConnectionFailed` / `_connectionFailureMessage` with ValueNotifiers on RoomSession
8. Update `build()` references from `_liveKitService` → `_session?.liveKitService`
9. Extract widget sections from build() (optional but recommended)
10. Rename `MyApp` → `TechWorldApp` (bonus cleanup)
11. Run `flutter analyze` + `flutter test` after each step

## Testability Gains

After extraction, RoomSession can be tested with:
- **Service creation**: verify `LiveKitService`, `ChatService` are created with correct params
- **Connection lifecycle**: mock LiveKit, verify `connect()` → `connected` state
- **Reconnection**: simulate `connectionLost` event, verify 2s delay → retry → state update
- **Disposal order**: verify consumers disposed before producers
- **State transitions**: verify `connectionFailed` ValueNotifier updates correctly

None of these tests exist today because all logic is entangled in `_MyAppState.build()`.

---

## Ordering

**Do Refactor 1 (BubbleManager) first.** It's more self-contained and doesn't affect `main.dart`. Refactor 2 touches `main.dart` extensively, so any in-flight changes to that file should land first.
