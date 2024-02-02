import 'dart:async';

import 'package:flutterfire_firestore_service/flutterfire_firestore_service.dart';
import 'package:flutterfire_firebase_auth_for_perception/flutterfire_firebase_auth_for_perception.dart';
import 'package:percepts/percepts.dart';
import 'package:error_correction_in_perception/error_correction_in_perception.dart';
import 'package:introspection/introspection.dart';
import 'package:locator_for_perception/locator_for_perception.dart';
import 'package:framing_in_perception/framing_in_perception.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firestore_service_interface/firestore_service_interface.dart';
import 'package:flutter/material.dart';
import 'package:abstractions/beliefs.dart';

import '../home/home_screen.dart';
import 'app_beliefs.dart';
import '../firebase_options.dart';
import '../game/tech_world_game.dart';
import '../networking/missions/update_game_server_connection.dart';
import '../networking/services/networking_service.dart';

Future<void> setupPriors() async {
  /// Setup FlutterFire
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  /// Setup Locator so plugins can add SystemChecks & Routes, configure the AppState, etc.
  Locator.add<Habits>(DefaultHabits());
  Locator.add<PageGenerator>(DefaultPageGenerator());
  Locator.add<AppBeliefs>(AppBeliefs.initial);

  ///
  Locator.add<FirestoreService>(FlutterfireFirestoreService());
  Locator.add<NetworkingService>(NetworkingService());

  /// Perform individual plugin initialization
  initializeErrorHandling<AppBeliefs>();
  initializeIdentity<AppBeliefs>(
      initialScreen: const HomeScreen(),
      considerOnSignedIn: [const UpdateGameServerConnection()],
      considerOnSignedOut: [const UpdateGameServerConnection()]);
  initializeIntrospection<AppBeliefs>();
  initializeFraming<AppBeliefs>();

  /// Finally, create our BeliefSystem and add to the Locator.
  final beliefSystem = DefaultBeliefSystem<AppBeliefs>(
      beliefs: locate<AppBeliefs>(),
      errorHandlers: DefaultErrorHandlers<AppBeliefs>(),
      habits: locate<Habits>(),
      beliefSystemFactory: ParentingBeliefSystem.new);
  Locator.add<BeliefSystem<AppBeliefs>>(beliefSystem);

  Locator.add<TechWorldGame>(
      TechWorldGame(appStateChanges: beliefSystem.onBeliefUpdate));
}

class OriginOPerception extends StatelessWidget {
  const OriginOPerception({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (const bool.fromEnvironment('IN-APP-INTROSPECTION'))
          Expanded(
            flex: 1,
            child: Material(
              child: IntrospectionScreen(locate<IntrospectionHabit>().stream),
            ),
          ),
        Expanded(
          flex: 1,
          child: FramingBuilder<AppBeliefs>(
            onInit: (beliefSystem) => beliefSystem.consider(
              const ObservingIdentity<AppBeliefs,
                  FlutterfireFirebaseAuthSubsystem>(),
            ),
          ),
        ),
      ],
    );
  }
}
