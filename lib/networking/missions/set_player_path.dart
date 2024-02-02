import 'package:abstractions/beliefs.dart';
import 'package:ws_game_server_types/ws_game_server_types.dart';

import '../../app/app_beliefs.dart';

class SetPlayerPath extends Conclusion<AppBeliefs> {
  const SetPlayerPath(this.message);

  final PlayerPathMessage message;

  @override
  AppBeliefs conclude(AppBeliefs state) {
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
