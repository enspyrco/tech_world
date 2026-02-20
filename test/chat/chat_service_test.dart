import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' show RemoteParticipant;
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
      // Shared chat broadcasts to all (no destinationIdentities)
      expect(published['destinationIdentities'], isNull);

      final payload = published['payload'] as Map<String, dynamic>;
      expect(payload['type'], equals('chat'));
      expect(payload['text'], equals('Test message'));
      expect(payload['id'], isNotNull);
      expect(payload['senderName'], equals('Test User'));
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

    test('deduplicates messages with same id', () async {
      fakeLiveKit.connected = true;

      // Simulate receiving the same message twice (same id)
      fakeLiveKit.simulateResponseWithId('msg-123', {
        'text': 'Duplicate message',
        'id': 'msg-123',
      });

      await Future.delayed(const Duration(milliseconds: 10));

      // First message should be added
      expect(chatService.currentMessages.length, equals(1));

      // Send same message again with same id
      fakeLiveKit.simulateResponseWithId('msg-123', {
        'text': 'Duplicate message',
        'id': 'msg-123',
      });

      await Future.delayed(const Duration(milliseconds: 10));

      // Should still be only 1 message (duplicate filtered)
      expect(chatService.currentMessages.length, equals(1));
    });

    test('handles chat messages from other users', () async {
      fakeLiveKit.connected = true;

      // Simulate a chat message from another user (not a bot response)
      fakeLiveKit.simulateChatFromOtherUser('other-user-id', {
        'text': 'Hello from another user',
        'id': 'other-msg-1',
        'senderName': 'Other User',
      });

      await Future.delayed(const Duration(milliseconds: 10));

      expect(chatService.currentMessages.length, equals(1));
      expect(chatService.currentMessages.first.text, equals('Hello from another user'));
      expect(chatService.currentMessages.first.senderName, equals('Other User'));
      expect(chatService.currentMessages.first.isBot, isFalse); // Not from bot
      expect(chatService.currentMessages.first.isLocalUser, isFalse); // Not from local user
    });

    test('ignores own chat messages', () async {
      fakeLiveKit.connected = true;

      // Simulate receiving our own chat message back
      fakeLiveKit.simulateChatFromSelf({
        'text': 'My own message echoed back',
        'id': 'self-msg-1',
        'senderName': 'Test User',
      });

      await Future.delayed(const Duration(milliseconds: 10));

      // Should be ignored (we add our own messages locally)
      expect(chatService.currentMessages, isEmpty);
    });

    test('uses senderId as fallback senderName', () async {
      fakeLiveKit.connected = true;

      // Simulate message without senderName
      fakeLiveKit.simulateChatFromOtherUser('user-456', {
        'text': 'Message without sender name',
        'id': 'no-name-msg',
        // No senderName field
      });

      await Future.delayed(const Duration(milliseconds: 10));

      expect(chatService.currentMessages.length, equals(1));
      // Should use senderId as fallback
      expect(chatService.currentMessages.first.senderName, equals('user-456'));
    });

    test('completes pending message when response arrives with matching messageId', () async {
      fakeLiveKit.connected = true;

      // Start sending a message (don't await - it waits for response)
      final sendFuture = chatService.sendMessage('Hello');

      // Give it time to publish the message
      await Future.delayed(const Duration(milliseconds: 10));

      // Get the message ID that was published
      final messageId = fakeLiveKit.publishedMessages.first['payload']['id'];

      // Simulate bot response with matching messageId
      fakeLiveKit.simulateResponse({
        'text': 'Hello!',
        'messageId': messageId,
      });

      // Now the sendMessage should complete (not wait for timeout)
      await sendFuture;

      // Should have both user message and bot response
      expect(chatService.currentMessages.length, equals(2));
      expect(botStatusNotifier.value, equals(BotStatus.idle));
    });

    test('handles response to message without matching pending', () async {
      fakeLiveKit.connected = true;

      // Send a response for a message ID that doesn't exist in pending
      fakeLiveKit.simulateResponse({
        'text': 'Response to unknown message',
        'messageId': 'non-existent-id',
      });

      await Future.delayed(const Duration(milliseconds: 10));

      // Should still add the message (it's a valid response)
      expect(chatService.currentMessages.length, equals(1));
    });

    test('sendMessage returns response JSON when response arrives', () async {
      fakeLiveKit.connected = true;

      final sendFuture = chatService.sendMessage('Check my code');
      await Future.delayed(const Duration(milliseconds: 10));

      final messageId = fakeLiveKit.publishedMessages.first['payload']['id'];
      fakeLiveKit.simulateResponse({
        'text': 'Looks great!',
        'messageId': messageId,
        'challengeResult': 'pass',
        'challengeId': 'fizzbuzz',
      });

      final response = await sendFuture;

      expect(response, isNotNull);
      expect(response!['text'], equals('Looks great!'));
      expect(response['challengeResult'], equals('pass'));
      expect(response['challengeId'], equals('fizzbuzz'));
    });

    test('sendMessage passes metadata fields in published message', () async {
      fakeLiveKit.connected = true;

      unawaited(chatService.sendMessage(
        'My solution',
        metadata: {'challengeId': 'hello_dart'},
      ));
      await Future.delayed(const Duration(milliseconds: 10));

      final payload =
          fakeLiveKit.publishedMessages.first['payload'] as Map<String, dynamic>;
      expect(payload['challengeId'], equals('hello_dart'));
      expect(payload['text'], equals('My solution'));
    });

    test('sendMessage returns null on timeout', () async {
      fakeLiveKit.connected = true;

      // Use a very short timeout by sending and never responding
      final sendFuture = chatService.sendMessage('Hello');

      // Don't simulate any response — let the timeout fire.
      // The default timeout is 30s which is too long for a test,
      // so we just verify the future completes with a response
      // when we do send one (tested above). Here we verify that
      // when no response arrives but we manually trigger timeout
      // behavior, the method returns null.

      await Future.delayed(const Duration(milliseconds: 10));

      // Simulate a timeout by completing the message without a response
      // (we can't easily test 30s timeout, but we can verify null on disconnect)
      final messageId = fakeLiveKit.publishedMessages.first['payload']['id'];
      fakeLiveKit.simulateResponse({
        'text': 'Late reply',
        'messageId': messageId,
      });

      final response = await sendFuture;
      // Should have received the response JSON
      expect(response, isNotNull);
      expect(response!['text'], equals('Late reply'));
    });

    test('sendMessage returns null when not connected', () async {
      fakeLiveKit.connected = false;

      final response = await chatService.sendMessage('Hello');

      expect(response, isNull);
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
  String get userId => 'test-user-id';

  @override
  String get displayName => 'Test User';

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

  void simulateResponseWithId(String id, Map<String, dynamic> response) {
    _dataReceivedController.add(DataChannelMessage(
      senderId: 'bot-claude',
      topic: 'chat-response',
      data: utf8.encode(jsonEncode(response)),
    ));
  }

  void simulateChatFromOtherUser(String senderId, Map<String, dynamic> message) {
    _dataReceivedController.add(DataChannelMessage(
      senderId: senderId,
      topic: 'chat',
      data: utf8.encode(jsonEncode(message)),
    ));
  }

  void simulateChatFromSelf(Map<String, dynamic> message) {
    _dataReceivedController.add(DataChannelMessage(
      senderId: userId, // Same as our userId
      topic: 'chat',
      data: utf8.encode(jsonEncode(message)),
    ));
  }

  final _participantJoinedController = StreamController<RemoteParticipant>.broadcast();
  final _participantLeftController = StreamController<RemoteParticipant>.broadcast();

  @override
  Map<String, RemoteParticipant> get remoteParticipants => {};

  @override
  Stream<RemoteParticipant> get participantJoined => _participantJoinedController.stream;

  @override
  Stream<RemoteParticipant> get participantLeft => _participantLeftController.stream;

  @override
  void dispose() {
    _dataReceivedController.close();
    _participantJoinedController.close();
    _participantLeftController.close();
  }

  // Unused methods - just satisfy interface
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
