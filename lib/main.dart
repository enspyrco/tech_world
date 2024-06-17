import 'package:flutter/material.dart';
import 'package:firedart/firedart.dart';
import 'package:tech_world/auth.dart';

void main() {
  FirebaseAuth.initialize(
    'AIzaSyBha-SvfU-i7Ux5mr5xIAchaEBxWpRSnDU',
    VolatileStore(),
  );
  Firestore.initialize('adventures-in-tech-world-0');

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
                        return Column(
                          children: [
                            Text('user ${FirebaseAuth.instance.userId}'),
                            TextButton(
                                onPressed: () {
                                  FirebaseAuth.instance.signOut();
                                },
                                child: const Text('Sign Out')),
                          ],
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
