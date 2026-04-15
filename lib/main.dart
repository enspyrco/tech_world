import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart'
    show LocalTrackPublication, lkPlatformIsDesktop;
import 'package:logging/logging.dart';
import 'package:tech_world/auth/auth_gate.dart';
import 'package:tech_world/auth/auth_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:tech_world/auth/auth_user.dart';
import 'package:tech_world/avatar/avatar.dart';
import 'package:tech_world/avatar/avatar_selection_screen.dart';
import 'package:tech_world/avatar/predefined_avatars.dart';
import 'package:tech_world/auth/user_profile_service.dart';
import 'package:tech_world/chat/chat_message_repository.dart';
import 'package:tech_world/chat/chat_panel.dart';
import 'package:tech_world/chat/chat_service.dart';
import 'package:tech_world/services/dreamfinder_client.dart';
import 'package:tech_world/editor/challenge.dart';
import 'package:tech_world/editor/code_editor_panel.dart';
import 'package:tech_world/editor/predefined_challenges.dart';
import 'package:tech_world/flame/tech_world.dart';
import 'package:tech_world/flame/tech_world_game.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/livekit/widgets/proximity_video_overlay.dart';
import 'package:tech_world/livekit/widgets/screen_share_overlay.dart';
import 'package:tech_world/progress/progress_service.dart';
import 'package:tech_world/map_editor/map_editor_panel.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';
import 'package:tech_world/proximity/proximity_service.dart';
import 'package:tech_world/rooms/room_browser.dart';
import 'package:tech_world/flame/maps/tmx_importer.dart';
import 'package:tech_world/flame/tiles/tileset_storage_service.dart';
import 'package:tech_world/rooms/room_data.dart';
import 'package:tech_world/rooms/room_service.dart';
import 'package:tech_world/widgets/auth_menu.dart';
import 'package:tech_world/widgets/join_overlay.dart';
import 'package:tech_world/widgets/map_selector.dart';
import 'package:tech_world/widgets/wire_states.dart';
import 'package:tech_world/widgets/edit_profile_dialog.dart'
    show EditProfileDialog, EditProfileResult;
import 'package:tech_world/widgets/loading_screen.dart';
import 'firebase_options.dart';
import 'package:tech_world/utils/locator.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _initLogging();
  runApp(const MyApp());
}

/// Configure the root logger to route all log records to [developer.log],
/// which shows up in DevTools and the debug console.
void _initLogging() {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    developer.log(
      record.message,
      time: record.time,
      level: record.level.value,
      name: record.loggerName,
      error: record.error,
      stackTrace: record.stackTrace,
    );
  });
}

