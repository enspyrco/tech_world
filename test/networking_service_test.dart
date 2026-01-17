import 'dart:async';
import 'dart:convert';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/auth/auth_user.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/networking/networking_service.dart';
import 'package:tech_world_networking_types/tech_world_networking_types.dart';

import 'test-doubles/fake_web_socket_channel.dart';

void main() {
  test('sends arrival message on sign in, departure on sign out', () {
    final authUserController = StreamController<AuthUser>();
    final serverController = StreamController.broadcast();
    final fakeWebSocketChannel =
        FakeWebSocketChannel(serverController.stream, serverController.sink);

    NetworkingService(
      uriString: '',
      authUserStream: authUserController.stream,
      webSocketChannel: fakeWebSocketChannel,
      roomId: 'test_room',
    );

    // When a user signs in / signs out, the authUserStream passed into the
    // NetworkService will emit an AuthUser / SignedOutUser
    authUserController.add(AuthUser(id: 'id', displayName: 'displayName'));
    authUserController.add(SignedOutUser(id: 'id', displayName: 'displayName'));

    // The NetworkService is listening to the auth state changes and will create
    // and encode an ArrivalMessage on sign in then send it to the server. Then
    // on sign out encode a DepartureMessage and send it to the server.
    expect(
      serverController.stream,
      emitsInOrder(
        [
          '{"type":"arrival","user":{"id":"id","displayName":"displayName"},"roomId":"test_room"}',
          '{"type":"departure","userId":"id"}'
        ],
      ),
    );
  });

  test('when server sends OtherPlayersMessage, the difference is emitted', () {
    final serverController = StreamController.broadcast();
    final fakeWebSocketChannel =
        FakeWebSocketChannel(serverController.stream, serverController.sink);

    final networkingService = NetworkingService(
      uriString: '',
      authUserStream: StreamController<AuthUser>().stream,
      webSocketChannel: fakeWebSocketChannel,
      roomId: 'test_room',
    );

    // First we have the server send OtherUsersMessage with one user, then
    // another OtherUsersMessage with one more user. We check that both new
    // users were emitted by the userAdded stream.
    final user1 = NetworkUser(id: '1', displayName: 'user1');
    final message1 = OtherUsersMessage(users: {user1});
    serverController.add(jsonEncode(message1));
    final user2 = NetworkUser(id: '2', displayName: 'user2');
    final message2 = OtherUsersMessage(users: {user1, user2});
    serverController.add(jsonEncode(message2));

    expect(
      networkingService.userAdded,
      emitsInOrder([user1, user2]),
    );

    // Then we have the server send OtherUsersMessage with just one user again
    // and check the missing user was emitted by userRemoved stream.
    final message3 = OtherUsersMessage(users: {user2});
    serverController.add(jsonEncode(message3));
    expect(
      networkingService.userRemoved,
      emitsInOrder([user1]),
    );
  });

  test(
      'when server sends PlayerPathMessage, it is emitted through playerPaths stream',
      () async {
    final serverController = StreamController<String>.broadcast();
    final fakeWebSocketChannel =
        FakeWebSocketChannel(serverController.stream, serverController.sink);

    final networkingService = NetworkingService(
      uriString: '',
      authUserStream: StreamController<AuthUser>().stream,
      webSocketChannel: fakeWebSocketChannel,
      roomId: 'test_room',
    );

    // Set up a future to capture the emitted PlayerPath
    final playerPathFuture = networkingService.playerPaths.first;

    // Server sends a PlayerPathMessage
    final pathMessage = {
      'type': 'player_path',
      'userId': 'player123',
      'roomId': 'test_room',
      'points': [
        {'x': 0.0, 'y': 0.0},
        {'x': 1.0, 'y': 1.0},
        {'x': 2.0, 'y': 2.0},
      ],
      'directions': ['downRight', 'downRight'],
    };
    serverController.add(jsonEncode(pathMessage));

    // Verify the PlayerPath was emitted correctly
    final playerPath = await playerPathFuture;
    expect(playerPath.playerId, equals('player123'));
    expect(playerPath.largeGridPoints.length, equals(3));
    expect(playerPath.largeGridPoints[0], equals(Vector2(0.0, 0.0)));
    expect(playerPath.largeGridPoints[1], equals(Vector2(1.0, 1.0)));
    expect(playerPath.largeGridPoints[2], equals(Vector2(2.0, 2.0)));
    expect(playerPath.directions,
        equals([Direction.downRight, Direction.downRight]));
  });

  test('publishPath sends correctly formatted PlayerPathMessage to server',
      () async {
    final serverController = StreamController<String>.broadcast();
    final messageSink = StreamController<String>();
    final fakeWebSocketChannel =
        FakeWebSocketChannel(serverController.stream, messageSink.sink);

    final networkingService = NetworkingService(
      uriString: '',
      authUserStream: StreamController<AuthUser>().stream,
      webSocketChannel: fakeWebSocketChannel,
      roomId: 'test_room',
    );

    // Capture the message sent to the server
    final sentMessageFuture = messageSink.stream.first;

    // Client publishes a path
    networkingService.publishPath(
      uid: 'player456',
      points: [Double2(x: 5.0, y: 5.0), Double2(x: 6.0, y: 6.0)],
      directions: [Direction.downRight],
    );

    // Verify the message was formatted correctly
    final sentMessage = await sentMessageFuture;
    final decoded = jsonDecode(sentMessage) as Map<String, dynamic>;
    expect(decoded['type'], equals('player_path'));
    expect(decoded['userId'], equals('player456'));
    expect(decoded['roomId'], equals('test_room'));
    expect(decoded['points'], hasLength(2));
    expect(decoded['directions'], equals(['downRight']));
  });

  test('does not send departure message when SignedOutUser has empty id',
      () async {
    final authUserController = StreamController<AuthUser>();
    final serverController = StreamController<String>.broadcast();
    final messageSink = StreamController<String>();
    final fakeWebSocketChannel =
        FakeWebSocketChannel(serverController.stream, messageSink.sink);

    NetworkingService(
      uriString: '',
      authUserStream: authUserController.stream,
      webSocketChannel: fakeWebSocketChannel,
      roomId: 'test_room',
    );

    // Collect all messages sent within a short time window
    final messages = <String>[];
    messageSink.stream.listen(messages.add);

    // Sign out with empty id (e.g., user was never signed in)
    authUserController.add(SignedOutUser(id: '', displayName: ''));

    // Give time for any messages to be sent
    await Future.delayed(const Duration(milliseconds: 50));

    // No departure message should be sent for empty id
    expect(messages.where((m) => m.contains('departure')), isEmpty);
  });
}
