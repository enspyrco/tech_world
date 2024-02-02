import 'package:abstractions/beliefs.dart';

import '../../app/app_beliefs.dart';

class SetOtherPlayerIds extends Conclusion<AppBeliefs> {
  const SetOtherPlayerIds(this.ids);

  final Set<String> ids;

  @override
  AppBeliefs conclude(AppBeliefs state) {
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
