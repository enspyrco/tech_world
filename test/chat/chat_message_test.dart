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
  });
}