final _log = Logger('Main');

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
  final ValueNotifier<String?> _activeDmPeer = ValueNotifier<String?>(null);
  ChatMessageRepository? _chatMessageRepository;
  bool _liveKitConnectionFailed = false;
  String? _connectionFailureMessage;
  StreamSubscription<AuthUser>? _authSubscription;

  /// Wire-state tracker for the current join operation's circuit-board overlay.
  WireStates? _wireStates;

  /// Whether the circuit-board join overlay is visible.
  bool _showJoinOverlay = false;

  Avatar? _selectedAvatar;
  bool _avatarLoaded = false;
  String? _currentUserId;
  bool _isAnonymous = false;
  String _currentDisplayName = '';
  String? _currentProfilePictureUrl;
  RoomService? _roomService;

  /// Cached list of the user's saved rooms. Invalidated on save/delete.
  List<RoomData>? _myRooms;

  /// The room the user is currently inside. Null = lobby view.
  RoomData? _currentRoom;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _wireStates?.dispose();
    super.dispose();
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
    _authSubscription = authService.authStateChanges.listen(_onAuthStateChanged);

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
      await _leaveRoom();
      _progressService?.dispose();
      _progressService = null;
      Locator.remove<ProgressService>();
      _roomService = null;
      _myRooms = null;
      Locator.remove<RoomService>();
      _liveKitConnectionFailed = false;
      _connectionFailureMessage = null;
      _selectedAvatar = null;
      _avatarLoaded = false;
      _currentUserId = null;
      _isAnonymous = false;
      _currentDisplayName = '';
      _currentProfilePictureUrl = null;
      _currentRoom = null;
      _log.info('User signed out - cleaned up');
      setState(() {});
    } else {
      // User signed in — set up profile & services, show lobby.
      _log.info('User signed in: ${user.id} (${user.displayName})');
      _currentUserId = user.id;
      _isAnonymous = user.isAnonymous;
      _currentDisplayName = user.displayName;

      // Load saved avatar and profile picture from Firestore
      try {
        final profileService = UserProfileService();
        final profile = await profileService.getUserProfile(user.id);
        if (profile?.avatarId != null) {
          _selectedAvatar = avatarById(profile!.avatarId!) ?? defaultAvatar;
        }
        _currentProfilePictureUrl = profile?.profilePictureUrl;
      } catch (e) {
        _log.warning('Failed to load profile: $e', e);
      }
      _avatarLoaded = true;

      // Load challenge progression
      _progressService = ProgressService(uid: user.id);
      try {
        await _progressService!.loadProgress();
      } catch (e) {
        _log.warning('Failed to load progress: $e', e);
      }
      Locator.add<ProgressService>(_progressService!);
      locate<TechWorld>().refreshTerminalStates();

      // Register RoomService for the lobby.
      _roomService = RoomService();
      Locator.add<RoomService>(_roomService!);

      setState(() {}); // Show lobby (or avatar picker first).
    }
  }

  /// Join a room — mount the game with overlay, run operations in parallel.
  ///
  /// The circuit-board overlay appears immediately over the game canvas.
  /// Tileset prefetch, LiveKit connection, and game engine init all run
  /// concurrently. The overlay fades out when every wire completes.
  Future<void> _joinRoom(RoomData room) async {
    final userId = _currentUserId;
    if (userId == null) return;

    final techWorld = locate<TechWorld>();
    final wires = WireStates();
    // Don't dispose the old WireStates eagerly — the CircuitBoardProgress
    // widget still holds a listener until didUpdateWidget/dispose runs.
    // Reassigning _wireStates lets the widget swap cleanly on the next frame.
    _wireStates = wires;

    _mapEditorState.setRoomId(room.id);

    // Store the map reference (fast — just updates ValueNotifier when not
    // mounted, so onLoad() will pick it up).
    await techWorld.loadMap(room.mapData);

    // Mount GameWidget + overlay immediately — no more black flash.
    setState(() {
      _currentRoom = room;
      _showJoinOverlay = true;
    });

    try {
      // Wire A: prefetch tileset bytes into cache (parallel with engine init).
      wires.start(Wire.tilesets);
      final wireA = () async {
        try {
          await techWorld.prefetchTilesetBytes(room.mapData);
          wires.complete(Wire.tilesets);
        } catch (e) {
          _log.warning('Tileset prefetch failed', e);
          wires.error(Wire.tilesets);
        }
      }();

      // Wire B: create services + connect to LiveKit server.
      wires.start(Wire.server);
      final wireB = () async {
        try {
          _createServices(room.id, userId, _currentDisplayName);
          final result = await _liveKitService!.connect();
          _log.info('LiveKit connection result for room ${room.id}: $result');
          if (result == ConnectionResult.connected) {
            wires.complete(Wire.server);
            await techWorld.connectToLiveKit(userId, _currentDisplayName);

            // Wire C: camera + mic (depends on server connection).
            wires.start(Wire.camera);
            final wireC = () async {
              try {
                await Future.wait([
                  _liveKitService!.setCameraEnabled(true),
                  _liveKitService!.setMicrophoneEnabled(true),
                ]);
                wires.complete(Wire.camera);
              } catch (e) {
                _log.warning('Camera/mic setup failed', e);
                wires.error(Wire.camera);
              }
            }();

            // Wire D: chat history (depends on server connection).
            wires.start(Wire.chat);
            final wireD = () async {
              try {
                await _chatService!.loadHistory(room.id);
                wires.complete(Wire.chat);
              } catch (e) {
                _log.warning('Chat history load failed', e);
                wires.error(Wire.chat);
              }
            }();

            await Future.wait([wireC, wireD]);
          } else if (result != ConnectionResult.alreadyConnected) {
            wires.complete(Wire.server);
            // Mark dependent wires as complete (skipped) so overlay dismisses.
            wires.complete(Wire.camera);
            wires.complete(Wire.chat);
            _liveKitConnectionFailed = true;
            _connectionFailureMessage = switch (result) {
              ConnectionResult.tokenAuthError =>
                'Session expired — please sign in again',
              ConnectionResult.tokenNetworkError =>
                'Could not reach server — check your connection',
              ConnectionResult.roomFailed =>
                'Room connection failed — try again later',
              _ => 'Video & chat unavailable — connection failed',
            };
          } else {
            wires.complete(Wire.server);
            wires.complete(Wire.camera);
            wires.complete(Wire.chat);
          }
        } catch (e) {
          _log.warning('LiveKit connection failed', e);
          wires.error(Wire.server);
          wires.complete(Wire.camera);
          wires.complete(Wire.chat);
        }
      }();

      // Wire E: game engine ready (TechWorld.onLoad finishes).
      // Times out after 30s to prevent hanging if onLoad throws.
      wires.start(Wire.gameReady);
      final wireE = () async {
        try {
          await techWorld.gameReady.waitForTrue(
            timeout: const Duration(seconds: 30),
          );
          wires.complete(Wire.gameReady);
        } catch (e) {
          _log.warning('Game engine ready timed out', e);
          wires.error(Wire.gameReady);
        }
      }();

      await Future.wait([wireA, wireB, wireE]);

      // Apply saved avatar to game world.
      if (_selectedAvatar != null) {
        techWorld.setLocalAvatar(_selectedAvatar!);
      }

      // Fade out the overlay.
      setState(() => _showJoinOverlay = false);
    } catch (e) {
      // If anything unexpected escapes the per-wire try/catch blocks,
      // tear down and return to the lobby so the user isn't stuck.
      _log.severe('Room join failed unexpectedly', e);
      await _leaveRoom();
    }
  }

  /// Create and register LiveKit, Chat, and Proximity services.
  void _createServices(String roomId, String userId, String displayName) {
    _liveKitService = LiveKitService(
      userId: userId,
      displayName: displayName,
      roomName: roomId,
    );
    _chatMessageRepository = ChatMessageRepository();
    _chatService = ChatService(
      liveKitService: _liveKitService!,
      repository: _chatMessageRepository,
      dreamfinderClient: DreamfinderClient(
        baseUrl: 'https://dreamfinder.imagineering.cc',
        apiKey: const String.fromEnvironment(
          'DREAMFINDER_API_KEY',
          defaultValue: '2aa0e9ab3207b197dc0d392fe6e35e8cbe8bfa78f72ce7f9',
        ),
      ),
    );
    _proximityService = ProximityService();

    Locator.add<LiveKitService>(_liveKitService!);
    Locator.add<ChatService>(_chatService!);
    Locator.add<ProximityService>(_proximityService!);
  }

  /// Create LiveKit, Chat, and Proximity services, connect, and enable media.
  ///
  /// Sets [_liveKitConnectionFailed] on failure so the UI can show a banner.
  /// Applies the saved avatar if one is selected.
  ///
  /// Used by the [_onCreateRoom] / save-room flow which doesn't use the
  /// circuit-board overlay.
  Future<void> _setupLiveKit(
    String roomId,
    String userId,
    String displayName,
  ) async {
    _createServices(roomId, userId, displayName);

    final result = await _liveKitService!.connect();
    _log.info('LiveKit connection result for room $roomId: $result');

    if (result == ConnectionResult.connected) {
      await locate<TechWorld>().connectToLiveKit(userId, displayName);
      await _liveKitService!.setCameraEnabled(true);
      await _liveKitService!.setMicrophoneEnabled(true);
      await _chatService!.loadHistory(roomId);
    } else if (result != ConnectionResult.alreadyConnected) {
      _liveKitConnectionFailed = true;
      _connectionFailureMessage = switch (result) {
        ConnectionResult.tokenAuthError =>
          'Session expired — please sign in again',
        ConnectionResult.tokenNetworkError =>
          'Could not reach server — check your connection',
        ConnectionResult.roomFailed =>
          'Room connection failed — try again later',
        _ => 'Video & chat unavailable — connection failed',
      };
    }

    // Apply saved avatar to game world.
    if (_selectedAvatar != null) {
      locate<TechWorld>().setLocalAvatar(_selectedAvatar!);
    }
  }

  /// Leave the current room — disconnect LiveKit and return to lobby.
  ///
  /// Disposal order: TechWorld subscriptions first (cancels stream listeners
  /// while the underlying services are still alive), then consumers before
  /// producers (ChatService → ProximityService → LiveKitService).
  Future<void> _leaveRoom() async {
    if (_currentRoom == null) return;

    // Exit editor mode if active (before tearing down services).
    final techWorld = locate<TechWorld>();
    if (techWorld.mapEditorActive.value) {
      await techWorld.exitEditorMode();
    }

    // Cancel TechWorld's LiveKit subscriptions before disposing services.
    techWorld.disconnectFromLiveKit();

    // Dispose consumers before producers.
    _chatService?.dispose();
    _proximityService?.dispose();
    await _liveKitService?.dispose();
    _chatService = null;
    _chatMessageRepository = null;
    _proximityService = null;
    _liveKitService = null;
    _activeDmPeer.value = null;
    _liveKitConnectionFailed = false;
    _connectionFailureMessage = null;
    Locator.remove<LiveKitService>();
    Locator.remove<ChatService>();
    Locator.remove<ProximityService>();
    _currentRoom = null;
    _mapEditorState.setRoomId(null);
    _wireStates?.dispose();
    _wireStates = null;
    _showJoinOverlay = false;

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
  ///
  /// If the user owns the room, updates it in place. If the user doesn't own
  /// the room (or it's a new room), creates a new room (fork-on-save).
  Future<void> _saveRoom() async {
    final userId = _currentUserId;
    if (userId == null || _roomService == null) return;

    // Upload custom tileset images to Firebase Storage in parallel
    // (idempotent — content-hash IDs mean re-uploads are no-ops).
    final customBytes = _mapEditorState.customTilesetBytes;
    if (customBytes.isNotEmpty) {
      final storageService = TilesetStorageService();
      await Future.wait(_mapEditorState.customTilesets.map((tileset) async {
        final bytes = customBytes[tileset.imagePath];
        if (bytes != null) {
          await storageService.uploadTilesetImage(
            tilesetId: tileset.id,
            imageBytes: bytes,
          );
        }
      }));
    }

    final gameMap = _mapEditorState.toGameMap();
    final existingRoomId = _mapEditorState.roomId;
    final isOwnedRoom = existingRoomId != null &&
        existingRoomId.isNotEmpty &&
        _currentRoom != null &&
        _currentRoom!.isOwner(userId);

    if (isOwnedRoom) {
      // Update existing room the user owns.
      await _roomService!.updateRoomMap(existingRoomId, gameMap);
      await _roomService!.updateRoomName(
        existingRoomId,
        _mapEditorState.mapName,
      );
      // Update local state.
      _currentRoom = _currentRoom?.copyWith(
        name: _mapEditorState.mapName,
        mapData: gameMap,
      );
    } else {
      // Create new room (fork or brand new).
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
        await _setupLiveKit(room.id, userId, _currentDisplayName);
      }
    }

    // Invalidate cached room list so it refreshes on next open.
    _myRooms = null;
    _mapEditorState.markClean();

    setState(() {});
  }

  /// Decode custom tileset images and register them with the game's
  /// [TilesetRegistry] so they render immediately in the editor preview.
  ///
  /// Also runs pixel-based barrier analysis on each custom tileset so the
  /// auto-barrier system can classify tiles without hand-curated metadata.
  Future<void> _registerCustomTilesets(
    TmxImportResultWithCustomTilesets result,
  ) async {
    final game = Locator.maybeLocate<TechWorldGame>();
    if (game == null) return;

    final registry = game.tilesetRegistry;

    for (final tileset in result.customTilesets) {
      if (registry.isLoaded(tileset.id)) continue;

      final bytes = result.customImageBytes[tileset.imagePath];
      if (bytes == null) continue;

      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      registry.loadFromImage(tileset, frame.image);
      await registry.analyzeBarriers(tileset.id);
    }

    // Ensure the editor state can use computed barrier analysis.
    _mapEditorState.setTilesetRegistry(registry);
  }

  /// Show a confirmation dialog when discarding unsaved editor changes.
  ///
  /// If the editor has no unsaved changes, exits immediately. Otherwise shows
  /// a dialog asking the user to confirm.
  Future<void> _confirmDiscardEditorChanges(
    BuildContext context,
    TechWorld techWorld,
  ) async {
    if (!_mapEditorState.isDirty) {
      await techWorld.exitEditorMode(applyChanges: false);
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'You have unsaved changes that will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (discard == true) {
      await techWorld.exitEditorMode(applyChanges: false);
      _mapEditorState.markClean();
    }
  }

  /// Load a saved room's map into the editor.
  ///
  /// Updates [_currentRoom] so that the fork-on-save logic in [_saveRoom]
  /// correctly detects ownership of the loaded room.
  Future<void> _loadSavedRoom(RoomData room) async {
    try {
      _mapEditorState.loadFromGameMap(room.mapData);
      _mapEditorState.setRoomId(room.id);
      _currentRoom = room;
      await locate<TechWorld>().loadMap(room.mapData);
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load map: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  /// Delete a saved room after confirmation.
  Future<void> _deleteSavedRoom(RoomData room) async {
    if (_roomService == null) return;
    try {
      await _roomService!.deleteRoom(room.id);
      // Invalidate cache so it refreshes on next open.
      _myRooms = null;
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  /// Refresh the cached list of the user's saved rooms.
  Future<void> _refreshMyRooms() async {
    if (_roomService == null || _currentUserId == null) return;
    try {
      _myRooms = await _roomService!.listMyRooms(_currentUserId!);
      setState(() {});
    } catch (e) {
      _log.warning('Failed to refresh saved rooms: $e', e);
    }
  }

  /// Opens the edit profile dialog and updates state on save.
  ///
  /// Takes [dialogContext] from below the [MaterialApp] so that
  /// [showDialog] can find [MaterialLocalizations].
  Future<void> _editProfile(BuildContext dialogContext) async {
    final result = await showDialog<EditProfileResult>(
      context: dialogContext,
      builder: (context) => EditProfileDialog(
        currentDisplayName: _currentDisplayName,
        currentProfilePictureUrl: _currentProfilePictureUrl,
      ),
    );
    if (result != null) {
      setState(() {
        _currentDisplayName = result.displayName;
        if (result.profilePictureUrl != null) {
          _currentProfilePictureUrl = result.profilePictureUrl;
        }
      });
    }
  }

  /// Resets avatar selection so the user can pick a new one.
  void _changeAvatar() {
    setState(() {
      _selectedAvatar = null;
    });
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
        _log.warning('Failed to save avatar: $e', e);
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
                    Expanded(
                      child: StreamBuilder<AuthUser>(
                        stream: locate<AuthService>().authStateChanges,
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const LoadingScreen(
                              message: 'Checking authentication...',
                            );
                          }
                          if (snapshot.data! is! SignedOutUser) {
                            // Still loading profile — show loading screen
                            // instead of flashing the game world.
                            if (!_avatarLoaded || _roomService == null) {
                              return const LoadingScreen(
                                message: 'Loading profile...',
                              );
                            }
                            // Show avatar selection if signed in but no avatar chosen yet
                            if (_selectedAvatar == null) {
                              return AvatarSelectionScreen(
                                onAvatarSelected: _onAvatarSelected,
                              );
                            }
                            // Show room browser (lobby) if not in a room
                            if (_currentRoom == null) {
                              return RoomBrowser(
                                roomService: _roomService!,
                                userId: _currentUserId!,
                                canCreateRoom: !_isAnonymous,
                                onSignOut: () => locate<AuthService>().signOut(),
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
                                // Circuit-board loading overlay
                                if (_wireStates != null)
                                  JoinOverlay(
                                    wireStates: _wireStates!,
                                    roomName: _currentRoom!.name,
                                    visible: _showJoinOverlay,
                                  ),
                              ],
                            );
                          }
                          return const AuthGate();
                        },
                      ),
                    ),
                    // Side panel - map editor or chat (hidden in lobby and
                    // during avatar selection)
                    StreamBuilder<AuthUser>(
                      stream: locate<AuthService>().authStateChanges,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData ||
                            snapshot.data is SignedOutUser ||
                            _currentRoom == null ||
                            _selectedAvatar == null) {
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
                                  onApply: () async {
                                    await techWorld.exitEditorMode();
                                    _mapEditorState.markClean();
                                  },
                                  onCancel: () => _confirmDiscardEditorChanges(
                                    context,
                                    techWorld,
                                  ),
                                  referenceMap: techWorld.currentMap.value,
                                  playerPosition:
                                      techWorld.playerGridPosition,
                                  onSave: _currentUserId != null
                                      ? _saveRoom
                                      : null,
                                  canEdit: canEdit,
                                  savedRooms: _myRooms,
                                  onRegisterCustomTilesets:
                                      _registerCustomTilesets,
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
                                        child: ValueListenableBuilder<int>(
                                          valueListenable: chatService
                                              .totalUnreadNotifier,
                                          builder:
                                              (context, unread, child) {
                                            return Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                IconButton(
                                                  onPressed: () =>
                                                      _chatCollapsed
                                                          .value = false,
                                                  icon: const Icon(
                                                      Icons.chat_bubble),
                                                  color: const Color(
                                                      0xFFD97757),
                                                  tooltip: 'Open chat',
                                                  style: IconButton
                                                      .styleFrom(
                                                    backgroundColor:
                                                        const Color(
                                                                0xFFD97757)
                                                            .withValues(
                                                                alpha:
                                                                    0.1),
                                                  ),
                                                ),
                                                if (unread > 0)
                                                  Positioned(
                                                    top: -2,
                                                    right: -2,
                                                    child: Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 5,
                                                          vertical: 1),
                                                      decoration:
                                                          BoxDecoration(
                                                        color: const Color(
                                                            0xFFD97757),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(
                                                                    10),
                                                      ),
                                                      child: Text(
                                                        '$unread',
                                                        style:
                                                            const TextStyle(
                                                          color:
                                                              Colors.white,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight
                                                                  .bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                return SizedBox(
                                  width: constraints.maxWidth >= 800
                                      ? 320
                                      : 280,
                                  child: ValueListenableBuilder<String?>(
                                    valueListenable: _activeDmPeer,
                                    builder: (context, dmPeer, _) {
                                      return ChatPanel(
                                        chatService: chatService,
                                        liveKitService: _liveKitService!,
                                        onCollapse: () =>
                                            _chatCollapsed.value = true,
                                        initialDmPeerId: dmPeer,
                                        onDmPeerConsumed: () =>
                                            _activeDmPeer.value = null,
                                      );
                                    },
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
                // Toolbar — top right when in a room (hidden during avatar
                // selection)
                StreamBuilder<AuthUser>(
                  stream: locate<AuthService>().authStateChanges,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData ||
                        snapshot.data is SignedOutUser ||
                        _currentRoom == null ||
                        _selectedAvatar == null) {
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
                            // Map selector with saved rooms
                            MapSelector(
                              techWorld: techWorld,
                              roomService: _roomService,
                              userId: _currentUserId,
                              savedRooms: _myRooms,
                              onPopupOpened: _refreshMyRooms,
                              onLoadRoom: _loadSavedRoom,
                              onDeleteRoom: _deleteSavedRoom,
                            ),
                            if (_currentRoom!.canEdit(_currentUserId!)) ...[
                              const SizedBox(width: 8),
                              _MapEditorButton(
                                mapEditorState: _mapEditorState,
                                techWorld: locate<TechWorld>(),
                              ),
                            ],
                            if (kIsWeb || lkPlatformIsDesktop()) ...[
                              const SizedBox(width: 8),
                              _ScreenShareButton(
                                liveKitService: _liveKitService,
                              ),
                            ],
                            const SizedBox(width: 8),
                            AuthMenu(
                              displayName: _currentDisplayName.isNotEmpty
                                  ? _currentDisplayName
                                  : snapshot.data!.displayName,
                              onChangeAvatar: _changeAvatar,
                              onEditProfile: _editProfile,
                              profilePictureUrl: _currentProfilePictureUrl,
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
                        _currentRoom == null ||
                        _selectedAvatar == null) {
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
                                _log.warning('Failed to persist completion: $e', e);
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
                // Screen share floating panels
                if (_liveKitService != null)
                  ScreenShareOverlay(liveKitService: _liveKitService!),
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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.wifi_off, color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              _connectionFailureMessage ??
                                  'Video & chat unavailable — connection failed',
                              style: const TextStyle(
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
          onPressed: () async {
            if (active) {
              await techWorld.exitEditorMode();
              mapEditorState.markClean();
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

/// Toggle button for starting/stopping screen share.
///
/// On web, the browser's native picker is shown automatically.
/// On desktop, LiveKit's `setScreenShareEnabled` triggers the native picker.
///
/// Listens to [LiveKitService.localTrackPublished] to stay in sync when the
/// share is stopped externally (e.g. browser's "Stop sharing" bar).
class _ScreenShareButton extends StatefulWidget {
  const _ScreenShareButton({required this.liveKitService});

  final LiveKitService? liveKitService;

  @override
  State<_ScreenShareButton> createState() => _ScreenShareButtonState();
}

class _ScreenShareButtonState extends State<_ScreenShareButton> {
  StreamSubscription<LocalTrackPublication>? _trackPubSub;

  bool get _sharing => widget.liveKitService?.isScreenShareEnabled ?? false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(_ScreenShareButton old) {
    super.didUpdateWidget(old);
    if (old.liveKitService != widget.liveKitService) {
      _trackPubSub?.cancel();
      _subscribe();
    }
  }

  void _subscribe() {
    // Rebuild whenever local tracks change so _sharing reflects reality.
    _trackPubSub = widget.liveKitService?.localTrackPublished.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _trackPubSub?.cancel();
    super.dispose();
  }

  Future<void> _toggleScreenShare() async {
    final service = widget.liveKitService;
    if (service == null || !service.isConnected) return;

    try {
      await service.setScreenShareEnabled(!_sharing);
    } catch (e) {
      _log.warning('Screen share toggle failed: $e', e);
    }
    // Rebuild to pick up the new isScreenShareEnabled state.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _toggleScreenShare,
      icon: Icon(
        _sharing ? Icons.stop_screen_share : Icons.screen_share,
        color: _sharing ? Colors.red.shade300 : Colors.white70,
        size: 20,
      ),
      tooltip: _sharing ? 'Stop sharing' : 'Share screen',
      style: IconButton.styleFrom(
        backgroundColor: _sharing
            ? Colors.red.shade300.withValues(alpha: 0.2)
            : Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
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
