import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:tech_world/auth/auth_gate.dart';
import 'package:tech_world/auth/auth_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:tech_world/auth/auth_user.dart';
import 'package:tech_world/flame/tech_world.dart';
import 'package:tech_world/flame/tech_world_game.dart';
import 'package:tech_world/networking/constants.dart' as constants;
import 'package:tech_world/networking/networking_service.dart';
import 'firebase_options.dart';
import 'package:tech_world/utils/locator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final authService = AuthService();
  final networkingService = NetworkingService(
    uriString: constants.usEast1ComputeEngine,
    authUserStream: authService.authStateChanges,
  );
  final techWorld = TechWorld(
      authStateChanges: authService.authStateChanges,
      playerPaths: networkingService.playerPaths,
      userAdded: networkingService.userAdded,
      userRemoved: networkingService.userRemoved);

  Locator.add<AuthService>(authService);
  Locator.add<NetworkingService>(networkingService);
  Locator.add<TechWorld>(techWorld);

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
                      if (snapshot.hasData &&
                          snapshot.data! is! SignedOutUser) {
                        return // const ConnectPage();
                            GameWidget(
                          game: TechWorldGame(world: locate<TechWorld>()),
                        );
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
