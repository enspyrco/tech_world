import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:tech_world/flame/components/barriers_component.dart';
import 'package:tech_world/flame/components/grid_component.dart';
import 'package:tech_world/flame/components/path_component.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:tech_world/flame/shared/constants.dart';

/// We create a [TechWorld] component by extending flame's [World] class and
/// the world world compent adds all other components that make up the game world.
///
/// The [TechWorld] component responds to taps by calculating the selected
/// grid point in minigrid space then passing the player position and selected
/// grid point to the [PathComponent]. The list of [Direction]s calculated in
/// the [PathComponent] are then passed to the [Player] component where they
/// are used to create a set of [MoveEffect]s and set the appropriate animation.
class TechWorld extends World with TapCallbacks {
  final PlayerComponent _playerComponent =
      PlayerComponent(position: Vector2(0, 0));
  final GridComponent _gridComponent = GridComponent();
  final BarriersComponent _barriersComponent = BarriersComponent();
  late PathComponent _pathComponent;

  @override
  Future<void> onLoad() async {
    _pathComponent = PathComponent(barriers: _barriersComponent);

    await add(_gridComponent);
    await add(_pathComponent);
    await add(_barriersComponent);
    await add(_playerComponent);
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    int miniGridX = (event.canvasPosition.x / gridSquareSize).floor();
    int miniGridY = (event.canvasPosition.y / gridSquareSize).floor();

    _pathComponent.calculatePath(
        start: _playerComponent.miniGridPosition,
        end: Point(miniGridX, miniGridY));

    _pathComponent.drawPath();

    _playerComponent.move(_pathComponent.directions);
  }
}
