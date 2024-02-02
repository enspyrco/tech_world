import 'package:abstractions/beliefs.dart';

import '../../app/app_beliefs.dart';

class DismissChallenge extends Conclusion<AppBeliefs> {
  const DismissChallenge();

  @override
  AppBeliefs conclude(AppBeliefs state) {
    return state.copyWith(challenge: null);
  }

  @override
  toJson() => {'name_': 'DismissChallenge', 'state_': <String, dynamic>{}};
}
