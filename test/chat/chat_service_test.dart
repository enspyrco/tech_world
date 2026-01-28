import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/chat/chat_message.dart';
import 'package:tech_world/chat/chat_service.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/livekit/livekit_service.dart';

void main() {
  group('ChatService', () {
    late FakeLiveKitService fakeLiveKit;
    late ChatService chatService;

    setUp(() {
      fakeLiveKit = FakeLiveKitService();
      chatService = ChatService(liveKitService: fakeLiveKit);
      // Reset bot status
      botStatusNotifier.value = BotStatus.idle;
    });

    tearDown(() {
      chatService.dispose();
    });

    test('initial state has empty messages', () {
      expect(chatService.currentMessages, isEmpty);
    });

    test('sendMessage does nothing for empty text', () async {
      await chatService.sendMessage('');
      await chatService.sendMessage('   ');

      expect(chatService.currentMessages, isEmpty);
      expect(fakeLiveKit.publishedMessages, isEmpty);
    });

    test('sendMessage adds user message to list', () async {
      // Don't await - it will wait for response
      unawaited(chatService.sendMessage('Hello bot'));

      // Give it time to process
      await Future.delayed(const Duration(milliseconds: 10));

      expect(chatService.currentMessages.length, equals(1));
      expect(chatService.currentMessages.first.text, equals('Hello bot'));
      expect(chatService.currentMessages.first.isUser, isTrue);
    });

    test('sendMessage publishes to LiveKit with correct format', () async {
      fakeLiveKit.connected = true;

      unawaited(chatService.sendMessage('Test message'));
      await Future.delayed(const Duration(milliseconds: 10));

      expect(fakeLiveKit.publishedMessages.length, equals(1));

      final published = fakeLiveKit.publishedMessages.first;
      expect(published['topic'], equals('chat'));
      expect(published['destinationIdentities'], equals(['bot-claude']));

      final payload = published['payload'] as Map<String, dynamic>;
      expect(payload['type'], equals('chat'));
      expect(payload['text'], equals('Test message'));
      expect(payload['id'], isNotNull);
      expect(payload['timestamp'], isNotNull);
    });

    test('sendMessage sets bot status to thinking', () async {
      fakeLiveKit.connected = true;

      unawaited(chatService.sendMessage('Hello'));
      await Future.delayed(const Duration(milliseconds: 10));

      expect(botStatusNotifier.value, equals(BotStatus.thinking));
    });

    test('receiving response adds bot message to list', () async {
      fakeLiveKit.connected = true;

      unawaited(chatService.sendMessage('Hello'));
      await Future.delayed(const Duration(milliseconds: 10));

      // Simulate bot response
      final messageId = fakeLiveKit.publishedMessages.first['payload']['id'];
      fakeLiveKit.simulateResponse({
        'text': 'Hello human!',
        'messageId': messageId,
      });

      await Future.delayed(const Duration(milliseconds: 10));

      expect(chatService.currentMessages.length, equals(2));
      expect(chatService.currentMessages.last.text, equals('Hello human!'));
      expect(chatService.currentMessages.last.isUser, isFalse);
    });

    test('receiving response sets bot status to idle', () async {
      fakeLiveKit.connected = true;

      unawaited(chatService.sendMessage('Hello'));
      await Future.delayed(const Duration(milliseconds: 10));

      final messageId = fakeLiveKit.publishedMessages.first['payload']['id'];
      fakeLiveKit.simulateResponse({
        'text': 'Hello!',
        'messageId': messageId,
      });

      await Future.delayed(const Duration(milliseconds: 10));

      expect(botStatusNotifier.value, equals(BotStatus.idle));
    });

    test('shows error when not connected', () async {
      fakeLiveKit.connected = false;

      await chatService.sendMessage('Hello');

      expect(chatService.currentMessages.length, equals(1));
      expect(
        chatService.currentMessages.first.text,
        contains("can't reach Clawd"),
      );
      expect(chatService.currentMessages.first.isUser, isFalse);
    });

    test('messages stream emits updates', () async {
      fakeLiveKit.connected = true;

      final messages = <List<ChatMessage>>[];
      chatService.messages.listen(messages.add);

      unawaited(chatService.sendMessage('Test'));
      await Future.delayed(const Duration(milliseconds: 10));

      expect(messages.length, greaterThan(0));
      expect(messages.last.first.text, equals('Test'));
    });

    test('ignores response with null JSON', () async {
      fakeLiveKit.connected = true;

      unawaited(chatService.sendMessage('Hello'));
      await Future.delayed(const Duration(milliseconds: 10));

      // Send invalid response (not JSON)
      fakeLiveKit.simulateInvalidResponse('not json at all');

      await Future.delayed(const Duration(milliseconds: 10));

      // Should only have user message, no bot response
      expect(chatService.currentMessages.length, equals(1));
      expect(chatService.currentMessages.first.isUser, isTrue);
    });

    test('ignores response with missing text field', () async {
      fakeLiveKit.connected = true;

      unawaited(chatService.sendMessage('Hello'));
      await Future.delayed(const Duration(milliseconds: 10));

      final messageId = fakeLiveKit.publishedMessages.first['payload']['id'];
      // Response missing 'text' field
      fakeLiveKit.simulateResponse({
        'messageId': messageId,
        'notText': 'wrong field',
      });

      await Future.delayed(const Duration(milliseconds: 10));

      // Should only have user message
      expect(chatService.currentMessages.length, equals(1));
    });

    test('handles response without messageId', () async {
      fakeLiveKit.connected = true;

      unawaited(chatService.sendMessage('Hello'));
      await Future.delayed(const Duration(milliseconds: 10));

      // Response without messageId - should still add message
      fakeLiveKit.simulateResponse({
        'text': 'Response without ID',
      });

      await Future.delayed(const Duration(milliseconds: 10));

      expect(chatService.currentMessages.length, equals(2));
      expect(chatService.currentMessages.last.text, equals('Response without ID'));
    });

    test('filters non-chat-response topics', () async {
      fakeLiveKit.connected = true;

      unawaited(chatService.sendMessage('Hello'));
      await Future.delayed(const Duration(milliseconds: 10));

      // Send message with wrong topic
      fakeLiveKit.simulateMessageWithTopic('other-topic', {
        'text': 'Should be ignored',
      });

      await Future.delayed(const Duration(milliseconds: 10));

      // Should only have user message
      expect(chatService.currentMessages.length, equals(1));
    });

    test('dispose cancels subscription', () async {
      chatService.dispose();

      // Should not throw after dispose
      fakeLiveKit.simulateResponse({'text': 'After dispose'});
      await Future.delayed(const Duration(milliseconds: 10));
    });
  });
}

