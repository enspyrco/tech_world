import 'dart:async';

import 'package:flutterfire_firestore_service/flutterfire_firestore_service.dart';
import 'package:identity_in_perception/identity_in_perception.dart';
import 'package:percepts/percepts.dart';
import 'package:error_correction_in_perception/error_correction_in_perception.dart';
import 'package:introspection/introspection.dart';
import 'package:locator_for_perception/locator_for_perception.dart';
import 'package:framing_in_perception/framing_in_perception.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firestore_service_interface/firestore_service_interface.dart';
import 'package:flutter/material.dart';
import 'package:abstractions/beliefs.dart';

import 'app/home_screen.dart';
import 'app/state/app_state.dart';
import 'firebase_options.dart';
import 'game/tech_world_game.dart';
import 'networking/missions/update_game_server_connection.dart';
import 'networking/services/networking_service.dart';

Future<void> setupPriors() async {
  /// Setup FlutterFire
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  /// Setup Locator so plugins can add SystemChecks & Routes, configure the AppState, etc.
  Locator.add<Habits>(DefaultHabits());
  Locator.add<PageGenerator>(DefaultPageGenerator());
  Locator.add<AppState>(AppState.initial);

  ///
  Locator.add<FirestoreService>(FlutterfireFirestoreService());
  Locator.add<NetworkingService>(NetworkingService());

  /// Perform any final initialization by the app such as setting up routes.
  initializeApp();

  /// Finally, create our BeliefSystem and add to the Locator.
  final beliefSystem = DefaultBeliefSystem<AppState>(
      beliefs: locate<AppState>(),
      errorHandlers: DefaultErrorHandlers<AppState>(),
      habits: locate<Habits>(),
      beliefSystemFactory: ParentingBeliefSystem.new);
  Locator.add<BeliefSystem<AppState>>(beliefSystem);

  Locator.add<TechWorldGame>(
      TechWorldGame(appStateChanges: beliefSystem.onBeliefUpdate));
}

void initializeApp() {
  /// Perform individual plugin initialization.
  initializeErrorHandling<AppState>();
  initializeAuthPlugin<AppState>(
      initialScreen: const HomeScreen(),
      launchOnSignedIn: [const UpdateGameServerConnection()],
      launchOnSignedOut: [const UpdateGameServerConnection()]);
  initializeIntrospection<AppState>();
  initializeFraming<AppState>();
}

class AstroBase extends StatelessWidget {
  const AstroBase({Key? key}) : super(key: key);

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
          child: FramingBuilder<AppState>(
            onInit: (beliefSystem) =>
                beliefSystem.consider(const BindAuthState<AppState>()),
          ),
        ),
      ],
    );
  }
}
