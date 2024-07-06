import 'package:flame/components.dart';

class PlayerPath {
  PlayerPath({required this.playerId, required this.largeGridPoints});

  final String playerId;
  final List<Vector2> largeGridPoints;
}
