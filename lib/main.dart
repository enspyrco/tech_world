import 'dart:async';
import 'dart:ui' as ui;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show ValueListenable, debugPrint, kDebugMode, kIsWeb;
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
import 'package:tech_world/diagnostics/diagnostics_service.dart';
import 'package:tech_world/chat/chat_panel.dart';
import 'package:tech_world/chat/chat_service.dart';
import 'package:tech_world/editor/challenge.dart';
import 'package:tech_world/editor/code_editor_panel.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/editor/predefined_challenges.dart';
import 'package:tech_world/flame/maps/terminal_mode.dart';
import 'package:tech_world/flame/tech_world.dart';
import 'package:tech_world/prompt/chat_evaluation_engine.dart';
import 'package:tech_world/prompt/predefined_prompt_challenges.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/prompt/prompt_challenge_panel.dart';
import 'package:tech_world/prompt/spell_slot_service.dart';
import 'package:tech_world/flame/tech_world_game.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/livekit/widgets/screen_share_overlay.dart';
import 'package:tech_world/progress/progress_service.dart';
import 'package:tech_world/services/stt_service.dart';
import 'package:tech_world/spellbook/cast_effects.dart';
import 'package:tech_world/spellbook/speech_cast_overlay.dart';
import 'package:tech_world/spellbook/speech_cast_service.dart';
import 'package:tech_world/spellbook/spellbook_panel.dart';
import 'package:tech_world/spellbook/spellbook_service.dart';
import 'package:tech_world/spellbook/word_of_power.dart' show arcaneColor;
import 'package:tech_world/map_editor/map_editor_panel.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';
import 'package:tech_world/map_editor/map_sync_service.dart';
import 'package:tech_world/rooms/room_browser.dart';
import 'package:tech_world/flame/maps/tmx_importer.dart';
import 'package:tech_world/flame/tiles/tileset_storage_service.dart';
import 'package:tech_world/rooms/room_data.dart';
import 'package:tech_world/rooms/room_service.dart';
import 'package:tech_world/preferences/user_preferences.dart';
import 'package:tech_world/rooms/room_session.dart';
import 'package:tech_world/timer/countdown_timer_state.dart';
import 'package:tech_world/timer/timer_service.dart';
import 'package:tech_world/widgets/auth_menu.dart';
import 'package:tech_world/widgets/join_overlay.dart';
import 'package:tech_world/widgets/map_selector.dart';
import 'package:tech_world/widgets/wire_states.dart';
import 'package:tech_world/widgets/edit_profile_dialog.dart'
    show EditProfileDialog, EditProfileResult;
import 'package:tech_world/widgets/loading_screen.dart';
import 'firebase_options.dart';
import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/logger_bridge_init.dart';
import 'package:tech_world/events/sinks/console_sink.dart';
import 'package:tech_world/events/types.dart';
import 'package:tech_world/events/sinks/file_sink.dart'
    if (dart.library.js_interop) 'package:tech_world/events/sinks/file_sink_stub.dart';
import 'package:tech_world/utils/locator.dart';
import 'package:tech_world/version/update_available_banner.dart';
import 'package:tech_world/version/version_check_service.dart';

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await _registerEventSinks();
    _initLogging();

    // Firebase must be initialized before Crashlytics can record errors.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Crashlytics is not supported on web.
    if (!kIsWeb) {
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;
      ui.PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }

    runApp(const MyApp());
  }, (error, stack) {
    _log.severe('Uncaught error', error, stack);
    if (!kIsWeb) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    }
  });
}

