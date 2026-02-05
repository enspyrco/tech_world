import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:tech_world/auth/auth_gate.dart';
import 'package:tech_world/auth/auth_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:tech_world/auth/auth_user.dart';
import 'package:tech_world/chat/chat_panel.dart';
import 'package:tech_world/chat/chat_service.dart';
import 'package:tech_world/editor/code_editor_panel.dart';
import 'package:tech_world/editor/predefined_challenges.dart';
import 'package:tech_world/flame/maps/predefined_maps.dart';
import 'package:tech_world/flame/tech_world.dart';
import 'package:tech_world/flame/tech_world_game.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/livekit/widgets/proximity_video_overlay.dart';
import 'package:tech_world/proximity/proximity_service.dart';
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
        roomName: defaultMap.id,
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
                    // Side panel - chat or code editor
                    StreamBuilder<AuthUser>(
                      stream: locate<AuthService>().authStateChanges,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData ||
                            snapshot.data is SignedOutUser) {
                          return const SizedBox.shrink();
                        }
                        final techWorld = locate<TechWorld>();
                        return ValueListenableBuilder<String?>(
                          valueListenable: techWorld.activeChallenge,
                          builder: (context, challengeId, _) {
                            if (challengeId != null) {
                              final challenge = allChallenges.firstWhere(
                                (c) => c.id == challengeId,
                                orElse: () => allChallenges.first,
                              );
                              return SizedBox(
                                width: constraints.maxWidth >= 800 ? 480 : 360,
                                child: CodeEditorPanel(
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
                                ),
                              );
                            }
                            // Default: show chat panel
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
                            return SizedBox(
                              width: constraints.maxWidth >= 800 ? 320 : 280,
                              child: ChatPanel(
                                chatService: chatService,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
                // Auth menu - top right when authenticated
                StreamBuilder<AuthUser>(
                  stream: locate<AuthService>().authStateChanges,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data is SignedOutUser) {
                      return const SizedBox.shrink();
                    }
                    return Positioned(
                      top: 16,
                      right: constraints.maxWidth >= 800 ? 336 : 296,
                      child: SafeArea(
                        child: AuthMenu(
                          displayName: snapshot.data!.displayName,
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
