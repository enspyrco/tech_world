import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/chat/mention_composer.dart';

void main() {
  const alice = MentionCandidate(uid: 'alice-uid', displayName: 'Alice');
  const bob = MentionCandidate(uid: 'bob-uid', displayName: 'Bob');
  const albert = MentionCandidate(uid: 'albert-uid', displayName: 'Albert');
  final all = [alice, bob, albert];

  group('activeQuery', () {
    test('detects a bare @ at end of text', () {
      final q = MentionComposer.activeQuery('hey @', 5);
      expect(q, isNotNull);
      expect(q!.query, equals(''));
      expect(q.atIndex, equals(4));
    });

    test('detects a partial @query', () {
      final q = MentionComposer.activeQuery('hey @Al', 7);
      expect(q!.query, equals('Al'));
      expect(q.atIndex, equals(4));
    });

    test('@ at the very start is valid', () {
      final q = MentionComposer.activeQuery('@bo', 3);
      expect(q!.query, equals('bo'));
      expect(q.atIndex, equals(0));
    });

    test('an @ embedded in a word (email-like) is NOT a mention', () {
      expect(MentionComposer.activeQuery('me@host', 7), isNull);
    });

    test('whitespace after @ ends the token', () {
      // Cursor is after the space — no active mention.
      expect(MentionComposer.activeQuery('@Alice ', 7), isNull);
    });

    test('cursor before the @ is not in the token', () {
      expect(MentionComposer.activeQuery('hey @Al', 2), isNull);
    });
  });

  group('filter', () {
    test('blank query returns all', () {
      expect(MentionComposer.filter(all, ''), equals(all));
    });

    test('case-insensitive substring match preserves order', () {
      final r = MentionComposer.filter(all, 'al');
      expect(r.map((c) => c.uid), equals(['alice-uid', 'albert-uid']));
    });

    test('no match returns empty', () {
      expect(MentionComposer.filter(all, 'zzz'), isEmpty);
    });
  });

  group('insert', () {
    test('replaces the @query token with @Name and a trailing space', () {
      final ins = MentionComposer.insert(
        text: 'hey @Al',
        atIndex: 4,
        cursor: 7,
        chosen: alice,
      );
      expect(ins.text, equals('hey @Alice '));
      expect(ins.cursor, equals('hey @Alice '.length));
      expect(ins.uid, equals('alice-uid'));
    });

    test('preserves text after the cursor', () {
      final ins = MentionComposer.insert(
        text: 'hey @Al you there',
        atIndex: 4,
        cursor: 7,
        chosen: alice,
      );
      expect(ins.text, equals('hey @Alice  you there'));
    });
  });

  group('survivingUids', () {
    test('keeps a UID whose @Name token is still in the text', () {
      expect(
        MentionComposer.survivingUids('hi @Alice and @Bob', [alice, bob]),
        equals(['alice-uid', 'bob-uid']),
      );
    });

    test('drops a UID whose @Name token was deleted', () {
      expect(
        MentionComposer.survivingUids('hi @Bob', [alice, bob]),
        equals(['bob-uid']),
      );
    });

    test('does not match @Name as a substring of a longer token', () {
      // @Alice picked, but text only has @AliceXYZ → not a real mention.
      expect(
        MentionComposer.survivingUids('hi @AliceXYZ', [alice]),
        isEmpty,
      );
    });

    test('dedupes repeated picks of the same UID', () {
      expect(
        MentionComposer.survivingUids('hi @Bob @Bob', [bob, bob]),
        equals(['bob-uid']),
      );
    });
  });
}
