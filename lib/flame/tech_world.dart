import 'dart:async';
import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:tech_world/auth/auth_user.dart';
import 'package:tech_world/flame/components/barriers_component.dart';
import 'package:tech_world/flame/components/bot_bubble_component.dart';
import 'package:tech_world/flame/components/grid_component.dart';
import 'package:tech_world/flame/components/path_component.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/shared/player_path.dart';
import 'package:tech_world/flame/tech_world_game.dart';
import 'package:tech_world/networking/networking_service.dart';
import 'package:tech_world/utils/locator.dart';
import 'package:tech_world_networking_types/tech_world_networking_types.dart';

/// We create a [TechWorld] component by extending flame's [World] class and
/// the world world compent adds all other components that make up the game world.
///
/// The [TechWorld] component responds to taps by calculating the selected
/// grid point in minigrid space then passing the player position and selected
/// grid point to the [PathComponent]. The list of [Direction]s calculated in
/// the [PathComponent] are then passed to the [Player] component where they
/// are used to create a set of [MoveEffect]s and set the appropriate animation.
class TechWorld extends World with TapCallbacks {
  TechWorld(
      {required Stream<AuthUser> authStateChanges,
      required Stream<NetworkUser> userAdded,
      required Stream<NetworkUser> userRemoved,
      required Stream<PlayerPath> playerPaths})
      : _authStateChanges = authStateChanges,
        _userAddedStream = userAdded,
        _userRemovedStream = userRemoved,
        _playerPathsStream = playerPaths;

  final PlayerComponent _userPlayerComponent = PlayerComponent(
    position: Vector2(0, 0),
    id: '',
    displayName: '',
  );

  final Map<String, PlayerComponent> _otherPlayerComponentsMap = {};
  final GridComponent _gridComponent = GridComponent();
  final BarriersComponent _barriersComponent = BarriersComponent();
  late PathComponent _pathComponent;

  // Bot bubble component - shown when player is near the bot
  static const _botUserId = 'bot-claude';
  static const _botDisplayName = 'Claude';
  static const _proximityThreshold = 3; // grid squares
  static final _botBubbleOffset =
      Vector2(16, -20); // center horizontally, above sprite
  BotBubbleComponent? _botBubble;
  Point<int>? _lastPlayerGridPosition; // track to skip unnecessary updates

  final Stream<NetworkUser> _userAddedStream;
  final Stream<NetworkUser> _userRemovedStream;
  final Stream<PlayerPath> _playerPathsStream;
  final Stream<AuthUser> _authStateChanges;
  StreamSubscription<AuthUser>? _authStateChangesSubscription;
  StreamSubscription<NetworkUser>? _userAddedSubscription;
  StreamSubscription<NetworkUser>? _userRemovedSubscription;
  StreamSubscription<PlayerPath>? _playerPathsSubscription;

  // Position tracking for proximity detection
  Point<int> get localPlayerPosition => _userPlayerComponent.miniGridPosition;
  String get localPlayerId => _userPlayerComponent.id;

  Map<String, Point<int>> get otherPlayerPositions {
    return _otherPlayerComponentsMap.map(
      (id, component) => MapEntry(id, component.miniGridPosition),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    _updateBotBubbleVisibility();
  }

  void _updateBotBubbleVisibility() {
    final botComponent = _otherPlayerComponentsMap[_botUserId];
    if (botComponent == null) {
      // Bot not in game, remove bubble if present
      _botBubble?.removeFromParent();
      _botBubble = null;
      _lastPlayerGridPosition = null;
      return;
    }

    // Skip update if player hasn't moved to a new grid position
    final playerGrid = _userPlayerComponent.miniGridPosition;
    if (_lastPlayerGridPosition == playerGrid && _botBubble != null) {
      return;
    }
    _lastPlayerGridPosition = playerGrid;

    // Calculate Chebyshev distance (max of x/y difference)
    final botGrid = botComponent.miniGridPosition;
    final distance = max(
      (botGrid.x - playerGrid.x).abs(),
      (botGrid.y - playerGrid.y).abs(),
    );

    final isNearby = distance <= _proximityThreshold;

    if (isNearby && _botBubble == null) {
      // Show bubble - position it above the bot
      _botBubble = BotBubbleComponent(name: _botDisplayName);
      _botBubble!.position = botComponent.position + _botBubbleOffset;
      add(_botBubble!);
    } else if (isNearby && _botBubble != null) {
      // Update bubble position to follow bot
      _botBubble!.position = botComponent.position + _botBubbleOffset;
    } else if (!isNearby && _botBubble != null) {
      // Hide bubble
      _botBubble!.removeFromParent();
      _botBubble = null;
    }
  }

  @override
  Future<void> onLoad() async {
    _pathComponent = PathComponent(barriers: _barriersComponent);

    await add(_gridComponent);
    await add(_pathComponent);
    await add(_barriersComponent);
    await add(_userPlayerComponent);

    (findGame() as TechWorldGame?)?.camera.follow(_userPlayerComponent);

    _authStateChangesSubscription = _authStateChanges.listen((authUser) {
      if (authUser is! PlaceholderUser && authUser is! SignedOutUser) {
        _userPlayerComponent.id = authUser.id;
        _userPlayerComponent.displayName = authUser.displayName;
      }
    });
    _userAddedSubscription = _userAddedStream.listen((networkUser) {
      final playerComponent = PlayerComponent.from(networkUser);
      _otherPlayerComponentsMap[networkUser.id] = playerComponent;
      add(playerComponent);
    });
    _userRemovedSubscription = _userRemovedStream.listen((networkUser) {
      final playerComponent = _otherPlayerComponentsMap.remove(networkUser.id);
      if (playerComponent != null) {
        remove(playerComponent);
      }
    });
    _playerPathsSubscription = _playerPathsStream.listen((PlayerPath path) {
      _otherPlayerComponentsMap[path.playerId]
          ?.move(path.directions, path.largeGridPoints);
    });
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    final worldPosition = event.localPosition;
    int miniGridX = (worldPosition.x / gridSquareSize).floor();
    int miniGridY = (worldPosition.y / gridSquareSize).floor();

    _pathComponent.calculatePath(
        start: _userPlayerComponent.miniGridPosition,
        end: Point(miniGridX, miniGridY));

    _pathComponent.drawPath();

    _userPlayerComponent.move(
        _pathComponent.directions, _pathComponent.largeGridPoints);

    final pathPoints = _pathComponent.largeGridPoints
        .map<Double2>((gridPoint) => Double2(x: gridPoint.x, y: gridPoint.y))
        .toList();

    locate<NetworkingService>().publishPath(
      uid: _userPlayerComponent.id,
      points: pathPoints,
      directions: _pathComponent.directions,
    );
  }

  dispose() {
    _userAddedSubscription?.cancel();
    _userRemovedSubscription?.cancel();
    _playerPathsSubscription?.cancel();
    _authStateChangesSubscription?.cancel();
  }
}
