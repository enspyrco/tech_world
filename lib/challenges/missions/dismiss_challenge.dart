import 'package:abstractions/beliefs.dart';

import '../../app/state/app_state.dart';

class DismissChallenge extends Conclusion<AppState> {
  const DismissChallenge();

  @override
  AppState update(AppState state) {
    return state.copyWith(challenge: null);
  }

  @override
  toJson() => {'name_': 'DismissChallenge', 'state_': <String, dynamic>{}};
}
