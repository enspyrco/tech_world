import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/livekit/livekit_service.dart';

void main() {
  group('DataChannelMessage', () {
    test('json getter decodes valid JSON data', () {
      final jsonData = {'type': 'chat', 'message': 'Hello'};
      final message = DataChannelMessage(
        senderId: 'user123',
        topic: 'chat',
        data: utf8.encode(jsonEncode(jsonData)),
      );

      expect(message.json, equals(jsonData));
    });

    test('json getter returns null for invalid JSON', () {
      final message = DataChannelMessage(
        senderId: 'user123',
        topic: 'chat',
        data: utf8.encode('not valid json'),
      );

      expect(message.json, isNull);
    });

    test('text getter decodes UTF-8 string', () {
      final message = DataChannelMessage(
        senderId: 'user123',
        topic: 'ping',
        data: utf8.encode('pong'),
      );

      expect(message.text, equals('pong'));
    });

    test('handles null senderId (server-sent message)', () {
      final message = DataChannelMessage(
        senderId: null,
        topic: 'system',
        data: utf8.encode('{"event": "shutdown"}'),
      );

      expect(message.senderId, isNull);
      expect(message.json, equals({'event': 'shutdown'}));
    });

    test('toString provides readable output', () {
      final message = DataChannelMessage(
        senderId: 'user123',
        topic: 'test',
        data: [1, 2, 3],
      );

      expect(
        message.toString(),
        equals('DataChannelMessage(senderId: user123, topic: test, data: 3 bytes)'),
      );
    });
  });
}
