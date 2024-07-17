import 'dart:async';

import 'package:flame/components.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:tech_world/flame/shared/player_path.dart';
import 'package:tech_world_networking_types/tech_world_networking_types.dart';

class PlayersService {
  PlayersService();
  final Map<String, PlayerComponent> _otherPlayersMap = {};
  final userAddedController = StreamController<NetworkUser>.broadcast();
  final userRemovedController = StreamController<String>.broadcast();
  final playerPathController = StreamController<PlayerPath>.broadcast();

  Stream<NetworkUser> get userAdded => userAddedController.stream;
  Stream<String> get userRemoved => userRemovedController.stream;
  Stream<PlayerPath> get playerPaths => playerPathController.stream;

  void inspectAndUpdate(Set<NetworkUser> networkUsers) {
    // add new players
    for (final networkUser in networkUsers) {
      if (!_otherPlayersMap.containsKey(networkUser.id)) {
        _otherPlayersMap[networkUser.id] = PlayerComponent.from(networkUser);
        userAddedController.add(networkUser);
      }
    }
    // remove departed players
    for (final playerId in _otherPlayersMap.keys) {
      if (networkUsers.where((authUser) => authUser.id == playerId).isEmpty) {
        userRemovedController.add(playerId);
        _otherPlayersMap.remove(playerId);
      }
    }
  }

  void addPathToPlayer(String playerId, List<Double2> points) {
    playerPathController.add(
      PlayerPath(
        playerId: playerId,
        largeGridPoints:
            points.map<Vector2>((point) => Vector2(point.x, point.y)).toList(),
      ),
    );
  }
}
