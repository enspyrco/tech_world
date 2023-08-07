import 'package:types_for_perception/beliefs.dart';

import '../../app/state/app_state.dart';

class SetOtherPlayerIds extends LandingMission<AppState> {
  const SetOtherPlayerIds(this.ids);

  final Set<String> ids;

  @override
  AppState landingInstructions(AppState state) {
    return state.copyWith(
        game: state.game
            .copyWith(otherPlayerIds: state.game.otherPlayerIds..addAll(ids)));
  }

  @override
  toJson() => {
        'name_': 'SetOtherPlayerIds',
        'state_': {'ids': ids.toList()}
      };
}
