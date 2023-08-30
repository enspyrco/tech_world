import 'package:abstractions/beliefs.dart';

import '../../app/state/app_state.dart';

class SetOtherPlayerIds extends Conclusion<AppState> {
  const SetOtherPlayerIds(this.ids);

  final Set<String> ids;

  @override
  AppState conclude(AppState state) {
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
