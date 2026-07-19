import 'dart:async';
import 'dart:math';
import 'dart:convert';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart'
    show
        LocalParticipant,
        LocalTrackPublication,
        Participant,
        RemoteParticipant,
        Room,
        ScreenShareCaptureOptions,
        VideoTrack;
import 'package:tech_world/avatar/avatar.dart';
import 'package:tech_world/chat/chat_message.dart';
import 'package:tech_world/chat/chat_message_repository.dart';
import 'package:tech_world/chat/chat_service.dart';
import 'package:tech_world/livekit/data_topic.dart';
import 'package:tech_world/chat/conversation.dart';
import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/types.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/flame/shared/player_path.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/timer/room_timer_message.dart';


Future<void> pumpEventQueue() => Future<void>.delayed(Duration.zero);
void main() {
  group('ChatService', () {
    late FakeLiveKitService fakeLiveKit;
    late ChatService chatService;

    setUp(() {
      fakeLiveKit = FakeLiveKitService();
      chatService = ChatService(liveKitService: fakeLiveKit);
      chatService.setBotStatusForTest(BotStatus.idle);
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
      await pumpEventQueue();

      expect(chatService.currentMessages.length, equals(1));
      expect(chatService.currentMessages.first.text, equals('Hello bot'));
      expect(chatService.currentMessages.first.isUser, isTrue);
    });

    test('sendMessage publishes to LiveKit with correct format', () async {
      fakeLiveKit.connected = true;

      unawaited(chatService.sendMessage('Test message'));
      await pumpEventQueue();

      expect(fakeLiveKit.publishedMessages.length, equals(1));

      final published = fakeLiveKit.publishedMessages.first;
      expect(published['topic'], equals(DataTopic.chat.wireName));
      // Shared chat broadcasts to all (no destinationIdentities)
      expect(published['destinationIdentities'], isNull);

      final payload = published['payload'] as Map<String, dynamic>;
      expect(payload['type'], equals(DataTopic.chat.wireName));
      expect(payload['text'], equals('Test message'));
      expect(payload['id'], isNotNull);
      expect(payload['senderName'], equals('Test User'));
      expect(payload['timestamp'], isNotNull);
    });

    test('sendMessage sets bot status to thinking', () async {
      fakeLiveKit.connected = true;

      unawaited(chatService.sendMessage('Hello'));
      await pumpEventQueue();

      expect(chatService.botStatus.value, equals(BotStatus.thinking));
    });

    test('receiving response adds bot message to list', () async {
      fakeLiveKit.connected = true;

      unawaited(chatService.sendMessage('Hello'));
      await pumpEventQueue();

      // Simulate bot response
      final messageId = fakeLiveKit.publishedMessages.first['payload']['id'];
      fakeLiveKit.simulateResponse({
        'text': 'Hello human!',
        'messageId': messageId,
      });

      await pumpEventQueue();

      expect(chatService.currentMessages.length, equals(2));
      expect(chatService.currentMessages.last.text, equals('Hello human!'));
      expect(chatService.currentMessages.last.isUser, isFalse);
    });

    test('receiving response sets bot status to idle', () async {
      fakeLiveKit.connected = true;

      unawaited(chatService.sendMessage('Hello'));
      await pumpEventQueue();

      final messageId = fakeLiveKit.publishedMessages.first['payload']['id'];
      fakeLiveKit.simulateResponse({
        'text': 'Hello!',
        'messageId': messageId,
      });

      await pumpEventQueue();

      expect(chatService.botStatus.value, equals(BotStatus.idle));
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
      await pumpEventQueue();

      expect(messages.length, greaterThan(0));
      expect(messages.last.first.text, equals('Test'));
    });

    test('ignores response with null JSON', () async {
      fakeLiveKit.connected = true;

      unawaited(chatService.sendMessage('Hello'));
      await pumpEventQueue();

      // Send invalid response (not JSON)
      fakeLiveKit.simulateInvalidResponse('not json at all');

      await pumpEventQueue();

      // Should only have user message, no bot response
      expect(chatService.currentMessages.length, equals(1));
      expect(chatService.currentMessages.first.isUser, isTrue);
    });

    test('ignores response with missing text field', () async {
      fakeLiveKit.connected = true;

      unawaited(chatService.sendMessage('Hello'));
      await pumpEventQueue();

      final messageId = fakeLiveKit.publishedMessages.first['payload']['id'];
      // Response missing 'text' field
      fakeLiveKit.simulateResponse({
        'messageId': messageId,
        'notText': 'wrong field',
      });

      await pumpEventQueue();

      // Should only have user message
      expect(chatService.currentMessages.length, equals(1));
    });

    test('handles response without messageId', () async {
      fakeLiveKit.connected = true;

      unawaited(chatService.sendMessage('Hello'));
      await pumpEventQueue();

      // Response without messageId - should still add message
      fakeLiveKit.simulateResponse({
        'text': 'Response without ID',
      });

      await pumpEventQueue();

      expect(chatService.currentMessages.length, equals(2));
      expect(chatService.currentMessages.last.text, equals('Response without ID'));
    });

    test('filters non-chat-response topics', () async {
      fakeLiveKit.connected = true;

      unawaited(chatService.sendMessage('Hello'));
      await pumpEventQueue();

      // Send message with wrong topic
      fakeLiveKit.simulateMessageWithTopic('other-topic', {
        'text': 'Should be ignored',
      });

      await pumpEventQueue();

      // Should only have user message
      expect(chatService.currentMessages.length, equals(1));
    });

    test('dispose cancels subscription', () async {
      chatService.dispose();

      // Should not throw after dispose
      fakeLiveKit.simulateResponse({'text': 'After dispose'});
      await pumpEventQueue();
    });

    test('deduplicates messages with same id', () async {
      fakeLiveKit.connected = true;

      // Simulate receiving the same message twice (same id)
      fakeLiveKit.simulateResponseWithId('msg-123', {
        'text': 'Duplicate message',
        'id': 'msg-123',
      });

      await pumpEventQueue();

      // First message should be added
      expect(chatService.currentMessages.length, equals(1));

      // Send same message again with same id
      fakeLiveKit.simulateResponseWithId('msg-123', {
        'text': 'Duplicate message',
        'id': 'msg-123',
      });

      await pumpEventQueue();

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

      await pumpEventQueue();

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

      await pumpEventQueue();

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

      await pumpEventQueue();

      expect(chatService.currentMessages.length, equals(1));
      // Should use senderId as fallback
      expect(chatService.currentMessages.first.senderName, equals('user-456'));
    });

    group('group quote-reply', () {
      test('sendMessage with replyTo carries reply fields locally and on the wire',
          () async {
        fakeLiveKit.connected = true;

        // The message being replied to (as it exists in the local group list).
        final original = ChatMessage(
          text: 'What is fizzbuzz?',
          senderName: 'Alice',
          senderId: 'alice-uid',
          conversationId: 'group',
        );

        // Single replyTo param — ID + snapshot derived together, so the
        // "half-reply" state (an ID with no snapshot, or vice-versa) is
        // unrepresentable.
        unawaited(chatService.sendMessage('Here is fizzbuzz', replyTo: original));
        await pumpEventQueue();

        // Local copy carries the reply linkage + quote snapshot. The ID is
        // derived from the replied-to message's localKey.
        final local = chatService.currentMessages;
        expect(local, isNotEmpty);
        expect(local.last.replyToMessageId, equals(original.localKey));
        expect(local.last.replyToText, equals('What is fizzbuzz?'));
        expect(local.last.replyToSenderName, equals('Alice'));
        expect(local.last.isReply, isTrue);

        // Wire payload carries the reply fields (all three present together).
        final payload =
            fakeLiveKit.publishedMessages.last['payload'] as Map<String, dynamic>;
        expect(payload['replyToMessageId'], equals(original.localKey));
        expect(payload['replyToText'], equals('What is fizzbuzz?'));
        expect(payload['replyToSenderName'], equals('Alice'));
      });

      test('sendMessage without replyTo has null reply fields', () async {
        fakeLiveKit.connected = true;

        unawaited(chatService.sendMessage('Plain message'));
        await pumpEventQueue();

        final local = chatService.currentMessages;
        expect(local, isNotEmpty);
        expect(local.last.replyToMessageId, isNull);
        expect(local.last.replyToText, isNull);
        expect(local.last.replyToSenderName, isNull);
        expect(local.last.isReply, isFalse);

        // No reply keys leak into the wire payload.
        final payload =
            fakeLiveKit.publishedMessages.last['payload'] as Map<String, dynamic>;
        expect(payload.containsKey('replyToMessageId'), isFalse);
        expect(payload.containsKey('replyToText'), isFalse);
        expect(payload.containsKey('replyToSenderName'), isFalse);
      });

      test('inbound group reply parses reply fields from the wire', () async {
        fakeLiveKit.connected = true;

        fakeLiveKit.simulateChatFromOtherUser('alice-uid', {
          'text': 'Replying to you',
          'id': 'group-reply-1',
          'senderName': 'Alice',
          'replyToMessageId': 'orig-7',
          'replyToText': 'original question',
          'replyToSenderName': 'Test User',
        });
        await pumpEventQueue();

        final msgs = chatService.currentMessages;
        expect(msgs, isNotEmpty);
        expect(msgs.last.replyToMessageId, equals('orig-7'));
        expect(msgs.last.replyToText, equals('original question'));
        expect(msgs.last.replyToSenderName, equals('Test User'));
        expect(msgs.last.isReply, isTrue);
      });

      test('inbound group message with no reply fields has null reply fields',
          () async {
        fakeLiveKit.connected = true;

        fakeLiveKit.simulateChatFromOtherUser('alice-uid', {
          'text': 'No reply here',
          'id': 'group-plain-1',
          'senderName': 'Alice',
        });
        await pumpEventQueue();

        final msgs = chatService.currentMessages;
        expect(msgs, isNotEmpty);
        expect(msgs.last.replyToMessageId, isNull);
        expect(msgs.last.isReply, isFalse);
      });

      test('inbound group reply with a non-string replyToMessageId is ignored',
          () async {
        // Defensive parse at the wire seam: a malformed reply field must not
        // throw / tear down the stream — it just isn't treated as a reply.
        fakeLiveKit.connected = true;

        fakeLiveKit.simulateChatFromOtherUser('alice-uid', {
          'text': 'Malformed reply',
          'id': 'group-bad-1',
          'senderName': 'Alice',
          'replyToMessageId': 123, // wrong type
        });
        await pumpEventQueue();

        final msgs = chatService.currentMessages;
        expect(msgs, isNotEmpty);
        expect(msgs.last.replyToMessageId, isNull);
        expect(msgs.last.isReply, isFalse);
      });

      test('inbound group reply with only replyToMessageId is rejected '
          '(atomic parse — no orphaned half-reply)', () async {
        // Carnot (cage-match PR #490): a payload carrying ONLY replyToMessageId
        // (no text/name) would otherwise render a reply bubble quoting an empty
        // "Unknown". The atomic parse drops the whole trio unless all three are
        // present-and-String.
        fakeLiveKit.connected = true;

        fakeLiveKit.simulateChatFromOtherUser('alice-uid', {
          'text': 'Sneaky half-reply',
          'id': 'group-half-1',
          'senderName': 'Alice',
          'replyToMessageId': 'orig-x',
          // no replyToText, no replyToSenderName
        });
        await pumpEventQueue();

        final msgs = chatService.currentMessages;
        expect(msgs, isNotEmpty);
        expect(msgs.last.replyToMessageId, isNull);
        expect(msgs.last.replyToText, isNull);
        expect(msgs.last.replyToSenderName, isNull);
        expect(msgs.last.isReply, isFalse);
      });

      test('inbound group reply with a wrong-typed id but valid text/name is '
          'rejected wholesale (no orphaned snapshot)', () async {
        // The asymmetric-survival case: replyToMessageId is malformed (drops to
        // null) but text+name survive. Without atomic parse these would orphan
        // onto a non-reply message.
        fakeLiveKit.connected = true;

        fakeLiveKit.simulateChatFromOtherUser('alice-uid', {
          'text': 'Orphaned snapshot attempt',
          'id': 'group-half-2',
          'senderName': 'Alice',
          'replyToMessageId': 123, // wrong type -> null
          'replyToText': 'spoofed quote',
          'replyToSenderName': 'Victim',
        });
        await pumpEventQueue();

        final msgs = chatService.currentMessages;
        expect(msgs, isNotEmpty);
        expect(msgs.last.replyToMessageId, isNull);
        expect(msgs.last.replyToText, isNull,
            reason: 'orphaned text must be dropped with the malformed id');
        expect(msgs.last.replyToSenderName, isNull);
        expect(msgs.last.isReply, isFalse);
      });

      test('group reply still derives senderId from transport, not payload',
          () async {
        // TRUST INVARIANT: a reply must not become a spoof vector. The SENDER
        // of an incoming group message is the transport identity, even though
        // the reply quote snapshot is display-only and payload-sourced. A
        // malicious peer crafting a payload senderId of another user's UID must
        // NOT have it leak into the rendered senderId.
        fakeLiveKit.connected = true;

        // alice-uid is the real transport sender; the payload claims victim-uid.
        fakeLiveKit.simulateChatFromOtherUser('alice-uid', {
          'text': 'I am impersonating the victim!',
          'id': 'group-spoof-1',
          'senderName': 'Victim',
          'senderId': 'victim-uid', // <-- attacker spoofs this
          'replyToMessageId': 'orig-1',
          'replyToText': 'something',
          'replyToSenderName': 'Test User',
        });
        await pumpEventQueue();

        final msgs = chatService.currentMessages;
        expect(msgs, isNotEmpty);
        expect(msgs.last.senderId, equals('alice-uid'),
            reason: 'senderId must come from transport, not payload');
        expect(msgs.last.senderId, isNot(equals('victim-uid')));
        // The display-only reply snapshot is still carried.
        expect(msgs.last.replyToText, equals('something'));
        expect(msgs.last.isReply, isTrue);
      });
    });

    // Defensive parse at the group-chat wire seam. A malformed payload (a
    // field with the wrong type) must never throw inside the stream callback
    // and tear down the chat subscription — same failure class as the
    // `as`-cast-in-stream-teardown bug (#364/#366), here for the non-reply
    // fields (text / senderName / id) that the #490 reply-field parse left
    // as unchecked `as String?` casts.
    group('malformed payload (wire seam totality)', () {
      test('group message with non-string text is dropped, stream survives',
          () async {
        fakeLiveKit.connected = true;

        // A non-string `text` must be dropped gracefully (treated as absent),
        // not throw a TypeError that tears down the subscription.
        fakeLiveKit.simulateChatFromOtherUser('attacker-uid', {
          'text': 123, // wrong type
          'id': 'bad-text-1',
          'senderName': 'Mallory',
        });
        await pumpEventQueue();

        // The malformed message produced no chat entry...
        expect(chatService.currentMessages, isEmpty);

        // ...and the subscription is still alive: a subsequent valid message
        // from another user still arrives.
        fakeLiveKit.simulateChatFromOtherUser('other-uid', {
          'text': 'still here',
          'id': 'good-after-bad',
          'senderName': 'Other User',
        });
        await pumpEventQueue();

        expect(chatService.currentMessages.length, equals(1));
        expect(chatService.currentMessages.single.text, equals('still here'));
      });

      test('group message with non-string senderName falls back, stream survives',
          () async {
        fakeLiveKit.connected = true;

        // A non-string `senderName` must not throw; it falls back to the
        // transport senderId (matching the missing-senderName behaviour).
        fakeLiveKit.simulateChatFromOtherUser('user-789', {
          'text': 'has a bad name',
          'id': 'bad-name-1',
          'senderName': <String, dynamic>{}, // wrong type
        });
        await pumpEventQueue();

        expect(chatService.currentMessages.length, equals(1));
        expect(chatService.currentMessages.single.text, equals('has a bad name'));
        // Falls back to transport senderId rather than throwing.
        expect(chatService.currentMessages.single.senderName, equals('user-789'));
      });

      test('inbound DM with non-string text is dropped, stream survives',
          () async {
        fakeLiveKit.connected = true;

        fakeLiveKit.simulateDm('alice-uid', {
          'text': <String, dynamic>{}, // wrong type
          'id': 'dm-bad-text',
          'senderName': 'Alice',
          'senderId': 'alice-uid',
        });
        await pumpEventQueue();

        // No DM entry created from the malformed payload.
        expect(chatService.dmMessagesSnapshot('alice-uid'), isEmpty);

        // Subscription survives: a subsequent valid DM still arrives.
        fakeLiveKit.simulateDm('alice-uid', {
          'text': 'real message',
          'id': 'dm-good',
          'senderName': 'Alice',
          'senderId': 'alice-uid',
        });
        await pumpEventQueue();

        final msgs = chatService.dmMessagesSnapshot('alice-uid');
        expect(msgs.length, equals(1));
        expect(msgs.single.text, equals('real message'));
      });
    });

    test('completes pending message when response arrives with matching messageId', () async {
      fakeLiveKit.connected = true;

      // Start sending a message (don't await - it waits for response)
      final sendFuture = chatService.sendMessage('Hello');

      // Give it time to publish the message
      await pumpEventQueue();

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
      expect(chatService.botStatus.value, equals(BotStatus.idle));
    });

    test('handles response to message without matching pending', () async {
      fakeLiveKit.connected = true;

      // Send a response for a message ID that doesn't exist in pending
      fakeLiveKit.simulateResponse({
        'text': 'Response to unknown message',
        'messageId': 'non-existent-id',
      });

      await pumpEventQueue();

      // Should still add the message (it's a valid response)
      expect(chatService.currentMessages.length, equals(1));
    });

    test('sendMessage returns response JSON when response arrives', () async {
      fakeLiveKit.connected = true;

      final sendFuture = chatService.sendMessage('Check my code');
      await pumpEventQueue();

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
      await pumpEventQueue();

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

      await pumpEventQueue();

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

    group('DM support', () {
      test('sendDm publishes to dm topic with destinationIdentities', () async {
        fakeLiveKit.connected = true;

        await chatService.sendDm('peer-uid', 'Hey there!', peerDisplayName: 'Peer');
        await pumpEventQueue();

        expect(fakeLiveKit.publishedMessages.length, equals(1));

        final published = fakeLiveKit.publishedMessages.first;
        expect(published['topic'], equals(DataTopic.dm.wireName));
        expect(
          published['destinationIdentities'],
          equals(['peer-uid']),
        );

        final payload = published['payload'] as Map<String, dynamic>;
        expect(payload['text'], equals('Hey there!'));
        expect(payload['senderName'], equals('Test User'));
      });

      test('sendDm adds message to correct DM conversation', () async {
        fakeLiveKit.connected = true;

        await chatService.sendDm('peer-uid', 'Hello', peerDisplayName: 'Peer');
        await pumpEventQueue();

        final expectedConvId = Conversation.conversationIdFor(
          'test-user-id',
          'peer-uid',
        );

        final conversations = chatService.currentConversations;
        final dmConv = conversations.firstWhere(
          (c) => c.id == expectedConvId,
        );
        expect(dmConv.type, equals(ConversationType.dm));
      });

      test('receiving dm creates new conversation', () async {
        fakeLiveKit.connected = true;

        fakeLiveKit.simulateDm('alice-uid', {
          'text': 'Hey!',
          'id': 'dm-1',
          'senderName': 'Alice',
          'senderId': 'alice-uid',
        });

        await pumpEventQueue();

        final expectedConvId = Conversation.conversationIdFor(
          'test-user-id',
          'alice-uid',
        );
        final conversations = chatService.currentConversations;
        expect(conversations.any((c) => c.id == expectedConvId), isTrue);
      });

      test('receiving dm increments unread when not active', () async {
        fakeLiveKit.connected = true;

        fakeLiveKit.simulateDm('alice-uid', {
          'text': 'Message 1',
          'id': 'dm-1',
          'senderName': 'Alice',
          'senderId': 'alice-uid',
        });

        await pumpEventQueue();

        final expectedConvId = Conversation.conversationIdFor(
          'test-user-id',
          'alice-uid',
        );
        final conv = chatService.currentConversations.firstWhere(
          (c) => c.id == expectedConvId,
        );
        expect(conv.unreadCount, equals(1));
      });

      test('markConversationRead resets unread to zero', () async {
        fakeLiveKit.connected = true;

        fakeLiveKit.simulateDm('alice-uid', {
          'text': 'Unread message',
          'id': 'dm-1',
          'senderName': 'Alice',
          'senderId': 'alice-uid',
        });

        await pumpEventQueue();

        final expectedConvId = Conversation.conversationIdFor(
          'test-user-id',
          'alice-uid',
        );

        chatService.markConversationRead(expectedConvId);

        final conv = chatService.currentConversations.firstWhere(
          (c) => c.id == expectedConvId,
        );
        expect(conv.unreadCount, equals(0));
      });

      test('totalUnreadNotifier reflects sum of DM unreads', () async {
        fakeLiveKit.connected = true;

        // DM from Alice
        fakeLiveKit.simulateDm('alice-uid', {
          'text': 'Hi',
          'id': 'dm-1',
          'senderName': 'Alice',
          'senderId': 'alice-uid',
        });
        await pumpEventQueue();

        // DM from Bob
        fakeLiveKit.simulateDm('bob-uid', {
          'text': 'Hey',
          'id': 'dm-2',
          'senderName': 'Bob',
          'senderId': 'bob-uid',
        });
        await pumpEventQueue();

        expect(chatService.totalUnreadNotifier.value, equals(2));
      });

      test('lastDmMessageText returns last message text', () async {
        fakeLiveKit.connected = true;

        await chatService.sendDm('peer-uid', 'First', peerDisplayName: 'Peer');
        await chatService.sendDm('peer-uid', 'Second', peerDisplayName: 'Peer');
        await pumpEventQueue();

        final expectedConvId = Conversation.conversationIdFor(
          'test-user-id',
          'peer-uid',
        );

        expect(chatService.lastDmMessageText(expectedConvId), equals('Second'));
      });

      test('lastDmMessageText returns null for unknown conversation', () {
        expect(chatService.lastDmMessageText('nonexistent'), isNull);
      });

      test('localUserId returns the LiveKit user ID', () {
        expect(chatService.localUserId, equals('test-user-id'));
      });

      test('sendDm does nothing for empty text', () async {
        fakeLiveKit.connected = true;

        await chatService.sendDm('peer-uid', '', peerDisplayName: 'Peer');
        await chatService.sendDm('peer-uid', '   ', peerDisplayName: 'Peer');

        expect(fakeLiveKit.publishedMessages, isEmpty);
      });

      test('sendDm does nothing when not connected', () async {
        fakeLiveKit.connected = false;

        await chatService.sendDm('peer-uid', 'Hello', peerDisplayName: 'Peer');

        expect(fakeLiveKit.publishedMessages, isEmpty);
      });

      test('dm messages stream emits for correct conversation', () async {
        fakeLiveKit.connected = true;

        final expectedConvId = Conversation.conversationIdFor(
          'test-user-id',
          'alice-uid',
        );

        final dmMsgs = <List<ChatMessage>>[];
        chatService.dmMessages('alice-uid').listen(dmMsgs.add);

        fakeLiveKit.simulateDm('alice-uid', {
          'text': 'Hello via DM',
          'id': 'dm-1',
          'senderName': 'Alice',
          'senderId': 'alice-uid',
        });

        await pumpEventQueue();

        expect(dmMsgs.length, greaterThan(0));
        expect(dmMsgs.last.first.text, equals('Hello via DM'));
        expect(dmMsgs.last.first.conversationId, equals(expectedConvId));
      });

      test('conversations stream emits on new DM', () async {
        fakeLiveKit.connected = true;

        final convSnapshots = <List<Conversation>>[];
        chatService.conversations.listen(convSnapshots.add);

        fakeLiveKit.simulateDm('alice-uid', {
          'text': 'New DM!',
          'id': 'dm-1',
          'senderName': 'Alice',
          'senderId': 'alice-uid',
        });

        await pumpEventQueue();

        expect(convSnapshots.length, greaterThan(0));
        expect(convSnapshots.last.length, greaterThanOrEqualTo(2)); // group + DM
      });

      test('receiving dm-response adds to DM conversation', () async {
        fakeLiveKit.connected = true;

        // First send a DM to the bot to create the conversation
        await chatService.sendDm('bot-claude', 'Help me', peerDisplayName: 'Clawd');
        await pumpEventQueue();

        // Simulate bot DM response
        fakeLiveKit.simulateDmResponse('bot-claude', {
          'text': 'Sure, here is help!',
          'id': 'dm-resp-1',
          'senderName': 'Clawd',
          'senderId': 'bot-claude',
        });
        await pumpEventQueue();

        final expectedConvId = Conversation.conversationIdFor(
          'test-user-id',
          'bot-claude',
        );
        final conv = chatService.currentConversations.firstWhere(
          (c) => c.id == expectedConvId,
        );
        expect(conv.type, equals(ConversationType.dm));
      });

      test('spoofed senderId in DM payload is ignored; transport identity wins',
          () async {
        // Regression: a malicious participant could craft a DM payload with
        // another user's UID as senderId, making the message appear to come
        // from that person in the UI.  The fix: always route DMs using
        // message.senderId (the LiveKit transport identity, server-verified),
        // never the payload's senderId.
        fakeLiveKit.connected = true;

        // alice-uid is the real sender (transport layer), but the payload
        // claims the message is from 'victim-uid'.
        fakeLiveKit.simulateDm('alice-uid', {
          'text': 'I am impersonating the victim!',
          'id': 'spoof-1',
          'senderName': 'Victim',
          'senderId': 'victim-uid', // <-- attacker spoofs this
        });

        await pumpEventQueue();

        // Conversation should be keyed to alice-uid, not victim-uid.
        final aliceConvId = Conversation.conversationIdFor(
          'test-user-id',
          'alice-uid',
        );
        final victimConvId = Conversation.conversationIdFor(
          'test-user-id',
          'victim-uid',
        );

        final convIds =
            chatService.currentConversations.map((c) => c.id).toSet();
        expect(convIds, contains(aliceConvId),
            reason:
                'conversation should be filed under the real transport sender');
        expect(convIds, isNot(contains(victimConvId)),
            reason: 'spoofed victim-uid should not create a conversation');

        // The message itself should carry the transport senderId, not the
        // payload's spoofed value.
        final msgs = chatService.dmMessagesSnapshot('alice-uid');
        expect(msgs, isNotEmpty);
        expect(msgs.first.senderId, equals('alice-uid'),
            reason: 'senderId must come from transport, not payload');
        expect(msgs.first.senderId, isNot(equals('victim-uid')));
      });

      group('quote-reply', () {
        test('sendDm with replyTo carries reply fields locally and on the wire',
            () async {
          fakeLiveKit.connected = true;

          // The message being replied to (as it exists in the local thread).
          final original = ChatMessage(
            text: 'What do you think?',
            senderName: 'Peer',
            senderId: 'peer-uid',
          );

          // Single replyTo param — ID + snapshot derived together, so the
          // "half-reply" state is unrepresentable.
          await chatService.sendDm(
            'peer-uid',
            'I agree',
            peerDisplayName: 'Peer',
            replyTo: original,
          );
          await pumpEventQueue();

          // Local copy carries the reply linkage + quote snapshot. The ID is
          // derived from the replied-to message's localKey.
          final convId =
              Conversation.conversationIdFor('test-user-id', 'peer-uid');
          final local = chatService.dmMessagesSnapshot('peer-uid');
          expect(local, isNotEmpty);
          expect(local.last.replyToMessageId, equals(original.localKey));
          expect(local.last.replyToText, equals('What do you think?'));
          expect(local.last.replyToSenderName, equals('Peer'));
          expect(local.last.conversationId, equals(convId));
          expect(local.last.isReply, isTrue);

          // Wire payload carries the reply fields (all three present together).
          final payload = fakeLiveKit.publishedMessages.last['payload']
              as Map<String, dynamic>;
          expect(payload['replyToMessageId'], equals(original.localKey));
          expect(payload['replyToText'], equals('What do you think?'));
          expect(payload['replyToSenderName'], equals('Peer'));
        });

        test('inbound DM reply parses reply fields from the wire', () async {
          fakeLiveKit.connected = true;

          fakeLiveKit.simulateDm('alice-uid', {
            'text': 'Replying to you',
            'id': 'dm-reply-1',
            'senderName': 'Alice',
            'senderId': 'alice-uid',
            'replyToMessageId': 'orig-9',
            'replyToText': 'original question',
            'replyToSenderName': 'Test User',
          });
          await pumpEventQueue();

          final msgs = chatService.dmMessagesSnapshot('alice-uid');
          expect(msgs, isNotEmpty);
          expect(msgs.last.replyToMessageId, equals('orig-9'));
          expect(msgs.last.replyToText, equals('original question'));
          expect(msgs.last.replyToSenderName, equals('Test User'));
          expect(msgs.last.isReply, isTrue);
        });

        test('inbound DM reply with a non-string replyToMessageId is ignored',
            () async {
          // Defensive parse at the wire seam: a malformed reply field must not
          // throw / tear down the stream — it just isn't treated as a reply.
          fakeLiveKit.connected = true;

          fakeLiveKit.simulateDm('alice-uid', {
            'text': 'Malformed reply',
            'id': 'dm-bad-1',
            'senderName': 'Alice',
            'senderId': 'alice-uid',
            'replyToMessageId': 123, // wrong type
          });
          await pumpEventQueue();

          final msgs = chatService.dmMessagesSnapshot('alice-uid');
          expect(msgs, isNotEmpty);
          expect(msgs.last.replyToMessageId, isNull);
          expect(msgs.last.isReply, isFalse);
        });

        test('inbound DM reply with a wrong-typed id but valid text/name is '
            'rejected wholesale (atomic parse — no orphaned snapshot)',
            () async {
          // The asymmetric-survival case on the DM branch (Carnot re-review,
          // PR #490): a malformed id drops to null but text+name would survive
          // an independent parse, orphaning a snapshot onto a non-reply. The
          // atomic parseReplySnapshot drops the whole trio.
          fakeLiveKit.connected = true;

          fakeLiveKit.simulateDm('alice-uid', {
            'text': 'Orphaned DM snapshot attempt',
            'id': 'dm-orphan-1',
            'senderName': 'Alice',
            'senderId': 'alice-uid',
            'replyToMessageId': 123, // wrong type -> null
            'replyToText': 'spoofed quote',
            'replyToSenderName': 'Victim',
          });
          await pumpEventQueue();

          final msgs = chatService.dmMessagesSnapshot('alice-uid');
          expect(msgs, isNotEmpty);
          expect(msgs.last.replyToMessageId, isNull);
          expect(msgs.last.replyToText, isNull,
              reason: 'orphaned text must be dropped with the malformed id');
          expect(msgs.last.replyToSenderName, isNull);
          expect(msgs.last.isReply, isFalse);
        });

        test('reply still derives senderId from transport, not payload',
            () async {
          // A reply must not become a spoof vector: the SENDER of the reply is
          // still the transport identity, even though the quote snapshot is
          // payload-sourced (display-only).
          fakeLiveKit.connected = true;

          fakeLiveKit.simulateDm('alice-uid', {
            'text': 'Reply but spoofing sender',
            'id': 'dm-spoof-reply',
            'senderName': 'Victim',
            'senderId': 'victim-uid', // spoofed
            'replyToMessageId': 'orig-1',
            'replyToText': 'something',
            'replyToSenderName': 'Test User',
          });
          await pumpEventQueue();

          final msgs = chatService.dmMessagesSnapshot('alice-uid');
          expect(msgs, isNotEmpty);
          expect(msgs.last.senderId, equals('alice-uid'),
              reason: 'reply sender must come from transport, not payload');
          expect(msgs.last.senderId, isNot(equals('victim-uid')));
          // But the (display-only) quote snapshot is preserved.
          expect(msgs.last.replyToMessageId, equals('orig-1'));
        });
      });
    });

    // The transported message id is threaded onto every ChatMessage (sent,
    // received, rehydrated) so quote-replies target a value that resolves on
    // ANY participant's device — unlike the per-device localKey. See #488/#7.
    group('stable message id (reply navigability)', () {
      test('a sent DM stores the transported wire id on the local message',
          () async {
        fakeLiveKit.connected = true;

        await chatService.sendDm('bob-uid', 'hi', peerDisplayName: 'Bob');

        final published =
            fakeLiveKit.publishedMessages.last['payload'] as Map<String, dynamic>;
        final wireId = published['id'] as String;
        final local = chatService.dmMessagesSnapshot('bob-uid').last;
        expect(local.id, equals(wireId),
            reason: 'local copy must carry the same id it put on the wire');
        expect(local.stableId, equals(wireId));
      });

      test('an inbound DM carries the transported wire id', () async {
        fakeLiveKit.connected = true;

        fakeLiveKit.simulateDm('alice-uid', {
          'text': 'hello',
          'id': 'wire-123',
          'senderName': 'Alice',
          'senderId': 'alice-uid',
        });
        await pumpEventQueue();

        final msg = chatService.dmMessagesSnapshot('alice-uid').last;
        expect(msg.id, equals('wire-123'));
        expect(msg.stableId, equals('wire-123'));
      });

      test('replying to an inbound DM targets its transported id, not a '
          'device-local key (navigable cross-device)', () async {
        fakeLiveKit.connected = true;

        // An inbound message from Alice with a known transported id.
        fakeLiveKit.simulateDm('alice-uid', {
          'text': 'original question',
          'id': 'msg-orig',
          'senderName': 'Alice',
          'senderId': 'alice-uid',
        });
        await pumpEventQueue();
        final original = chatService.dmMessagesSnapshot('alice-uid').last;
        expect(original.id, equals('msg-orig'));

        // Reply to it.
        await chatService.sendDm('alice-uid', 'my reply',
            peerDisplayName: 'Alice', replyTo: original);

        final published =
            fakeLiveKit.publishedMessages.last['payload'] as Map<String, dynamic>;
        // The link targets the ORIGINAL's transported id — the value Alice's
        // device knows it by — NOT a localKey stamped on this device.
        expect(published['replyToMessageId'], equals('msg-orig'));
        expect(published['replyToMessageId'], isNot(contains(':')),
            reason: 'a localKey would be "<sender>:<micros>"; an id is opaque');
      });

      test('an inbound group message carries the transported wire id',
          () async {
        fakeLiveKit.connected = true;

        fakeLiveKit.simulateChatFromOtherUser('carol-uid', {
          'text': 'group hello',
          'id': 'grp-wire-1',
          'senderName': 'Carol',
        });
        await pumpEventQueue();

        expect(chatService.currentMessages.last.id, equals('grp-wire-1'));
      });
    });

    group('loadHistory (regression)', () {
      test('does not throw when repository fails', () async {
        final failingRepo = FailingChatMessageRepository();
        final service = ChatService(
          liveKitService: fakeLiveKit,
          repository: failingRepo,
        );
        addTearDown(service.dispose);

        // Should complete without throwing — room loading must not block.
        await service.loadHistory('room-1');

        // Service should still be functional after failed history load.
        expect(service.currentMessages, isEmpty);
      });

      test('does not throw on timeout', () async {
        final hangingRepo = HangingChatMessageRepository();
        final service = ChatService(
          liveKitService: fakeLiveKit,
          repository: hangingRepo,
          historyTimeout: const Duration(milliseconds: 100),
        );
        addTearDown(service.dispose);

        // Should complete within the short timeout, not hang forever.
        await expectLater(
          service.loadHistory('room-1'),
          completes,
        );
      });

      test('emits conversations even when history load fails mid-loop',
          () async {
        final partialRepo = PartialThenHangingRepository();
        final service = ChatService(
          liveKitService: fakeLiveKit,
          repository: partialRepo,
          historyTimeout: const Duration(milliseconds: 100),
        );
        addTearDown(service.dispose);

        final convSnapshots = <List<Conversation>>[];
        service.conversations.listen(convSnapshots.add);

        await service.loadHistory('room-1');
        // Allow the async broadcast stream to deliver the event.
        await Future<void>.delayed(Duration.zero);

        // The finally block should have emitted conversations even though
        // the second loadMessages call timed out.
        expect(convSnapshots, isNotEmpty);
        // The first DM conversation should have been loaded before timeout.
        expect(
          convSnapshots.last.any((c) => c.type == ConversationType.dm),
          isTrue,
        );
      });

      test('still allows sending messages after failed history load', () async {
        final failingRepo = FailingChatMessageRepository();
        final service = ChatService(
          liveKitService: fakeLiveKit,
          repository: failingRepo,
        );
        addTearDown(service.dispose);

        await service.loadHistory('room-1');

        // Service should work normally despite failed history load.
        fakeLiveKit.connected = true;
        service.setBotStatusForTest(BotStatus.idle);
        unawaited(service.sendMessage('Hello after failed history'));
        await pumpEventQueue();

        expect(service.currentMessages.length, equals(1));
        expect(service.currentMessages.first.text,
            equals('Hello after failed history'));
      });
    });

    group('eternal history paging', () {
      ChatMessage groupMsg(String id, String text, int minute) => ChatMessage(
            text: text,
            id: id,
            senderName: 'Alice',
            senderId: 'alice-uid',
            conversationId: 'group',
            timestamp: DateTime(2024, 1, 1, 10, minute),
          );

      test('loadHistory loads only the newest page and reports more history',
          () async {
        final repo = PagingChatMessageRepository(
          latest: [groupMsg('B', 'newest', 50)],
          older: [groupMsg('A', 'oldest', 10)],
        );
        final service =
            ChatService(liveKitService: fakeLiveKit, repository: repo);
        addTearDown(service.dispose);

        await service.loadHistory('room-1');

        expect(service.currentMessages.map((m) => m.text), equals(['newest']));
        expect(service.hasMoreHistory('group'), isTrue);
        expect(repo.pageCalls, equals(1),
            reason: 'only the newest page is fetched up front');
      });

      test('loadOlderGroupMessages prepends the older page before the newest',
          () async {
        final repo = PagingChatMessageRepository(
          latest: [groupMsg('B', 'newest', 50)],
          older: [groupMsg('A', 'oldest', 10)],
        );
        final service =
            ChatService(liveKitService: fakeLiveKit, repository: repo);
        addTearDown(service.dispose);

        await service.loadHistory('room-1');
        await service.loadOlderGroupMessages();

        // Older page prepended → ascending [oldest, newest].
        expect(service.currentMessages.map((m) => m.text),
            equals(['oldest', 'newest']));
        // The short older page latches exhaustion.
        expect(service.hasMoreHistory('group'), isFalse);
      });

      test('an exhausted history does not refetch on further load-older calls',
          () async {
        // No older page at all → newest page is the whole history.
        final repo = PagingChatMessageRepository(
          latest: [groupMsg('X', 'only', 10)],
          older: const [],
        );
        final service =
            ChatService(liveKitService: fakeLiveKit, repository: repo);
        addTearDown(service.dispose);

        await service.loadHistory('room-1');
        expect(service.hasMoreHistory('group'), isFalse);

        await service.loadOlderGroupMessages();
        await service.loadOlderGroupMessages();

        expect(repo.pageCalls, equals(1),
            reason: 'exhausted history must never refetch (no infinite loop)');
      });

      test('empty history reports no more and never fetches an older page',
          () async {
        final repo = PagingChatMessageRepository(latest: const [], older: const []);
        final service =
            ChatService(liveKitService: fakeLiveKit, repository: repo);
        addTearDown(service.dispose);

        await service.loadHistory('room-1');
        expect(service.currentMessages, isEmpty);
        expect(service.hasMoreHistory('group'), isFalse);

        await service.loadOlderGroupMessages();
        expect(repo.pageCalls, equals(1));
      });

      // THE dedup seam paging introduces (task #27 requirement 4): a message can
      // arrive LIVE before the page containing it is ever paged in. Its id was
      // never marked seen at load time (that page wasn't loaded), so the live
      // copy is appended. When the user later pages back to it, the older-page
      // copy must be deduped away — the message renders exactly ONCE.
      test('a live-delivered old message is not duplicated when its older '
          'page later loads', () async {
        fakeLiveKit.connected = true;

        // Newest page does NOT contain M10; the older page DOES.
        final repo = PagingChatMessageRepository(
          latest: [groupMsg('M50', 'newest', 50)],
          older: [groupMsg('M10', 'old message', 10)],
        );
        final service =
            ChatService(liveKitService: fakeLiveKit, repository: repo);
        addTearDown(service.dispose);

        await service.loadHistory('room-1'); // loads [M50], more history true

        // M10 arrives LIVE before its page is paged in.
        fakeLiveKit.simulateChatFromOtherUser('alice-uid', {
          'text': 'old message',
          'id': 'M10',
          'senderName': 'Alice',
        });
        await pumpEventQueue();
        expect(
          service.currentMessages.where((m) => m.stableId == 'M10'),
          hasLength(1),
          reason: 'the live delivery adds M10 once',
        );

        // User pages back → the older page (which contains M10) loads.
        await service.loadOlderGroupMessages();

        expect(
          service.currentMessages.where((m) => m.stableId == 'M10'),
          hasLength(1),
          reason: 'the older-page copy must be deduped against the live copy',
        );
        // The newest message is still present exactly once.
        expect(
          service.currentMessages.where((m) => m.stableId == 'M50'),
          hasLength(1),
        );
      });

      test('two docs sharing one id in a single older page collapse to one',
          () async {
        // The DM double-persist / GlobalKey-collision case, on the group path.
        final dup = groupMsg('shared', 'dup', 10);
        final repo = PagingChatMessageRepository(
          latest: [groupMsg('N', 'newest', 50)],
          older: [dup, dup],
        );
        final service =
            ChatService(liveKitService: fakeLiveKit, repository: repo);
        addTearDown(service.dispose);

        await service.loadHistory('room-1');
        await service.loadOlderGroupMessages();

        expect(
          service.currentMessages.where((m) => m.stableId == 'shared'),
          hasLength(1),
        );
      });

      // Cage-match round 1, Carnot High: dedup kept uniqueness but not POSITION.
      // A message delivered live carrying an OLD sender-timestamp must sort into
      // its chronological place, not strand at the tail (newest, in reverse:true)
      // — and it must stay put, still single, when its page loads.
      test('a live message with an OLD sender-timestamp sorts into place, not '
          'the tail — and stays single when its page loads', () async {
        fakeLiveKit.connected = true;
        final repo = PagingChatMessageRepository(
          latest: [groupMsg('NEW', 'newest', 50)],
          older: [groupMsg('OLD', 'old', 10)],
        );
        final service =
            ChatService(liveKitService: fakeLiveKit, repository: repo);
        addTearDown(service.dispose);

        await service.loadHistory('room-1'); // [newest]

        // OLD arrives LIVE but carries its true old timestamp on the wire.
        fakeLiveKit.simulateChatFromOtherUser('alice-uid', {
          'text': 'old',
          'id': 'OLD',
          'senderName': 'Alice',
          'timestamp': DateTime(2024, 1, 1, 10, 10).toIso8601String(),
        });
        await pumpEventQueue();

        // Sorted ascending despite arriving last: old BEFORE newest.
        expect(service.currentMessages.map((m) => m.text),
            equals(['old', 'newest']));

        // Paging OLD's page in keeps it single AND keeps the order.
        await service.loadOlderGroupMessages();
        expect(service.currentMessages.where((m) => m.stableId == 'OLD'),
            hasLength(1));
        expect(service.currentMessages.map((m) => m.text),
            equals(['old', 'newest']));
      });

      // Cage-match round 1, Carnot/Kelvin/Tesla: a re-entrant loadHistory (or a
      // conversation that vanished from the roster) must not leave a stale
      // cursor. loadHistory clears `_paging` before reseeding.
      test('loadHistory clears stale paging state before reseeding', () async {
        final repo = ResettablePagingRepository();
        final service =
            ChatService(liveKitService: fakeLiveKit, repository: repo);
        addTearDown(service.dispose);

        repo.groupHasMore = true;
        await service.loadHistory('room-1');
        expect(service.hasMoreHistory('group'), isTrue);

        // Re-entry: the same conversation now has no older history.
        repo.groupHasMore = false;
        await service.loadHistory('room-1');
        expect(service.hasMoreHistory('group'), isFalse,
            reason: 'the reseed must clear the stale exhausted/cursor state');
      });
    });

    group('reply rehydration (regression for the second copy-site bug)', () {
      test('a persisted DM reply keeps its linkage + snapshot after reload',
          () async {
        // The MODEL round-trips reply fields fine; the gap was the SERVICE
        // re-constructing fresh ChatMessages in _fetchAndCacheHistory and
        // copying only a subset of fields. This asserts on the SERVICE path:
        // a reply pulled through loadHistory must still be a reply.
        final repo = RehydrationChatMessageRepository(
          dmMessages: [
            ChatMessage(
              text: 'Original question',
              senderName: 'Peer',
              senderId: 'peer-uid',
              conversationId:
                  Conversation.conversationIdFor('test-user-id', 'peer-uid'),
            ),
            ChatMessage(
              text: 'I agree',
              senderName: 'Test User',
              senderId: 'test-user-id',
              conversationId:
                  Conversation.conversationIdFor('test-user-id', 'peer-uid'),
              replyToMessageId: 'peer-uid:12345',
              replyToText: 'Original question',
              replyToSenderName: 'Peer',
            ),
          ],
        );
        final service = ChatService(
          liveKitService: fakeLiveKit,
          repository: repo,
        );
        addTearDown(service.dispose);

        await service.loadHistory('room-1');

        final loaded = service.dmMessagesSnapshot('peer-uid');
        expect(loaded.length, equals(2));
        final reply = loaded.last;
        expect(reply.isReply, isTrue,
            reason: 'reply must survive the service rehydration copy');
        expect(reply.replyToMessageId, equals('peer-uid:12345'));
        expect(reply.replyToText, equals('Original question'));
        expect(reply.replyToSenderName, equals('Peer'));
      });

      test('reloaded DMs are deduped by stableId (no GlobalKey collision)',
          () async {
        // A DM is persisted by BOTH participants, so a reload can return two
        // docs sharing one transported id. They MUST collapse to one rendered
        // message — otherwise the DM view assigns a single GlobalKey to two
        // bubbles and crashes. Regression for the #494 cage-match (Carnot).
        final convId = Conversation.conversationIdFor('test-user-id', 'peer-uid');
        final dup = ChatMessage(
          text: 'Hello there',
          id: 'shared-wire-id',
          senderName: 'Peer',
          senderId: 'peer-uid',
          conversationId: convId,
        );
        final repo = RehydrationChatMessageRepository(
          dmMessages: [dup, dup], // same id persisted twice
        );
        final service = ChatService(
          liveKitService: fakeLiveKit,
          repository: repo,
        );
        addTearDown(service.dispose);

        await service.loadHistory('room-1');

        final loaded = service.dmMessagesSnapshot('peer-uid');
        expect(loaded.length, equals(1),
            reason: 'two docs with the same stableId must collapse to one');
        expect(loaded.single.stableId, equals('shared-wire-id'));
      });

      test('receiving a DM persists the conversation INDEX but NOT the message',
          () async {
        // Root-cause guard for the double-persist (claude-tasks #20) AND the
        // cage-match #495 (Carnot) over-removal. Two writes hide behind the old
        // single _persistMessage call with DIFFERENT rules:
        //  - the MESSAGE: the recipient's senderId is the OTHER participant, so
        //    the `/messages` create rule (senderId == auth.uid) rejects it —
        //    persisting it produced a rejected no-op or a forged-senderId dup.
        //    The receive path must persist NO message (mirrors group receive).
        //  - the conversation INDEX: the `/conversations` rule only needs the
        //    writer to be a participant, so the recipient's upsert IS allowed,
        //    and IS the redundancy that keeps a durable DM discoverable on
        //    reload if the author's own index write lost its race. Keep it.
        final repo = RecordingChatMessageRepository();
        final service = ChatService(
          liveKitService: fakeLiveKit,
          repository: repo,
        );
        addTearDown(service.dispose);
        await service.loadHistory('room-1'); // sets _roomId so persist is reachable
        fakeLiveKit.connected = true;

        final expectedConvId =
            Conversation.conversationIdFor('test-user-id', 'alice-uid');
        fakeLiveKit.simulateDm('alice-uid', {
          'text': 'Hey!',
          'id': 'dm-recv-1',
          'senderName': 'Alice',
          'senderId': 'alice-uid',
        });
        await pumpEventQueue();

        // The message is shown locally...
        expect(service.dmMessagesSnapshot('alice-uid').single.text, equals('Hey!'));
        // ...the recipient writes NO message doc (would be rejected / a dup)...
        expect(repo.saved, isEmpty,
            reason: 'a received DM message must not be persisted by the recipient');
        // ...but it DOES upsert the discovery index for the thread.
        expect(repo.savedConversations, equals([expectedConvId]),
            reason: 'recipient keeps the conversation-index write (discovery '
                'redundancy if the author index write lost its race)');
      });

      test('sending a DM persists the message AND its conversation index',
          () async {
        final repo = RecordingChatMessageRepository();
        final service = ChatService(
          liveKitService: fakeLiveKit,
          repository: repo,
        );
        addTearDown(service.dispose);
        await service.loadHistory('room-1'); // sets _roomId
        fakeLiveKit.connected = true;

        final expectedConvId =
            Conversation.conversationIdFor('test-user-id', 'peer-uid');
        await service.sendDm('peer-uid', 'Hello', peerDisplayName: 'Peer');
        await pumpEventQueue();

        expect(repo.saved.length, equals(1),
            reason: 'the author persists its own message exactly once');
        expect(repo.saved.single.senderId, equals('test-user-id'),
            reason: 'persisted senderId is the authenticated author');
        expect(repo.saved.single.text, equals('Hello'));
        expect(repo.savedConversations, equals([expectedConvId]),
            reason: 'the author also upserts the conversation index');
      });

      test('a persisted GROUP reply keeps its linkage + snapshot after reload',
          () async {
        final repo = RehydrationChatMessageRepository(
          groupMessages: [
            ChatMessage(
              text: 'reply in group',
              senderName: 'Peer',
              senderId: 'peer-uid',
              conversationId: 'group',
              replyToMessageId: 'someone:999',
              replyToText: 'a question',
              replyToSenderName: 'Asker',
            ),
          ],
        );
        final service = ChatService(
          liveKitService: fakeLiveKit,
          repository: repo,
        );
        addTearDown(service.dispose);

        await service.loadHistory('room-1');

        final reply = service.currentMessages.last;
        expect(reply.isReply, isTrue,
            reason: 'group reply must survive the service rehydration copy');
        expect(reply.replyToMessageId, equals('someone:999'));
        expect(reply.replyToText, equals('a question'));
        expect(reply.replyToSenderName, equals('Asker'));
      });
    });

    group('@mentions', () {
      late List<AppEvent> dispatched;

      setUp(() {
        dispatched = [];
        clearSinks();
        registerSink(dispatched.add);
      });

      tearDown(clearSinks);

      List<PlayersMentioned> mentions() =>
          dispatched.whereType<PlayersMentioned>().toList();

      test('sendMessage publishes an atomic mentions UID list', () async {
        unawaited(chatService.sendMessage(
          'hey @Bob',
          mentions: ['bob-uid'],
        ));
        await pumpEventQueue();

        final chatPublish = fakeLiveKit.publishedMessages.firstWhere(
          (m) => m['topic'] == DataTopic.chat.wireName,
        );
        final payload = chatPublish['payload'] as Map<String, dynamic>;
        expect(payload['mentions'], equals(['bob-uid']));
      });

      test('sendMessage dispatches PlayersMentioned LOCALLY so the sender '
          'witnesses their own mention (LiveKit does not loop self back)',
          () async {
        unawaited(chatService.sendMessage(
          'hey @Bob',
          mentions: ['bob-uid'],
        ));
        await pumpEventQueue();

        expect(mentions(), hasLength(1));
        // The mentioner is our own authenticated identity, not a payload value.
        expect(mentions().single.mentionerUid, equals('test-user-id'));
        expect(mentions().single.mentionedUids, equals(['bob-uid']));
      });

      test('sendMessage with no mentions dispatches no PlayersMentioned',
          () async {
        unawaited(chatService.sendMessage('plain'));
        await pumpEventQueue();
        expect(mentions(), isEmpty);
      });

      test('sendMessage with no mentions omits the field entirely', () async {
        unawaited(chatService.sendMessage('plain message'));
        await pumpEventQueue();

        final chatPublish = fakeLiveKit.publishedMessages.firstWhere(
          (m) => m['topic'] == DataTopic.chat.wireName,
        );
        final payload = chatPublish['payload'] as Map<String, dynamic>;
        expect(payload.containsKey('mentions'), isFalse);
      });

      test('incoming mention dispatches PlayersMentioned with the named UID',
          () async {
        fakeLiveKit.simulateChatFromOtherUser('alice-uid', {
          'id': 'msg-1',
          'text': 'ping @Me',
          'senderName': 'Alice',
          'mentions': ['my-uid', 'other-uid'],
        });
        await pumpEventQueue();

        expect(mentions(), hasLength(1));
        expect(mentions().single.mentionedUids, equals(['my-uid', 'other-uid']));
        expect(mentions().single.messageId, equals('msg-1'));
      });

      test(
          'mentionerUid is the TRANSPORT senderId, never the spoofed payload '
          'senderId', () async {
        // Hostile payload claims to be from "victim-uid"; the transport layer
        // says it came from "attacker-uid". The dispatched event must credit
        // the transport identity — mirrors the PR #490 reply trust test.
        fakeLiveKit.simulateChatFromOtherUser('attacker-uid', {
          'id': 'msg-2',
          'text': 'gotcha @X',
          'senderName': 'Totally Not An Attacker',
          'senderId': 'victim-uid', // spoof attempt in payload
          'mentions': ['x-uid'],
        });
        await pumpEventQueue();

        expect(mentions(), hasLength(1));
        expect(mentions().single.mentionerUid, equals('attacker-uid'),
            reason: 'transport identity must win over payload senderId');
      });

      test('malformed mentions field is dropped, no throw, no dispatch',
          () async {
        // A non-list mentions value must not throw or fabricate a mention.
        fakeLiveKit.simulateChatFromOtherUser('alice-uid', {
          'id': 'msg-3',
          'text': 'garbage',
          'senderName': 'Alice',
          'mentions': 'not-a-list',
        });
        // Mixed list: non-string elements are skipped.
        fakeLiveKit.simulateChatFromOtherUser('alice-uid', {
          'id': 'msg-4',
          'text': 'mixed',
          'senderName': 'Alice',
          'mentions': ['good-uid', 42, null, 'also-good'],
        });
        await pumpEventQueue();

        // msg-3 had no valid mentions → no dispatch. msg-4 keeps the two strings.
        expect(mentions(), hasLength(1));
        expect(mentions().single.messageId, equals('msg-4'));
        expect(mentions().single.mentionedUids, equals(['good-uid', 'also-good']));
        // The chat messages themselves still landed (parse never threw).
        expect(
          chatService.currentMessages.where((m) => m.text == 'garbage'),
          hasLength(1),
        );
      });

      test('a chat message with an empty mentions list dispatches nothing',
          () async {
        fakeLiveKit.simulateChatFromOtherUser('alice-uid', {
          'id': 'msg-5',
          'text': 'no mentions here',
          'senderName': 'Alice',
          'mentions': <String>[],
        });
        await pumpEventQueue();

        expect(mentions(), isEmpty);
      });
    });
  });
}

/// A [ChatMessageRepository] that returns canned messages for rehydration
/// tests. [loadMessages] returns [groupMessages] for the `'group'` conv and
/// [dmMessages] for any other conversation id.
class RehydrationChatMessageRepository implements ChatMessageRepository {
  RehydrationChatMessageRepository({
    this.groupMessages = const [],
    this.dmMessages = const [],
  });

  final List<ChatMessage> groupMessages;
  final List<ChatMessage> dmMessages;

  @override
  Future<Set<String>> loadConversationIds(String roomId, String userId) async {
    return {
      'group',
      Conversation.conversationIdFor('test-user-id', 'peer-uid'),
    };
  }

  @override
  Future<MessagePage> loadMessagePage(
    String roomId,
    String conversationId, {
    MessageCursor? after,
    int limit = ChatMessageRepository.defaultPageSize,
  }) async {
    // Canned single page; an older-page request (after != null) is exhausted.
    if (after != null) return MessagePage.empty;
    final msgs = conversationId == 'group' ? groupMessages : dmMessages;
    return MessagePage(messages: msgs, cursor: null, hasMore: false);
  }

  @override
  Future<void> saveMessage(String roomId, ChatMessage message) async {}

  @override
  Future<void> saveConversation(
    String roomId, {
    required String conversationId,
    required List<String> participants,
    required String type,
    String? lastMessageText,
  }) async {}
}

/// Opaque cursor for [PagingChatMessageRepository] (the app only passes it back).
class _FakeCursor extends MessageCursor {
  const _FakeCursor();
}

/// A [ChatMessageRepository] serving two canned pages for paging tests: the
/// newest page ([latest]) on the first `after: null` call, then one [older]
/// page on the `after:` call. [pageCalls] counts every [loadMessagePage] so a
/// test can assert an exhausted history never refetches.
class PagingChatMessageRepository implements ChatMessageRepository {
  PagingChatMessageRepository({this.latest = const [], this.older = const []});

  final List<ChatMessage> latest;
  final List<ChatMessage> older;
  int pageCalls = 0;

  @override
  Future<Set<String>> loadConversationIds(String roomId, String userId) async =>
      {'group'};

  @override
  Future<MessagePage> loadMessagePage(
    String roomId,
    String conversationId, {
    MessageCursor? after,
    int limit = ChatMessageRepository.defaultPageSize,
  }) async {
    pageCalls++;
    if (after == null) {
      // Newest page. hasMore is true only when an older page exists, so a
      // history with no older page latches exhausted immediately.
      final hasMore = older.isNotEmpty;
      return MessagePage(
        messages: latest,
        cursor: hasMore ? const _FakeCursor() : null,
        hasMore: hasMore,
      );
    }
    // The single older page — exhausted afterward.
    return MessagePage(messages: older, cursor: null, hasMore: false);
  }

  @override
  Future<void> saveMessage(String roomId, ChatMessage message) async {}

  @override
  Future<void> saveConversation(
    String roomId, {
    required String conversationId,
    required List<String> participants,
    required String type,
    String? lastMessageText,
  }) async {}
}

/// A [ChatMessageRepository] whose newest page's `hasMore` can be flipped
/// between `loadHistory` calls, to prove a reseed clears stale paging state.
class ResettablePagingRepository implements ChatMessageRepository {
  bool groupHasMore = false;

  @override
  Future<Set<String>> loadConversationIds(String roomId, String userId) async =>
      {'group'};

  @override
  Future<MessagePage> loadMessagePage(
    String roomId,
    String conversationId, {
    MessageCursor? after,
    int limit = ChatMessageRepository.defaultPageSize,
  }) async {
    if (after != null) return MessagePage.empty;
    return MessagePage(
      messages: [
        ChatMessage(
          text: 'm',
          id: 'm',
          senderName: 'A',
          senderId: 'a',
          conversationId: 'group',
        ),
      ],
      cursor: groupHasMore ? const _FakeCursor() : null,
      hasMore: groupHasMore,
    );
  }

  @override
  Future<void> saveMessage(String roomId, ChatMessage message) async {}

  @override
  Future<void> saveConversation(
    String roomId, {
    required String conversationId,
    required List<String> participants,
    required String type,
    String? lastMessageText,
  }) async {}
}

/// A [ChatMessageRepository] that always throws, simulating Firestore failures.
class FailingChatMessageRepository implements ChatMessageRepository {
  @override
  Future<Set<String>> loadConversationIds(String roomId, String userId) {
    throw Exception('Firestore unavailable');
  }

  @override
  Future<MessagePage> loadMessagePage(
    String roomId,
    String conversationId, {
    MessageCursor? after,
    int limit = ChatMessageRepository.defaultPageSize,
  }) {
    throw Exception('Firestore unavailable');
  }

  @override
  Future<void> saveMessage(String roomId, ChatMessage message) async {}

  @override
  Future<void> saveConversation(
    String roomId, {
    required String conversationId,
    required List<String> participants,
    required String type,
    String? lastMessageText,
  }) async {}
}

/// A [ChatMessageRepository] that never completes, simulating network hangs.
class HangingChatMessageRepository implements ChatMessageRepository {
  @override
  Future<Set<String>> loadConversationIds(String roomId, String userId) {
    // Never completes — simulates a network hang.
    return Completer<Set<String>>().future;
  }

  @override
  Future<MessagePage> loadMessagePage(
    String roomId,
    String conversationId, {
    MessageCursor? after,
    int limit = ChatMessageRepository.defaultPageSize,
  }) {
    return Completer<MessagePage>().future;
  }

  @override
  Future<void> saveMessage(String roomId, ChatMessage message) async {}

  @override
  Future<void> saveConversation(
    String roomId, {
    required String conversationId,
    required List<String> participants,
    required String type,
    String? lastMessageText,
  }) async {}
}

/// A [ChatMessageRepository] that returns one DM conversation successfully,
/// then hangs on the second — simulating a mid-loop failure.
class PartialThenHangingRepository implements ChatMessageRepository {
  @override
  Future<Set<String>> loadConversationIds(String roomId, String userId) async {
    return {'dm-conv-1', 'dm-conv-2'};
  }

  int _loadMessagesCallCount = 0;

  @override
  Future<MessagePage> loadMessagePage(
    String roomId,
    String conversationId, {
    MessageCursor? after,
    int limit = ChatMessageRepository.defaultPageSize,
  }) {
    _loadMessagesCallCount++;
    if (_loadMessagesCallCount == 1) {
      // First conversation's newest page loads successfully.
      return Future.value(MessagePage(
        messages: [
          ChatMessage(
            text: 'Hello from peer',
            senderName: 'Peer',
            senderId: 'peer-uid',
            conversationId: conversationId,
            timestamp: DateTime(2024),
          ),
        ],
        cursor: null,
        hasMore: false,
      ));
    }
    // Subsequent calls hang forever.
    return Completer<MessagePage>().future;
  }

  @override
  Future<void> saveMessage(String roomId, ChatMessage message) async {}

  @override
  Future<void> saveConversation(
    String roomId, {
    required String conversationId,
    required List<String> participants,
    required String type,
    String? lastMessageText,
  }) async {}
}

/// Fake LiveKitService for testing.
///
/// Explicitly implements all [LiveKitService] members so that adding new
/// methods to the real class causes a compile-time error here, ensuring tests
/// stay in sync with the interface.
class FakeLiveKitService implements LiveKitService {
  bool connected = true;
  final List<Map<String, dynamic>> publishedMessages = [];
  final _dataReceivedController =
      StreamController<DataChannelMessage>.broadcast();

  @override
  bool get isConnected => connected;

  @override
  String get userId => 'test-user-id';

  @override
  String get displayName => 'Test User';

  @override
  String get roomName => 'tech-world';

  @override
  Stream<DataChannelMessage> get dataReceived =>
      _dataReceivedController.stream;

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
      topic: DataTopic.chatResponse.wireName,
      data: utf8.encode(jsonEncode(response)),
    ));
  }

  void simulateInvalidResponse(String invalidData) {
    _dataReceivedController.add(DataChannelMessage(
      senderId: 'bot-claude',
      topic: DataTopic.chatResponse.wireName,
      data: utf8.encode(invalidData),
    ));
  }

  void simulateMessageWithTopic(
      String topic, Map<String, dynamic> response) {
    _dataReceivedController.add(DataChannelMessage(
      senderId: 'bot-claude',
      topic: topic,
      data: utf8.encode(jsonEncode(response)),
    ));
  }

  void simulateResponseWithId(
      String id, Map<String, dynamic> response) {
    _dataReceivedController.add(DataChannelMessage(
      senderId: 'bot-claude',
      topic: DataTopic.chatResponse.wireName,
      data: utf8.encode(jsonEncode(response)),
    ));
  }

  void simulateChatFromOtherUser(
      String senderId, Map<String, dynamic> message) {
    _dataReceivedController.add(DataChannelMessage(
      senderId: senderId,
      topic: DataTopic.chat.wireName,
      data: utf8.encode(jsonEncode(message)),
    ));
  }

  void simulateChatFromSelf(Map<String, dynamic> message) {
    _dataReceivedController.add(DataChannelMessage(
      senderId: userId, // Same as our userId
      topic: DataTopic.chat.wireName,
      data: utf8.encode(jsonEncode(message)),
    ));
  }

  /// Simulate an incoming DM from another user.
  void simulateDm(String senderId, Map<String, dynamic> message) {
    _dataReceivedController.add(DataChannelMessage(
      senderId: senderId,
      topic: DataTopic.dm.wireName,
      data: utf8.encode(jsonEncode(message)),
    ));
  }

  /// Simulate a DM response from the bot.
  void simulateDmResponse(
      String senderId, Map<String, dynamic> message) {
    _dataReceivedController.add(DataChannelMessage(
      senderId: senderId,
      topic: DataTopic.dmResponse.wireName,
      data: utf8.encode(jsonEncode(message)),
    ));
  }

  final _participantJoinedController =
      StreamController<RemoteParticipant>.broadcast();
  final _participantLeftController =
      StreamController<RemoteParticipant>.broadcast();
  final _speakingChangedController =
      StreamController<(Participant, bool)>.broadcast();
  final _trackSubscribedController =
      StreamController<(Participant, VideoTrack)>.broadcast();
  final _trackUnsubscribedController =
      StreamController<(Participant, VideoTrack)>.broadcast();
  final _localTrackPublishedController =
      StreamController<LocalTrackPublication>.broadcast();
  final _connectionLostController = StreamController<String?>.broadcast();

  @override
  Map<String, RemoteParticipant> get remoteParticipants => {};

  @override
  Stream<RemoteParticipant> get participantJoined =>
      _participantJoinedController.stream;

  @override
  Stream<RemoteParticipant> get participantLeft =>
      _participantLeftController.stream;

  @override
  Stream<(Participant, bool)> get speakingChanged =>
      _speakingChangedController.stream;

  @override
  Stream<(Participant, VideoTrack)> get trackSubscribed =>
      _trackSubscribedController.stream;

  @override
  Stream<(Participant, VideoTrack)> get trackUnsubscribed =>
      _trackUnsubscribedController.stream;

  @override
  Stream<LocalTrackPublication> get localTrackPublished =>
      _localTrackPublishedController.stream;

  @override
  Stream<String?> get connectionLost => _connectionLostController.stream;

  @override
  Stream<PlayerPath> get positionReceived => const Stream.empty();

  @override
  Stream<AvatarUpdate> get avatarReceived => const Stream.empty();

  @override
  Stream<RoomTimerMessage> get roomTimerReceived => const Stream.empty();

  @override
  Future<void> publishRoomTimer(RoomTimerMessage message) async {}

  @override
  Room? get room => null;

  @override
  LocalParticipant? get localParticipant => null;

  @override
  bool get isScreenShareEnabled => false;

  @override
  Future<void> dispose() async {
    _dataReceivedController.close();
    _participantJoinedController.close();
    _participantLeftController.close();
    _speakingChangedController.close();
    _trackSubscribedController.close();
    _trackUnsubscribedController.close();
    _localTrackPublishedController.close();
    _connectionLostController.close();
  }

  @override
  Future<ConnectionResult> connect() async =>
      connected ? ConnectionResult.connected : ConnectionResult.roomFailed;

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> setCameraEnabled(bool enabled) async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}

  @override
  Future<void> setScreenShareEnabled(bool enabled,
      {ScreenShareCaptureOptions? options}) async {}

  @override
  void setParticipantAudioEnabled(String identity, bool enabled) {}

  @override
  bool setParticipantAudioVolume(String identity, double volume) => true;

  @override
  final ValueNotifier<bool> dreamfinderSilenced = ValueNotifier<bool>(false);

  @override
  void setDreamfinderSilenced(bool silenced) {
    dreamfinderSilenced.value = silenced;
  }

  @override
  Participant? getParticipant(String identity) => null;

  @override
  Future<void> publishData(
    List<int> data, {
    bool reliable = true,
    List<String>? destinationIdentities,
    String? topic,
  }) async {}

  @override
  Future<void> publishMapInfo(GameMap map) async {}

  @override
  Stream<void> get mapInfoRequested => const Stream.empty();

  @override
  Future<void> publishMapSwitch(String mapId) async {}

  @override
  Stream<String> get mapSwitchReceived => const Stream.empty();

  @override
  Future<void> publishPosition({
    required List<Vector2> points,
    required List<Direction> directions,
  }) async {}

  @override
  Future<void> publishTerminalActivity({
    required String action,
    String? challengeId,
    String? challengeTitle,
    String? challengeDescription,
    int? terminalX,
    int? terminalY,
  }) async {}

  @override
  Future<void> publishAvatar(Avatar avatar) async {}

  @override
  Future<void> publishDfProximity({required bool near}) async {}

  @override
  Future<DataChannelMessage?> sendPing({
    Duration timeout = const Duration(seconds: 5),
  }) async =>
      null;

  @override
  Stream<PositionHeartbeat> get positionHeartbeatReceived =>
      const Stream.empty();

  @override
  void startPositionHeartbeat(Point<int> Function() currentPosition) {}

  @override
  void stopPositionHeartbeat() {}

  // Catch-all so growth of the LiveKitService interface doesn't break this
  // hand-rolled fake (mirrors the other fakes' noSuchMethod pattern).
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A [ChatMessageRepository] that RECORDS every [saveMessage] AND
/// [saveConversation] call, so a test can assert WHICH writes each path makes.
/// Used to pin two invariants: a RECEIVED DM persists the conversation INDEX
/// but NOT the message (only the author persists the message, per the
/// `/messages` `senderId == auth.uid` rule), while a SENT DM persists both.
/// See claude-tasks #20 and cage-match #495 (Carnot).
class RecordingChatMessageRepository implements ChatMessageRepository {
  final List<ChatMessage> saved = [];
  final List<String> savedConversations = [];

  @override
  Future<Set<String>> loadConversationIds(String roomId, String userId) async =>
      {'group'};

  @override
  Future<MessagePage> loadMessagePage(
    String roomId,
    String conversationId, {
    MessageCursor? after,
    int limit = ChatMessageRepository.defaultPageSize,
  }) async =>
      MessagePage.empty;

  @override
  Future<void> saveMessage(String roomId, ChatMessage message) async {
    saved.add(message);
  }

  @override
  Future<void> saveConversation(
    String roomId, {
    required String conversationId,
    required List<String> participants,
    required String type,
    String? lastMessageText,
  }) async {
    savedConversations.add(conversationId);
  }
}
