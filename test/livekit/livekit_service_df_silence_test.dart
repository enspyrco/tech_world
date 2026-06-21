import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/livekit/livekit_service.dart';

/// Tests for the Dreamfinder silence-on-subscribe seam.
///
/// LiveKitService holds a concrete LiveKit `Room`, which makes the
/// silence-on-track-subscribe logic awkward to drive end-to-end. The
/// `silenceParticipantAudio` DI seam ([LiveKitService.new]'s
/// `@visibleForTesting` callback) lets us observe whether the disable effect
/// fires for a freshly-subscribed track without faking the whole SDK — we
/// drive the decision through [LiveKitService.applyDreamfinderSilenceOnSubscribe]
/// and assert on the recorded identities.
void main() {
  group('Dreamfinder silence on track-subscribe', () {
    late List<String> silencedIdentities;
    late LiveKitService service;

    setUp(() {
      silencedIdentities = [];
      service = LiveKitService(
        userId: 'user-1',
        displayName: 'User 1',
        silenceParticipantAudio: silencedIdentities.add,
      );
    });

    tearDown(() {
      service.dispose();
    });

    test('silenced + DF audio track subscribed -> disables that track', () {
      service.dreamfinderSilenced.value = true;

      service.applyDreamfinderSilenceOnSubscribe(
        isAudioTrack: true,
        identity: 'agent-abc123',
      );

      expect(silencedIdentities, ['agent-abc123']);
    });

    test('silenced + bot-dreamfinder identity -> disables that track', () {
      service.dreamfinderSilenced.value = true;

      service.applyDreamfinderSilenceOnSubscribe(
        isAudioTrack: true,
        identity: 'bot-dreamfinder',
      );

      expect(silencedIdentities, ['bot-dreamfinder']);
    });

    test('NOT silenced + DF audio track subscribed -> does NOT disable', () {
      // dreamfinderSilenced defaults to false.
      service.applyDreamfinderSilenceOnSubscribe(
        isAudioTrack: true,
        identity: 'agent-abc123',
      );

      expect(silencedIdentities, isEmpty);
    });

    test('silenced + DF VIDEO track subscribed -> does NOT disable audio', () {
      service.dreamfinderSilenced.value = true;

      service.applyDreamfinderSilenceOnSubscribe(
        isAudioTrack: false,
        identity: 'agent-abc123',
      );

      expect(silencedIdentities, isEmpty);
    });

    test('silenced + non-DF audio track subscribed -> does NOT disable', () {
      service.dreamfinderSilenced.value = true;

      service.applyDreamfinderSilenceOnSubscribe(
        isAudioTrack: true,
        identity: 'bot-claude',
      );

      expect(silencedIdentities, isEmpty);
    });

    test('silenced + human peer audio track subscribed -> does NOT disable',
        () {
      service.dreamfinderSilenced.value = true;

      service.applyDreamfinderSilenceOnSubscribe(
        isAudioTrack: true,
        identity: 'user-2',
      );

      expect(silencedIdentities, isEmpty);
    });
  });
}
