import 'dart:async';
import 'dart:convert';

import 'package:flame/components.dart';
import 'package:tech_world/auth/auth_user.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/flame/shared/player_path.dart';
import 'package:tech_world_networking_types/tech_world_networking_types.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The core of th [NetworkingService] is a websocket connected to the game server.
///
/// When the [NetworkingService] is created it connects to the websocket server
/// at [uriString], unless a pre-made [WebSocketChannel] is supplied (for tests).
///
/// Incoming events are [_identify]'d and pushed into the appropriate stream.
///
///
class NetworkingService {
  NetworkingService(
      {required Stream<AuthUser> authUserStream,
      required String uriString,
      WebSocketChannel? webSocketChannel}) {
    _connect(uriString: uriString, webSocketChannel: webSocketChannel);
    _authUserStreamSubscription = authUserStream.listen((authUser) {
      if (authUser is SignedOutUser) {
        _announceDeparture(authUser);
      } else {
        _announceArrival(authUser);
      }
    });
  }

  // int _departureTime = 0;
  Set<NetworkUser> _otherNetworkUsers = {};
  final _userAddedController = StreamController<NetworkUser>();
  final _userRemovedController = StreamController<NetworkUser>();
  final _playerPathController = StreamController<PlayerPath>();
  StreamSubscription<AuthUser>? _authUserStreamSubscription;
  WebSocketChannel? _webSocket;
  StreamSubscription<dynamic>? _serverSubscription;
  Stream<Object?>? _serverStream;
  Sink<Object?>? _serverSink;

  Stream<NetworkUser> get userAdded => _userAddedController.stream;
  Stream<NetworkUser> get userRemoved => _userRemovedController.stream;
  Stream<PlayerPath> get playerPaths => _playerPathController.stream;

  publishPath({
    required String uid,
    required List<Double2> points,
    required List<Direction> directions,
  }) {
    final message = PlayerPathMessage(
        userId: uid,
        points: points,
        directions:
            directions.map<String>((direction) => direction.name).toList());
    _publish(message);
  }

  void _publish(ServerMessage message) {
    // record time and send data via websocket
    // _departureTime = DateTime.now().millisecondsSinceEpoch;
    final jsonString = jsonEncode(message.toJson());
    _serverSink?.add(jsonString);
  }

  // Create a websocket connected to the server and attach callbacks.
  void _connect(
      {required String uriString, WebSocketChannel? webSocketChannel}) {
    print('connecting to $uriString');
    _webSocket =
        webSocketChannel ?? WebSocketChannel.connect(Uri.parse(uriString));
    _serverStream = _webSocket!.stream;
    _serverSink = _webSocket!.sink;

    // Listen to the websocket, identify events & add missions to a stream
    _serverSubscription = _serverStream?.listen(
      (dynamic data) {
        _identify(jsonDecode(data as String) as JsonMap);
      },
      onError: (dynamic err) =>
          print('${DateTime.now()} > CONNECTION ERROR: $err'),
      onDone: () => print(
          '${DateTime.now()} > CONNECTION DONE! closeCode=${_webSocket?.closeCode}, closeReason= ${_webSocket?.closeReason}'),
    );
  }

  void _identify(JsonMap json) {
    print('identifying: $json');
    // Check the type of data in the event and respond appropriately.
    if (json['type'] == 'other_players') {
      final message = OtherUsersMessage.fromJson(json);
      _inspectAndUpdate(message.users);
    } else if (json['type'] == 'player_path') {
      final message = PlayerPathMessage.fromJson(json);
      // if (message.userId == _userId) {
      //   print('ws: ${DateTime.now().millisecondsSinceEpoch - _departureTime}');
      // }
      _addPathToPlayer(
        message.userId,
        message.points,
        message.directions
            .map<Direction>(
              (directionString) =>
                  Direction.values.asNameMap()[directionString] ??
                  Direction.none,
            )
            .toList(),
      );
    }
  }

  // Announce our arrival to the set of clients running the game.
  void _announceArrival(AuthUser authUser) => _serverSink?.add(
        jsonEncode(
          ArrivalMessage(
            NetworkUser(id: authUser.id, displayName: authUser.displayName),
          ).toJson(),
        ),
      );

  // Announce our departure to the set of clients running the game.
  void _announceDeparture(AuthUser user) =>
      _serverSink?.add(jsonEncode(DepartureMessage(user.id).toJson()));

  void _inspectAndUpdate(Set<NetworkUser> newNetworkUsers) {
    if (newNetworkUsers.length > _otherNetworkUsers.length) {
      Set<NetworkUser> differenceSet =
          newNetworkUsers.difference(_otherNetworkUsers);
      for (final user in differenceSet) {
        _userAddedController.add(user);
      }
      _otherNetworkUsers = newNetworkUsers;
    } else if (_otherNetworkUsers.length > newNetworkUsers.length) {
      Set<NetworkUser> differenceSet =
          _otherNetworkUsers.difference(newNetworkUsers);
      for (final user in differenceSet) {
        _userRemovedController.add(user);
      }
      _otherNetworkUsers = newNetworkUsers;
    }
  }

  void _addPathToPlayer(
      String playerId, List<Double2> points, List<Direction> directions) {
    _playerPathController.add(
      PlayerPath(
          playerId: playerId,
          largeGridPoints: points
              .map<Vector2>((point) => Vector2(point.x, point.y))
              .toList(),
          directions: directions),
    );
  }

  Future<void> _disconnect() async {
    print('disconnecting from websocket server...');
    await _serverSubscription?.cancel();
    if (_webSocket != null) {
      _serverSink?.close();
      _webSocket = null;
    }
  }

  Future<void> dispose() async {
    await _disconnect();
    await _authUserStreamSubscription?.cancel();
  }
}