/// Fake LiveKitService for testing
class FakeLiveKitService implements LiveKitService {
  bool connected = true;
  final List<Map<String, dynamic>> publishedMessages = [];
  final _dataReceivedController = StreamController<DataChannelMessage>.broadcast();

  @override
  bool get isConnected => connected;

  @override
  Stream<DataChannelMessage> get dataReceived => _dataReceivedController.stream;

  @override
  Future<void> publishJson(
    Map<String, dynamic> json, {
    bool reliable = true,
    List<String>? destinationIdentities,
    String? topic,
  }) async {
    publishedMessages.add({
      'payload': json,
      'topic': topic,
      'destinationIdentities': destinationIdentities,
    });
  }

  void simulateResponse(Map<String, dynamic> response) {
    _dataReceivedController.add(DataChannelMessage(
      senderId: 'bot-claude',
      topic: 'chat-response',
      data: utf8.encode(jsonEncode(response)),
    ));
  }

  void simulateInvalidResponse(String invalidData) {
    _dataReceivedController.add(DataChannelMessage(
      senderId: 'bot-claude',
      topic: 'chat-response',
      data: utf8.encode(invalidData),
    ));
  }

  void simulateMessageWithTopic(String topic, Map<String, dynamic> response) {
    _dataReceivedController.add(DataChannelMessage(
      senderId: 'bot-claude',
      topic: topic,
      data: utf8.encode(jsonEncode(response)),
    ));
  }

  @override
  void dispose() {
    _dataReceivedController.close();
  }

  // Unused methods - just satisfy interface
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
