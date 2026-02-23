import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/chat/conversation.dart';

void main() {
  group('ConversationType', () {
    test('has group and dm values', () {
      expect(ConversationType.values, containsAll([
        ConversationType.group,
        ConversationType.dm,
      ]));
    });
  });

  group('Conversation', () {
    test('creates group conversation', () {
      final conversation = Conversation(
        id: 'group',
        type: ConversationType.group,
      );

      expect(conversation.id, equals('group'));
      expect(conversation.type, equals(ConversationType.group));
      expect(conversation.peerId, isNull);
      expect(conversation.peerDisplayName, isNull);
      expect(conversation.unreadCount, equals(0));
      expect(conversation.lastActivity, isNull);
    });

    test('creates DM conversation', () {
      final now = DateTime.now();
      final conversation = Conversation(
        id: 'dm_alice_bob',
        type: ConversationType.dm,
        peerId: 'alice-uid',
        peerDisplayName: 'Alice',
        unreadCount: 3,
        lastActivity: now,
      );

      expect(conversation.id, equals('dm_alice_bob'));
      expect(conversation.type, equals(ConversationType.dm));
      expect(conversation.peerId, equals('alice-uid'));
      expect(conversation.peerDisplayName, equals('Alice'));
      expect(conversation.unreadCount, equals(3));
      expect(conversation.lastActivity, equals(now));
    });
  });

  group('Conversation.copyWith', () {
    test('returns copy with updated fields', () {
      final now = DateTime.now();
      final original = Conversation(
        id: 'dm_a_b',
        type: ConversationType.dm,
        peerId: 'a',
        peerDisplayName: 'Alice',
        unreadCount: 2,
        lastActivity: now,
      );

      final later = now.add(const Duration(minutes: 5));
      final updated = original.copyWith(
        unreadCount: 3,
        lastActivity: later,
      );

      expect(updated.id, equals('dm_a_b'));
      expect(updated.type, equals(ConversationType.dm));
      expect(updated.peerId, equals('a'));
      expect(updated.peerDisplayName, equals('Alice'));
      expect(updated.unreadCount, equals(3));
      expect(updated.lastActivity, equals(later));
    });

    test('preserves all fields when no arguments given', () {
      final now = DateTime.now();
      final original = Conversation(
        id: 'dm_a_b',
        type: ConversationType.dm,
        peerId: 'a',
        peerDisplayName: 'Alice',
        unreadCount: 5,
        lastActivity: now,
      );

      final copy = original.copyWith();

      expect(copy.id, equals(original.id));
      expect(copy.type, equals(original.type));
      expect(copy.peerId, equals(original.peerId));
      expect(copy.peerDisplayName, equals(original.peerDisplayName));
      expect(copy.unreadCount, equals(original.unreadCount));
      expect(copy.lastActivity, equals(original.lastActivity));
    });

    test('can update peerDisplayName', () {
      final original = Conversation(
        id: 'dm_a_b',
        type: ConversationType.dm,
        peerId: 'a',
        peerDisplayName: 'Old Name',
      );

      final updated = original.copyWith(peerDisplayName: 'New Name');

      expect(updated.peerDisplayName, equals('New Name'));
      expect(updated.peerId, equals('a'));
    });
  });

  group('Conversation.conversationIdFor', () {
    test('sorts UIDs alphabetically and joins with underscore', () {
      final id = Conversation.conversationIdFor('bob-uid', 'alice-uid');
      expect(id, equals('dm_alice-uid_bob-uid'));
    });

    test('produces same ID regardless of argument order', () {
      final id1 = Conversation.conversationIdFor('user-a', 'user-b');
      final id2 = Conversation.conversationIdFor('user-b', 'user-a');
      expect(id1, equals(id2));
    });

    test('handles same UID twice (self-DM edge case)', () {
      final id = Conversation.conversationIdFor('same-uid', 'same-uid');
      expect(id, equals('dm_same-uid_same-uid'));
    });

    test('handles UIDs with special characters', () {
      final id = Conversation.conversationIdFor(
        'abc123XYZ',
        '789defGHI',
      );
      // '789defGHI' < 'abc123XYZ' lexicographically
      expect(id, equals('dm_789defGHI_abc123XYZ'));
    });
  });
}
