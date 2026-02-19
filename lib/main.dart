import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tech_world/auth/auth_gate.dart';
import 'package:tech_world/auth/auth_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:tech_world/auth/auth_user.dart';
import 'package:tech_world/chat/chat_panel.dart';
import 'package:tech_world/chat/chat_service.dart';
import 'package:tech_world/editor/challenge.dart';
import 'package:tech_world/editor/code_editor_panel.dart';
import 'package:tech_world/editor/predefined_challenges.dart';
import 'package:tech_world/flame/tech_world.dart';
import 'package:tech_world/flame/tech_world_game.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/livekit/widgets/proximity_video_overlay.dart';
import 'package:tech_world/map_editor/map_editor_panel.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';
import 'package:tech_world/proximity/proximity_service.dart';
import 'package:tech_world/widgets/auth_menu.dart';
import 'package:tech_world/widgets/map_selector.dart';
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
  final MapEditorState _mapEditorState = MapEditorState();
  final ValueNotifier<bool> _chatCollapsed = ValueNotifier<bool>(false);
  bool _liveKitConnectionFailed = false;

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
      // User signed out - disconnect LiveKit
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
      debugPrint('User signed out - LiveKit disconnected');
      setState(() {}); // Trigger rebuild to remove overlay
    } else {
      // User signed in - create and connect LiveKit
      debugPrint('User signed in: ${user.id} (${user.displayName})');

      _liveKitService = LiveKitService(
        userId: user.id,
        displayName: user.displayName,
        roomName: 'tech-world',
      );

      _chatService = ChatService(liveKitService: _liveKitService!);
      _proximityService = ProximityService();

      Locator.add<LiveKitService>(_liveKitService!);
      Locator.add<ChatService>(_chatService!);
      Locator.add<ProximityService>(_proximityService!);

      // Connect to LiveKit
      final connected = await _liveKitService!.connect();
      debugPrint('LiveKit connected: $connected');

      if (connected) {
        // Enable camera and microphone
        await _liveKitService!.setCameraEnabled(true);
        await _liveKitService!.setMicrophoneEnabled(true);
      } else {
        _liveKitConnectionFailed = true;
      }

      setState(() {}); // Trigger rebuild to show overlay
    }
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
                    // Side panel - map editor or chat
                    StreamBuilder<AuthUser>(
                      stream: locate<AuthService>().authStateChanges,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData ||
                            snapshot.data is SignedOutUser) {
                          return const SizedBox.shrink();
                        }
                        final techWorld = locate<TechWorld>();
                        return ValueListenableBuilder<bool>(
                          valueListenable: techWorld.mapEditorActive,
                          builder: (context, editorActive, _) {
                            if (editorActive) {
                              return SizedBox(
                                width: constraints.maxWidth >= 800 ? 480 : 360,
                                child: MapEditorPanel(
                                  state: _mapEditorState,
                                  onClose: techWorld.exitEditorMode,
                                  referenceMap: techWorld.currentMap.value,
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
                // Auth menu + map editor button - top right when authenticated
                StreamBuilder<AuthUser>(
                  stream: locate<AuthService>().authStateChanges,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data is SignedOutUser) {
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
                            MapSelector(techWorld: locate<TechWorld>()),
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
                    if (!snapshot.hasData || snapshot.data is SignedOutUser) {
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
                        return _CodeEditorModal(
                          challenge: challenge,
                          onClose: techWorld.closeEditor,
                          onSubmit: (code) {
                            final chatService =
                                Locator.maybeLocate<ChatService>();
                            if (chatService != null) {
                              chatService.sendMessage(
                                'Please review my "${challenge.title}" '
                                'solution:\n\n```dart\n$code\n```',
                              );
                            }
                            techWorld.closeEditor();
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
    required this.onClose,
    required this.onSubmit,
  });

  final Challenge challenge;
  final VoidCallback onClose;
  final void Function(String code) onSubmit;

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
                      onClose: onClose,
                      onSubmit: onSubmit,
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
