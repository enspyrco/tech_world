import 'dart:math';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/chat/chat_message_repository.dart';
import 'package:tech_world/chat/chat_service.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/proximity/proximity_service.dart';
import 'package:tech_world/rooms/room_data.dart';
import 'package:tech_world/rooms/room_session.dart';
import 'package:tech_world/utils/locator.dart';

const _testMap = GameMap(
  id: 'test_map',
  name: 'Test Map',
  barriers: [Point(1, 2)],
);

const _testRoom = RoomData(
  id: 'test-room',
  name: 'Test Room',
  ownerId: 'user-1',
  ownerDisplayName: 'User 1',
  mapData: _testMap,
);

/// Create a [RoomSession] with a fake Firestore-backed [ChatMessageRepository]
/// to avoid Firebase initialization in tests.
RoomSession _createSession({
  RoomData room = _testRoom,
  String userId = 'user-1',
  String displayName = 'User 1',
  void Function()? onStateChanged,
  Future<void> Function()? onReconnectWorld,
}) {
  return RoomSession.create(
    room: room,
    userId: userId,
    displayName: displayName,
    onStateChanged: onStateChanged ?? () {},
    onReconnectWorld: onReconnectWorld ?? () async {},
    chatMessageRepository:
        ChatMessageRepository(firestore: FakeFirebaseFirestore()),
  );
}

void main() {
  tearDown(() {
    Locator.remove<LiveKitService>();
    Locator.remove<ChatService>();
    Locator.remove<ProximityService>();
  });

  group('RoomSession.create', () {
    test('registers LiveKitService, ChatService, ProximityService in Locator',
        () {
      final session = _createSession();

      expect(Locator.maybeLocate<LiveKitService>(), isNotNull);
      expect(Locator.maybeLocate<ChatService>(), isNotNull);
      expect(Locator.maybeLocate<ProximityService>(), isNotNull);
      expect(
          session.liveKitService, same(Locator.maybeLocate<LiveKitService>()));
      expect(session.chatService, same(Locator.maybeLocate<ChatService>()));
      expect(session.proximityService,
          same(Locator.maybeLocate<ProximityService>()));

      session.chatService.dispose();
      session.proximityService.dispose();
    });

    test('sets room, userId, displayName', () {
      final session = _createSession();

      expect(session.room.id, 'test-room');
      expect(session.userId, 'user-1');
      expect(session.displayName, 'User 1');

      session.chatService.dispose();
      session.proximityService.dispose();
    });

    test('creates LiveKitService with correct roomName', () {
      final session = _createSession();

      expect(session.liveKitService.roomName, 'test-room');

      session.chatService.dispose();
      session.proximityService.dispose();
    });
  });

  group('failureMessageFor', () {
    test('maps tokenAuthError to session-expired message', () {
      expect(
        RoomSession.failureMessageFor(ConnectionResult.tokenAuthError),
        contains('Session expired'),
      );
    });

    test('maps tokenNetworkError to connection message', () {
      expect(
        RoomSession.failureMessageFor(ConnectionResult.tokenNetworkError),
        contains('connection'),
      );
    });

    test('maps roomFailed to room-specific message', () {
      expect(
        RoomSession.failureMessageFor(ConnectionResult.roomFailed),
        contains('Room connection failed'),
      );
    });

    test('maps unknown result to generic message', () {
      expect(
        RoomSession.failureMessageFor(ConnectionResult.tokenUnknownError),
        contains('connection failed'),
      );
    });
  });

  group('oracleService', () {
    test('creates lazily on first access and returns same instance', () {
      final session = _createSession();

      final oracle1 = session.oracleService;
      final oracle2 = session.oracleService;
      expect(oracle1, same(oracle2));

      session.chatService.dispose();
      session.proximityService.dispose();
    });
  });

  group('leave', () {
    test('removes all three services from Locator', () async {
      final session = _createSession();

      expect(Locator.maybeLocate<LiveKitService>(), isNotNull);
      expect(Locator.maybeLocate<ChatService>(), isNotNull);
      expect(Locator.maybeLocate<ProximityService>(), isNotNull);

      await session.leave();

      expect(Locator.maybeLocate<LiveKitService>(), isNull);
      expect(Locator.maybeLocate<ChatService>(), isNull);
      expect(Locator.maybeLocate<ProximityService>(), isNull);
    });
  });

  group('connectionFailed', () {
    test('starts as false with null message', () {
      final session = _createSession();

      expect(session.connectionFailed.value, isFalse);
      expect(session.connectionMessage.value, isNull);

      session.chatService.dispose();
      session.proximityService.dispose();
    });
  });
}
