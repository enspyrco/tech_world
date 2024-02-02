import 'dart:async';

import 'package:locator_for_perception/locator_for_perception.dart';
import 'package:types_for_auth/types_for_auth.dart';
import 'package:abstractions/beliefs.dart';

import '../../app/app_beliefs.dart';
import '../services/networking_service.dart';

StreamSubscription<Cognition>? _subscription;

/// ConnectGameServer is launched when auth state changes to either signedIn
/// or notSignedIn. The [UpdateGameServerConnection.consider] connects or disconnects
/// based on on the app state.
class UpdateGameServerConnection extends Consideration<AppBeliefs> {
  const UpdateGameServerConnection();

  @override
  Future<void> consider(BeliefSystem<AppBeliefs> beliefSystem) async {
    var service = locate<NetworkingService>();
    var state = beliefSystem.beliefs;

    if (state.identity.userAuthState.signedIn == SignedInState.notSignedIn) {
      _subscription?.cancel();
      service.disconnect();
      return;
    }

    if (state.identity.userAuthState.signedIn == SignedInState.signedIn) {
      // listen to the networking service and dispatch any actions
      _subscription = service.missionsStream.listen(beliefSystem.conclude,
          onError: (Object error) => throw error);
      // ask the networking service to connect to the server
      service.connect(state.identity.userAuthState.uid!);
      return;
    }

    throw 'ConnectGameServer AwayMission was launched when state.identity.userAuthState.signedIn was ${state.identity.userAuthState.signedIn}.\n'
        'The mission assumes either SignedInState.signedIn or SignedInState.notSignedIn.\n'
        'Use the Inspector to determine what changed the state.';
  }

  @override
  toJson() => {'name_': 'ConnectGameServer', 'state_': <String, dynamic>{}};
}
