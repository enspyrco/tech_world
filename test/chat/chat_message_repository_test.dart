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

    group('loadMessagePage', () {
      /// Add [count] group messages with increasing timestamps ("Message 0"
      /// oldest → "Message N-1" newest).
      Future<void> seedGroup(int count) async {
        final messagesRef = fakeFirestore
            .collection('rooms')
            .doc('room-1')
            .collection('messages');
        for (var i = 0; i < count; i++) {
          await messagesRef.add({
            'text': 'Message $i',
            'senderName': 'User',
            'senderId': 'user-uid',
            'conversationId': 'group',
            'timestamp': DateTime(2024, 6, 15, 10, i).toIso8601String(),
          });
        }
      }

      test('returns messages for a specific conversationId, ascending in page',
          () async {
        final messagesRef = fakeFirestore
            .collection('rooms')
            .doc('room-1')
            .collection('messages');

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
        // A DM must NOT appear in the group query.
        await messagesRef.add({
          'text': 'Private DM',
          'senderName': 'Alice',
          'senderId': 'alice-uid',
          'conversationId': 'dm_alice-uid_bob-uid',
          'timestamp': DateTime(2024, 6, 15, 10, 2).toIso8601String(),
        });

        final page = await repository.loadMessagePage('room-1', 'group');

        // Newest-first query, but the page is returned ASCENDING.
        expect(page.messages.map((m) => m.text),
            equals(['Group message 1', 'Group message 2']));
        // Both fit under the default limit → no older page.
        expect(page.hasMore, isFalse);
        expect(page.cursor, isNull);
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

        final page = await repository.loadMessagePage(
          'room-1',
          'dm_alice-uid_bob-uid',
        );

        expect(page.messages.length, equals(1));
        expect(page.messages.first.text, equals('Hey Bob'));
      });

      test('the newest page returns the NEWEST `limit` messages, ascending',
          () async {
        await seedGroup(5); // Message 0 (oldest) .. Message 4 (newest)

        final page =
            await repository.loadMessagePage('room-1', 'group', limit: 3);

        // Newest 3 (Message 2,3,4), ascending within the page.
        expect(page.messages.map((m) => m.text),
            equals(['Message 2', 'Message 3', 'Message 4']));
        // Filled to the limit → an older page may exist.
        expect(page.hasMore, isTrue);
        expect(page.cursor, isNotNull);
      });

      test('the cursor pages BACKWARD to older messages with no overlap',
          () async {
        await seedGroup(5);

        final first =
            await repository.loadMessagePage('room-1', 'group', limit: 3);
        expect(first.messages.map((m) => m.text),
            equals(['Message 2', 'Message 3', 'Message 4']));

        final older = await repository.loadMessagePage(
          'room-1',
          'group',
          after: first.cursor,
          limit: 3,
        );

        // The remaining 2 older messages, ascending, no overlap with page 1.
        expect(older.messages.map((m) => m.text),
            equals(['Message 0', 'Message 1']));
        // Short page → history exhausted, no further cursor.
        expect(older.hasMore, isFalse);
        expect(older.cursor, isNull);
      });

      test('an exactly-one-full-page conversation exhausts on the next fetch',
          () async {
        await seedGroup(3); // exactly limit

        final first =
            await repository.loadMessagePage('room-1', 'group', limit: 3);
        expect(first.messages.length, equals(3));
        // Exactly `limit` → hasMore true (we can't tell it's the last page yet).
        expect(first.hasMore, isTrue);
        expect(first.cursor, isNotNull);

        // The next fetch comes back empty → exhausted, latch.
        final next = await repository.loadMessagePage(
          'room-1',
          'group',
          after: first.cursor,
          limit: 3,
        );
        expect(next.messages, isEmpty);
        expect(next.hasMore, isFalse);
        expect(next.cursor, isNull);
      });

      test('returns an empty exhausted page when no messages exist', () async {
        final page = await repository.loadMessagePage('room-1', 'group');

        expect(page.messages, isEmpty);
        expect(page.hasMore, isFalse);
        expect(page.cursor, isNull);
      });

      test('rejects a foreign cursor with a named ArgumentError', () async {
        // Cage-match round 1, Carnot Med: a cursor not minted by THIS repository
        // (e.g. a fake's MessageCursor) must fail with a clear contract error,
        // not a confusing internal cast failure.
        expect(
          () => repository.loadMessagePage('room-1', 'group',
              after: const _ForeignCursor()),
          throwsArgumentError,
        );
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

/// A [MessageCursor] not produced by [ChatMessageRepository] — used to prove
/// `loadMessagePage` rejects a foreign cursor rather than casting it blindly.
class _ForeignCursor extends MessageCursor {
  const _ForeignCursor();
}
