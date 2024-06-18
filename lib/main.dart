import 'package:flutter/material.dart';
import 'package:firedart/firedart.dart';
import 'package:tech_world/firebase/firebase_auth.dart';
import 'package:tech_world/firebase/firebase_config.dart';
import 'package:tech_world/livekit/pages/connect.dart';

void main() {
  FirebaseAuth.initialize(
    firebaseWebApiKey,
    VolatileStore(),
  );
  Firestore.initialize(firebaseProjectId);

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
                  child: StreamBuilder<bool>(
                    stream: FirebaseAuth.instance.signInState,
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data == true) {
                        return const ConnectPage();
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