/// Register event sinks before the app starts. Console sink runs in
/// debug mode only; file sink and diagnostic sinks run on native
/// platforms (not web).
///
/// Also constructs and registers [DiagnosticsService] — the single
/// owner of runtime toggle state for AV diagnostics and error logging.
/// Sinks read `.value` from the service's listenables via their
/// `enabledCheck` callbacks; producers (`BubbleManager`,
/// `VideoBubbleComponent`, `LiveKitGameBridge`) read the same service
/// to gate AV-event dispatches. Module-level globals retired per
/// `feedback_cross_cutting_toggle_needs_single_owner`.
///
/// Guarded against duplicate registration on hot restart — sinks are
/// global mutable state that persists across restarts.
Future<void> _registerEventSinks() async {
  // DiagnosticsService registration is INTENTIONALLY outside the
  // `sinksRegistered` guard. The two pieces of global state (the sinks
  // list and the Locator's DiagnosticsService entry) live in different
  // mutable singletons; if they ever diverge (hot restart wipes one but
  // not the other), producers would call `Locator.maybeLocate` and get
  // null, silently disabling all diagnostics. Belt-and-braces: ensure
  // the service is present before returning, even when sinks are already
  // wired. Idempotent: `maybeLocate` returns the existing instance if
  // there is one, otherwise we load + add.
  final diagnostics = Locator.maybeLocate<DiagnosticsService>() ??
      await _bootstrapDiagnosticsService();

  if (sinksRegistered) return;

  if (kDebugMode) {
    registerSink(consoleSink);
  }
  if (!kIsWeb) {
    try {
      final fileSink = await createFileSink();
      registerSink(fileSink);

      final avSink = await createAvPipelineSink(
        enabledCheck: () => diagnostics.avEnabled.value,
      );
      registerSink(avSink);

      final errSink = await createErrorSink(
        enabledCheck: () => diagnostics.errorLoggingEnabled.value,
      );
      registerSink(errSink);
    } catch (e) {
      // path_provider failure — continue without file logging.
      debugPrint('[events] File sink registration failed: $e');
    }
  }
}

/// Loads a fresh [DiagnosticsService] from persisted preferences and
/// registers it with [Locator]. Called from [_registerEventSinks] when
/// no service is yet registered.
Future<DiagnosticsService> _bootstrapDiagnosticsService() async {
  final svc = await DiagnosticsService.load();
  Locator.add<DiagnosticsService>(svc);
  return svc;
}

/// Teardown closure returned by [initLoggerBridge] — stored so the
/// previous subscription can be cancelled on hot restart, preventing
/// duplicate dispatches.
void Function()? _loggerBridgeTeardown;

