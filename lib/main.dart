import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:firedart/firedart.dart';
import 'package:tech_world/firebase/firebase_config.dart';
import 'package:tech_world/flame/tech_world.dart';
import 'package:tech_world/flame/tech_world_game.dart';

void main() {
  FirebaseAuth.initialize(
    firebaseWebApiKey,
    VolatileStore(),
  );
  Firestore.initialize(firebaseProjectId);

  final techWorldGame = TechWorldGame(world: TechWorld());

  runApp(MyApp(game: techWorldGame));
}

class MyApp extends StatelessWidget {
  const MyApp({required this.game, super.key});

  final TechWorldGame game;

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
                  child: GameWidget(game: game),
                  // StreamBuilder<bool>(
                  //   stream: FirebaseAuth.instance.signInState,
                  //   builder: (context, snapshot) {
                  //     if (snapshot.hasData && snapshot.data == true) {
                  //       return GameWidget(game: game); // ConnectPage();
                  //     } else {
                  //       return const AuthGate();
                  //     }
                  //   },
                  // ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
