import 'dart:async';

import 'package:locator_for_perception/locator_for_perception.dart';
import 'package:types_for_auth/types_for_auth.dart';
import 'package:abstractions/beliefs.dart';

import '../../app/state/app_state.dart';
import '../services/networking_service.dart';

StreamSubscription<Cognition>? _subscription;

/// ConnectGameServer is launched when auth state changes to either signedIn
/// or notSignedIn. The [UpdateGameServerConnection.consider] connects or disconnects
/// based on on the app state.
class UpdateGameServerConnection extends Consideration<AppState> {
  const UpdateGameServerConnection();

  @override
  Future<void> consider(BeliefSystem<AppState> beliefSystem) async {
    var service = locate<NetworkingService>();
    var state = beliefSystem.state;

    if (state.auth.user.signedIn == SignedInState.notSignedIn) {
      _subscription?.cancel();
      service.disconnect();
      return;
    }

    if (state.auth.user.signedIn == SignedInState.signedIn) {
      // listen to the networking service and dispatch any actions
      _subscription = service.missionsStream.listen(beliefSystem.conclude,
          onError: (Object error) => throw error);
      // ask the networking service to connect to the server
      service.connect(state.auth.user.uid!);
      return;
    }

    throw 'ConnectGameServer AwayMission was launched when state.auth.user.signedIn was ${state.auth.user.signedIn}.\n'
        'The mission assumes either SignedInState.signedIn or SignedInState.notSignedIn.\n'
        'Use the Inspector to determine what changed the state.';
  }

  @override
  toJson() => {'name_': 'ConnectGameServer', 'state_': <String, dynamic>{}};
}
