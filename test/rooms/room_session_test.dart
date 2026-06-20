import 'dart:async';
import 'dart:math';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tech_world/chat/chat_message_repository.dart';
import 'package:tech_world/chat/chat_service.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/proximity/proximity_service.dart';
import 'package:tech_world/rooms/room_data.dart';
import 'package:tech_world/rooms/room_session.dart';
import 'package:tech_world/utils/locator.dart';

class _FakeLiveKit extends Mock implements LiveKitService {}

/// Stub the LiveKitService surface that ChatService and RoomSession touch
/// during construction. Returns the live-stream controllers so callers can
/// inject events post-setup.
({StreamController<String?> connectionLost,}) _stubLiveKit(_FakeLiveKit fake) {
  final lostCtrl = StreamController<String?>.broadcast();
  when(() => fake.connectionLost).thenAnswer((_) => lostCtrl.stream);
  when(() => fake.dataReceived).thenAnswer((_) => const Stream.empty());
  when(() => fake.roomTimerReceived).thenAnswer((_) => const Stream.empty());
  when(() => fake.participantJoined).thenAnswer((_) => const Stream.empty());
  when(() => fake.participantLeft).thenAnswer((_) => const Stream.empty());
  when(() => fake.remoteParticipants).thenReturn({});
  when(() => fake.userId).thenReturn('user-1');
  when(fake.dispose).thenAnswer((_) async {});
  when(() => fake.setCameraEnabled(any())).thenAnswer((_) async {});
  when(() => fake.setMicrophoneEnabled(any())).thenAnswer((_) async {});
  return (connectionLost: lostCtrl,);
}

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
  void Function()? onRoomDeleted,
}) {
  return RoomSession.create(
    room: room,
    userId: userId,
    displayName: displayName,
    onStateChanged: onStateChanged ?? () {},
    onReconnectWorld: onReconnectWorld ?? () async {},
    onRoomDeleted: onRoomDeleted ?? () {},
    chatMessageRepository:
        ChatMessageRepository(firestore: FakeFirebaseFirestore()),
    firestore: FakeFirebaseFirestore(),
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

    test('omitting proximityRadius uses the ProximityService default', () {
      final session = _createSession();

      expect(session.proximityService.proximityThreshold,
          equals(ProximityService().proximityThreshold));

      session.chatService.dispose();
      session.proximityService.dispose();
    });

    test('proximityRadius is piped through to ProximityService', () {
      final session = RoomSession.create(
        room: _testRoom,
        userId: 'user-1',
        displayName: 'User 1',
        onStateChanged: () {},
        onReconnectWorld: () async {},
        onRoomDeleted: () {},
        proximityRadius: 6,
        chatMessageRepository:
            ChatMessageRepository(firestore: FakeFirebaseFirestore()),
        firestore: FakeFirebaseFirestore(),
      );

      expect(session.proximityService.proximityThreshold, equals(6));

      session.chatService.dispose();
      session.proximityService.dispose();
    });

    test('proximityRadius: 0 produces a disabled ProximityService', () {
      final session = RoomSession.create(
        room: _testRoom,
        userId: 'user-1',
        displayName: 'User 1',
        onStateChanged: () {},
        onReconnectWorld: () async {},
        onRoomDeleted: () {},
        proximityRadius: 0,
        chatMessageRepository:
            ChatMessageRepository(firestore: FakeFirebaseFirestore()),
        firestore: FakeFirebaseFirestore(),
      );

      expect(session.proximityService.proximityThreshold, equals(0));

      // Smoke-check the disabled semantic: even co-located players don't
      // become nearby.
      session.proximityService.checkProximity(
        localPlayerPosition: const Point(5, 5),
        otherPlayerPositions: {'other': const Point(5, 5)},
      );
      expect(session.proximityService.nearbyPlayers, isEmpty);

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

  group('room deletion listener', () {
    test('fires onRoomDeleted when the room doc is deleted', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('rooms').doc(_testRoom.id).set({
        'name': _testRoom.name,
        'ownerId': _testRoom.ownerId,
      });

      final liveKit = _FakeLiveKit();
      _stubLiveKit(liveKit);
      when(liveKit.connect)
          .thenAnswer((_) async => ConnectionResult.tokenAuthError);

      var deletedCount = 0;
      final session = RoomSession.create(
        room: _testRoom,
        userId: 'user-1',
        displayName: 'User 1',
        onStateChanged: () {},
        onReconnectWorld: () async {},
        onRoomDeleted: () => deletedCount++,
        chatMessageRepository:
            ChatMessageRepository(firestore: FakeFirebaseFirestore()),
        liveKitService: liveKit,
        firestore: firestore,
      );

      await session.connect();
      // Listener subscribes synchronously; let the initial snapshot drain.
      await Future<void>.delayed(Duration.zero);
      expect(deletedCount, 0, reason: 'doc still exists');

      await firestore.collection('rooms').doc(_testRoom.id).delete();
      await Future<void>.delayed(Duration.zero);

      expect(deletedCount, 1);

      await session.leave();
    });
  });

  group('reconnection use-after-dispose guard', () {
    test('leave during reconnect delay does not mutate disposed services',
        () async {
      final liveKit = _FakeLiveKit();
      final stubs = _stubLiveKit(liveKit);
      final lostCtrl = stubs.connectionLost;
      var connectCalls = 0;
      when(liveKit.connect).thenAnswer((_) async {
        connectCalls++;
        return ConnectionResult.connected;
      });

      var reconnectWorldCalls = 0;
      final session = RoomSession.create(
        room: _testRoom,
        userId: 'user-1',
        displayName: 'User 1',
        onStateChanged: () {},
        onReconnectWorld: () async => reconnectWorldCalls++,
        onRoomDeleted: () {},
        chatMessageRepository:
            ChatMessageRepository(firestore: FakeFirebaseFirestore()),
        liveKitService: liveKit,
        firestore: FakeFirebaseFirestore(),
      );

      await session.connect();
      expect(connectCalls, 1, reason: 'initial connect happened');

      // Fire connection loss; _handleConnectionLost begins its 2s delay.
      lostCtrl.add('peer-disconnected');
      await Future<void>.delayed(Duration.zero);

      // Leave during the delay — _disposed flips to true, services dispose.
      await session.leave();

      // Wait past the 2s reconnect delay, then verify the continuation
      // bailed out without touching disposed state.
      await Future<void>.delayed(const Duration(seconds: 3));

      expect(connectCalls, 1,
          reason: 'reconnection must not call connect() after leave()');
      expect(reconnectWorldCalls, 0,
          reason: 'onReconnectWorld must not run post-dispose');

      await lostCtrl.close();
    });
  });

  group('reconnection backoff', () {
    // Zero-duration delays for fast testing.
    const zeroDelays = [Duration.zero, Duration.zero, Duration.zero];

    test('retries up to 3 times then shows failure message', () async {
      final liveKit = _FakeLiveKit();
      final stubs = _stubLiveKit(liveKit);
      final lostCtrl = stubs.connectionLost;
      var connectCalls = 0;
      var initialConnectDone = false;
      when(liveKit.connect).thenAnswer((_) async {
        connectCalls++;
        // First call is the initial connect — succeed so the loss listener
        // is wired up. All subsequent calls (reconnection) fail.
        if (!initialConnectDone) {
          initialConnectDone = true;
          return ConnectionResult.connected;
        }
        return ConnectionResult.tokenNetworkError;
      });

      final session = RoomSession.create(
        room: _testRoom,
        userId: 'user-1',
        displayName: 'User 1',
        onStateChanged: () {},
        onReconnectWorld: () async {},
        onRoomDeleted: () {},
        chatMessageRepository:
            ChatMessageRepository(firestore: FakeFirebaseFirestore()),
        liveKitService: liveKit,
        firestore: FakeFirebaseFirestore(),
        reconnectDelays: zeroDelays,
      );

      await session.connect();
      expect(connectCalls, 1, reason: 'initial connect');
      connectCalls = 0;

      // Fire connection loss and let the handler run to completion.
      lostCtrl.add('peer-disconnected');
      // Give async handler time to run all 3 zero-delay attempts.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(connectCalls, 3, reason: 'should attempt 3 reconnections');
      expect(session.connectionFailed.value, isTrue);
      expect(session.connectionMessage.value, contains('connection lost'));

      await session.leave();
      await lostCtrl.close();
    });

    test('aborts immediately on tokenAuthError with session-expired message',
        () async {
      final liveKit = _FakeLiveKit();
      final stubs = _stubLiveKit(liveKit);
      final lostCtrl = stubs.connectionLost;
      var connectCalls = 0;
      var initialConnectDone = false;
      when(liveKit.connect).thenAnswer((_) async {
        connectCalls++;
        if (!initialConnectDone) {
          initialConnectDone = true;
          return ConnectionResult.connected;
        }
        return ConnectionResult.tokenAuthError;
      });

      final session = RoomSession.create(
        room: _testRoom,
        userId: 'user-1',
        displayName: 'User 1',
        onStateChanged: () {},
        onReconnectWorld: () async {},
        onRoomDeleted: () {},
        chatMessageRepository:
            ChatMessageRepository(firestore: FakeFirebaseFirestore()),
        liveKitService: liveKit,
        firestore: FakeFirebaseFirestore(),
        reconnectDelays: zeroDelays,
      );

      await session.connect();
      connectCalls = 0;

      lostCtrl.add('auth-expired');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(connectCalls, 1, reason: 'auth error should abort after 1 try');
      expect(session.connectionMessage.value, contains('Session expired'));

      await session.leave();
      await lostCtrl.close();
    });

    test('succeeds on second attempt and clears failure state', () async {
      final liveKit = _FakeLiveKit();
      final stubs = _stubLiveKit(liveKit);
      final lostCtrl = stubs.connectionLost;
      var connectCalls = 0;
      var initialConnectDone = false;
      var reconnectAttempts = 0;
      when(liveKit.connect).thenAnswer((_) async {
        connectCalls++;
        if (!initialConnectDone) {
          initialConnectDone = true;
          return ConnectionResult.connected;
        }
        reconnectAttempts++;
        // First reconnect attempt fails, second succeeds.
        if (reconnectAttempts == 1) return ConnectionResult.tokenNetworkError;
        return ConnectionResult.connected;
      });

      var reconnectWorldCalls = 0;
      final session = RoomSession.create(
        room: _testRoom,
        userId: 'user-1',
        displayName: 'User 1',
        onStateChanged: () {},
        onReconnectWorld: () async => reconnectWorldCalls++,
        onRoomDeleted: () {},
        chatMessageRepository:
            ChatMessageRepository(firestore: FakeFirebaseFirestore()),
        liveKitService: liveKit,
        firestore: FakeFirebaseFirestore(),
        reconnectDelays: zeroDelays,
      );

      await session.connect();
      connectCalls = 0;

      lostCtrl.add('network-blip');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(connectCalls, 2, reason: 'should try twice');
      expect(reconnectWorldCalls, 1);
      expect(session.connectionFailed.value, isFalse);
      expect(session.connectionMessage.value, isNull);

      await session.leave();
      await lostCtrl.close();
    });
  });
}
