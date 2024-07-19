import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/auth/auth_user.dart';
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
          '{"type":"arrival","user":{"id":"id","displayName":"displayName"}}',
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
}
