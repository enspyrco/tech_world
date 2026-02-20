import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/progress/progress_service.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
  });

  ProgressService createService({String uid = 'test-user'}) {
    return ProgressService(
      uid: uid,
      collection: fakeFirestore.collection('users'),
    );
  }

  group('ProgressService', () {
    test('loads empty progress when no Firestore document exists', () async {
      final service = createService();
      await service.loadProgress();

      expect(service.isChallengeCompleted('hello_dart'), isFalse);
      expect(service.completedCount, 0);
    });

    test('loads existing completed challenges from Firestore', () async {
      // Pre-populate Firestore with completed challenges.
      await fakeFirestore.collection('users').doc('test-user').set({
        'completedChallenges': ['hello_dart', 'fizzbuzz'],
      });

      final service = createService();
      await service.loadProgress();

      expect(service.isChallengeCompleted('hello_dart'), isTrue);
      expect(service.isChallengeCompleted('fizzbuzz'), isTrue);
      expect(service.isChallengeCompleted('binary_search'), isFalse);
      expect(service.completedCount, 2);
    });

    test('markChallengeCompleted updates local cache and Firestore', () async {
      final service = createService();
      await service.loadProgress();

      await service.markChallengeCompleted('hello_dart');

      // Local cache updated.
      expect(service.isChallengeCompleted('hello_dart'), isTrue);
      expect(service.completedCount, 1);

      // Firestore updated.
      final doc =
          await fakeFirestore.collection('users').doc('test-user').get();
      expect(doc.data()?['completedChallenges'], contains('hello_dart'));
    });

    test('markChallengeCompleted is idempotent', () async {
      final service = createService();
      await service.loadProgress();

      await service.markChallengeCompleted('hello_dart');
      await service.markChallengeCompleted('hello_dart');

      expect(service.completedCount, 1);

      // Firestore array should not have duplicates.
      final doc =
          await fakeFirestore.collection('users').doc('test-user').get();
      final challenges =
          List<String>.from(doc.data()?['completedChallenges'] ?? []);
      expect(
        challenges.where((c) => c == 'hello_dart').length,
        1,
      );
    });

    test('completedChallenges stream emits on changes', () async {
      final service = createService();
      await service.loadProgress();

      // Collect stream events.
      final events = <Set<String>>[];
      service.completedChallenges.listen(events.add);

      await service.markChallengeCompleted('hello_dart');
      await service.markChallengeCompleted('fizzbuzz');

      // Stream should have emitted after each mark.
      expect(events.length, 2);
      expect(events[0], {'hello_dart'});
      expect(events[1], {'hello_dart', 'fizzbuzz'});
    });

    test('dispose closes the stream', () async {
      final service = createService();
      await service.loadProgress();

      service.dispose();

      // Stream should be done after dispose.
      expect(
        service.completedChallenges,
        emitsDone,
      );
    });

    test('separate users have independent progress', () async {
      await fakeFirestore.collection('users').doc('user-a').set({
        'completedChallenges': ['hello_dart'],
      });

      final serviceA = ProgressService(
        uid: 'user-a',
        collection: fakeFirestore.collection('users'),
      );
      final serviceB = ProgressService(
        uid: 'user-b',
        collection: fakeFirestore.collection('users'),
      );

      await serviceA.loadProgress();
      await serviceB.loadProgress();

      expect(serviceA.isChallengeCompleted('hello_dart'), isTrue);
      expect(serviceB.isChallengeCompleted('hello_dart'), isFalse);

      serviceA.dispose();
      serviceB.dispose();
    });
  });
}
