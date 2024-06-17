import 'package:flutter/material.dart';
import 'package:firedart/firedart.dart';

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
    return const MaterialApp(
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: StreamBuilder(
          stream: FirebaseAuth.instance.signInState,
          builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const CircularProgressIndicator();
            }
            if (snapshot.data == null) return const CircularProgressIndicator();
            final bool signedIn = snapshot.data!;
            if (snapshot.connectionState == ConnectionState.active ||
                snapshot.connectionState == ConnectionState.done) {
              if (signedIn) {
                return Column(
                  children: [
                    Text('user ${FirebaseAuth.instance.userId}'),
                    TextButton(
                        onPressed: () {
                          FirebaseAuth.instance.signOut();
                          setState(() {
                            _submitting = false;
                          });
                        },
                        child: const Text('Sign Out')),
                  ],
                );
              } else {
                return (_submitting)
                    ? const CircularProgressIndicator()
                    : Column(
                        children: [
                          TextField(
                            onSubmitted: (value) {
                              FirebaseAuth.instance
                                  .signUp('$value@email.com', '${value}abc123');
                              setState(() {
                                _submitting = true;
                              });
                            },
                          ),
                          TextButton(
                            onPressed: () {
                              FirebaseAuth.instance.signInAnonymously();
                            },
                            child: const Text('Sign in Anonymously'),
                          ),
                        ],
                      );
              }
            } else {
              return const CircularProgressIndicator();
            }
          },
        ),
      ),
    );
  }
}
