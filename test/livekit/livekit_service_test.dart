import 'dart:async';
import 'dart:convert';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/livekit/livekit_service.dart';

void main() {
  group('LiveKitService', () {
    group('stream getters', () {
      late LiveKitService service;

      setUp(() {
        service = LiveKitService(
          userId: 'test',
          displayName: 'Test',
          roomName: 'test-room',
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

      test('room is initially null', () {
        expect(service.room, isNull);
      });

      test('isConnected is initially false', () {
        expect(service.isConnected, isFalse);
      });

      test('localParticipant is null when not connected', () {
        expect(service.localParticipant, isNull);
      });

      test('remoteParticipants is empty when not connected', () {
        expect(service.remoteParticipants, isEmpty);
      });

      test('getParticipant returns null when not connected', () {
        expect(service.getParticipant('any-id'), isNull);
      });

      test('constructor sets userId and displayName', () {
        expect(service.userId, equals('test'));
        expect(service.displayName, equals('Test'));
        expect(service.roomName, equals('test-room'));
      });

      test('publishData does nothing when not connected', () async {
        // Should not throw, just return early
        await service.publishData([1, 2, 3]);
      });

      test('publishJson does nothing when not connected', () async {
        // Should not throw, just return early
        await service.publishJson({'test': 'data'});
      });

      test('publishPosition does nothing when not connected', () async {
        // Should not throw, just return early
        await service.publishPosition(
          points: [],
          directions: [],
        );
      });

      test('setCameraEnabled does nothing when not connected', () async {
        // Should not throw
        await service.setCameraEnabled(true);
      });

      test('setMicrophoneEnabled does nothing when not connected', () async {
        // Should not throw
        await service.setMicrophoneEnabled(true);
      });

      test('disconnect does nothing when not connected', () async {
        // Should not throw
        await service.disconnect();
      });
    });

    group('positionReceived stream', () {
      late TestableLiveKitService service;

      setUp(() {
        service = TestableLiveKitService();
      });

      tearDown(() {
        service.dispose();
      });

      test('filters messages by position topic', () async {
        final positions = <dynamic>[];
        service.positionReceived.listen(positions.add);

        // Send position message
        service.injectDataMessage(DataChannelMessage(
          senderId: 'player1',
          topic: 'position',
          data: utf8.encode(jsonEncode({
            'playerId': 'player1',
            'points': [{'x': 100.0, 'y': 200.0}],
            'directions': ['right'],
          })),
        ));

        // Send non-position message (should be filtered)
        service.injectDataMessage(DataChannelMessage(
          senderId: 'player1',
          topic: 'chat',
          data: utf8.encode('{"text": "hello"}'),
        ));

        await Future.delayed(const Duration(milliseconds: 10));

        expect(positions.length, equals(1));
      });

      test('parses valid position into PlayerPath', () async {
        final positions = <dynamic>[];
        service.positionReceived.listen(positions.add);

        service.injectDataMessage(DataChannelMessage(
          senderId: 'player1',
          topic: 'position',
          data: utf8.encode(jsonEncode({
            'playerId': 'player1',
            'points': [
              {'x': 100.0, 'y': 200.0},
              {'x': 150.0, 'y': 200.0},
            ],
            'directions': ['right', 'right'],
          })),
        ));

        await Future.delayed(const Duration(milliseconds: 10));

        expect(positions.length, equals(1));
        final path = positions.first;
        expect(path.playerId, equals('player1'));
        expect(path.largeGridPoints.length, equals(2));
        expect(path.largeGridPoints[0], equals(Vector2(100.0, 200.0)));
        expect(path.directions, equals([Direction.right, Direction.right]));
      });

      test('filters out invalid JSON', () async {
        final positions = <dynamic>[];
        service.positionReceived.listen(positions.add);

        service.injectDataMessage(DataChannelMessage(
          senderId: 'player1',
          topic: 'position',
          data: utf8.encode('not valid json'),
        ));

        await Future.delayed(const Duration(milliseconds: 10));

        expect(positions, isEmpty);
      });

      test('filters out messages with missing playerId', () async {
        final positions = <dynamic>[];
        service.positionReceived.listen(positions.add);

        service.injectDataMessage(DataChannelMessage(
          senderId: 'player1',
          topic: 'position',
          data: utf8.encode(jsonEncode({
            'points': [{'x': 100.0, 'y': 200.0}],
            'directions': ['right'],
          })),
        ));

        await Future.delayed(const Duration(milliseconds: 10));

        expect(positions, isEmpty);
      });

      test('filters out messages with missing points', () async {
        final positions = <dynamic>[];
        service.positionReceived.listen(positions.add);

        service.injectDataMessage(DataChannelMessage(
          senderId: 'player1',
          topic: 'position',
          data: utf8.encode(jsonEncode({
            'playerId': 'player1',
            'directions': ['right'],
          })),
        ));

        await Future.delayed(const Duration(milliseconds: 10));

        expect(positions, isEmpty);
      });

      test('handles integer coordinates', () async {
        final positions = <dynamic>[];
        service.positionReceived.listen(positions.add);

        service.injectDataMessage(DataChannelMessage(
          senderId: 'player1',
          topic: 'position',
          data: utf8.encode(jsonEncode({
            'playerId': 'player1',
            'points': [{'x': 100, 'y': 200}],
            'directions': ['down'],
          })),
        ));

        await Future.delayed(const Duration(milliseconds: 10));

        expect(positions.length, equals(1));
        expect(positions.first.largeGridPoints[0], equals(Vector2(100.0, 200.0)));
      });

      test('handles unknown direction as none', () async {
        final positions = <dynamic>[];
        service.positionReceived.listen(positions.add);

        service.injectDataMessage(DataChannelMessage(
          senderId: 'player1',
          topic: 'position',
          data: utf8.encode(jsonEncode({
            'playerId': 'player1',
            'points': [{'x': 0.0, 'y': 0.0}],
            'directions': ['unknown_direction'],
          })),
        ));

        await Future.delayed(const Duration(milliseconds: 10));

        expect(positions.length, equals(1));
        expect(positions.first.directions, equals([Direction.none]));
      });

      test('handles all direction values', () async {
        final positions = <dynamic>[];
        service.positionReceived.listen(positions.add);

        service.injectDataMessage(DataChannelMessage(
          senderId: 'player1',
          topic: 'position',
          data: utf8.encode(jsonEncode({
            'playerId': 'player1',
            'points': List.generate(9, (i) => {'x': i.toDouble(), 'y': i.toDouble()}),
            'directions': [
              'up', 'down', 'left', 'right',
              'upLeft', 'upRight', 'downLeft', 'downRight', 'none'
            ],
          })),
        ));

        await Future.delayed(const Duration(milliseconds: 10));

        expect(positions.length, equals(1));
        expect(positions.first.directions, equals([
          Direction.up, Direction.down, Direction.left, Direction.right,
          Direction.upLeft, Direction.upRight, Direction.downLeft, Direction.downRight,
          Direction.none,
        ]));
      });

      test('handles empty path', () async {
        final positions = <dynamic>[];
        service.positionReceived.listen(positions.add);

        service.injectDataMessage(DataChannelMessage(
          senderId: 'player1',
          topic: 'position',
          data: utf8.encode(jsonEncode({
            'playerId': 'player1',
            'points': <Map<String, dynamic>>[],
            'directions': <String>[],
          })),
        ));

        await Future.delayed(const Duration(milliseconds: 10));

        expect(positions.length, equals(1));
        expect(positions.first.largeGridPoints, isEmpty);
        expect(positions.first.directions, isEmpty);
      });

      test('handles multiple position messages', () async {
        final positions = <dynamic>[];
        service.positionReceived.listen(positions.add);

        for (var i = 0; i < 5; i++) {
          service.injectDataMessage(DataChannelMessage(
            senderId: 'player$i',
            topic: 'position',
            data: utf8.encode(jsonEncode({
              'playerId': 'player$i',
              'points': [{'x': i.toDouble(), 'y': i.toDouble()}],
              'directions': ['right'],
            })),
          ));
        }

        await Future.delayed(const Duration(milliseconds: 20));

        expect(positions.length, equals(5));
      });
    });

    group('DataChannelMessage', () {
      test('json getter handles malformed data gracefully', () {
        final message = DataChannelMessage(
          senderId: 'test',
          topic: 'test',
          data: [0xFF, 0xFE], // Invalid UTF-8
        );

        // Should not throw, returns null
        expect(message.json, isNull);
      });

      test('text getter with valid UTF-8', () {
        final message = DataChannelMessage(
          senderId: 'test',
          topic: 'test',
          data: utf8.encode('Hello, 世界!'),
        );

        expect(message.text, equals('Hello, 世界!'));
      });

      test('handles empty data', () {
        final message = DataChannelMessage(
          senderId: 'test',
          topic: 'test',
          data: [],
        );

        expect(message.text, equals(''));
        expect(message.json, isNull);
      });
    });
  });
}

/// Testable subclass that exposes internal stream controllers
class TestableLiveKitService extends LiveKitService {
  TestableLiveKitService() : super(
    userId: 'test-user',
    displayName: 'Test User',
    roomName: 'test-room',
  );

  final _dataController = StreamController<DataChannelMessage>.broadcast();

  @override
  Stream<DataChannelMessage> get dataReceived => _dataController.stream;

  void injectDataMessage(DataChannelMessage message) {
    _dataController.add(message);
  }

  @override
  void dispose() {
    _dataController.close();
    super.dispose();
  }
}
