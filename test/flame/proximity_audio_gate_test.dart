import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tech_world/flame/proximity_audio_gate.dart';
import 'package:tech_world/livekit/livekit_service.dart';

class MockLiveKitService extends Mock implements LiveKitService {}

void main() {
  // The enable/disable hysteresis is already covered end-to-end through
  // BubbleManager (bubble_manager_proximity_radius_test.dart). What was NOT
  // reachable from a test, and is the reason this gate is delicate, is the
  // SEND-CONFIRMED latching: gate state must only advance when the effect
  // actually landed. That is PR #481's signal-lost-forever fix, and it is what
  // this file pins.

  late MockLiveKitService service;
  late ValueNotifier<bool> silenced;

  ProximityAudioGate build({
    int radius = 5,
    LiveKitService? Function()? liveKit,
    String dfIdentity = 'bot-dreamfinder',
  }) =>
      ProximityAudioGate(
        proximityRadius: () => radius,
        liveKitService: liveKit ?? () => service,
        diagnosticsEnabled: () => false,
        dreamfinderIdentity: () => dfIdentity,
      );

  setUp(() {
    service = MockLiveKitService();
    silenced = ValueNotifier<bool>(false);
    when(() => service.dreamfinderSilenced).thenReturn(silenced);
    when(() => service.dreamfinderIdentities()).thenReturn(<String>{});
    when(() => service.setParticipantAudioEnabled(any(), any()))
        .thenReturn(true);
    when(() => service.setParticipantAudioVolume(any(), any()))
        .thenReturn(true);
  });

  group('send-confirmed latching', () {
    test('a null service does not latch the gate — the transition re-fires',
        () {
      LiveKitService? current;
      final gate = build(liveKit: () => current);

      // In range, but nothing to send to.
      gate.update('peer', 0);
      expect(gate.isEnabled('peer'), isFalse,
          reason: 'latching without sending is the lost-signal bug');

      // Service arrives. The SAME distance must now take effect.
      current = service;
      gate.update('peer', 0);

      expect(gate.isEnabled('peer'), isTrue);
      verify(() => service.setParticipantAudioEnabled('peer', true)).called(1);
    });

    test('a volume write that does not land is retried next frame', () {
      // The track has not subscribed yet, so the volume call no-ops. Caching
      // it anyway would suppress the retry and strand the late track at
      // default volume.
      when(() => service.setParticipantAudioVolume(any(), any()))
          .thenReturn(false);
      final gate = build();

      gate.update('peer', 3);
      gate.update('peer', 3);
      gate.update('peer', 3);

      verify(() => service.setParticipantAudioVolume('peer', any()))
          .called(3);
    });

    test('a volume write that lands is cached, not rewritten every frame', () {
      final gate = build();

      gate.update('peer', 3);
      gate.update('peer', 3);
      gate.update('peer', 3);

      // Once for the landed write; the identical value is not re-sent.
      verify(() => service.setParticipantAudioVolume('peer', any()))
          .called(1);
    });
  });

  group('the hysteresis pair is a pair, not a threshold', () {
    test('enable is one square tighter than disable', () {
      final gate = build(radius: 5);
      expect(gate.enableThreshold, equals(4));
      expect(gate.disableThreshold, equals(5));
    });

    test('inside the band, state is HELD rather than recomputed', () {
      final gate = build(radius: 5);

      // Not yet enabled, sitting in the band (5 > enable 4, <= disable 5):
      // must not enable.
      gate.update('peer', 5);
      expect(gate.isEnabled('peer'), isFalse);

      // Come inside the enable threshold.
      gate.update('peer', 4);
      expect(gate.isEnabled('peer'), isTrue);

      // Back into the band: must HOLD enabled, not drop.
      gate.update('peer', 5);
      expect(gate.isEnabled('peer'), isTrue,
          reason: 'collapsing the pair makes a boundary-hovering peer flap');

      // Past disable: now it drops.
      gate.update('peer', 6);
      expect(gate.isEnabled('peer'), isFalse);
    });

    test('radius 0 enables nobody, including a co-located peer', () {
      final gate = build(radius: 0);
      expect(gate.enableThreshold, equals(-1));

      gate.update('peer', 0);

      expect(gate.isEnabled('peer'), isFalse);
      verifyNever(() => service.setParticipantAudioEnabled(any(), true));
    });
  });

  group('volume ramp', () {
    test('full volume at and within the full-volume distance', () {
      final gate = build(radius: 5);
      expect(gate.volumeForDistance(0), equals(1.0));
      expect(gate.volumeForDistance(ProximityAudioGate.fullVolumeDistance),
          equals(1.0));
    });

    test('steps down monotonically to silence at the disable threshold', () {
      final gate = build(radius: 5);
      final ramp = [for (var d = 1; d <= 5; d++) gate.volumeForDistance(d)];

      expect(ramp.first, equals(1.0));
      expect(ramp.last, equals(0.0));
      for (var i = 1; i < ramp.length; i++) {
        expect(ramp[i], lessThan(ramp[i - 1]), reason: 'ramp at distance $i');
      }
    });

    test('a radius that collapses the ramp does not divide by zero', () {
      final gate = build(radius: 1);
      expect(gate.volumeForDistance(1), equals(1.0));
      expect(() => gate.volumeForDistance(5), returnsNormally);
    });
  });

  group('Dreamfinder', () {
    test('gates every DF identity in the room, not just the bound one', () {
      // Agent respawns mean several `agent-*` identities can coexist; any one
      // outside the gate is ungoverned audio.
      when(() => service.dreamfinderIdentities())
          .thenReturn({'agent-abc', 'agent-def'});
      final gate = build();

      gate.updateDreamfinder(0);

      for (final id in ['bot-dreamfinder', 'agent-abc', 'agent-def']) {
        expect(gate.isEnabled(id), isTrue, reason: id);
      }
    });

    test('silencing feeds "infinitely far" through the same gate', () {
      final gate = build();
      gate.updateDreamfinder(0);
      expect(gate.isEnabled('bot-dreamfinder'), isTrue);

      silenced.value = true;
      gate.updateDreamfinder(0);

      expect(gate.isEnabled('bot-dreamfinder'), isFalse);
    });

    test('silencing also hard-mutes locally, not just server-side', () {
      // If the server-side disable is ineffective, nothing else writes volume
      // for a gate-DISABLED participant, so audio would keep playing at its
      // last value forever. Half of the 2026-07-18 silence failure.
      silenced.value = true;
      build().updateDreamfinder(0);

      verify(() => service.setParticipantAudioVolume('bot-dreamfinder', 0.0))
          .called(greaterThanOrEqualTo(1));
    });
  });

  group('bookkeeping', () {
    test('forget drops a vanished participant', () {
      final gate = build()..update('peer', 0);
      expect(gate.isEnabled('peer'), isTrue);

      gate.forget('peer');

      expect(gate.isEnabled('peer'), isFalse);
    });

    test('clear drops everyone', () {
      final gate = build()
        ..update('a', 0)
        ..update('b', 0);

      gate.clear();

      expect(gate.isEnabled('a'), isFalse);
      expect(gate.isEnabled('b'), isFalse);
    });
  });

  group('the gate latches only on a CONFIRMED effect (cage-match #530, Carnot)',
      () {
    // A peer whose audio track has not subscribed yet is absent from
    // remoteParticipants, so setParticipantAudioEnabled lands on nothing. It
    // used to return void, so the gate latched anyway — and every later frame
    // then saw hasAudio == true, skipped the enable, and left that peer muted
    // for the rest of the session while diagnostics reported it enabled.

    test('an enable that does not land is NOT latched, and retries', () {
      final gate = build(radius: 5);
      when(() => service.setParticipantAudioEnabled(any(), any()))
          .thenReturn(false); // participant not subscribed yet

      gate.update('peer', 1);
      expect(gate.isEnabled('peer'), isFalse,
          reason: 'nothing was enabled, so the gate must not claim it was');

      // The track subscribes; the next frame must try AGAIN.
      when(() => service.setParticipantAudioEnabled(any(), any()))
          .thenReturn(true);
      gate.update('peer', 1);
      expect(gate.isEnabled('peer'), isTrue);
    });

    test('a disable that does not land is NOT latched, and retries', () {
      final gate = build(radius: 5);
      gate.update('peer', 1);
      expect(gate.isEnabled('peer'), isTrue);

      when(() => service.setParticipantAudioEnabled(any(), any()))
          .thenReturn(false);
      gate.update('peer', 9); // past disable threshold
      expect(gate.isEnabled('peer'), isTrue,
          reason: 'the peer is still audible — the gate must not report a '
              'cut it could not make');

      when(() => service.setParticipantAudioEnabled(any(), any()))
          .thenReturn(true);
      gate.update('peer', 9);
      expect(gate.isEnabled('peer'), isFalse);
    });

    test('NULL ARM: a landing enable latches exactly once', () {
      final gate = build(radius: 5);
      gate.update('peer', 1);
      gate.update('peer', 1);
      expect(gate.isEnabled('peer'), isTrue);
      verify(() => service.setParticipantAudioEnabled('peer', true)).called(1);
    });
  });

  group('radius 0 closes BOTH ways (cage-match #530, Tesla)', () {
    // The old radius-0 proof was one-sided. enableThreshold becomes -1, which
    // no distance satisfies, so nobody can be STRUCK — but the disable arm is
    // `distance > disableThreshold`, and at radius 0 that threshold is 0, so a
    // co-located peer at distance 0 is not greater than 0 and could never be
    // RELEASED. Only "the preference is applied before room entry" kept that
    // unreachable, while the field is read live every frame. That was a
    // property of the caller, not of the gate.

    test('an enabled co-located peer IS released when radius drops to 0', () {
      var radius = 5;
      final gate = ProximityAudioGate(
        proximityRadius: () => radius,
        liveKitService: () => service,
        diagnosticsEnabled: () => false,
        dreamfinderIdentity: () => 'bot-dreamfinder',
      );

      gate.update('peer', 0); // co-located, well inside enable
      expect(gate.isEnabled('peer'), isTrue);

      radius = 0; // "proximity off"
      gate.update('peer', 0);
      expect(gate.isEnabled('peer'), isFalse,
          reason: 'proximity off must mean silent, from BOTH directions');
      verify(() => service.setParticipantAudioEnabled('peer', false))
          .called(1);
    });

    test('NULL ARM: a non-zero radius still uses the hysteresis band', () {
      // The fix must not turn the disable arm into a bare radius test.
      final gate = build(radius: 5);
      gate.update('peer', 4);
      expect(gate.isEnabled('peer'), isTrue);
      gate.update('peer', 5); // in the band — must HOLD, not drop
      expect(gate.isEnabled('peer'), isTrue);
    });
  });
}
