import 'package:flame/components.dart';
import 'package:tech_world/flame/shared/direction.dart';

class PlayerPath {
  PlayerPath({
    required this.playerId,
    required this.largeGridPoints,
    required this.directions,
  });

  final String playerId;
  final List<Direction> directions;
  final List<Vector2> largeGridPoints;
}
