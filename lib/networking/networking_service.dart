import 'dart:async';
import 'dart:convert';

import 'package:tech_world/auth/auth_user.dart';
import 'package:tech_world/flame/players_service.dart';
import 'package:tech_world/networking/constants.dart' as constants;
import 'package:tech_world_networking_types/tech_world_networking_types.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _uriString = constants.usCentral1ServerUrl;

/// The core of th [NetworkingService] is a websocket connected to a CloudRun
/// instance.
///
/// Incoming events are [_identify]'d, converted to missions and pushed into the
/// stream controlled by [_missionsStreamController].  A middleware ensures the
/// missions are dispatched to the [Store].
class NetworkingService {
  NetworkingService(
      {required PlayersService playersService,
      required Stream<AuthUser> authUserStream})
      : _playersService = playersService {
    _connect();
    _authUserStreamSubscription = authUserStream.listen((authUser) {
      if (authUser is SignedOutUser) {
        _announceDeparture(authUser);
      } else {
        _announceArrival(authUser);
      }
    });
  }

  // int _departureTime = 0;
  final PlayersService _playersService;
  late StreamSubscription<AuthUser> _authUserStreamSubscription;
  WebSocketChannel? _webSocket;
  StreamSubscription<dynamic>? _serverSubscription;
  Stream<Object?>? _serverStream;
  Sink<Object?>? _serverSink;

  // Create a websocket connected to the server and attach callbacks.
  void _connect() {
    print('connecting to $_uriString');
    _webSocket = WebSocketChannel.connect(Uri.parse(_uriString));
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

  // Announce our arrival to the set of clients running the game.
  void _announceArrival(AuthUser authUser) => _serverSink?.add(
        jsonEncode(
          ArrivalMessage(NetworkUser(
                  id: authUser.id, displayName: authUser.displayName))
              .toJson(),
        ),
      );

  // Announce our departure to the set of clients running the game.
  void _announceDeparture(AuthUser user) =>
      _serverSink?.add(jsonEncode(DepartureMessage(user.id).toJson()));

  void publish(ServerMessage message) {
    // record time and send data via websocket
    // _departureTime = DateTime.now().millisecondsSinceEpoch;
    final jsonString = jsonEncode(message.toJson());
    _serverSink?.add(jsonString);
  }

  void _identify(JsonMap json) {
    print('identifying: $json');
    // Check the type of data in the event and respond appropriately.
    if (json['type'] == 'other_players') {
      final message = OtherPlayersMessage.fromJson(json);
      _playersService.inspectAndUpdate(message.users);
    } else if (json['type'] == 'player_path') {
      final message = PlayerPathMessage.fromJson(json);
      // if (message.userId == _userId) {
      //   print('ws: ${DateTime.now().millisecondsSinceEpoch - _departureTime}');
      // }
      _playersService.addPathToPlayer(message.userId, message.points);
    }
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
    await _authUserStreamSubscription.cancel();
  }
}
