import 'package:flutter/material.dart';
import 'package:tech_world/auth/auth_service.dart';
import 'package:tech_world/auth/auth_gate.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:tech_world/auth/auth_user.dart';
import 'package:tech_world/flame/players_service.dart';
import 'package:tech_world/flame/tech_world.dart';
import 'package:tech_world/flame/tech_world_game.dart';
import 'package:tech_world/livekit/pages/connect.dart';
import 'package:tech_world/networking/networking_service.dart';
import 'firebase_options.dart';
import 'package:tech_world/utils/locator.dart';

void main() async {
  final playersService = PlayersService();
  final authService = AuthService();
  Locator.add<AuthService>(authService);
  Locator.add<TechWorldGame>(
    TechWorldGame(
      world: TechWorld(
        authUser: PlaceholderUser(),
        playerPaths: playersService.playerPaths,
        userAdded: playersService.userAdded,
        userRemoved: playersService.userRemoved,
      ),
    ),
  );
  Locator.add<NetworkingService>(
    NetworkingService(
        playersService: playersService,
        authUserStream: authService.authStateChanges),
  );

  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            return Row(
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
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: constraints.maxWidth >= 1200
                      ? constraints.maxWidth / 2
                      : constraints.maxWidth,
                  child: StreamBuilder<AuthUser>(
                    stream: locate<AuthService>().authStateChanges,
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return const ConnectPage(); // GameWidget(game: game);
                      } else {
                        return const AuthGate();
                      }
                    },
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
