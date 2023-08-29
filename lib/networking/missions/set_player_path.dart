import 'package:abstractions/beliefs.dart';
import 'package:ws_game_server_types/ws_game_server_types.dart';

import '../../app/state/app_state.dart';

class SetPlayerPath extends Conclusion<AppState> {
  const SetPlayerPath(this.message);

  final PlayerPathMessage message;

  @override
  AppState update(AppState state) {
    return state.copyWith(
        game: state.game.copyWith(
            playerPaths: state.game.playerPaths
              ..[message.userId] = message.points.toList()));
  }

  @override
  toJson() => {
        'name_': 'SetPlayerPath',
        'state_': {'message': message.toJson()}
      };
}
