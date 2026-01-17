import 'dart:async' show StreamSubscription, unawaited;
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:tech_world/auth/auth_user.dart';
import 'package:tech_world/flame/components/barriers_component.dart';
import 'package:tech_world/flame/components/grid_component.dart';
import 'package:tech_world/flame/components/path_component.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:tech_world/flame/managers/bubble_manager.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/shared/player_path.dart';
import 'package:tech_world/flame/shared/tech_world_config.dart';
import 'package:tech_world/flame/tech_world_game.dart';
import 'package:tech_world/livekit/livekit_service.dart';
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
  late BubbleManager _bubbleManager;

  // LiveKit integration for video bubbles
  LiveKitService? _liveKitService;

  final Stream<NetworkUser> _userAddedStream;
  final Stream<NetworkUser> _userRemovedStream;
  final Stream<PlayerPath> _playerPathsStream;
  final Stream<AuthUser> _authStateChanges;
  StreamSubscription<AuthUser>? _authStateChangesSubscription;
  StreamSubscription<NetworkUser>? _userAddedSubscription;
  StreamSubscription<NetworkUser>? _userRemovedSubscription;
  StreamSubscription<PlayerPath>? _playerPathsSubscription;
  StreamSubscription<(Participant, VideoTrack)>? _trackSubscribedSubscription;
  StreamSubscription<LocalTrackPublication>? _localTrackPublishedSubscription;

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

    _bubbleManager.update(
      localPlayerPosition: _userPlayerComponent.miniGridPosition,
      localPlayerDisplayName: _userPlayerComponent.displayName,
      localPlayerId: _userPlayerComponent.id,
      otherPlayers: _otherPlayerComponentsMap,
    );
  }

  /// Load the video bubble shader program
  Future<void> _loadVideoBubbleShader() async {
    try {
      final shaderProgram =
          await ui.FragmentProgram.fromAsset('shaders/video_bubble.frag');
      _bubbleManager.setShaderProgram(shaderProgram);
    } catch (e) {
      // Shader loading failed - video bubbles will render without effects
    }
  }

  /// Connect to LiveKit room
  Future<void> _connectToLiveKit(String userId, String displayName) async {
    if (_liveKitService != null) {
      debugPrint('LiveKit already initialized');
      return;
    }

    debugPrint('Initializing LiveKit for user: $userId');
    _liveKitService = LiveKitService(
      userId: userId,
      displayName: displayName,
    );

    _bubbleManager.setLiveKitService(_liveKitService!);

    // Listen for participant events to update video bubbles
    _liveKitService!.participantJoined.listen((participant) {
      debugPrint('LiveKit participant joined: ${participant.identity}');
      _refreshBubble(participant.identity);
    });

    _liveKitService!.speakingChanged.listen((event) {
      final (participant, isSpeaking) = event;
      _bubbleManager.updateSpeakingState(participant.identity, isSpeaking);
    });

    // Listen for track subscription events to trigger capture init immediately
    _trackSubscribedSubscription =
        _liveKitService!.trackSubscribed.listen((event) {
      final (participant, _) = event;
      _bubbleManager.notifyTrackReady(participant.identity);
    });

    // Listen for local track publication to refresh local bubble when camera is ready
    _localTrackPublishedSubscription =
        _liveKitService!.localTrackPublished.listen((publication) {
      if (publication.kind == TrackType.VIDEO) {
        _refreshBubble(TechWorldConfig.localPlayerBubbleKey, isLocal: true);
      }
    });

    // Connect to room
    final connected = await _liveKitService!.connect();
    if (connected) {
      debugPrint('LiveKit connected successfully');

      // Enable camera and microphone in the background (don't block game loop)
      // The localTrackPublished stream will notify us when tracks are ready
      unawaited(_liveKitService!.setCameraEnabled(true));
      unawaited(_liveKitService!.setMicrophoneEnabled(true));
    } else {
      debugPrint('LiveKit connection failed');
    }
  }

  /// Refresh a player's bubble (recreate if video is now available)
  void _refreshBubble(String bubbleKey, {bool isLocal = false}) {
    _bubbleManager.refreshBubble(
      bubbleKey,
      isLocal: isLocal,
      localPlayerDisplayName: _userPlayerComponent.displayName,
      localPlayerId: _userPlayerComponent.id,
      otherPlayers: _otherPlayerComponentsMap,
    );
  }

  @override
  Future<void> onLoad() async {
    _bubbleManager = BubbleManager(
      addComponent: add,
      localPlayerComponent: _userPlayerComponent,
    );
    _pathComponent = PathComponent(barriers: _barriersComponent);

    await add(_gridComponent);
    await add(_pathComponent);
    await add(_barriersComponent);
    await add(_userPlayerComponent);

    (findGame() as TechWorldGame?)?.camera.follow(_userPlayerComponent);

    // Load the video bubble shader
    await _loadVideoBubbleShader();

    _authStateChangesSubscription = _authStateChanges.listen((authUser) async {
      if (authUser is! PlaceholderUser && authUser is! SignedOutUser) {
        _userPlayerComponent.id = authUser.id;
        _userPlayerComponent.displayName = authUser.displayName;

        // Connect to LiveKit when user is authenticated
        await _connectToLiveKit(authUser.id, authUser.displayName);
      }
    });
    _userAddedSubscription = _userAddedStream.listen((networkUser) {
      debugPrint('Adding user: ${networkUser.id}');
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
      debugPrint(
          'Received path for ${path.playerId}, component exists: ${_otherPlayerComponentsMap.containsKey(path.playerId)}');
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
        start: _userPlayerComponent.miniGridTuple, end: (miniGridX, miniGridY));

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

  void dispose() {
    _userAddedSubscription?.cancel();
    _userRemovedSubscription?.cancel();
    _playerPathsSubscription?.cancel();
    _authStateChangesSubscription?.cancel();
    _trackSubscribedSubscription?.cancel();
    _localTrackPublishedSubscription?.cancel();
    _liveKitService?.dispose();
  }
}
