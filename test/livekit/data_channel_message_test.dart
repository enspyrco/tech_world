import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/livekit/livekit_service.dart';

void main() {
  group('DataChannelMessage', () {
    test('creates message with required fields', () {
      final message = DataChannelMessage(
        senderId: 'user-123',
        topic: 'test-topic',
        data: utf8.encode('hello'),
      );

      expect(message.senderId, equals('user-123'));
      expect(message.topic, equals('test-topic'));
      expect(message.data, equals(utf8.encode('hello')));
    });

    test('creates message with null senderId', () {
      final message = DataChannelMessage(
        senderId: null,
        topic: 'server-message',
        data: utf8.encode('from server'),
      );

      expect(message.senderId, isNull);
    });

    test('creates message with null topic', () {
      final message = DataChannelMessage(
        senderId: 'user-456',
        topic: null,
        data: utf8.encode('no topic'),
      );

      expect(message.topic, isNull);
    });

    group('text getter', () {
      test('decodes UTF-8 data as text', () {
        final message = DataChannelMessage(
          senderId: 'user',
          topic: 'text',
          data: utf8.encode('Hello, World!'),
        );

        expect(message.text, equals('Hello, World!'));
      });

      test('decodes unicode characters', () {
        final message = DataChannelMessage(
          senderId: 'user',
          topic: 'text',
          data: utf8.encode('Hello 🌍 世界'),
        );

        expect(message.text, equals('Hello 🌍 世界'));
      });

      test('decodes empty data as empty string', () {
        final message = DataChannelMessage(
          senderId: 'user',
          topic: 'text',
          data: [],
        );

        expect(message.text, equals(''));
      });
    });

    group('json getter', () {
      test('decodes valid JSON object', () {
        final jsonData = {'name': 'test', 'value': 42};
        final message = DataChannelMessage(
          senderId: 'user',
          topic: 'json',
          data: utf8.encode(jsonEncode(jsonData)),
        );

        expect(message.json, equals(jsonData));
      });

      test('decodes nested JSON object', () {
        final jsonData = {
          'player': {'id': 'p1', 'name': 'Player 1'},
          'position': {'x': 100.5, 'y': 200.0},
          'tags': ['active', 'online'],
        };
        final message = DataChannelMessage(
          senderId: 'user',
          topic: 'json',
          data: utf8.encode(jsonEncode(jsonData)),
        );

        expect(message.json, equals(jsonData));
        expect(message.json!['player']['id'], equals('p1'));
        expect(message.json!['position']['x'], equals(100.5));
      });

      test('returns null for invalid JSON', () {
        final message = DataChannelMessage(
          senderId: 'user',
          topic: 'invalid',
          data: utf8.encode('not valid json {'),
        );

        expect(message.json, isNull);
      });

      test('returns null for non-object JSON (array)', () {
        final message = DataChannelMessage(
          senderId: 'user',
          topic: 'array',
          data: utf8.encode('[1, 2, 3]'),
        );

        // json getter expects Map<String, dynamic>, not List
        expect(message.json, isNull);
      });

      test('returns null for non-object JSON (string)', () {
        final message = DataChannelMessage(
          senderId: 'user',
          topic: 'string',
          data: utf8.encode('"just a string"'),
        );

        expect(message.json, isNull);
      });

      test('returns null for empty data', () {
        final message = DataChannelMessage(
          senderId: 'user',
          topic: 'empty',
          data: [],
        );

        expect(message.json, isNull);
      });

      test('handles JSON with various types', () {
        final jsonData = {
          'string': 'text',
          'int': 42,
          'double': 3.14,
          'bool': true,
          'null': null,
          'list': [1, 2, 3],
          'map': {'nested': 'value'},
        };
        final message = DataChannelMessage(
          senderId: 'user',
          topic: 'types',
          data: utf8.encode(jsonEncode(jsonData)),
        );

        final json = message.json!;
        expect(json['string'], equals('text'));
        expect(json['int'], equals(42));
        expect(json['double'], equals(3.14));
        expect(json['bool'], equals(true));
        expect(json['null'], isNull);
        expect(json['list'], equals([1, 2, 3]));
        expect(json['map'], equals({'nested': 'value'}));
      });
    });

    group('toString', () {
      test('includes senderId, topic, and data length', () {
        final message = DataChannelMessage(
          senderId: 'user-123',
          topic: 'test',
          data: utf8.encode('12345'),
        );

        expect(
          message.toString(),
          equals('DataChannelMessage(senderId: user-123, topic: test, data: 5 bytes)'),
        );
      });

      test('handles null values', () {
        final message = DataChannelMessage(
          senderId: null,
          topic: null,
          data: [],
        );

        expect(
          message.toString(),
          equals('DataChannelMessage(senderId: null, topic: null, data: 0 bytes)'),
        );
      });
    });
  });
}
