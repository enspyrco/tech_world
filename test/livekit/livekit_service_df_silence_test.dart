import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/livekit/livekit_service.dart';

/// Tests for the Dreamfinder audio silence/disable seams.
///
/// LiveKitService holds a concrete LiveKit `Room`, which makes both the
/// silence-on-track-subscribe logic and `setDreamfinderSilenced`'s participant
/// iteration awkward to drive end-to-end. Two `@visibleForTesting` seams on
/// [LiveKitService.new] let us observe the effects without faking the SDK:
///   - `silenceParticipantAudio` — records which identities get disabled.
///   - `remoteParticipantIdentities` — supplies the "room roster" so
///     [LiveKitService.setDreamfinderSilenced] can be exercised offline.
///
/// Mirrors the `@visibleForTesting` + fake DI pattern in room_session_test.dart.
void main() {
  group('Dreamfinder audio disable on track-subscribe', () {
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

    tearDown(() async {
      await service.dispose();
    });

    // The disable-on-subscribe path is now UNCONDITIONAL for DF audio (the
    // proximity gate re-enables when near) — closing the deferred-component
    // window where a fresh DF track was audible from anywhere before the gate's
    // first tick. So it fires whether or not the silence toggle is set.

    test('DF audio track subscribed while NOT silenced -> disables it', () {
      // dreamfinderSilenced defaults to false; we still disable on subscribe.
      service.disableDreamfinderAudioOnSubscribe(
        isAudioTrack: true,
        identity: 'agent-abc123',
      );

      expect(silencedIdentities, ['agent-abc123']);
    });

    test('DF audio track subscribed while silenced -> disables it', () {
      service.dreamfinderSilenced.value = true;

      service.disableDreamfinderAudioOnSubscribe(
        isAudioTrack: true,
        identity: 'agent-abc123',
      );

      expect(silencedIdentities, ['agent-abc123']);
    });

    test('bot-dreamfinder audio track subscribed -> disables it', () {
      service.disableDreamfinderAudioOnSubscribe(
        isAudioTrack: true,
        identity: 'bot-dreamfinder',
      );

      expect(silencedIdentities, ['bot-dreamfinder']);
    });

    test('DF VIDEO track subscribed -> does NOT disable audio', () {
      service.disableDreamfinderAudioOnSubscribe(
        isAudioTrack: false,
        identity: 'agent-abc123',
      );

      expect(silencedIdentities, isEmpty);
    });

    test('non-DF bot audio track subscribed -> does NOT disable', () {
      service.disableDreamfinderAudioOnSubscribe(
        isAudioTrack: true,
        identity: 'bot-claude',
      );

      expect(silencedIdentities, isEmpty);
    });

    test('human peer audio track subscribed -> does NOT disable', () {
      service.disableDreamfinderAudioOnSubscribe(
        isAudioTrack: true,
        identity: 'user-2',
      );

      expect(silencedIdentities, isEmpty);
    });
  });

  group('setDreamfinderSilenced (Room-seam)', () {
    late List<String> silencedIdentities;
    late List<String> roster;
    late LiveKitService service;

    setUp(() {
      silencedIdentities = [];
      roster = [];
      service = LiveKitService(
        userId: 'user-1',
        displayName: 'User 1',
        silenceParticipantAudio: silencedIdentities.add,
        remoteParticipantIdentities: () => roster,
      );
    });

    tearDown(() async {
      await service.dispose();
    });

    test('silence(true) disables every DF participant in the room', () {
      roster = ['user-2', 'bot-claude', 'bot-dreamfinder', 'agent-xyz'];

      service.setDreamfinderSilenced(true);

      expect(service.dreamfinderSilenced.value, isTrue);
      // Both DF identities (bot-dreamfinder + agent-*) disabled; nobody else.
      expect(silencedIdentities, ['bot-dreamfinder', 'agent-xyz']);
    });

    test('silence(true) with no DF in room disables nobody', () {
      roster = ['user-2', 'bot-claude'];

      service.setDreamfinderSilenced(true);

      expect(service.dreamfinderSilenced.value, isTrue);
      expect(silencedIdentities, isEmpty);
    });

    test('silence(false) does NOT enable/touch any participant (#485 leak)', () {
      roster = ['bot-dreamfinder', 'agent-xyz'];

      service.setDreamfinderSilenced(false);

      // The proximity gate is the sole enabler; un-silence must not force
      // anything on (or off) here.
      expect(service.dreamfinderSilenced.value, isFalse);
      expect(silencedIdentities, isEmpty);
    });

    test('silence(true) then silence(false) leaves the gate as sole enabler',
        () {
      roster = ['bot-dreamfinder'];

      service.setDreamfinderSilenced(true);
      expect(silencedIdentities, ['bot-dreamfinder']);

      service.setDreamfinderSilenced(false);
      // No further disable AND no enable — the false branch is a pure no-op
      // beyond flipping the notifier.
      expect(silencedIdentities, ['bot-dreamfinder']);
      expect(service.dreamfinderSilenced.value, isFalse);
    });
  });
}
