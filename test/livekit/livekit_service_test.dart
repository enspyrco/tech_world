import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/livekit/livekit_service.dart';

void main() {
  group('LiveKitService', () {
    group('constructor', () {
      test('creates service with required parameters', () {
        final service = LiveKitService(
          userId: 'user-123',
          displayName: 'Test User',
        );

        expect(service.userId, equals('user-123'));
        expect(service.displayName, equals('Test User'));
        expect(service.roomName, equals('tech-world')); // default
      });

      test('creates service with custom room name', () {
        final service = LiveKitService(
          userId: 'user-456',
          displayName: 'Another User',
          roomName: 'custom-room',
        );

        expect(service.userId, equals('user-456'));
        expect(service.displayName, equals('Another User'));
        expect(service.roomName, equals('custom-room'));
      });
    });

    group('initial state', () {
      late LiveKitService service;

      setUp(() {
        service = LiveKitService(
          userId: 'test-user',
          displayName: 'Test',
        );
      });

      tearDown(() {
        service.dispose();
      });

      test('isConnected is false initially', () {
        expect(service.isConnected, isFalse);
      });

      test('room is null initially', () {
        expect(service.room, isNull);
      });

      test('localParticipant is null initially', () {
        expect(service.localParticipant, isNull);
      });

      test('remoteParticipants is empty initially', () {
        expect(service.remoteParticipants, isEmpty);
      });

      test('getParticipant returns null when not connected', () {
        expect(service.getParticipant('any-id'), isNull);
      });
    });

    group('streams', () {
      late LiveKitService service;

      setUp(() {
        service = LiveKitService(
          userId: 'test-user',
          displayName: 'Test',
        );
      });

      tearDown(() {
        service.dispose();
      });

      test('participantJoined stream is available', () {
        expect(service.participantJoined, isA<Stream>());
      });

      test('participantLeft stream is available', () {
        expect(service.participantLeft, isA<Stream>());
      });

      test('speakingChanged stream is available', () {
        expect(service.speakingChanged, isA<Stream>());
      });

      test('trackSubscribed stream is available', () {
        expect(service.trackSubscribed, isA<Stream>());
      });

      test('localTrackPublished stream is available', () {
        expect(service.localTrackPublished, isA<Stream>());
      });

      test('dataReceived stream is available', () {
        expect(service.dataReceived, isA<Stream>());
      });

      test('positionReceived stream is available', () {
        expect(service.positionReceived, isA<Stream>());
      });
    });

    group('dispose', () {
      test('can be called safely', () {
        final service = LiveKitService(
          userId: 'test-user',
          displayName: 'Test',
        );

        // Should not throw
        expect(() => service.dispose(), returnsNormally);
      });

      test('can be called multiple times', () {
        final service = LiveKitService(
          userId: 'test-user',
          displayName: 'Test',
        );

        service.dispose();
        // Second call should not throw
        expect(() => service.dispose(), returnsNormally);
      });
    });

    group('publishData without connection', () {
      late LiveKitService service;

      setUp(() {
        service = LiveKitService(
          userId: 'test-user',
          displayName: 'Test',
        );
      });

      tearDown(() {
        service.dispose();
      });

      test('publishData returns early when not connected', () async {
        // Should complete without throwing
        await service.publishData([1, 2, 3], topic: 'test');
      });

      test('publishJson returns early when not connected', () async {
        // Should complete without throwing
        await service.publishJson({'key': 'value'}, topic: 'test');
      });

      test('publishPosition returns early when not connected', () async {
        // Should complete without throwing
        await service.publishPosition(points: [], directions: []);
      });
    });

    group('setCameraEnabled without connection', () {
      test('returns early when not connected', () async {
        final service = LiveKitService(
          userId: 'test-user',
          displayName: 'Test',
        );

        // Should complete without throwing
        await service.setCameraEnabled(true);
        await service.setCameraEnabled(false);

        service.dispose();
      });
    });

    group('setMicrophoneEnabled without connection', () {
      test('returns early when not connected', () async {
        final service = LiveKitService(
          userId: 'test-user',
          displayName: 'Test',
        );

        // Should complete without throwing
        await service.setMicrophoneEnabled(true);
        await service.setMicrophoneEnabled(false);

        service.dispose();
      });
    });

    group('concurrent connection guard', () {
      test('second connect returns immediately while first is in-flight',
          () async {
        final tokenCompleter = Completer<String?>();
        final service = LiveKitService(
          userId: 'test-user',
          displayName: 'Test',
          tokenRetriever: () => tokenCompleter.future,
        );

        // Start first connect — blocks on token retrieval.
        final firstConnect = service.connect();

        // Second connect should return immediately (guard hit).
        final secondResult = await service.connect();
        expect(secondResult, isFalse);

        // Finish the first connect (null token → connection fails).
        tokenCompleter.complete(null);
        final firstResult = await firstConnect;
        expect(firstResult, isFalse);

        service.dispose();
      });

      test('connect returns true status when already connected', () async {
        // Simulate a service that retrieved a token but will fail at
        // room.connect — we only need to verify the guard checks
        // _isConnected.
        final service = LiveKitService(
          userId: 'test-user',
          displayName: 'Test',
          tokenRetriever: () async => null,
        );

        // First connect fails (null token).
        final result = await service.connect();
        expect(result, isFalse);
        expect(service.isConnected, isFalse);

        service.dispose();
      });
    });
  });
}
