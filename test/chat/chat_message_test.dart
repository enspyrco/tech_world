import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/chat/chat_message.dart';

void main() {
  group('ChatMessage', () {
    test('creates message with required fields', () {
      final message = ChatMessage(
        text: 'Hello!',
        senderName: 'John',
      );

      expect(message.text, equals('Hello!'));
      expect(message.senderName, equals('John'));
    });

    test('has default values for optional fields', () {
      final message = ChatMessage(
        text: 'Test',
        senderName: 'User',
      );

      expect(message.isLocalUser, isFalse);
      expect(message.isBot, isFalse);
      expect(message.timestamp, isNotNull);
    });

    test('creates user message', () {
      final message = ChatMessage(
        text: 'User message',
        senderName: 'Player 1',
        isLocalUser: true,
      );

      expect(message.isLocalUser, isTrue);
      expect(message.isBot, isFalse);
    });

    test('creates bot message', () {
      final message = ChatMessage(
        text: 'Bot response',
        senderName: 'Claude',
        isBot: true,
      );

      expect(message.isLocalUser, isFalse);
      expect(message.isBot, isTrue);
    });

    test('creates message with custom timestamp', () {
      final customTime = DateTime(2024, 1, 15, 10, 30);
      final message = ChatMessage(
        text: 'Timed message',
        senderName: 'Sender',
        timestamp: customTime,
      );

      expect(message.timestamp, equals(customTime));
    });

    test('generates timestamp when not provided', () {
      final before = DateTime.now();
      final message = ChatMessage(
        text: 'Auto timestamp',
        senderName: 'Sender',
      );
      final after = DateTime.now();

      expect(message.timestamp.isAfter(before) || message.timestamp.isAtSameMomentAs(before), isTrue);
      expect(message.timestamp.isBefore(after) || message.timestamp.isAtSameMomentAs(after), isTrue);
    });

    group('isUser getter (legacy)', () {
      test('returns same value as isLocalUser', () {
        final localMessage = ChatMessage(
          text: 'Local',
          senderName: 'Me',
          isLocalUser: true,
        );
        final remoteMessage = ChatMessage(
          text: 'Remote',
          senderName: 'Other',
          isLocalUser: false,
        );

        expect(localMessage.isUser, equals(localMessage.isLocalUser));
        expect(localMessage.isUser, isTrue);

        expect(remoteMessage.isUser, equals(remoteMessage.isLocalUser));
        expect(remoteMessage.isUser, isFalse);
      });
    });

    test('handles empty text', () {
      final message = ChatMessage(
        text: '',
        senderName: 'Sender',
      );

      expect(message.text, equals(''));
    });

    test('handles empty sender name', () {
      final message = ChatMessage(
        text: 'Message',
        senderName: '',
      );

      expect(message.senderName, equals(''));
    });

    test('handles multiline text', () {
      final multilineText = 'Line 1\nLine 2\nLine 3';
      final message = ChatMessage(
        text: multilineText,
        senderName: 'Sender',
      );

      expect(message.text, equals(multilineText));
      expect(message.text.split('\n').length, equals(3));
    });

    test('handles special characters in text', () {
      final specialText = 'Hello! @#\$%^&*()_+-=[]{}|;:\'",.<>?/\\`~';
      final message = ChatMessage(
        text: specialText,
        senderName: 'Sender',
      );

      expect(message.text, equals(specialText));
    });

    test('handles unicode in text', () {
      final unicodeText = 'Hello 🌍 世界 مرحبا';
      final message = ChatMessage(
        text: unicodeText,
        senderName: 'Sender',
      );

      expect(message.text, equals(unicodeText));
    });

    test('both isLocalUser and isBot can be true', () {
      // Edge case: technically possible though semantically odd
      final message = ChatMessage(
        text: 'Both flags',
        senderName: 'Hybrid',
        isLocalUser: true,
        isBot: true,
      );

      expect(message.isLocalUser, isTrue);
      expect(message.isBot, isTrue);
    });

    group('new optional fields', () {
      test('senderId and conversationId default to null', () {
        final message = ChatMessage(
          text: 'Hello',
          senderName: 'User',
        );

        expect(message.senderId, isNull);
        expect(message.conversationId, isNull);
      });

      test('accepts senderId and conversationId', () {
        final message = ChatMessage(
          text: 'Hello',
          senderName: 'Alice',
          senderId: 'alice-uid',
          conversationId: 'group',
        );

        expect(message.senderId, equals('alice-uid'));
        expect(message.conversationId, equals('group'));
      });

      test('accepts DM conversationId', () {
        final message = ChatMessage(
          text: 'Hey Bob',
          senderName: 'Alice',
          senderId: 'alice-uid',
          conversationId: 'dm_alice-uid_bob-uid',
        );

        expect(message.conversationId, equals('dm_alice-uid_bob-uid'));
      });
    });

    group('participants field', () {
      test('defaults to null', () {
        final message = ChatMessage(
          text: 'Hello',
          senderName: 'User',
        );

        expect(message.participants, isNull);
      });

      test('accepts participants list', () {
        final message = ChatMessage(
          text: 'DM',
          senderName: 'Alice',
          participants: ['alice-uid', 'bob-uid'],
        );

        expect(message.participants, equals(['alice-uid', 'bob-uid']));
      });
    });

    group('reply fields', () {
      test('reply fields default to null', () {
        final message = ChatMessage(text: 'Hi', senderName: 'User');

        expect(message.replyToMessageId, isNull);
        expect(message.replyToText, isNull);
        expect(message.replyToSenderName, isNull);
      });

      test('isReply is false without a replyToMessageId', () {
        final message = ChatMessage(text: 'Hi', senderName: 'User');
        expect(message.isReply, isFalse);
      });

      test('accepts reply fields and reports isReply true', () {
        final message = ChatMessage(
          text: 'I agree',
          senderName: 'Bob',
          replyToMessageId: 'msg-42',
          replyToText: 'What do you think?',
          replyToSenderName: 'Alice',
        );

        expect(message.replyToMessageId, equals('msg-42'));
        expect(message.replyToText, equals('What do you think?'));
        expect(message.replyToSenderName, equals('Alice'));
        expect(message.isReply, isTrue);
      });

      test('toFirestore includes reply fields when present', () {
        final message = ChatMessage(
          text: 'reply body',
          senderName: 'Bob',
          replyToMessageId: 'msg-42',
          replyToText: 'original',
          replyToSenderName: 'Alice',
        );

        final json = message.toFirestore();

        expect(json['replyToMessageId'], equals('msg-42'));
        expect(json['replyToText'], equals('original'));
        expect(json['replyToSenderName'], equals('Alice'));
      });

      test('toFirestore omits reply fields when null', () {
        final message = ChatMessage(text: 'plain', senderName: 'Bob');

        final json = message.toFirestore();

        expect(json.containsKey('replyToMessageId'), isFalse);
        expect(json.containsKey('replyToText'), isFalse);
        expect(json.containsKey('replyToSenderName'), isFalse);
      });

      test('fromFirestore parses reply fields', () {
        final json = {
          'text': 'reply body',
          'senderName': 'Bob',
          'replyToMessageId': 'msg-42',
          'replyToText': 'original',
          'replyToSenderName': 'Alice',
          'timestamp': DateTime(2024, 6, 15).toIso8601String(),
        };

        final message = ChatMessage.fromFirestore(json);

        expect(message.replyToMessageId, equals('msg-42'));
        expect(message.replyToText, equals('original'));
        expect(message.replyToSenderName, equals('Alice'));
        expect(message.isReply, isTrue);
      });

      test('fromFirestore handles missing reply fields (legacy)', () {
        final json = {
          'text': 'plain',
          'senderName': 'Bob',
          'timestamp': DateTime(2024, 6, 15).toIso8601String(),
        };

        final message = ChatMessage.fromFirestore(json);

        expect(message.replyToMessageId, isNull);
        expect(message.isReply, isFalse);
      });

      test('fromFirestore tolerates a non-string replyToMessageId', () {
        // Defensive parse at the wire seam — a malformed payload (here an int
        // where a string is expected) must not throw, just drop the field.
        final json = <String, dynamic>{
          'text': 'plain',
          'senderName': 'Bob',
          'replyToMessageId': 12345, // wrong type
          'timestamp': DateTime(2024, 6, 15).toIso8601String(),
        };

        final message = ChatMessage.fromFirestore(json);

        expect(message.replyToMessageId, isNull);
        expect(message.isReply, isFalse);
      });
    });

    group('defensive Firestore parsing (malformed docs must not throw)', () {
      test('non-string timestamp falls back to now, no throw', () {
        final before = DateTime.now();
        final json = <String, dynamic>{
          'text': 'bad ts',
          'senderName': 'X',
          'timestamp': 12345, // not a String
        };

        final message = ChatMessage.fromFirestore(json);

        // Falls back to ~now rather than throwing.
        expect(
          message.timestamp
              .isAfter(before.subtract(const Duration(seconds: 5))),
          isTrue,
        );
      });

      test('unparseable timestamp string falls back to now, no throw', () {
        final json = <String, dynamic>{
          'text': 'bad ts',
          'senderName': 'X',
          'timestamp': 'not-a-date',
        };

        expect(() => ChatMessage.fromFirestore(json), returnsNormally);
        final message = ChatMessage.fromFirestore(json);
        expect(message.timestamp, isNotNull);
      });

      test('non-list participants drops to null, no throw', () {
        final json = <String, dynamic>{
          'text': 'bad participants',
          'senderName': 'X',
          'participants': 'alice,bob', // a String, not a List
          'timestamp': DateTime(2024).toIso8601String(),
        };

        final message = ChatMessage.fromFirestore(json);
        expect(message.participants, isNull);
      });

      test('participants with non-string elements skips them, no throw', () {
        final json = <String, dynamic>{
          'text': 'mixed participants',
          'senderName': 'X',
          'participants': ['alice-uid', 42, null, 'bob-uid'],
          'timestamp': DateTime(2024).toIso8601String(),
        };

        final message = ChatMessage.fromFirestore(json);
        expect(message.participants, equals(['alice-uid', 'bob-uid']));
      });

      test('non-string senderId / conversationId drop to null, no throw', () {
        final json = <String, dynamic>{
          'text': 'bad ids',
          'senderName': 'X',
          'senderId': 99,
          'conversationId': true,
          'timestamp': DateTime(2024).toIso8601String(),
        };

        final message = ChatMessage.fromFirestore(json);
        expect(message.senderId, isNull);
        expect(message.conversationId, isNull);
      });

      test('a fully malformed legacy doc parses without throwing', () {
        final json = <String, dynamic>{
          'text': 'survivor',
          'senderName': 'X',
          'senderId': <dynamic>[],
          'conversationId': 3.14,
          'participants': {'not': 'a list'},
          'replyToMessageId': 0,
          'timestamp': null,
        };

        expect(() => ChatMessage.fromFirestore(json), returnsNormally);
        final message = ChatMessage.fromFirestore(json);
        expect(message.text, equals('survivor'));
        expect(message.isReply, isFalse);
      });
    });

    group('Firestore serialization', () {
      test('toFirestore includes all fields', () {
        final timestamp = DateTime(2024, 6, 15, 14, 30);
        final message = ChatMessage(
          text: 'Hello world',
          senderName: 'Alice',
          senderId: 'alice-uid',
          conversationId: 'group',
          isBot: false,
          timestamp: timestamp,
        );

        final json = message.toFirestore();

        expect(json['text'], equals('Hello world'));
        expect(json['senderName'], equals('Alice'));
        expect(json['senderId'], equals('alice-uid'));
        expect(json['conversationId'], equals('group'));
        expect(json['timestamp'], equals(timestamp.toIso8601String()));
      });

      test('toFirestore includes participants for DMs', () {
        final message = ChatMessage(
          text: 'Hey',
          senderName: 'Alice',
          senderId: 'alice-uid',
          conversationId: 'dm_alice-uid_bob-uid',
          participants: ['alice-uid', 'bob-uid'],
          timestamp: DateTime(2024, 6, 15, 14, 30),
        );

        final json = message.toFirestore();

        expect(json['participants'], equals(['alice-uid', 'bob-uid']));
      });

      test('toFirestore omits null participants', () {
        final message = ChatMessage(
          text: 'Group message',
          senderName: 'Alice',
          conversationId: 'group',
        );

        final json = message.toFirestore();

        expect(json.containsKey('participants'), isFalse);
      });

      test('fromFirestore parses participants', () {
        final json = {
          'text': 'DM',
          'senderName': 'Alice',
          'senderId': 'alice-uid',
          'conversationId': 'dm_alice-uid_bob-uid',
          'participants': ['alice-uid', 'bob-uid'],
          'timestamp': DateTime(2024, 6, 15).toIso8601String(),
        };

        final message = ChatMessage.fromFirestore(json);

        expect(message.participants, equals(['alice-uid', 'bob-uid']));
      });

      test('fromFirestore handles missing participants (legacy)', () {
        final json = {
          'text': 'Old DM',
          'senderName': 'Alice',
          'conversationId': 'dm_alice-uid_bob-uid',
          'timestamp': DateTime(2024, 6, 15).toIso8601String(),
        };

        final message = ChatMessage.fromFirestore(json);

        expect(message.participants, isNull);
      });

      test('toFirestore omits null senderId and conversationId', () {
        final message = ChatMessage(
          text: 'Legacy message',
          senderName: 'System',
        );

        final json = message.toFirestore();

        expect(json.containsKey('senderId'), isFalse);
        expect(json.containsKey('conversationId'), isFalse);
      });

      test('fromFirestore round-trips correctly', () {
        final original = ChatMessage(
          text: 'Round trip',
          senderName: 'Bob',
          senderId: 'bob-uid',
          conversationId: 'dm_alice-uid_bob-uid',
          timestamp: DateTime(2024, 6, 15, 14, 30),
        );

        final json = original.toFirestore();
        final restored = ChatMessage.fromFirestore(json);

        expect(restored.text, equals(original.text));
        expect(restored.senderName, equals(original.senderName));
        expect(restored.senderId, equals(original.senderId));
        expect(restored.conversationId, equals(original.conversationId));
      });

      test('fromFirestore handles missing optional fields', () {
        final json = {
          'text': 'Minimal',
          'senderName': 'Somebody',
          'timestamp': DateTime(2024, 1, 1).toIso8601String(),
        };

        final message = ChatMessage.fromFirestore(json);

        expect(message.text, equals('Minimal'));
        expect(message.senderName, equals('Somebody'));
        expect(message.senderId, isNull);
        expect(message.conversationId, isNull);
        expect(message.isBot, isFalse);
        expect(message.isLocalUser, isFalse);
      });

      test('fromFirestore parses bot messages', () {
        final json = {
          'text': 'I am bot',
          'senderName': 'Clawd',
          'senderId': 'bot-claude',
          'conversationId': 'group',
          'timestamp': DateTime(2024, 1, 1).toIso8601String(),
        };

        final message = ChatMessage.fromFirestore(json);

        expect(message.senderId, equals('bot-claude'));
      });
    });

    group('parseReplySnapshot (atomic reply parse)', () {
      test('all three valid strings -> full trio', () {
        final r = ChatMessage.parseReplySnapshot({
          'replyToMessageId': 'orig-1',
          'replyToText': 'the quote',
          'replyToSenderName': 'Alice',
        });
        expect(r.messageId, equals('orig-1'));
        expect(r.text, equals('the quote'));
        expect(r.senderName, equals('Alice'));
      });

      test('missing text -> all null (no half-reply)', () {
        final r = ChatMessage.parseReplySnapshot({
          'replyToMessageId': 'orig-1',
          'replyToSenderName': 'Alice',
          // no replyToText
        });
        expect(r.messageId, isNull);
        expect(r.text, isNull);
        expect(r.senderName, isNull);
      });

      test('wrong-typed id but valid text/name -> all null (no orphan)', () {
        final r = ChatMessage.parseReplySnapshot({
          'replyToMessageId': 123, // wrong type
          'replyToText': 'spoofed quote',
          'replyToSenderName': 'Victim',
        });
        expect(r.messageId, isNull);
        expect(r.text, isNull);
        expect(r.senderName, isNull);
      });

      test('no reply fields -> all null', () {
        final r = ChatMessage.parseReplySnapshot({'text': 'plain'});
        expect(r.messageId, isNull);
        expect(r.text, isNull);
        expect(r.senderName, isNull);
      });
    });

    group('parseMentions', () {
      test('non-list drops to empty', () {
        expect(ChatMessage.parseMentions('nope'), isEmpty);
        expect(ChatMessage.parseMentions(null), isEmpty);
        expect(ChatMessage.parseMentions(42), isEmpty);
      });

      test('keeps string elements, skips non-strings', () {
        expect(
          ChatMessage.parseMentions(['a', 1, null, 'b', true, 'c']),
          equals(['a', 'b', 'c']),
        );
      });

      test('dedupes repeated UIDs', () {
        expect(
          ChatMessage.parseMentions(['a', 'a', 'b', 'a']),
          equals(['a', 'b']),
        );
      });

      test('caps at maxMentions distinct UIDs (bounded resource at the wire)',
          () {
        final huge = List.generate(1000, (i) => 'uid-$i');
        final parsed = ChatMessage.parseMentions(huge);
        expect(parsed.length, equals(ChatMessage.maxMentions));
        // The cap keeps the FIRST distinct UIDs (insertion order preserved).
        expect(parsed.first, equals('uid-0'));
      });
    });
  });
}
