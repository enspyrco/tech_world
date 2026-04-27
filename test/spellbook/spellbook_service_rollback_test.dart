import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tech_world/spellbook/spellbook_service.dart';

// Cloud Firestore types are sealed; mocking them is a legitimate test-only
// use case that the analyzer doesn't have a more specific exemption for.
// ignore_for_file: subtype_of_sealed_class

class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockDoc extends Mock implements DocumentReference<Map<String, dynamic>> {
}

class _MockSnap extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class _FakeSetOptions extends Fake implements SetOptions {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(_FakeSetOptions());
  });

  test('learnWord rolls back local cache when Firestore write throws',
      () async {
    final collection = _MockCollection();
    final doc = _MockDoc();
    final snap = _MockSnap();

    when(() => collection.doc(any())).thenReturn(doc);
    when(() => doc.get()).thenAnswer((_) async => snap);
    when(() => snap.data()).thenReturn(null); // no prior words

    // First write throws asynchronously — simulating a Firestore RPC failure.
    // Async (rather than sync `thenThrow`) so the SpellbookService's `await`
    // actually yields, letting both optimistic-add and rollback stream
    // emissions deliver to listeners.
    when(() => doc.set(any(), any())).thenAnswer((_) async {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    });

    final service = SpellbookService(uid: 'u', collection: collection);
    await service.loadSpellbook();
    expect(service.count, 0);

    // Capture stream emissions to confirm we see add then remove.
    final events = <Set<String>>[];
    service.learnedWords.listen(events.add);

    await expectLater(
      () => service.learnWord('ignis'),
      throwsA(isA<FirebaseException>()),
    );

    // Cache rolled back to empty.
    expect(service.hasWord('ignis'), isFalse);
    expect(service.count, 0);

    // Drain the broadcast-stream microtask queue so the rollback emission
    // delivered after the rethrow lands in `events` before we assert.
    await Future<void>.delayed(Duration.zero);

    // Stream saw the optimistic add followed by the rollback.
    expect(events.length, 2);
    expect(events[0], {'ignis'});
    expect(events[1], <String>{});

    service.dispose();
  });
}