/// Configure the root logger to route all log records to [developer.log]
/// (which shows up in DevTools) AND to the event dispatch pipeline (which
/// routes to JSONL file sinks on native platforms).
///
/// The wiring lives in `lib/events/logger_bridge_init.dart` as
/// [initLoggerBridge] — a DI-seam function tested in
/// `test/events/logger_bridge_init_test.dart`. The PII gate
/// ([mapLogRecord] dropping FINE/FINER/FINEST) lives in
/// `lib/events/logger_bridge.dart` and is tested in
/// `test/events/logger_bridge_test.dart`.
void _initLogging() {
  Logger.root.level = Level.INFO;
  _loggerBridgeTeardown?.call();
  _loggerBridgeTeardown = initLoggerBridge();
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
  ProgressService? _progressService;
  SpellbookService? _spellbookService;
  SttService? _sttService;
  SpeechCastService? _speechCastService;
  final ValueNotifier<bool> _spellbookOpen = ValueNotifier<bool>(false);
  final MapEditorState _mapEditorState = MapEditorState();
  final ValueNotifier<bool> _chatCollapsed = ValueNotifier<bool>(false);
  final ValueNotifier<String?> _activeDmPeer = ValueNotifier<String?>(null);
  final SpellSlotService _spellSlotService = SpellSlotService();
  StreamSubscription<AuthUser>? _authSubscription;

  /// The current room session, or null when in the lobby / signed out.
  /// Encapsulates LiveKit, Chat, Proximity, Oracle, and the room-deletion
  /// listener.
  RoomSession? _session;

  /// Re-entrancy guard: true while [_joinRoom] is running its async wires.
  /// Prevents double-tap on a room card from launching two concurrent joins.
  bool _isJoining = false;

  /// Deferred leave: set by [_leaveRoom] when called while [_isJoining] is
  /// true.  [_joinRoom]'s finally block checks this and calls [_leaveRoom]
  /// so that dispose happens after in-flight wire operations complete.
  bool _pendingLeave = false;

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
    _spellbookOpen.dispose();
    _spellbookService?.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    // Firebase is already initialized in main().

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

    // Background poll for newer deployed bundles. The banner widget in
    // build() listens to `updateAvailable` and renders when it flips.
    // `APP_BUILD_SHA` is injected by CI via --dart-define at build time;
    // `dev` is the local-build fallback. On native platforms the poll
    // still runs but the "Refresh" button no-ops (see reload_page_stub).
    if (Locator.maybeLocate<VersionCheckService>() == null) {
      const runtimeBuild =
          String.fromEnvironment('APP_BUILD_SHA', defaultValue: 'dev');
      final versionCheck = VersionCheckService(
        runtimeBuild: runtimeBuild,
        versionJsonUrl: 'version.json',
      );
      Locator.add<VersionCheckService>(versionCheck);
      versionCheck.start();
    }

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
      locate<TechWorld>().progressService = null;
      _spellbookService?.dispose();
      _spellbookService = null;
      Locator.remove<SpellbookService>();
      _speechCastService = null;
      _sttService?.dispose();
      _sttService = null;
      _spellbookOpen.value = false;
      _roomService = null;
      _myRooms = null;
      Locator.remove<RoomService>();
      _selectedAvatar = null;
      _avatarLoaded = false;
      _currentUserId = null;
      _isAnonymous = false;
      _currentDisplayName = '';
      _currentProfilePictureUrl = null;
      _currentRoom = null;
      _log.info('User signed out - cleaned up');
      dispatch([UserSignedOut()]);
      setState(() {});
    } else {
      // User signed in — set up profile & services, show lobby.
      _log.info('User signed in: ${user.id} (${user.displayName})');
      _currentUserId = user.id;
      _isAnonymous = user is SignedInUser && user.isAnonymous;
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
      locate<TechWorld>().progressService = _progressService;
      locate<TechWorld>().refreshTerminalStates();

      // Load spellbook (words of power earned by completing prompt challenges).
      _spellbookService = SpellbookService(uid: user.id);
      try {
        await _spellbookService!.loadSpellbook();
      } catch (e) {
        _log.warning('Failed to load spellbook for uid ${user.id}: $e', e);
      }
      Locator.add<SpellbookService>(_spellbookService!);

      // Voice-cast wiring — SttService is platform-conditional (web only).
      // SpeechCastService combines STT + the cast pipeline into a single
      // entry-point for the SpeechCastOverlay widget. OracleService is
      // constructed lazily when LiveKit is connected (per-room).
      _sttService = SttService();
      _speechCastService = SpeechCastService(
        stt: _sttService!,
        spellbook: _spellbookService,
        progress: _progressService,
      );

      // Register RoomService for the lobby.
      _roomService = RoomService();
      Locator.add<RoomService>(_roomService!);

      // Ensure the Wizard's Tower public room exists and is up-to-date.
      await _roomService!.seedWizardsTower(
        ownerId: user.id,
        ownerDisplayName: user.displayName,
      );

      dispatch([UserSignedIn(
        userId: user.id,
        displayName: user.displayName,
      )]);
      setState(() {}); // Show lobby (or avatar picker first).
    }
  }

  /// Join a room — mount the game with overlay, run operations in parallel.
  ///
  /// The circuit-board overlay appears immediately over the game canvas.
  /// Tileset prefetch, LiveKit connection, and game engine init all run
  /// concurrently. The overlay fades out when every wire completes.
  Future<void> _joinRoom(RoomData room) async {
    if (_isJoining) return; // Re-entrancy guard: join already in progress.
    _isJoining = true;
    _pendingLeave = false;

    final userId = _currentUserId;
    if (userId == null) {
      _isJoining = false;
      return;
    }

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
          // Read the proximity-radius preference *before* RoomSession.create
          // so it's frozen into the ProximityService for this session. Live
          // toggle changes take effect on next room entry — see the slider
          // subtitle in EditProfileDialog.
          final proximityRadius = await UserPreferences.proximityRadius();
          _session = RoomSession.create(
            room: room,
            userId: userId,
            displayName: _currentDisplayName,
            onStateChanged: () => setState(() {}),
            onReconnectWorld: () {
                final tw = locate<TechWorld>();
                tw.setBotStatus(_session!.chatService.botStatus);
                return tw.connectToLiveKit(userId, _currentDisplayName);
              },
            onRoomDeleted: _onRoomDeleted,
            proximityRadius: proximityRadius,
          );
          final result = await _session!.connect();
          if (result == ConnectionResult.connected) {
            wires.complete(Wire.server);
            techWorld.setBotStatus(_session!.chatService.botStatus);
            // Apply the user's avatar-only preference before any bubble can
            // be created. Toggle takes effect on next room entry.
            techWorld.setHideVideoBubbles(
                await UserPreferences.hideVideoBubbles());
            techWorld.setReduceMotion(await UserPreferences.reduceMotion());
            await techWorld.connectToLiveKit(userId, _currentDisplayName);

            // Wire C: camera + mic (depends on server connection).
            wires.start(Wire.camera);
            final wireC = () async {
              try {
                await _session!.enableMedia();
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
                await _session!.chatService.loadHistory(room.id);
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
            // Session already set connectionFailed/connectionMessage.
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
      dispatch([RoomJoined(roomId: room.id, roomName: room.name)]);
      setState(() => _showJoinOverlay = false);
    } catch (e) {
      // If anything unexpected escapes the per-wire try/catch blocks,
      // tear down and return to the lobby so the user isn't stuck.
      _log.severe('Room join failed unexpectedly', e);
      await _leaveRoom();
    } finally {
      _isJoining = false;
      if (_pendingLeave) {
        _pendingLeave = false;
        await _leaveRoom();
      }
    }
  }

  /// Leave the current room — disconnect LiveKit and return to lobby.
  ///
  /// Disposal order: TechWorld subscriptions first (cancels stream listeners
  /// while the underlying services are still alive), then RoomSession handles
  /// consumer-before-producer disposal (ChatService → ProximityService →
  /// LiveKitService).
  Future<void> _leaveRoom() async {
    if (_currentRoom == null) return;

    // If a join is still in-flight, defer the leave so we don't dispose
    // services that running wire operations still reference.
    if (_isJoining) {
      _pendingLeave = true;
      return;
    }

    // Reset bot status so stale state (e.g. thinking) doesn't carry over.
    _session?.chatService.markBotAbsent();

    // Exit editor mode if active (before tearing down services).
    final techWorld = locate<TechWorld>();
    if (techWorld.mapEditorActive.value) {
      await techWorld.exitEditorMode();
    }

    // Cancel TechWorld's LiveKit subscriptions before disposing services.
    techWorld.disconnectFromLiveKit();

    // RoomSession handles service disposal in dependency order.
    await _session?.leave();
    _session = null;

    dispatch([RoomLeft(roomId: _currentRoom?.id)]);
    _activeDmPeer.value = null;
    _currentRoom = null;
    _mapEditorState.setRoomId(null);
    _wireStates?.dispose();
    _wireStates = null;
    _showJoinOverlay = false;

    setState(() {});
  }

  /// Handle host-deletion of the current room: tell the user, return to lobby.
  ///
  /// Wired into [RoomSession.create] as `onRoomDeleted`; fires when the
  /// Firestore room document goes from existing → non-existing while the
  /// user is inside.
  void _onRoomDeleted() {
    if (_currentRoom == null) return;
    _log.info('Room ${_currentRoom!.id} was deleted — returning to lobby');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This room has been deleted by its owner.'),
        ),
      );
    }
    _leaveRoom();
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
      // Update existing room the user owns (single atomic Firestore write).
      await _roomService!.updateRoomMapAndName(
        existingRoomId,
        gameMap,
        _mapEditorState.mapName,
      );
      // Update local state.
      _currentRoom = _currentRoom?.copyWith(
        name: _mapEditorState.mapName,
        mapData: gameMap,
      );
      dispatch([RoomMapSaved(
        roomId: existingRoomId,
        roomName: _mapEditorState.mapName,
      )]);
    } else {
      // Create new room (fork or brand new).
      final room = await _roomService!.createRoom(
        name: _mapEditorState.mapName,
        ownerId: userId,
        ownerDisplayName: _currentDisplayName,
        map: gameMap,
      );
      _mapEditorState.setRoomId(room.id);
      dispatch([RoomCreated(roomId: room.id, roomName: room.name)]);
      _currentRoom = room;

      // Now connect LiveKit for the new room.
      if (_session == null) {
        // Read proximity-radius pref before RoomSession.create — see the
        // comment at the other call site above.
        final proximityRadius = await UserPreferences.proximityRadius();
        _session = RoomSession.create(
          room: room,
          userId: userId,
          displayName: _currentDisplayName,
          onStateChanged: () => setState(() {}),
          onReconnectWorld: () {
                final tw = locate<TechWorld>();
                tw.setBotStatus(_session!.chatService.botStatus);
                return tw.connectToLiveKit(userId, _currentDisplayName);
              },
          onRoomDeleted: _onRoomDeleted,
          proximityRadius: proximityRadius,
        );
        final result = await _session!.connect();
        if (result == ConnectionResult.connected) {
          final tw = locate<TechWorld>();
          tw.setBotStatus(_session!.chatService.botStatus);
          tw.setHideVideoBubbles(await UserPreferences.hideVideoBubbles());
          tw.setReduceMotion(await UserPreferences.reduceMotion());
          await tw.connectToLiveKit(userId, _currentDisplayName);
          await _session!.enableMedia();
          await _session!.chatService.loadHistory(room.id);
        }

        // Apply saved avatar to game world.
        if (_selectedAvatar != null) {
          locate<TechWorld>().setLocalAvatar(_selectedAvatar!);
        }
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
      dispatch([RoomDeleted(roomId: room.id, roomName: room.name)]);
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
    dispatch([AvatarSelected(avatarId: avatar.id)]);

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
        body: Column(
          children: [
            // Update-available banner — shows when CI has deployed a newer
            // bundle than the one this client is running. Subtle amber bar
            // above the toolbar; per-session dismissible. See
            // `lib/version/version_check_service.dart`.
            UpdateAvailableBanner(
              updateAvailable:
                  locate<VersionCheckService>().updateAvailable,
            ),
            Expanded(
              child: LayoutBuilder(
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
                                // Video bubbles render in-world as Flame components
                                // (VideoBubbleComponent) — no Flutter overlay needed.
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
                    if (_currentRoom != null && _selectedAvatar != null)
                      ValueListenableBuilder<bool>(
                          valueListenable: locate<TechWorld>().mapEditorActive,
                          builder: (context, editorActive, _) {
                            final techWorld = locate<TechWorld>();
                            if (editorActive) {
                              final canEdit = _currentRoom != null &&
                                  _currentUserId != null &&
                                  _currentRoom!.canEdit(_currentUserId!);
                              return SizedBox(
                                width: constraints.maxWidth >= 800 ? 480 : 360,
                                child: MapEditorPanel(
                                  state: _mapEditorState,
                                  syncService: Locator.maybeLocate<MapSyncService>(),
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
                                        liveKitService: _session!.liveKitService,
                                        onCollapse: () =>
                                            _chatCollapsed.value = true,
                                        initialDmPeerId: dmPeer,
                                        onDmPeerConsumed: () =>
                                            _activeDmPeer.value = null,
                                        // Seeing chat acknowledges any mention of
                                        // the local user (stops their pulse).
                                        onOpened: () =>
                                            locate<TechWorld>().onChatPanelOpened(),
                                      );
                                    },
                                  ),
                                );
                              },
                            );
                          },
                        ),
                  ],
                ),
                // Toolbar — top right when in a room (hidden during avatar
                // selection and in the lobby)
                if (_currentRoom != null && _selectedAvatar != null)
                  ValueListenableBuilder<bool>(
                    valueListenable: _chatCollapsed,
                    builder: (context, chatCollapsed, child) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: _spellbookOpen,
                    builder: (context, spellbookOpen, _) {
                  final techWorld = locate<TechWorld>();
                  // The spellbook panel only renders when no challenge is
                  // active — see the overlay's gating below — so the
                  // toolbar should only shift for the spellbook in that
                  // same window.
                  final spellbookVisible = spellbookOpen &&
                      techWorld.activePromptChallenge.value == null;
                  // Toolbar offset depends on what's showing in the side panel
                  final double toolbarRight;
                  if (techWorld.mapEditorActive.value) {
                    toolbarRight = (constraints.maxWidth >= 800 ? 480 : 360) + 16;
                  } else if (spellbookVisible) {
                    toolbarRight = constraints.maxWidth >= 800 ? 400 : 320;
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
                              liveKitService: _session?.liveKitService,
                            ),
                          ],
                          const SizedBox(width: 8),
                          _DreamfinderSilenceButton(
                            liveKitService: _session?.liveKitService,
                          ),
                          const SizedBox(width: 8),
                          _TimerButton(timerService: _session?.timerService),
                          const SizedBox(width: 8),
                          _SpellbookButton(
                            open: _spellbookOpen,
                            activePromptChallenge:
                                techWorld.activePromptChallenge,
                          ),
                          const SizedBox(width: 8),
                          AuthMenu(
                            displayName: _currentDisplayName,
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
                // Shared countdown timer overlay — visible to everyone in the
                // room while a timer is running. Top-centre so it clears the
                // top-right toolbar.
                if (_session?.timerService != null)
                  Positioned(
                    top: 16,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      child: Center(
                        child: _TimerOverlay(
                          timerService: _session!.timerService,
                        ),
                      ),
                    ),
                  ),
                // Code editor modal overlay — only for code-mode terminals.
                if (_currentRoom != null &&
                    _selectedAvatar != null &&
                    locate<TechWorld>().currentMap.value.terminalMode ==
                        TerminalMode.code)
                  ValueListenableBuilder<CodeChallengeId?>(
                    valueListenable: locate<TechWorld>().activeChallenge,
                    builder: (context, challengeId, _) {
                        if (challengeId == null) {
                          return const SizedBox.shrink();
                        }
                        final techWorld = locate<TechWorld>();
                        final challenge = allChallenges.firstWhere(
                          (c) => c.id == challengeId,
                          orElse: () => allChallenges.first,
                        );
                        final isCompleted = Locator.maybeLocate<
                                    ProgressService>()
                                ?.isChallengeCompleted(challenge.id.wireName) ??
                            false;
                        return _CodeEditorModal(
                          challenge: challenge,
                          isCompleted: isCompleted,
                          botStatus: _session!.chatService.botStatus,
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
                              metadata: {'challengeId': challenge.id.wireName},
                            );

                            // Only mark completed when bot confirms pass
                            final codeResult = CodeSubmitResult.fromWire(
                              response?['challengeResult'] as String?,
                            );
                            dispatch([CodeSubmitted(
                              challengeId: challenge.id,
                              result: codeResult,
                            )]);
                            if (codeResult == CodeSubmitResult.pass) {
                              await applyCodeSubmitEffects(
                                challengeId: challenge.id,
                                progress:
                                    Locator.maybeLocate<ProgressService>(),
                              );
                              techWorld.refreshTerminalStates();
                            } else if (response?['challengeResult'] != null) {
                              _log.warning(
                                  'Unrecognised challengeResult: '
                                  '${response!['challengeResult']}');
                            }
                          },
                        );
                      },
                  ),
                // Prompt challenge modal overlay — only for prompt-mode terminals.
                if (_currentRoom != null &&
                    locate<TechWorld>().currentMap.value.terminalMode ==
                        TerminalMode.prompt)
                  ValueListenableBuilder<PromptChallengeId?>(
                    valueListenable:
                        locate<TechWorld>().activePromptChallenge,
                    builder: (context, challengeId, _) {
                      if (challengeId == null) {
                        return const SizedBox.shrink();
                      }
                      final techWorld = locate<TechWorld>();
                      final challenge = allPromptChallenges.firstWhere(
                        (c) => c.id == challengeId,
                        orElse: () => allPromptChallenges.first,
                      );
                      final chatService =
                          Locator.maybeLocate<ChatService>();
                      return Positioned(
                        top: 60,
                        right: 0,
                        bottom: 0,
                        width: MediaQuery.of(context).size.width >= 800
                            ? 400
                            : 320,
                        child: PromptChallengePanel(
                          challenge: challenge,
                          spellSlotService: _spellSlotService,
                          onClose: techWorld.closeEditor,
                          onCast: (prompt) async {
                            if (chatService == null) {
                              throw Exception('Chat service not available');
                            }
                            final engine =
                                ChatEvaluationEngine(chatService);
                            final result =
                                await engine.evaluate(challenge, prompt);
                            final (_, castResult) = result;

                            // Persistent side-effects of a successful cast:
                            // grant the word of power, then mark the
                            // challenge completed. See applyCastSuccessEffects
                            // for the rationale on ordering.
                            if (castResult.passed) {
                              await applyCastSuccessEffects(
                                challengeId: challenge.id,
                                spellbook: Locator
                                    .maybeLocate<SpellbookService>(),
                                progress: Locator
                                    .maybeLocate<ProgressService>(),
                              );
                              final doors = techWorld
                                  .doorsForChallenge(challenge.id);
                              for (final door in doors) {
                                final _ = techWorld.unlockDoor(door);
                              }
                            }

                            return result;
                          },
                        ),
                      );
                    },
                  ),
                // Spellbook side panel — toggled by the toolbar button.
                // Hidden while a prompt challenge is active so the two
                // right-aligned panels never collide; reappears when the
                // challenge closes if `_spellbookOpen` is still true.
                if (_spellbookService != null)
                  ValueListenableBuilder<PromptChallengeId?>(
                    valueListenable:
                        locate<TechWorld>().activePromptChallenge,
                    builder: (context, activeChallenge, _) {
                      if (activeChallenge != null) {
                        return const SizedBox.shrink();
                      }
                      return ValueListenableBuilder<bool>(
                        valueListenable: _spellbookOpen,
                        builder: (context, open, _) {
                          if (!open) return const SizedBox.shrink();
                          return Positioned(
                            top: 60,
                            right: 0,
                            bottom: 0,
                            width: MediaQuery.of(context).size.width >= 800
                                ? 400
                                : 320,
                            child: SpellbookPanel(
                              service: _spellbookService!,
                              onClose: () => _spellbookOpen.value = false,
                            ),
                          );
                        },
                      );
                    },
                  ),
                // Voice-cast affordance — proximity-gated mic FAB at
                // bottom-centre. Visible only when the player is near a
                // locked door and STT is supported (web). The
                // OracleService is cached on RoomSession so its
                // request-sequence counter is meaningful across rebuilds.
                if (_session != null && _speechCastService != null)
                  SpeechCastOverlay(
                    nearbyLockedDoor: locate<TechWorld>().nearbyLockedDoor,
                    speechCast: _speechCastService!,
                    oracle: _session!.oracleService,
                    onCastSuccess: (door) =>
                        locate<TechWorld>().unlockDoor(door),
                  ),

                // Screen share floating panels
                if (_session != null)
                  ScreenShareOverlay(
                      liveKitService: _session!.liveKitService),
                // Connection failure banner — listens to both the failed
                // flag and the message so reconnection text updates reactively.
                if (_session != null)
                  ValueListenableBuilder<bool>(
                    valueListenable: _session!.connectionFailed,
                    builder: (context, failed, _) {
                      if (!failed) return const SizedBox.shrink();
                      return ValueListenableBuilder<String?>(
                        valueListenable: _session!.connectionMessage,
                        builder: (context, message, _) {
                          return Positioned(
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
                                    const Icon(Icons.wifi_off,
                                        color: Colors.white, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      message ??
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
                          );
                        },
                      );
                    },
                  ),
              ],
            );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Toggle button for entering/exiting map editor mode.
