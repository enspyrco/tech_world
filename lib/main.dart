import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tech_world/auth/auth_gate.dart';
import 'package:tech_world/auth/auth_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:tech_world/auth/auth_user.dart';
import 'package:tech_world/avatar/avatar.dart';
import 'package:tech_world/avatar/avatar_selection_screen.dart';
import 'package:tech_world/avatar/predefined_avatars.dart';
import 'package:tech_world/auth/user_profile_service.dart';
import 'package:tech_world/chat/chat_panel.dart';
import 'package:tech_world/chat/chat_service.dart';
import 'package:tech_world/editor/challenge.dart';
import 'package:tech_world/editor/code_editor_panel.dart';
import 'package:tech_world/editor/predefined_challenges.dart';
import 'package:tech_world/flame/tech_world.dart';
import 'package:tech_world/flame/tech_world_game.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/livekit/widgets/proximity_video_overlay.dart';
import 'package:tech_world/progress/progress_service.dart';
import 'package:tech_world/map_editor/map_editor_panel.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';
import 'package:tech_world/proximity/proximity_service.dart';
import 'package:tech_world/rooms/room_browser.dart';
import 'package:tech_world/rooms/room_data.dart';
import 'package:tech_world/rooms/room_service.dart';
import 'package:tech_world/widgets/auth_menu.dart';
import 'package:tech_world/widgets/loading_screen.dart';
import 'firebase_options.dart';
import 'package:tech_world/utils/locator.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _initialized = false;
  String _loadingMessage = 'Initializing...';
  double? _progress;
  LiveKitService? _liveKitService;
  ChatService? _chatService;
  ProximityService? _proximityService;
  ProgressService? _progressService;
  final MapEditorState _mapEditorState = MapEditorState();
  final ValueNotifier<bool> _chatCollapsed = ValueNotifier<bool>(false);
  bool _liveKitConnectionFailed = false;
  Avatar? _selectedAvatar;
  bool _avatarLoaded = false;
  String? _currentUserId;
  String _currentDisplayName = '';
  RoomService? _roomService;

  /// The room the user is currently inside. Null = lobby view.
  RoomData? _currentRoom;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Stage 1: Initialize Firebase
    setState(() {
      _loadingMessage = 'Connecting to Firebase...';
      _progress = 0.2;
    });

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Stage 2: Initialize services
    setState(() {
      _loadingMessage = 'Setting up services...';
      _progress = 0.5;
    });

    final authService = AuthService();

    // Stage 3: Initialize game world
    setState(() {
      _loadingMessage = 'Loading game world...';
      _progress = 0.7;
    });

    final techWorld = TechWorld(
      authStateChanges: authService.authStateChanges,
    );
    final techWorldGame = TechWorldGame(world: techWorld);

    // Stage 4: Register services
    setState(() {
      _loadingMessage = 'Almost ready...';
      _progress = 0.9;
    });

    Locator.add<AuthService>(authService);
    Locator.add<TechWorld>(techWorld);
    Locator.add<TechWorldGame>(techWorldGame);

    // Listen for auth changes to set up LiveKit when user signs in
    authService.authStateChanges.listen(_onAuthStateChanged);

    // Complete
    setState(() {
      _loadingMessage = 'Ready!';
      _progress = 1.0;
    });

    // Brief delay to show completion
    await Future.delayed(const Duration(milliseconds: 200));

    setState(() {
      _initialized = true;
    });
  }

  Future<void> _onAuthStateChanged(AuthUser user) async {
    if (user is SignedOutUser) {
      // User signed out — tear down everything.
      _leaveRoom();
      _progressService?.dispose();
      _progressService = null;
      Locator.remove<ProgressService>();
      _roomService = null;
      Locator.remove<RoomService>();
      _liveKitConnectionFailed = false;
      _selectedAvatar = null;
      _avatarLoaded = false;
      _currentUserId = null;
      _currentDisplayName = '';
      _currentRoom = null;
      debugPrint('User signed out - cleaned up');
      setState(() {});
    } else {
      // User signed in — set up profile & services, show lobby.
      debugPrint('User signed in: ${user.id} (${user.displayName})');
      _currentUserId = user.id;
      _currentDisplayName = user.displayName;

      // Load saved avatar from Firestore
      try {
        final profileService = UserProfileService();
        final savedAvatarId = await profileService.getAvatarId(user.id);
        if (savedAvatarId != null) {
          _selectedAvatar = avatarById(savedAvatarId) ?? defaultAvatar;
        }
      } catch (e) {
        debugPrint('Failed to load avatar: $e');
      }
      _avatarLoaded = true;

      // Load challenge progression
      _progressService = ProgressService(uid: user.id);
      try {
        await _progressService!.loadProgress();
      } catch (e) {
        debugPrint('Failed to load progress: $e');
      }
      Locator.add<ProgressService>(_progressService!);
      locate<TechWorld>().refreshTerminalStates();

      // Register RoomService for the lobby.
      _roomService = RoomService();
      Locator.add<RoomService>(_roomService!);

      setState(() {}); // Show lobby (or avatar picker first).
    }
  }

  /// Join a room — load map and connect to LiveKit.
  Future<void> _joinRoom(RoomData room) async {
    final userId = _currentUserId;
    final displayName = _currentDisplayName;
    if (userId == null) return;

    _currentRoom = room;
    _mapEditorState.setRoomId(room.id);

    // Load the room's map into the game world.
    await locate<TechWorld>().loadMap(room.mapData);

    // Create and connect LiveKit using the room ID as LiveKit room name.
    _liveKitService = LiveKitService(
      userId: userId,
      displayName: displayName,
      roomName: room.id,
    );
    _chatService = ChatService(liveKitService: _liveKitService!);
    _proximityService = ProximityService();

    Locator.add<LiveKitService>(_liveKitService!);
    Locator.add<ChatService>(_chatService!);
    Locator.add<ProximityService>(_proximityService!);

    final connected = await _liveKitService!.connect();
    debugPrint('LiveKit connected to room ${room.id}: $connected');

    if (connected) {
      await locate<TechWorld>().connectToLiveKit(userId, displayName);
      await _liveKitService!.setCameraEnabled(true);
      await _liveKitService!.setMicrophoneEnabled(true);
    } else {
      _liveKitConnectionFailed = true;
    }

    // Apply saved avatar to game world.
    if (_selectedAvatar != null) {
      locate<TechWorld>().setLocalAvatar(_selectedAvatar!);
    }

    setState(() {});
  }

  /// Leave the current room — disconnect LiveKit and return to lobby.
  void _leaveRoom() {
    if (_currentRoom == null) return;

    _liveKitService?.dispose();
    _chatService?.dispose();
    _proximityService?.dispose();
    _liveKitService = null;
    _chatService = null;
    _proximityService = null;
    _liveKitConnectionFailed = false;
    Locator.remove<LiveKitService>();
    Locator.remove<ChatService>();
    Locator.remove<ProximityService>();
    _currentRoom = null;
    _mapEditorState.setRoomId(null);

    // Exit editor mode if active.
    final techWorld = locate<TechWorld>();
    if (techWorld.mapEditorActive.value) {
      techWorld.exitEditorMode();
    }

    setState(() {});
  }

  /// Create a new room — enter editor with empty map, then save.
  Future<void> _onCreateRoom() async {
    // Jump into a temporary "new room" in the game with a blank map
    // and open the editor. The save button will create the Firestore doc.
    _mapEditorState.clearAll();
    _mapEditorState.setRoomId(null);
    _mapEditorState.setMapName('New Room');
    _mapEditorState.setMapId('new_room');

    // Use a transient room so the user can see the editor.
    // We load the blank map into the game world.
    final blankMap = _mapEditorState.toGameMap();
    _currentRoom = RoomData(
      id: '',
      name: 'New Room',
      ownerId: _currentUserId ?? '',
      ownerDisplayName: _currentDisplayName,
      mapData: blankMap,
    );

    await locate<TechWorld>().loadMap(blankMap);
    locate<TechWorld>().enterEditorMode(_mapEditorState);

    setState(() {});
  }

  /// Save the current editor state as a room. Creates a new room or updates existing.
  Future<void> _saveRoom() async {
    final userId = _currentUserId;
    if (userId == null || _roomService == null) return;

    final gameMap = _mapEditorState.toGameMap();

    if (_mapEditorState.roomId != null && _mapEditorState.roomId!.isNotEmpty) {
      // Update existing room.
      await _roomService!.updateRoomMap(_mapEditorState.roomId!, gameMap);
      await _roomService!.updateRoomName(
        _mapEditorState.roomId!,
        _mapEditorState.mapName,
      );
      // Update local state.
      _currentRoom = _currentRoom?.copyWith(
        name: _mapEditorState.mapName,
        mapData: gameMap,
      );
    } else {
      // Create new room.
      final room = await _roomService!.createRoom(
        name: _mapEditorState.mapName,
        ownerId: userId,
        ownerDisplayName: _currentDisplayName,
        map: gameMap,
      );
      _mapEditorState.setRoomId(room.id);
      _currentRoom = room;

      // Now connect LiveKit for the new room.
      if (_liveKitService == null) {
        _liveKitService = LiveKitService(
          userId: userId,
          displayName: _currentDisplayName,
          roomName: room.id,
        );
        _chatService = ChatService(liveKitService: _liveKitService!);
        _proximityService = ProximityService();

        Locator.add<LiveKitService>(_liveKitService!);
        Locator.add<ChatService>(_chatService!);
        Locator.add<ProximityService>(_proximityService!);

        final connected = await _liveKitService!.connect();
        if (connected) {
          await locate<TechWorld>()
              .connectToLiveKit(userId, _currentDisplayName);
          await _liveKitService!.setCameraEnabled(true);
          await _liveKitService!.setMicrophoneEnabled(true);
        }

        if (_selectedAvatar != null) {
          locate<TechWorld>().setLocalAvatar(_selectedAvatar!);
        }
      }
    }

    setState(() {});
  }

  /// Called when the user confirms an avatar choice from the selection screen.
  Future<void> _onAvatarSelected(Avatar avatar) async {
    _selectedAvatar = avatar;

    // Save to Firestore
    if (_currentUserId != null) {
      try {
        final profileService = UserProfileService();
        await profileService.saveAvatarId(_currentUserId!, avatar.id);
      } catch (e) {
        debugPrint('Failed to save avatar: $e');
      }
    }

    // Apply to game world (also broadcasts via LiveKit)
    locate<TechWorld>().setLocalAvatar(avatar);

    setState(() {}); // Transition from selection screen to game
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return MaterialApp(
        home: LoadingScreen(
          message: _loadingMessage,
          progress: _progress,
        ),
      );
    }

    return MaterialApp(
      home: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Row(
                  children: [
                    Visibility(
                      visible: constraints.maxWidth >= 1200,
                      child: Expanded(
                        child: Container(
                          height: double.infinity,
                          color: Theme.of(context).colorScheme.primary,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Welcome to Tech World',
                                  style:
                                      Theme.of(context).textTheme.headlineMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: StreamBuilder<AuthUser>(
                        stream: locate<AuthService>().authStateChanges,
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const LoadingScreen(
                              message: 'Checking authentication...',
                            );
                          }
                          if (snapshot.data! is! SignedOutUser) {
                            // Show avatar selection if signed in but no avatar chosen yet
                            if (_avatarLoaded && _selectedAvatar == null) {
                              return AvatarSelectionScreen(
                                onAvatarSelected: _onAvatarSelected,
                              );
                            }
                            // Show room browser (lobby) if not in a room
                            if (_currentRoom == null && _roomService != null) {
                              return RoomBrowser(
                                roomService: _roomService!,
                                userId: _currentUserId!,
                                onJoinRoom: _joinRoom,
                                onCreateRoom: _onCreateRoom,
                              );
                            }
                            return Stack(
                              children: [
                                GameWidget(
                                  game: locate<TechWorldGame>(),
                                ),
                                // Video bubble overlay using native Flutter rendering
                                if (_liveKitService?.room != null &&
                                    _proximityService != null)
                                  ProximityVideoOverlay(
                                    room: _liveKitService!.room!,
                                    techWorld: locate<TechWorld>(),
                                    proximityService: _proximityService!,
                                  ),
                              ],
                            );
                          }
                          return const AuthGate();
                        },
                      ),
                    ),
                    // Side panel - map editor or chat (hidden in lobby)
                    StreamBuilder<AuthUser>(
                      stream: locate<AuthService>().authStateChanges,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData ||
                            snapshot.data is SignedOutUser ||
                            _currentRoom == null) {
                          return const SizedBox.shrink();
                        }
                        final techWorld = locate<TechWorld>();
                        return ValueListenableBuilder<bool>(
                          valueListenable: techWorld.mapEditorActive,
                          builder: (context, editorActive, _) {
                            if (editorActive) {
                              final canEdit = _currentRoom != null &&
                                  _currentUserId != null &&
                                  _currentRoom!.canEdit(_currentUserId!);
                              return SizedBox(
                                width: constraints.maxWidth >= 800 ? 480 : 360,
                                child: MapEditorPanel(
                                  state: _mapEditorState,
                                  onClose: techWorld.exitEditorMode,
                                  referenceMap: techWorld.currentMap.value,
                                  playerPosition:
                                      techWorld.playerGridPosition,
                                  onSave: canEdit ? _saveRoom : null,
                                  canEdit: canEdit,
                                ),
                              );
                            }
                            // Show chat panel
                            final chatService =
                                Locator.maybeLocate<ChatService>();
                            if (chatService == null) {
                              return SizedBox(
                                width:
                                    constraints.maxWidth >= 800 ? 320 : 280,
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            return ValueListenableBuilder<bool>(
                              valueListenable: _chatCollapsed,
                              builder: (context, collapsed, _) {
                                if (collapsed) {
                                  return Container(
                                    width: 48,
                                    color: const Color(0xFF2D2D2D),
                                    child: Align(
                                      alignment: Alignment.topCenter,
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(top: 12),
                                        child: IconButton(
                                          onPressed: () =>
                                              _chatCollapsed.value = false,
                                          icon:
                                              const Icon(Icons.chat_bubble),
                                          color: const Color(0xFFD97757),
                                          tooltip: 'Open chat',
                                          style: IconButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFFD97757)
                                                    .withValues(
                                                        alpha: 0.1),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                return SizedBox(
                                  width: constraints.maxWidth >= 800
                                      ? 320
                                      : 280,
                                  child: ChatPanel(
                                    chatService: chatService,
                                    onCollapse: () =>
                                        _chatCollapsed.value = true,
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
                // Toolbar — top right when in a room
                StreamBuilder<AuthUser>(
                  stream: locate<AuthService>().authStateChanges,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData ||
                        snapshot.data is SignedOutUser ||
                        _currentRoom == null) {
                      return const SizedBox.shrink();
                    }
                    return ValueListenableBuilder<bool>(
                      valueListenable: _chatCollapsed,
                      builder: (context, chatCollapsed, child) {
                    final techWorld = locate<TechWorld>();
                    // Toolbar offset depends on what's showing in the side panel
                    final double toolbarRight;
                    if (techWorld.mapEditorActive.value) {
                      toolbarRight = (constraints.maxWidth >= 800 ? 480 : 360) + 16;
                    } else if (chatCollapsed) {
                      toolbarRight = 64;
                    } else {
                      toolbarRight = constraints.maxWidth >= 800 ? 336 : 296;
                    }
                    return Positioned(
                      top: 16,
                      right: toolbarRight,
                      child: SafeArea(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Leave room button
                            IconButton(
                              onPressed: _leaveRoom,
                              icon: const Icon(Icons.arrow_back,
                                  color: Colors.white70, size: 20),
                              tooltip: 'Leave room',
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black54,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Room name indicator
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.meeting_room,
                                      color: Colors.white70, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    _currentRoom?.name ?? '',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _MapEditorButton(
                              mapEditorState: _mapEditorState,
                              techWorld: locate<TechWorld>(),
                            ),
                            const SizedBox(width: 8),
                            AuthMenu(
                              displayName: snapshot.data!.displayName,
                            ),
                          ],
                        ),
                      ),
                    );
                      },
                    );
                  },
                ),
                // Code editor modal overlay
                StreamBuilder<AuthUser>(
                  stream: locate<AuthService>().authStateChanges,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData ||
                        snapshot.data is SignedOutUser ||
                        _currentRoom == null) {
                      return const SizedBox.shrink();
                    }
                    final techWorld = locate<TechWorld>();
                    return ValueListenableBuilder<String?>(
                      valueListenable: techWorld.activeChallenge,
                      builder: (context, challengeId, _) {
                        if (challengeId == null) {
                          return const SizedBox.shrink();
                        }
                        final challenge = allChallenges.firstWhere(
                          (c) => c.id == challengeId,
                          orElse: () => allChallenges.first,
                        );
                        final isCompleted = Locator.maybeLocate<
                                    ProgressService>()
                                ?.isChallengeCompleted(challenge.id) ??
                            false;
                        return _CodeEditorModal(
                          challenge: challenge,
                          isCompleted: isCompleted,
                          onClose: techWorld.closeEditor,
                          onHelpRequest: (code) async {
                            final chatService =
                                Locator.maybeLocate<ChatService>();
                            if (chatService == null) return null;

                            final terminalPos =
                                techWorld.activeTerminalPosition.value;
                            return chatService.requestHelp(
                              challengeId: challenge.id,
                              challengeTitle: challenge.title,
                              challengeDescription: challenge.description,
                              code: code,
                              terminalX: terminalPos?.x ?? 0,
                              terminalY: terminalPos?.y ?? 0,
                            );
                          },
                          onSubmit: (code) async {
                            // Close the editor immediately so the player
                            // returns to the game while waiting for Clawd.
                            techWorld.closeEditor();

                            final chatService =
                                Locator.maybeLocate<ChatService>();
                            if (chatService == null) return;

                            final response = await chatService.sendMessage(
                              'Please review my "${challenge.title}" '
                              'solution:\n\n```dart\n$code\n```',
                              metadata: {'challengeId': challenge.id},
                            );

                            // Only mark completed when bot confirms pass
                            if (response?['challengeResult'] == 'pass') {
                              try {
                                await Locator.maybeLocate<ProgressService>()
                                    ?.markChallengeCompleted(challenge.id);
                              } catch (e) {
                                debugPrint('Failed to persist completion: $e');
                                // Rollback already handled by ProgressService.
                              }
                              techWorld.refreshTerminalStates();
                            }
                          },
                        );
                      },
                    );
                  },
                ),
                // Connection failure banner
                if (_liveKitConnectionFailed)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade800,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.wifi_off, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Video & chat unavailable — connection failed',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Toggle button for entering/exiting map editor mode.
class _MapEditorButton extends StatelessWidget {
  const _MapEditorButton({
    required this.mapEditorState,
    required this.techWorld,
  });

  final MapEditorState mapEditorState;
  final TechWorld techWorld;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: techWorld.mapEditorActive,
      builder: (context, active, _) {
        return IconButton(
          onPressed: () {
            if (active) {
              techWorld.exitEditorMode();
            } else {
              techWorld.enterEditorMode(mapEditorState);
            }
          },
          icon: Icon(
            Icons.grid_on,
            color: active ? const Color(0xFF4444FF) : Colors.white70,
            size: 20,
          ),
          tooltip: active ? 'Close map editor' : 'Open map editor',
          style: IconButton.styleFrom(
            backgroundColor:
                active ? const Color(0xFF4444FF).withValues(alpha: 0.2) : Colors.black54,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      },
    );
  }
}

/// Modal overlay that displays the code editor centered on screen with a scrim.
class _CodeEditorModal extends StatelessWidget {
  const _CodeEditorModal({
    required this.challenge,
    required this.isCompleted,
    required this.onClose,
    required this.onSubmit,
    this.onHelpRequest,
  });

  final Challenge challenge;
  final bool isCompleted;
  final VoidCallback onClose;
  final void Function(String code) onSubmit;
  final Future<String?> Function(String code)? onHelpRequest;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            onClose();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            // Semi-transparent scrim — tap to close
            GestureDetector(
              onTap: onClose,
              child: Container(color: Colors.black54),
            ),
            // Centered editor
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: FractionallySizedBox(
                  heightFactor: 0.85,
                  child: Material(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    elevation: 24,
                    child: CodeEditorPanel(
                      challenge: challenge,
                      isCompleted: isCompleted,
                      onClose: onClose,
                      onSubmit: onSubmit,
                      onHelpRequest: onHelpRequest,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
