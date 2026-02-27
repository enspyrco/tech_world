import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/livekit/livekit_service.dart';

void main() {
  group('LiveKitService screen share', () {
    late LiveKitService service;

    setUp(() {
      service = LiveKitService(
        userId: 'test-user',
        displayName: 'Test',
      );
    });

    tearDown(() {
      service.dispose();
    });

    group('trackUnsubscribed stream', () {
      test('is available', () {
        expect(service.trackUnsubscribed, isA<Stream>());
      });

      test('is a broadcast stream (multiple listeners allowed)', () {
        // Should not throw when adding multiple listeners.
        final sub1 = service.trackUnsubscribed.listen((_) {});
        final sub2 = service.trackUnsubscribed.listen((_) {});
        addTearDown(() {
          sub1.cancel();
          sub2.cancel();
        });
      });
    });

    group('setScreenShareEnabled', () {
      test('returns early without throwing when not connected', () async {
        // Room is null, so this should be a no-op.
        await service.setScreenShareEnabled(true);
        await service.setScreenShareEnabled(false);
      });
    });

    group('isScreenShareEnabled', () {
      test('returns false when not connected', () {
        expect(service.isScreenShareEnabled, isFalse);
      });
    });

    group('dispose', () {
      test('closes trackUnsubscribed stream', () async {
        service.dispose();

        // After dispose, listening should indicate the stream is done.
        final events = <dynamic>[];
        service.trackUnsubscribed.listen(
          events.add,
          onDone: () => events.add('done'),
        );
        // Allow microtask to process.
        await Future.delayed(Duration.zero);
        expect(events, contains('done'));
      });
    });
  });
}