/// Toolbar toggle for the [SpellbookPanel] side panel.
///
/// Disabled (and visually dimmed) while a prompt challenge is active so the
/// player can't toggle a panel that's hidden anyway by the same gating in
/// the spellbook overlay above.
class _SpellbookButton extends StatelessWidget {
  const _SpellbookButton({
    required this.open,
    required this.activePromptChallenge,
  });

  final ValueNotifier<bool> open;
  final ValueListenable<PromptChallengeId?> activePromptChallenge;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PromptChallengeId?>(
      valueListenable: activePromptChallenge,
      builder: (context, activeChallenge, _) {
        final disabled = activeChallenge != null;
        return ValueListenableBuilder<bool>(
          valueListenable: open,
          builder: (context, isOpen, _) {
            return IconButton(
              onPressed: disabled ? null : () => open.value = !isOpen,
              icon: Icon(
                Icons.auto_stories,
                color: disabled
                    ? Colors.white24
                    : (isOpen ? arcaneColor : Colors.white70),
                size: 20,
              ),
              tooltip: disabled
                  ? 'Spellbook unavailable while casting'
                  : (isOpen ? 'Close spellbook' : 'Open spellbook'),
              style: IconButton.styleFrom(
                backgroundColor: isOpen && !disabled
                    ? arcaneColor.withValues(alpha: 0.2)
                    : Colors.black54,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

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

    final starting = !_sharing;
    try {
      await service.setScreenShareEnabled(starting);
      dispatch([ScreenShareToggled(started: starting)]);
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

/// Toolbar button to silence Dreamfinder's audio.
///
/// Drives [LiveKitService.dreamfinderSilenced]; the service handles
/// applying the toggle to current and late-joining DF participants.
class _DreamfinderSilenceButton extends StatelessWidget {
  const _DreamfinderSilenceButton({required this.liveKitService});

  final LiveKitService? liveKitService;

  @override
  Widget build(BuildContext context) {
    final service = liveKitService;
    if (service == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<bool>(
      valueListenable: service.dreamfinderSilenced,
      builder: (context, silenced, _) => IconButton(
        onPressed: () => service.setDreamfinderSilenced(!silenced),
        icon: Icon(
          silenced ? Icons.volume_off : Icons.volume_up,
          color: silenced ? Colors.amber.shade300 : Colors.white70,
          size: 20,
        ),
        tooltip:
            silenced ? 'Unsilence Dreamfinder' : 'Silence Dreamfinder',
        style: IconButton.styleFrom(
          backgroundColor: silenced
              ? Colors.amber.shade300.withValues(alpha: 0.2)
              : Colors.black54,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}

/// Toolbar button that opens a small picker to start the shared room timer.
///
/// Any participant can press it; the chosen duration starts the countdown for
/// everyone. While a timer is running the button offers a cancel action
/// instead. The trigger lives in the toolbar (not a world entity) because the
/// "world is the listener" rule governs *casting/magic* affordances, not
/// generic UI like a timer.
class _TimerButton extends StatelessWidget {
  const _TimerButton({required this.timerService});

  final TimerService? timerService;

  /// Preset durations offered in the picker, in minutes.
  static const _presetMinutes = [1, 3, 5, 10];

  @override
  Widget build(BuildContext context) {
    final service = timerService;
    if (service == null) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: service.state,
      builder: (context, _) {
        final running = service.state.running;
        return PopupMenuButton<int>(
          tooltip: running ? 'Shared timer' : 'Start a shared timer',
          icon: Icon(
            running ? Icons.timer : Icons.timer_outlined,
            color: running ? Colors.amber.shade300 : Colors.white70,
            size: 20,
          ),
          color: const Color(0xFF2A2A2A),
          itemBuilder: (context) => [
            for (final mins in _presetMinutes)
              PopupMenuItem<int>(
                value: mins * 60,
                child: Text(
                  '$mins min',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            if (running)
              const PopupMenuItem<int>(
                value: 0,
                child: Text(
                  'Cancel timer',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
          onSelected: (seconds) {
            if (seconds == 0) {
              service.cancel();
            } else {
              service.start(seconds);
            }
          },
        );
      },
    );
  }
}

/// On-screen countdown shown to every participant while the shared timer runs.
///
/// Renders `mm:ss` from [TimerService.state]. When the countdown reaches zero
/// the alarm plays (handled in [TimerService]) and a brief "Time's up!" banner
/// with a dismiss button replaces the count until dismissed.
class _TimerOverlay extends StatelessWidget {
  const _TimerOverlay({required this.timerService});

  final TimerService timerService;

  @override
  Widget build(BuildContext context) {
    final CountdownTimerState state = timerService.state;
    return ListenableBuilder(
      listenable: Listenable.merge([state, timerService.alarmActive]),
      builder: (context, _) {
        final running = state.running;
        final finished = !running && timerService.alarmActive.value;
        // Show only while counting down or while the alarm banner is active.
        if (!running && !finished) {
          return const SizedBox.shrink();
        }
        return Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: finished
                    ? Colors.redAccent
                    : Colors.amber.shade300.withValues(alpha: 0.6),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  finished ? Icons.alarm : Icons.timer,
                  color: finished ? Colors.redAccent : Colors.amber.shade300,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  finished ? "Time's up!" : state.formatted,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                    letterSpacing: finished ? 0 : 2,
                  ),
                ),
                if (finished) ...[
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: timerService.dismissAlarm,
                    icon: const Icon(Icons.close,
                        color: Colors.white70, size: 20),
                    tooltip: 'Dismiss alarm',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
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
    required this.botStatus,
    required this.onClose,
    required this.onSubmit,
    this.onHelpRequest,
  });

  final Challenge challenge;
  final bool isCompleted;
  final ValueListenable<BotStatus> botStatus;
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
                      botStatus: botStatus,
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
