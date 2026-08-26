import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tech_world/flame/dreamfinder_proximity_signal.dart';
import 'package:tech_world/livekit/livekit_service.dart';

class MockLiveKitService extends Mock implements LiveKitService {}

void main() {
  // Unlike the other extracted concerns this one already had coverage, driven
  // through BubbleManager's debugUpdateDreamfinderProximity seam: hysteresis,
  // null-distance exit, and null-service-does-not-latch are all pinned there
  // and were left untouched by the extraction.
  //
  // What NO test reached is reset() — the teardown exit that stops Dreamfinder
  // holding a stale `near: true` for a player who has left the room. That is
  // what this file is for.

  late MockLiveKitService service;

  DreamfinderProximitySignal build({
    int enable = 4,
    int disable = 5,
    LiveKitService? Function()? liveKit,
  }) =>
      DreamfinderProximitySignal(
        enableThreshold: () => enable,
        disableThreshold: () => disable,
        liveKitService: liveKit ?? () => service,
      );

  setUp(() {
    service = MockLiveKitService();
    when(() => service.publishDfProximity(near: any(named: 'near')))
        .thenAnswer((_) async {});
  });

  group('reset — the teardown exit', () {
    test('publishes a final exit when the player was near', () {
      final signal = build()..update(0);
      expect(signal.isNear, isTrue);

      signal.reset();

      verify(() => service.publishDfProximity(near: false)).called(1);
      expect(signal.isNear, isFalse);
    });

    test('publishes NOTHING when the player was not near', () {
      final signal = build();
      expect(signal.isNear, isFalse);

      signal.reset();

      verifyNever(() => service.publishDfProximity(near: any(named: 'near')));
    });

    test('is idempotent — a second reset does not re-emit', () {
      final signal = build()..update(0);

      signal.reset();
      signal.reset();

      verify(() => service.publishDfProximity(near: false)).called(1);
    });

    test('clears the local flag even with no service to publish through', () {
      // Unlike update(), reset() MUST clear regardless: after teardown there is
      // no session left for a retry to belong to, so holding `near` would make
      // the next room start from a stale state.
      LiveKitService? current = service;
      final signal = build(liveKit: () => current)..update(0);
      expect(signal.isNear, isTrue);

      current = null;
      signal.reset();

      expect(signal.isNear, isFalse);
    });

    test('a reset signal re-enters cleanly on the next room', () {
      final signal = build()
        ..update(0)
        ..reset();
      clearInteractions(service);

      signal.update(0);

      verify(() => service.publishDfProximity(near: true)).called(1);
    });
  });

  group('the hysteresis band is a band', () {
    test('inside the band, an entered signal does NOT exit yet', () {
      // This is the assertion the pre-existing coverage was missing. Walking
      // 4 -> 5 -> 6 and counting "one enter, one exit" stays green even with
      // both branches collapsed onto the enable threshold, because the exit
      // simply happens one square early and the COUNT is unchanged. Verified:
      // collapsing the pair left the whole suite green until this test existed.
      final signal = build(enable: 4, disable: 5)..update(4);
      verify(() => service.publishDfProximity(near: true)).called(1);

      signal.update(5); // > enable(4), but <= disable(5): hold.

      verifyNever(() => service.publishDfProximity(near: false));
      expect(signal.isNear, isTrue);
    });

    test('past the disable threshold it finally exits', () {
      final signal = build(enable: 4, disable: 5)
        ..update(4)
        ..update(5);

      signal.update(6);

      verify(() => service.publishDfProximity(near: false)).called(1);
      expect(signal.isNear, isFalse);
    });

    test('entry needs the TIGHTER threshold — the band does not let you in',
        () {
      // Symmetric to the hold above: sitting in the band from outside must not
      // enter. Collapsing the pair the other way (both on disable) breaks this.
      final signal = build(enable: 4, disable: 5)..update(5);

      verifyNever(() => service.publishDfProximity(near: any(named: 'near')));
      expect(signal.isNear, isFalse);
    });
  });

  group('thresholds are read live, not captured', () {
    test('a radius applied at room entry moves the gate', () {
      // Thresholds are functions because the underlying radius is a user
      // preference applied before each room entry.
      var enable = 4;
      var disable = 5;
      final signal = DreamfinderProximitySignal(
        enableThreshold: () => enable,
        disableThreshold: () => disable,
        liveKitService: () => service,
      );

      signal.update(8);
      expect(signal.isNear, isFalse, reason: '8 is outside enable(4)');

      enable = 10;
      disable = 11;
      signal.update(8);

      expect(signal.isNear, isTrue, reason: '8 is inside the widened enable');
    });
  });
}
