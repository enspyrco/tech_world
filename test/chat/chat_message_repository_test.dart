import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/chat/chat_message.dart';
import 'package:tech_world/chat/chat_message_repository.dart';

void main() {
  group('ChatMessageRepository', () {
    late FakeFirebaseFirestore fakeFirestore;
    late ChatMessageRepository repository;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      repository = ChatMessageRepository(firestore: fakeFirestore);
    });

    group('saveMessage', () {
      test('writes message to Firestore subcollection', () async {
        final message = ChatMessage(
          text: 'Hello group!',
          senderName: 'Alice',
          senderId: 'alice-uid',
          conversationId: 'group',
          timestamp: DateTime(2024, 6, 15),
        );

        await repository.saveMessage('room-1', message);

        final snapshot = await fakeFirestore
            .collection('rooms')
            .doc('room-1')
            .collection('messages')
            .get();
        expect(snapshot.docs.length, equals(1));
        expect(snapshot.docs.first.data()['text'], equals('Hello group!'));
        expect(snapshot.docs.first.data()['senderId'], equals('alice-uid'));
        expect(
            snapshot.docs.first.data()['conversationId'], equals('group'));
      });

      test('writes DM message with correct conversationId', () async {
        final message = ChatMessage(
          text: 'Hey Bob',
          senderName: 'Alice',
          senderId: 'alice-uid',
          conversationId: 'dm_alice-uid_bob-uid',
          participants: ['alice-uid', 'bob-uid'],
          timestamp: DateTime(2024, 6, 15),
        );

        await repository.saveMessage('room-1', message);

        final snapshot = await fakeFirestore
            .collection('rooms')
            .doc('room-1')
            .collection('messages')
            .get();
        expect(snapshot.docs.first.data()['conversationId'],
            equals('dm_alice-uid_bob-uid'));
        expect(snapshot.docs.first.data()['participants'],
            equals(['alice-uid', 'bob-uid']));
      });
    });

    group('saveConversation', () {
      test('creates conversation metadata document', () async {
        await repository.saveConversation(
          'room-1',
          conversationId: 'dm_alice-uid_bob-uid',
          participants: ['alice-uid', 'bob-uid'],
          type: 'dm',
          lastMessageText: 'Hey Bob',
        );

        final doc = await fakeFirestore
            .collection('rooms')
            .doc('room-1')
            .collection('conversations')
            .doc('dm_alice-uid_bob-uid')
            .get();

        expect(doc.exists, isTrue);
        expect(doc.data()!['participants'], equals(['alice-uid', 'bob-uid']));
        expect(doc.data()!['type'], equals('dm'));
        expect(doc.data()!['lastMessageText'], equals('Hey Bob'));
      });

      test('upserts on repeated calls (merge)', () async {
        await repository.saveConversation(
          'room-1',
          conversationId: 'dm_alice-uid_bob-uid',
          participants: ['alice-uid', 'bob-uid'],
          type: 'dm',
          lastMessageText: 'First message',
        );

        await repository.saveConversation(
          'room-1',
          conversationId: 'dm_alice-uid_bob-uid',
          participants: ['alice-uid', 'bob-uid'],
          type: 'dm',
          lastMessageText: 'Second message',
        );

        final doc = await fakeFirestore
            .collection('rooms')
            .doc('room-1')
            .collection('conversations')
            .doc('dm_alice-uid_bob-uid')
            .get();

        expect(doc.data()!['lastMessageText'], equals('Second message'));
      });

      test('omits lastMessageText when null', () async {
        await repository.saveConversation(
          'room-1',
          conversationId: 'dm_alice-uid_bob-uid',
          participants: ['alice-uid', 'bob-uid'],
          type: 'dm',
        );

        final doc = await fakeFirestore
            .collection('rooms')
            .doc('room-1')
            .collection('conversations')
            .doc('dm_alice-uid_bob-uid')
            .get();

        expect(doc.data()!.containsKey('lastMessageText'), isFalse);
      });
    });

    group('loadMessages', () {
      test('returns messages for a specific conversationId', () async {
        final messagesRef = fakeFirestore
            .collection('rooms')
            .doc('room-1')
            .collection('messages');

        // Add group messages
        await messagesRef.add({
          'text': 'Group message 1',
          'senderName': 'Alice',
          'senderId': 'alice-uid',
          'conversationId': 'group',
          'timestamp': DateTime(2024, 6, 15, 10, 0).toIso8601String(),
        });
        await messagesRef.add({
          'text': 'Group message 2',
          'senderName': 'Bob',
          'senderId': 'bob-uid',
          'conversationId': 'group',
          'timestamp': DateTime(2024, 6, 15, 10, 1).toIso8601String(),
        });
        // Add a DM (should not appear in group query)
        await messagesRef.add({
          'text': 'Private DM',
          'senderName': 'Alice',
          'senderId': 'alice-uid',
          'conversationId': 'dm_alice-uid_bob-uid',
          'timestamp': DateTime(2024, 6, 15, 10, 2).toIso8601String(),
        });

        final messages =
            await repository.loadMessages('room-1', 'group');

        expect(messages.length, equals(2));
        expect(messages[0].text, equals('Group message 1'));
        expect(messages[1].text, equals('Group message 2'));
      });

      test('returns DM messages filtered by conversationId', () async {
        final messagesRef = fakeFirestore
            .collection('rooms')
            .doc('room-1')
            .collection('messages');

        await messagesRef.add({
          'text': 'Group chat',
          'senderName': 'Alice',
          'senderId': 'alice-uid',
          'conversationId': 'group',
          'timestamp': DateTime(2024, 6, 15, 10, 0).toIso8601String(),
        });
        await messagesRef.add({
          'text': 'Hey Bob',
          'senderName': 'Alice',
          'senderId': 'alice-uid',
          'conversationId': 'dm_alice-uid_bob-uid',
          'timestamp': DateTime(2024, 6, 15, 10, 1).toIso8601String(),
        });

        final messages = await repository.loadMessages(
          'room-1',
          'dm_alice-uid_bob-uid',
        );

        expect(messages.length, equals(1));
        expect(messages.first.text, equals('Hey Bob'));
      });

      test('respects limit parameter', () async {
        final messagesRef = fakeFirestore
            .collection('rooms')
            .doc('room-1')
            .collection('messages');

        for (var i = 0; i < 5; i++) {
          await messagesRef.add({
            'text': 'Message $i',
            'senderName': 'User',
            'senderId': 'user-uid',
            'conversationId': 'group',
            'timestamp':
                DateTime(2024, 6, 15, 10, i).toIso8601String(),
          });
        }

        final messages =
            await repository.loadMessages('room-1', 'group', limit: 3);

        expect(messages.length, equals(3));
      });

      test('returns empty list when no messages exist', () async {
        final messages =
            await repository.loadMessages('room-1', 'group');

        expect(messages, isEmpty);
      });
    });

    group('loadConversationIds', () {
      test('returns group plus DM conversation IDs from subcollection',
          () async {
        final convsRef = fakeFirestore
            .collection('rooms')
            .doc('room-1')
            .collection('conversations');

        // Alice's DM with Bob
        await convsRef.doc('dm_alice-uid_bob-uid').set({
          'participants': ['alice-uid', 'bob-uid'],
          'type': 'dm',
        });
        // Bob's DM with Charlie — Alice is not a participant
        await convsRef.doc('dm_bob-uid_charlie-uid').set({
          'participants': ['bob-uid', 'charlie-uid'],
          'type': 'dm',
        });

        final ids =
            await repository.loadConversationIds('room-1', 'alice-uid');

        expect(ids, contains('group'));
        expect(ids, contains('dm_alice-uid_bob-uid'));
        expect(ids, isNot(contains('dm_bob-uid_charlie-uid')));
      });

      test('always includes group even with no conversations', () async {
        final ids =
            await repository.loadConversationIds('room-1', 'alice-uid');

        expect(ids, equals({'group'}));
      });

      test('returns multiple DM conversations for same user', () async {
        final convsRef = fakeFirestore
            .collection('rooms')
            .doc('room-1')
            .collection('conversations');

        await convsRef.doc('dm_alice-uid_bob-uid').set({
          'participants': ['alice-uid', 'bob-uid'],
          'type': 'dm',
        });
        await convsRef.doc('dm_alice-uid_charlie-uid').set({
          'participants': ['alice-uid', 'charlie-uid'],
          'type': 'dm',
        });

        final ids =
            await repository.loadConversationIds('room-1', 'alice-uid');

        expect(ids, contains('group'));
        expect(ids, contains('dm_alice-uid_bob-uid'));
        expect(ids, contains('dm_alice-uid_charlie-uid'));
        expect(ids.length, equals(3));
      });
    });
  });
}
