import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tech_world/diagnostics/diagnostics_service.dart';
import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/types.dart';
import 'package:tech_world/flame/bubble_manager.dart';
import 'package:tech_world/flame/components/bot_bubble_component.dart';
import 'package:tech_world/flame/components/bot_character_component.dart';
import 'package:tech_world/flame/components/player_bubble_component.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:tech_world/flame/components/video_bubble_component.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:livekit_client/livekit_client.dart';

class MockLiveKitService extends Mock implements LiveKitService {}

class MockParticipant extends Mock implements Participant {}

class MockRemoteParticipant extends Mock implements RemoteParticipant {}

class MockLocalParticipant extends Mock implements LocalParticipant {}

class MockRemoteVideoTrackPublication extends Mock
    implements RemoteTrackPublication<RemoteVideoTrack> {}

class MockLocalVideoTrackPublication extends Mock
    implements LocalTrackPublication<LocalVideoTrack> {}

class MockRemoteVideoTrack extends Mock implements RemoteVideoTrack {}

class MockLocalVideoTrack extends Mock implements LocalVideoTrack {}

void main() {
  // Required by the DiagnosticsService reader-side test group below
  // (any test that calls `service.setAvEnabled` touches SharedPreferences).
  // Idempotent — safe for tests that don't need it.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BubbleManager', () {
    group('chebyshevDistance', () {
      test('returns max of x and y difference', () {
        expect(
          BubbleManager.chebyshevDistance(
              const Point(0, 0), const Point(3, 4)),
          equals(4),
        );
      });

      test('returns 0 for identical points', () {
        expect(
          BubbleManager.chebyshevDistance(
              const Point(5, 5), const Point(5, 5)),
          equals(0),
        );
      });

      test('handles negative coordinates', () {
        expect(
          BubbleManager.chebyshevDistance(
              const Point(-2, 3), const Point(1, 0)),
          equals(3),
        );
      });

      test('is symmetric', () {
        const a = Point(1, 7);
        const b = Point(4, 2);
        expect(
          BubbleManager.chebyshevDistance(a, b),
          equals(BubbleManager.chebyshevDistance(b, a)),
        );
      });

      test('returns x distance when y is 0', () {
        expect(
          BubbleManager.chebyshevDistance(
              const Point(0, 0), const Point(7, 0)),
          equals(7),
        );
      });

      test('returns y distance when x is 0', () {
        expect(
          BubbleManager.chebyshevDistance(
              const Point(0, 0), const Point(0, 3)),
          equals(3),
        );
      });

      test('adjacent diagonal is distance 1', () {
        expect(
          BubbleManager.chebyshevDistance(
              const Point(0, 0), const Point(1, 1)),
          equals(1),
        );
      });
    });

    group('update — bubble lifecycle', () {
      late BubbleManager manager;
      late PlayerComponent localPlayer;
      late Map<String, PlayerComponent> remotePlayers;
      late Map<String, BotCharacterComponent> bots;
      late List<Component> addedComponents;

      setUp(() {
        addedComponents = [];
        localPlayer = PlayerComponent(
          position: Vector2(160, 160), // grid (5, 5) assuming 32px squares
          id: 'local-user',
          displayName: 'Local',
        );
        remotePlayers = {};
        bots = {};

        manager = BubbleManager(
          localPlayer: localPlayer,
          addComponent: addedComponents.add,
          remotePlayers: remotePlayers,
          bots: bots,
        );
      });

      test('creates bubble for nearby remote player', () {
        // Place remote player 3 grid squares away (within visual threshold)
        final remote = PlayerComponent(
          position: Vector2(256, 160), // grid (8, 5) — 3 away on x
          id: 'remote-1',
          displayName: 'Remote',
        );
        remotePlayers['remote-1'] = remote;

        manager.update(0.016);

        // Should create 2 bubbles: one for remote, one for local
        expect(addedComponents.length, equals(2));
        expect(
          addedComponents.whereType<PlayerBubbleComponent>().length,
          equals(2),
        );
      });

      test('does not create bubble for distant remote player', () {
        // Place remote player 10 grid squares away (beyond threshold)
        final remote = PlayerComponent(
          position: Vector2(480, 160), // grid (15, 5) — 10 away
          id: 'remote-1',
          displayName: 'Remote',
        );
        remotePlayers['remote-1'] = remote;

        manager.update(0.016);

        expect(addedComponents, isEmpty);
      });

      test('creates bot bubble for nearby bot', () {
        final bot = BotCharacterComponent(
          position: Vector2(192, 160), // grid (6, 5) — 1 away
          id: 'bot-claude',
          displayName: 'Clawd',
        );
        bots['bot-claude'] = bot;

        manager.update(0.016);

        // Bot bubble + local player bubble
        expect(addedComponents.length, equals(2));
        expect(
          addedComponents.whereType<BotBubbleComponent>().length,
          equals(1),
        );
      });

      test('skips proximity re-evaluation on same grid position', () {
        final remote = PlayerComponent(
          position: Vector2(256, 160),
          id: 'remote-1',
          displayName: 'Remote',
        );
        remotePlayers['remote-1'] = remote;

        // First update creates bubbles
        manager.update(0.016);
        final initialCount = addedComponents.length;

        // Second update at same position — no new bubbles
        manager.update(0.016);
        expect(addedComponents.length, equals(initialCount));
      });
    });

    group('audio threshold', () {
      late BubbleManager manager;
      late MockLiveKitService mockLiveKit;
      late PlayerComponent localPlayer;
      late Map<String, PlayerComponent> remotePlayers;

      setUp(() {
        mockLiveKit = MockLiveKitService();
        when(() => mockLiveKit.setParticipantAudioVolume(any(), any()))
            .thenReturn(true);
        localPlayer = PlayerComponent(
          position: Vector2(160, 160),
          id: 'local-user',
          displayName: 'Local',
        );
        remotePlayers = {};

        manager = BubbleManager(
          localPlayer: localPlayer,
          addComponent: (_) {},
          remotePlayers: remotePlayers,
          bots: {},
        );
        manager.setLiveKitService(mockLiveKit);
      });

      test('enables audio within threshold', () {
        when(() => mockLiveKit.setParticipantAudioEnabled(any(), any()))
            .thenReturn(null);
        when(() => mockLiveKit.getParticipant(any())).thenReturn(null);

        // Place player 2 squares away (at audio threshold)
        remotePlayers['remote-1'] = PlayerComponent(
          position: Vector2(224, 160), // 2 away
          id: 'remote-1',
          displayName: 'Remote',
        );

        manager.update(0.016);

        verify(() =>
                mockLiveKit.setParticipantAudioEnabled('remote-1', true))
            .called(1);
      });

      test('does not enable audio beyond the enable threshold', () {
        when(() => mockLiveKit.setParticipantAudioEnabled(any(), any()))
            .thenReturn(null);
        when(() => mockLiveKit.getParticipant(any())).thenReturn(null);

        // Place player 6 squares away — beyond the enable threshold (4).
        remotePlayers['remote-1'] = PlayerComponent(
          position: Vector2(352, 160), // 6 away
          id: 'remote-1',
          displayName: 'Remote',
        );

        manager.update(0.016);

        verifyNever(() =>
            mockLiveKit.setParticipantAudioEnabled('remote-1', true));
      });

      test('hysteresis: stays enabled between thresholds, cuts past disable', () {
        when(() => mockLiveKit.setParticipantAudioEnabled(any(), any()))
            .thenReturn(null);
        when(() => mockLiveKit.getParticipant(any())).thenReturn(null);

        final remote = PlayerComponent(
          position: Vector2(256, 160), // 3 away — within enable threshold (4)
          id: 'remote-1',
          displayName: 'Remote',
        );
        remotePlayers['remote-1'] = remote;

        // Enters enable range → audio turns on.
        manager.update(0.016);
        verify(() => mockLiveKit.setParticipantAudioEnabled('remote-1', true))
            .called(1);

        // Drifts to 5 — inside the hysteresis band (> enable 4, ≤ disable 5).
        // Audio must NOT cut: no further enable/disable calls.
        remote.position = Vector2(320, 160); // 5 away
        manager.update(0.016);
        verifyNever(
            () => mockLiveKit.setParticipantAudioEnabled('remote-1', false));

        // Drifts past the disable threshold (6 > 5) → audio cuts.
        remote.position = Vector2(352, 160); // 6 away
        manager.update(0.016);
        verify(() => mockLiveKit.setParticipantAudioEnabled('remote-1', false))
            .called(1);
      });

      test('fades volume by distance while subscribed', () {
        when(() => mockLiveKit.setParticipantAudioEnabled(any(), any()))
            .thenReturn(null);
        when(() => mockLiveKit.setParticipantAudioVolume(any(), any()))
            .thenReturn(true);
        when(() => mockLiveKit.getParticipant(any())).thenReturn(null);

        // distance 3 → linear volume (5-3)/(5-1) = 0.5
        final remote = PlayerComponent(
          position: Vector2(256, 160), // 3 away
          id: 'remote-1',
          displayName: 'Remote',
        );
        remotePlayers['remote-1'] = remote;
        manager.update(0.016);
        verify(() => mockLiveKit.setParticipantAudioVolume('remote-1', 0.5))
            .called(1);

        // distance 1 → full volume.
        remote.position = Vector2(192, 160); // 1 away
        manager.update(0.016);
        verify(() => mockLiveKit.setParticipantAudioVolume('remote-1', 1.0))
            .called(1);
      });

      test('does not cache volume until a track is actually addressed', () {
        when(() => mockLiveKit.setParticipantAudioEnabled(any(), any()))
            .thenReturn(null);
        when(() => mockLiveKit.getParticipant(any())).thenReturn(null);
        // Track not subscribed yet → setParticipantAudioVolume returns false.
        when(() => mockLiveKit.setParticipantAudioVolume(any(), any()))
            .thenReturn(false);

        final remote = PlayerComponent(
          position: Vector2(256, 160), // 3 away → volume 0.5
          id: 'remote-1',
          displayName: 'Remote',
        );
        remotePlayers['remote-1'] = remote;

        // Two frames at the same distance: because the volume never landed, it
        // must be retried every frame (NOT cached after the first no-op).
        manager.update(0.016);
        manager.update(0.016);
        verify(() => mockLiveKit.setParticipantAudioVolume('remote-1', 0.5))
            .called(2);

        // Track subscribes → call now succeeds; next frame caches and stops.
        when(() => mockLiveKit.setParticipantAudioVolume(any(), any()))
            .thenReturn(true);
        manager.update(0.016);
        manager.update(0.016);
        verify(() => mockLiveKit.setParticipantAudioVolume('remote-1', 0.5))
            .called(1); // landed once, then cached
      });
    });

    group('video threshold', () {
      late BubbleManager manager;
      late MockLiveKitService mockLiveKit;
      late PlayerComponent localPlayer;
      late Map<String, PlayerComponent> remotePlayers;

      setUp(() {
        mockLiveKit = MockLiveKitService();
        // The proximity loop drives the audio gate too; stub it so update()
        // doesn't throw while we assert on the video gate.
        when(() => mockLiveKit.setParticipantAudioEnabled(any(), any()))
            .thenReturn(null);
        when(() => mockLiveKit.setParticipantAudioVolume(any(), any()))
            .thenReturn(true);
        when(() => mockLiveKit.setParticipantVideoEnabled(any(), any()))
            .thenReturn(null);
        when(() => mockLiveKit.getParticipant(any())).thenReturn(null);
        localPlayer = PlayerComponent(
          position: Vector2(160, 160),
          id: 'local-user',
          displayName: 'Local',
        );
        remotePlayers = {};

        manager = BubbleManager(
          localPlayer: localPlayer,
          addComponent: (_) {},
          remotePlayers: remotePlayers,
          bots: {},
        );
        manager.setLiveKitService(mockLiveKit);
      });

      test('enables camera as soon as the bubble is visible (at the edge)', () {
        // 5 squares away — exactly the visual threshold, where the bubble
        // appears. Video enables here too (decode-across-visible), so the
        // bubble always has a live — if blurred — frame; no black band.
        remotePlayers['remote-1'] = PlayerComponent(
          position: Vector2(320, 160), // 5 away
          id: 'remote-1',
          displayName: 'Remote',
        );

        manager.update(0.016);

        verify(() => mockLiveKit.setParticipantVideoEnabled('remote-1', true))
            .called(1);
      });

      test('does not enable a camera beyond visual range (no bubble)', () {
        // 6 squares away — past the visual threshold, so no bubble and no
        // decode: nothing to paint means nothing to forward.
        remotePlayers['remote-1'] = PlayerComponent(
          position: Vector2(352, 160), // 6 away
          id: 'remote-1',
          displayName: 'Remote',
        );

        manager.update(0.016);

        verifyNever(
            () => mockLiveKit.setParticipantVideoEnabled('remote-1', true));
      });

      test('holds through the 1-square disable hysteresis, cuts past visual+1',
          () {
        final remote = PlayerComponent(
          position: Vector2(320, 160), // 5 away — at the visual edge
          id: 'remote-1',
          displayName: 'Remote',
        );
        remotePlayers['remote-1'] = remote;

        // Visible → camera turns on.
        manager.update(0.016);
        verify(() => mockLiveKit.setParticipantVideoEnabled('remote-1', true))
            .called(1);

        // Drifts to 6 — one square past the visual edge (bubble gone), inside
        // the disable hysteresis (≤ _videoDisableThreshold 6). Camera holds so a
        // peer parked on the line doesn't re-keyframe every jitter.
        remote.position = Vector2(352, 160); // 6 away
        manager.update(0.016);
        verifyNever(
            () => mockLiveKit.setParticipantVideoEnabled('remote-1', false));

        // Drifts past the disable threshold (7 > 6) → camera cuts.
        remote.position = Vector2(384, 160); // 7 away
        manager.update(0.016);
        verify(() => mockLiveKit.setParticipantVideoEnabled('remote-1', false))
            .called(1);
      });

      test('avatar-only client (hideVideoBubbles) never enables camera decode',
          () {
        manager.hideVideoBubbles = true;
        // Right on top of the local player (distance 1) — well inside every
        // threshold. An avatar-only client must still never turn on decode.
        remotePlayers['remote-1'] = PlayerComponent(
          position: Vector2(192, 160), // 1 away
          id: 'remote-1',
          displayName: 'Remote',
        );

        manager.update(0.016);

        verifyNever(
            () => mockLiveKit.setParticipantVideoEnabled('remote-1', true));
      });

      test(
          'registers a camera-desire predicate tracking the enabled set '
          '(the subscribe-reconcile seam that fixes the latch race)', () {
        // Capture the predicate BubbleManager registered on the service in
        // setUp. On a TrackSubscribedEvent, LiveKitService reads THIS to decide
        // whether a fresh/re-subscribed camera should be ON — so it must always
        // reflect the gate's live desire, never a stale latch.
        final captured =
            verify(() => mockLiveKit.cameraDesiredForIdentity = captureAny())
                .captured;
        final predicate = captured.last as bool Function(String);

        // Nobody near yet → not desired.
        expect(predicate('remote-1'), isFalse);

        // Peer already within enable range: the gate latches desire. A camera
        // that subscribes NOW (after the gate fired) must be reconciled ON —
        // the predicate says so, which is exactly what closes the race.
        remotePlayers['remote-1'] = PlayerComponent(
          position: Vector2(256, 160), // 3 away
          id: 'remote-1',
          displayName: 'Remote',
        );
        manager.update(0.016);
        expect(predicate('remote-1'), isTrue);

        // Peer walks well out of range (past the disable hysteresis) → desire
        // cleared → a late/re-subscribe reads false and stays OFF.
        remotePlayers['remote-1']!.position = Vector2(384, 160); // 7 away
        manager.update(0.016);
        expect(predicate('remote-1'), isFalse);
      });
    });

    group('Dreamfinder proximity signal', () {
      late BubbleManager manager;
      late MockLiveKitService mockLiveKit;

      setUp(() {
        mockLiveKit = MockLiveKitService();
        when(() => mockLiveKit.setParticipantAudioVolume(any(), any()))
            .thenReturn(true);
        when(() => mockLiveKit.publishDfProximity(near: any(named: 'near')))
            .thenAnswer((_) async {});
        manager = BubbleManager(
          localPlayer: PlayerComponent(
            position: Vector2(160, 160),
            id: 'local-user',
            displayName: 'Local',
          ),
          addComponent: (_) {},
          remotePlayers: {},
          bots: {},
        );
        manager.setLiveKitService(mockLiveKit);
      });

      test('enters at the enable threshold, exits past the disable threshold',
          () {
        // d=4 ≤ enable(4) → enter.
        manager.debugUpdateDreamfinderProximity(4);
        verify(() => mockLiveKit.publishDfProximity(near: true)).called(1);

        // d=5 — inside the hysteresis band (> enable 4, ≤ disable 5). No re-emit.
        manager.debugUpdateDreamfinderProximity(5);
        // d=6 > disable(5) → exit.
        manager.debugUpdateDreamfinderProximity(6);
        verify(() => mockLiveKit.publishDfProximity(near: false)).called(1);
        // Exactly one enter + one exit across the whole sweep.
        verifyNever(() => mockLiveKit.publishDfProximity(near: any(named: 'near')));
      });

      test('DF absent (null distance) forces an exit', () {
        manager.debugUpdateDreamfinderProximity(2); // near
        verify(() => mockLiveKit.publishDfProximity(near: true)).called(1);
        manager.debugUpdateDreamfinderProximity(null); // DF gone → exit
        verify(() => mockLiveKit.publishDfProximity(near: false)).called(1);
      });

      test('null service does NOT latch — re-fires once the service is set', () {
        // Fresh manager with no service set yet (_liveKitService is null).
        final noService = BubbleManager(
          localPlayer: PlayerComponent(
            position: Vector2(160, 160),
            id: 'local-user',
            displayName: 'Local',
          ),
          addComponent: (_) {},
          remotePlayers: {},
          bots: {},
        );
        noService.debugUpdateDreamfinderProximity(2); // can't emit, must not latch
        // Now the service is available; the SAME distance must still fire enter.
        noService.setLiveKitService(mockLiveKit);
        noService.debugUpdateDreamfinderProximity(2);
        verify(() => mockLiveKit.publishDfProximity(near: true)).called(1);
      });

      test('clear() emits a final exit when the player was near DF', () {
        manager.debugUpdateDreamfinderProximity(1); // near
        verify(() => mockLiveKit.publishDfProximity(near: true)).called(1);
        manager.clear();
        verify(() => mockLiveKit.publishDfProximity(near: false)).called(1);
      });
    });

    group('Dreamfinder audio gate', () {
      late BubbleManager manager;
      late MockLiveKitService mockLiveKit;
      late ValueNotifier<bool> silenced;

      setUp(() {
        mockLiveKit = MockLiveKitService();
        silenced = ValueNotifier<bool>(false);
        when(() => mockLiveKit.dreamfinderSilenced).thenReturn(silenced);
        when(() => mockLiveKit.setParticipantAudioEnabled(any(), any()))
            .thenReturn(null);
        when(() => mockLiveKit.setParticipantAudioVolume(any(), any()))
            .thenReturn(true);
        when(() => mockLiveKit.getParticipant(any())).thenReturn(null);
        when(() => mockLiveKit.dreamfinderIdentities())
            .thenReturn(const <String>[]);
        manager = BubbleManager(
          localPlayer: PlayerComponent(
            position: Vector2(160, 160),
            id: 'local-user',
            displayName: 'Local',
          ),
          addComponent: (_) {},
          remotePlayers: {},
          bots: {},
        );
        manager.setLiveKitService(mockLiveKit);
      });

      tearDown(() => silenced.dispose());

      test('gates EVERY DF identity the service reports, not just the slot',
          () {
        // Two live agent identities (respawn/stale-session overlap) — both
        // must pass through the gate; the single-slot assumption was half of
        // the 2026-07-18 silence failure.
        when(() => mockLiveKit.dreamfinderIdentities())
            .thenReturn(const ['agent-a', 'agent-b']);
        manager.debugUpdateDreamfinderAudio(2); // within enable range
        verify(() =>
                mockLiveKit.setParticipantAudioEnabled('agent-a', true))
            .called(1);
        verify(() =>
                mockLiveKit.setParticipantAudioEnabled('agent-b', true))
            .called(1);
      });

      test('while silenced, forces local volume 0 on every DF identity', () {
        when(() => mockLiveKit.dreamfinderIdentities())
            .thenReturn(const ['agent-a', 'agent-b']);
        silenced.value = true;
        manager.debugUpdateDreamfinderAudio(1); // near but silenced
        // Local hard-mute regardless of the server-side disable's efficacy
        // (the 2026-07-18 "DF will STILL not shut up" failure).
        verify(() => mockLiveKit.setParticipantAudioVolume('agent-a', 0.0))
            .called(1);
        verify(() => mockLiveKit.setParticipantAudioVolume('agent-b', 0.0))
            .called(1);
        // And the volume-0 write is cached: a second silenced frame does not
        // re-write (retry-until-landed semantics, matching the fade layer).
        manager.debugUpdateDreamfinderAudio(1);
        verifyNever(() =>
            mockLiveKit.setParticipantAudioVolume('agent-a', 0.0));
      });

      test('enables DF audio when within the enable threshold', () {
        manager.debugUpdateDreamfinderAudio(2); // ≤ enable (4)
        verify(() => mockLiveKit.setParticipantAudioEnabled(
            manager.dreamfinderIdentity, true)).called(1);
      });

      test('does not enable DF audio beyond the enable threshold', () {
        manager.debugUpdateDreamfinderAudio(6); // > disable (5)
        verifyNever(() => mockLiveKit.setParticipantAudioEnabled(
            manager.dreamfinderIdentity, true));
      });

      test('cuts DF audio once past the disable threshold', () {
        manager.debugUpdateDreamfinderAudio(2); // within → on
        verify(() => mockLiveKit.setParticipantAudioEnabled(
            manager.dreamfinderIdentity, true)).called(1);
        manager.debugUpdateDreamfinderAudio(6); // past disable → off
        verify(() => mockLiveKit.setParticipantAudioEnabled(
            manager.dreamfinderIdentity, false)).called(1);
      });

      test('manual silence vetoes proximity — DF stays muted even when close',
          () {
        silenced.value = true;
        manager.debugUpdateDreamfinderAudio(1); // as close as possible
        verifyNever(() => mockLiveKit.setParticipantAudioEnabled(
            manager.dreamfinderIdentity, true));
      });

      test('silencing while near forces DF audio off', () {
        manager.debugUpdateDreamfinderAudio(1); // on
        verify(() => mockLiveKit.setParticipantAudioEnabled(
            manager.dreamfinderIdentity, true)).called(1);
        silenced.value = true;
        manager.debugUpdateDreamfinderAudio(1); // near but silenced → off
        verify(() => mockLiveKit.setParticipantAudioEnabled(
            manager.dreamfinderIdentity, false)).called(1);
      });

      // Regression for the cage-match #594/#485 leak: the gate is the SOLE
      // enabler. Even right after un-silencing, if you're out of range the gate
      // must not enable DF — so an un-silence-while-far can never leave DF
      // audible (the silence button no longer force-enables; see
      // LiveKitService.setDreamfinderSilenced).
      test('does not enable DF when far, even immediately after un-silencing',
          () {
        silenced.value = true;
        manager.debugUpdateDreamfinderAudio(1); // silenced + near → stays off
        silenced.value = false; // un-silence...
        manager.debugUpdateDreamfinderAudio(6); // ...but now out of range
        verifyNever(() => mockLiveKit.setParticipantAudioEnabled(
            manager.dreamfinderIdentity, true));
      });
    });

    group('clear', () {
      late BubbleManager manager;
      late List<Component> addedComponents;
      late Map<String, PlayerComponent> remotePlayers;

      setUp(() {
        addedComponents = [];
        remotePlayers = {};
        manager = BubbleManager(
          localPlayer: PlayerComponent(
            position: Vector2(160, 160),
            id: 'local-user',
            displayName: 'Local',
          ),
          addComponent: addedComponents.add,
          remotePlayers: remotePlayers,
          bots: {},
        );
      });

      test('removes all bubbles and resets state', () {
        // Create some bubbles
        remotePlayers['remote-1'] = PlayerComponent(
          position: Vector2(192, 160),
          id: 'remote-1',
          displayName: 'Remote',
        );
        manager.update(0.016);
        expect(addedComponents, isNotEmpty);

        // Clear everything
        manager.clear();

        // After clear, a new update with a different position should
        // not carry over stale state.
        addedComponents.clear();
        remotePlayers.remove('remote-1');
        manager.update(0.016);
        expect(addedComponents, isEmpty);
      });

      test('is idempotent', () {
        manager.clear();
        manager.clear(); // Should not throw
      });
    });

    group('removeBubble', () {
      late BubbleManager manager;
      late List<Component> addedComponents;
      late Map<String, PlayerComponent> remotePlayers;

      setUp(() {
        addedComponents = [];
        remotePlayers = {};
        manager = BubbleManager(
          localPlayer: PlayerComponent(
            position: Vector2(160, 160),
            id: 'local-user',
            displayName: 'Local',
          ),
          addComponent: addedComponents.add,
          remotePlayers: remotePlayers,
          bots: {},
        );
      });

      test('no-op for non-existent player', () {
        manager.removeBubble('nonexistent');
        // Should not throw
      });
    });

    group('updateSpeakingState', () {
      test('no-op when no bubble exists', () {
        final manager = BubbleManager(
          localPlayer: PlayerComponent(
            position: Vector2.zero(),
            id: 'local',
            displayName: 'Local',
          ),
          addComponent: (_) {},
          remotePlayers: {},
          bots: {},
        );

        // Should not throw
        manager.updateSpeakingState('nonexistent', true);
      });
    });

    group('notifyTrackReady', () {
      test('no-op when no bubble exists', () {
        final manager = BubbleManager(
          localPlayer: PlayerComponent(
            position: Vector2.zero(),
            id: 'local',
            displayName: 'Local',
          ),
          addComponent: (_) {},
          remotePlayers: {},
          bots: {},
        );

        // Should not throw
        manager.notifyTrackReady('nonexistent');
      });
    });

    group('refreshBubbleForPlayer', () {
      test('no-op when no bubble exists for player', () {
        final manager = BubbleManager(
          localPlayer: PlayerComponent(
            position: Vector2.zero(),
            id: 'local',
            displayName: 'Local',
          ),
          addComponent: (_) {},
          remotePlayers: {},
          bots: {},
        );

        // Should not throw
        manager.refreshBubbleForPlayer('nonexistent');
      });
    });

    group('refreshLocalPlayerBubble', () {
      test('no-op when no local bubble exists', () {
        final manager = BubbleManager(
          localPlayer: PlayerComponent(
            position: Vector2.zero(),
            id: 'local',
            displayName: 'Local',
          ),
          addComponent: (_) {},
          remotePlayers: {},
          bots: {},
        );

        // Should not throw
        manager.refreshLocalPlayerBubble();
      });
    });

    group('downgradeVideoBubble', () {
      test('no-op when no bubble exists', () {
        final manager = BubbleManager(
          localPlayer: PlayerComponent(
            position: Vector2.zero(),
            id: 'local',
            displayName: 'Local',
          ),
          addComponent: (_) {},
          remotePlayers: {},
          bots: {},
        );

        // Should not throw
        manager.downgradeVideoBubble('nonexistent');
      });
    });

    group('hideVideoBubbles toggle', () {
      late List<Component> addedComponents;
      late PlayerComponent localPlayer;
      late Map<String, PlayerComponent> remotePlayers;
      late MockLiveKitService mockLiveKit;

      /// Build a remote-participant mock that advertises a subscribed video
      /// track — i.e. the path that would normally produce a
      /// [VideoBubbleComponent] from `_createBubbleForPlayer`.
      MockRemoteParticipant remoteWithVideo() {
        final pub = MockRemoteVideoTrackPublication();
        final track = MockRemoteVideoTrack();
        when(() => pub.track).thenReturn(track);
        when(() => pub.subscribed).thenReturn(true);
        final p = MockRemoteParticipant();
        when(() => p.videoTrackPublications).thenReturn([pub]);
        return p;
      }

      /// Local-participant mock with a video track published. Hits the
      /// `LocalParticipant` arm of `_hasVideoTrack`, which does not require
      /// `subscribed: true`.
      MockLocalParticipant localWithVideo() {
        final pub = MockLocalVideoTrackPublication();
        final track = MockLocalVideoTrack();
        when(() => pub.track).thenReturn(track);
        when(() => pub.subscribed).thenReturn(true);
        final p = MockLocalParticipant();
        when(() => p.videoTrackPublications).thenReturn([pub]);
        return p;
      }

      setUp(() {
        addedComponents = [];
        remotePlayers = {};
        mockLiveKit = MockLiveKitService();
        when(() => mockLiveKit.setParticipantAudioVolume(any(), any()))
            .thenReturn(true);
        when(() => mockLiveKit.setParticipantAudioEnabled(any(), any()))
            .thenReturn(null);
        localPlayer = PlayerComponent(
          position: Vector2(160, 160),
          id: 'local-user',
          displayName: 'Local',
        );
      });

      test('default (off) keeps video bubble for remote with subscribed track',
          () {
        final manager = BubbleManager(
          localPlayer: localPlayer,
          addComponent: addedComponents.add,
          remotePlayers: remotePlayers,
          bots: {},
        );
        manager.setLiveKitService(mockLiveKit);

        final remote = PlayerComponent(
          position: Vector2(192, 160), // 1 grid square away
          id: 'remote-1',
          displayName: 'Remote',
        );
        remotePlayers['remote-1'] = remote;
        final remoteParticipant = remoteWithVideo();
        when(() => mockLiveKit.getParticipant('remote-1'))
            .thenReturn(remoteParticipant);
        when(() => mockLiveKit.localParticipant).thenReturn(null);

        manager.update(0.016);

        expect(
          addedComponents.whereType<VideoBubbleComponent>().length,
          equals(1),
          reason: 'remote with subscribed video should render as video bubble',
        );
      });

      test(
          'hideVideoBubbles=true returns PlayerBubbleComponent for remote '
          'even when participant has a video track', () {
        final manager = BubbleManager(
          localPlayer: localPlayer,
          addComponent: addedComponents.add,
          remotePlayers: remotePlayers,
          bots: {},
          hideVideoBubbles: true,
        );
        manager.setLiveKitService(mockLiveKit);

        final remote = PlayerComponent(
          position: Vector2(192, 160),
          id: 'remote-1',
          displayName: 'Remote',
        );
        remotePlayers['remote-1'] = remote;
        final remoteParticipant = remoteWithVideo();
        when(() => mockLiveKit.getParticipant('remote-1'))
            .thenReturn(remoteParticipant);
        when(() => mockLiveKit.localParticipant).thenReturn(null);

        manager.update(0.016);

        expect(
          addedComponents.whereType<VideoBubbleComponent>(),
          isEmpty,
          reason: 'no video bubbles should be created when toggle is on',
        );
        // Two PlayerBubbleComponents: one for remote, one for local.
        expect(
          addedComponents.whereType<PlayerBubbleComponent>().length,
          equals(2),
        );
      });

      test(
          'hideVideoBubbles=true returns PlayerBubbleComponent for local '
          'even when local participant has a video track', () {
        final manager = BubbleManager(
          localPlayer: localPlayer,
          addComponent: addedComponents.add,
          remotePlayers: remotePlayers,
          bots: {},
          hideVideoBubbles: true,
        );
        manager.setLiveKitService(mockLiveKit);

        // Need a nearby remote to trigger local-bubble creation.
        remotePlayers['remote-1'] = PlayerComponent(
          position: Vector2(192, 160),
          id: 'remote-1',
          displayName: 'Remote',
        );
        when(() => mockLiveKit.getParticipant('remote-1')).thenReturn(null);
        final localParticipant = localWithVideo();
        when(() => mockLiveKit.localParticipant).thenReturn(localParticipant);

        manager.update(0.016);

        expect(
          addedComponents.whereType<VideoBubbleComponent>(),
          isEmpty,
          reason: 'local bubble must not be a video bubble when toggle is on',
        );
      });
    });

    group('reduceMotion toggle', () {
      late List<Component> addedComponents;
      late PlayerComponent localPlayer;
      late Map<String, PlayerComponent> remotePlayers;
      late MockLiveKitService mockLiveKit;

      MockRemoteParticipant remoteWithVideo() {
        final pub = MockRemoteVideoTrackPublication();
        final track = MockRemoteVideoTrack();
        when(() => pub.track).thenReturn(track);
        when(() => pub.subscribed).thenReturn(true);
        final p = MockRemoteParticipant();
        when(() => p.videoTrackPublications).thenReturn([pub]);
        return p;
      }

      MockLocalParticipant localWithVideo() {
        final pub = MockLocalVideoTrackPublication();
        final track = MockLocalVideoTrack();
        when(() => pub.track).thenReturn(track);
        when(() => pub.subscribed).thenReturn(true);
        final p = MockLocalParticipant();
        when(() => p.videoTrackPublications).thenReturn([pub]);
        return p;
      }

      setUp(() {
        addedComponents = [];
        remotePlayers = {};
        mockLiveKit = MockLiveKitService();
        when(() => mockLiveKit.setParticipantAudioVolume(any(), any()))
            .thenReturn(true);
        when(() => mockLiveKit.setParticipantAudioEnabled(any(), any()))
            .thenReturn(null);
        localPlayer = PlayerComponent(
          position: Vector2(160, 160),
          id: 'local-user',
          displayName: 'Local',
        );
      });

      test('default (off) creates video bubbles with reduceMotion=false', () {
        final manager = BubbleManager(
          localPlayer: localPlayer,
          addComponent: addedComponents.add,
          remotePlayers: remotePlayers,
          bots: {},
        );
        manager.setLiveKitService(mockLiveKit);

        remotePlayers['remote-1'] = PlayerComponent(
          position: Vector2(192, 160),
          id: 'remote-1',
          displayName: 'Remote',
        );
        final remoteParticipant = remoteWithVideo();
        when(() => mockLiveKit.getParticipant('remote-1'))
            .thenReturn(remoteParticipant);
        when(() => mockLiveKit.localParticipant).thenReturn(null);

        manager.update(0.016);

        final videoBubbles =
            addedComponents.whereType<VideoBubbleComponent>().toList();
        expect(videoBubbles, hasLength(1));
        expect(videoBubbles.single.reduceMotion, isFalse,
            reason: 'default state must leave decorative animation on');
      });

      test(
          'reduceMotion=true propagates to a newly-created remote video bubble',
          () {
        final manager = BubbleManager(
          localPlayer: localPlayer,
          addComponent: addedComponents.add,
          remotePlayers: remotePlayers,
          bots: {},
          reduceMotion: true,
        );
        manager.setLiveKitService(mockLiveKit);

        remotePlayers['remote-1'] = PlayerComponent(
          position: Vector2(192, 160),
          id: 'remote-1',
          displayName: 'Remote',
        );
        final remoteParticipant = remoteWithVideo();
        when(() => mockLiveKit.getParticipant('remote-1'))
            .thenReturn(remoteParticipant);
        when(() => mockLiveKit.localParticipant).thenReturn(null);

        manager.update(0.016);

        final videoBubbles =
            addedComponents.whereType<VideoBubbleComponent>().toList();
        expect(videoBubbles, hasLength(1),
            reason: 'reduce-motion must not suppress the video bubble itself');
        expect(videoBubbles.single.reduceMotion, isTrue,
            reason: 'reduceMotion must flow into the created bubble');
      });

      test('reduceMotion=true propagates to a newly-created local video bubble',
          () {
        final manager = BubbleManager(
          localPlayer: localPlayer,
          addComponent: addedComponents.add,
          remotePlayers: remotePlayers,
          bots: {},
          reduceMotion: true,
        );
        manager.setLiveKitService(mockLiveKit);

        remotePlayers['remote-1'] = PlayerComponent(
          position: Vector2(192, 160),
          id: 'remote-1',
          displayName: 'Remote',
        );
        when(() => mockLiveKit.getParticipant('remote-1')).thenReturn(null);
        final localParticipant = localWithVideo();
        when(() => mockLiveKit.localParticipant).thenReturn(localParticipant);

        manager.update(0.016);

        final localBubble =
            addedComponents.whereType<VideoBubbleComponent>().firstWhere(
                  (b) => b.participant is LocalParticipant,
                );
        expect(localBubble.reduceMotion, isTrue);
      });
    });

    group('reads avDiagnosticsEnabled from the injected DiagnosticsService', () {
      // Locks in the architectural invariant that there is exactly one
      // source of truth for the AV diagnostics toggle. Without this test,
      // a future change that reintroduces a shadow `bool avDiagnosticsEnabled`
      // field on BubbleManager would silently re-create the dual-write
      // invariant the DiagnosticsService extraction exists to prevent.
      // See `feedback_cross_cutting_toggle_needs_single_owner`.

      test('initial value tracks service', () {
        final service = DiagnosticsService(
          avEnabled: true,
          errorLoggingEnabled: true,
        );
        final manager = BubbleManager(
          localPlayer: PlayerComponent(
            position: Vector2(160, 160),
            id: 'local',
            displayName: 'Local',
          ),
          addComponent: (_) {},
          remotePlayers: {},
          bots: {},
          diagnostics: service,
        );
        expect(manager.avDiagnosticsEnabled, isTrue);
      });

      test('flipping the service flips the getter (live read, not snapshot)',
          () async {
        final service = DiagnosticsService(
          avEnabled: false,
          errorLoggingEnabled: true,
        );
        final manager = BubbleManager(
          localPlayer: PlayerComponent(
            position: Vector2(160, 160),
            id: 'local',
            displayName: 'Local',
          ),
          addComponent: (_) {},
          remotePlayers: {},
          bots: {},
          diagnostics: service,
        );
        expect(manager.avDiagnosticsEnabled, isFalse);

        // Mutate the source. The manager's getter must reflect the new
        // value without any propagation call — that's the single-owner
        // contract. (Persistence is not asserted here; the explicit
        // DiagnosticsService constructor bypasses SharedPreferences.)
        service.avEnabled.addListener(() {}); // noop, just to be explicit
        // Flip via the public setter equivalent — explicit constructor's
        // ValueNotifier is private, so use setAvEnabled which both
        // updates the notifier and persists. SharedPreferences mock
        // is set up at top-level setUp.
        await service.setAvEnabled(true);

        expect(manager.avDiagnosticsEnabled, isTrue);
      });

      test('default constructor falls back to Locator lookup (null-safe)', () {
        // No DiagnosticsService passed and none in Locator — manager must
        // not crash; getter returns false (fail-safe default).
        final manager = BubbleManager(
          localPlayer: PlayerComponent(
            position: Vector2(160, 160),
            id: 'local',
            displayName: 'Local',
          ),
          addComponent: (_) {},
          remotePlayers: {},
          bots: {},
        );
        expect(manager.avDiagnosticsEnabled, isFalse);
      });
    });

    // ---------------------------------------------------------------------
    // AvBubbleType classification — Carnot LOW from #466 cage-match.
    //
    // Pre-fix, both switch sites in BubbleManager fell back to
    // `AvBubbleType.player` for any unrecognised PositionComponent
    // subclass. That made AvBubbleCreated / AvPipelineSnapshot lie about
    // what was on screen. The fix adds AvBubbleType.unknown and routes
    // the fallback there. This group pins the classifier so a future
    // edit cannot silently revert.
    // ---------------------------------------------------------------------
    group('classifyBubble (AvBubbleType fallback)', () {
      // The named-type arms (video / player / bot) are covered indirectly
      // by the existing lifecycle tests — bubbles get created and an
      // AvBubbleCreated event is dispatched. The case the fix actually
      // changes is the wildcard fallback, pinned below.
      test('unknown PositionComponent subclass maps to AvBubbleType.unknown',
          () {
        final sentinel = _SentinelBubble();
        expect(
          BubbleManager.classifyBubble(sentinel),
          AvBubbleType.unknown,
          reason:
              'Unknown PositionComponent subclasses must fall back to '
              'AvBubbleType.unknown — using AvBubbleType.player as the '
              'catch-all (the pre-#466 behaviour) makes AV diagnostic '
              'events lie about what is on screen.',
        );
      });

      test('AvBubbleCreated round-trips bubbleType.unknown through JSON', () {
        final event = AvBubbleCreated(
          participant: 'mystery',
          bubbleType: AvBubbleType.unknown,
        );
        expect(event.toJson()['bubbleType'], 'unknown');
      });
    });

    group('_replaceBubble lifecycle dispatch', () {
      // Spiral F7 from PR #465. Locks in that every slot mutation routes
      // through the single-owner helper, so AvBubbleCreated /
      // AvBubbleRemoved events fan to consumers for upgrades AND downgrades
      // — not just the initial create/exit-proximity edges.

      late List<AppEvent> captured;
      late DiagnosticsService diagnostics;
      late MockLiveKitService mockLiveKit;
      late List<Component> addedComponents;
      late PlayerComponent localPlayer;
      late Map<String, PlayerComponent> remotePlayers;

      MockRemoteParticipant remoteWithVideo() {
        final pub = MockRemoteVideoTrackPublication();
        final track = MockRemoteVideoTrack();
        when(() => pub.track).thenReturn(track);
        when(() => pub.subscribed).thenReturn(true);
        final p = MockRemoteParticipant();
        when(() => p.videoTrackPublications).thenReturn([pub]);
        return p;
      }

      setUp(() {
        clearSinks();
        captured = [];
        registerSink(captured.add);

        diagnostics = DiagnosticsService(
          avEnabled: true,
          errorLoggingEnabled: true,
        );

        addedComponents = [];
        mockLiveKit = MockLiveKitService();
        when(() => mockLiveKit.setParticipantAudioVolume(any(), any()))
            .thenReturn(true);
        when(() => mockLiveKit.setParticipantAudioEnabled(any(), any()))
            .thenReturn(null);
        when(() => mockLiveKit.localParticipant).thenReturn(null);

        localPlayer = PlayerComponent(
          position: Vector2(160, 160),
          id: 'local-user',
          displayName: 'Local',
        );
        remotePlayers = {};
      });

      tearDown(clearSinks);

      test(
          'upgrade (player -> video) dispatches AvBubbleRemoved then '
          'AvBubbleCreated for the same participant', () {
        // Start with a remote player but NO video track — first update
        // yields a PlayerBubbleComponent.
        final remote = PlayerComponent(
          position: Vector2(192, 160), // 1 grid square away
          id: 'remote-1',
          displayName: 'Remote',
        );
        remotePlayers['remote-1'] = remote;
        when(() => mockLiveKit.getParticipant('remote-1')).thenReturn(null);

        final manager = BubbleManager(
          localPlayer: localPlayer,
          addComponent: addedComponents.add,
          remotePlayers: remotePlayers,
          bots: {},
          diagnostics: diagnostics,
        );
        manager.setLiveKitService(mockLiveKit);
        manager.update(0.016);

        // Baseline: at least one AvBubbleCreated for remote-1 (no Removed
        // yet — there was no prior occupant in that slot).
        final initialRemoteCreates = captured
            .whereType<AvBubbleCreated>()
            .where((e) => e.participant == 'remote-1')
            .toList();
        expect(initialRemoteCreates, hasLength(1));
        expect(initialRemoteCreates.single.bubbleType,
            equals(AvBubbleType.player));
        expect(
          captured
              .whereType<AvBubbleRemoved>()
              .where((e) => e.participant == 'remote-1'),
          isEmpty,
          reason: 'no prior occupant means no Removed event yet',
        );

        // Now the video track lands. Calling refreshBubbleForPlayer
        // triggers the upgrade path — old PlayerBubbleComponent goes
        // away, new VideoBubbleComponent takes its place.
        captured.clear();
        final videoParticipant = remoteWithVideo();
        when(() => mockLiveKit.getParticipant('remote-1'))
            .thenReturn(videoParticipant);
        manager.refreshBubbleForPlayer('remote-1');

        // _replaceBubble contract: Removed then Created, in that order.
        final remoteEvents = captured
            .where((e) =>
                (e is AvBubbleCreated && e.participant == 'remote-1') ||
                (e is AvBubbleRemoved && e.participant == 'remote-1'))
            .toList();
        expect(remoteEvents, hasLength(2),
            reason: 'upgrade is one Removed + one Created pair');
        expect(remoteEvents[0], isA<AvBubbleRemoved>());
        expect(remoteEvents[1], isA<AvBubbleCreated>());
        expect(
          (remoteEvents[1] as AvBubbleCreated).bubbleType,
          equals(AvBubbleType.video),
          reason: 'upgraded bubble carries the video type marker',
        );
      });

      test(
          'downgrade (video -> player) dispatches AvBubbleRemoved then '
          'AvBubbleCreated for the same participant', () {
        // Start with a remote player that HAS a video track — first
        // update yields a VideoBubbleComponent.
        final remote = PlayerComponent(
          position: Vector2(192, 160),
          id: 'remote-1',
          displayName: 'Remote',
        );
        remotePlayers['remote-1'] = remote;
        final videoParticipant = remoteWithVideo();
        when(() => mockLiveKit.getParticipant('remote-1'))
            .thenReturn(videoParticipant);

        final manager = BubbleManager(
          localPlayer: localPlayer,
          addComponent: addedComponents.add,
          remotePlayers: remotePlayers,
          bots: {},
          diagnostics: diagnostics,
        );
        manager.setLiveKitService(mockLiveKit);
        manager.update(0.016);

        // Baseline: one AvBubbleCreated with type=video.
        final initialCreate = captured
            .whereType<AvBubbleCreated>()
            .firstWhere((e) => e.participant == 'remote-1');
        expect(initialCreate.bubbleType, equals(AvBubbleType.video));

        // Track went away or device lost — caller invokes downgrade.
        captured.clear();
        manager.downgradeVideoBubble('remote-1');

        // Same Removed+Created pair, but Created now carries .player.
        final remoteEvents = captured
            .where((e) =>
                (e is AvBubbleCreated && e.participant == 'remote-1') ||
                (e is AvBubbleRemoved && e.participant == 'remote-1'))
            .toList();
        expect(remoteEvents, hasLength(2));
        expect(remoteEvents[0], isA<AvBubbleRemoved>());
        expect(remoteEvents[1], isA<AvBubbleCreated>());
        expect(
          (remoteEvents[1] as AvBubbleCreated).bubbleType,
          equals(AvBubbleType.player),
          reason: 'downgraded bubble carries the player type marker',
        );
      });

      test('removeBubble dispatches AvBubbleRemoved (single-owner coverage)',
          () {
        // Seed a bubble via the normal create path.
        final remote = PlayerComponent(
          position: Vector2(192, 160),
          id: 'remote-1',
          displayName: 'Remote',
        );
        remotePlayers['remote-1'] = remote;
        when(() => mockLiveKit.getParticipant('remote-1')).thenReturn(null);

        final manager = BubbleManager(
          localPlayer: localPlayer,
          addComponent: addedComponents.add,
          remotePlayers: remotePlayers,
          bots: {},
          diagnostics: diagnostics,
        );
        manager.setLiveKitService(mockLiveKit);
        manager.update(0.016);

        // Drop the bubble explicitly — must produce AvBubbleRemoved.
        captured.clear();
        manager.removeBubble('remote-1');

        expect(
          captured
              .whereType<AvBubbleRemoved>()
              .where((e) => e.participant == 'remote-1'),
          hasLength(1),
          reason: 'removeBubble must route through the lifecycle owner',
        );
        // And no spurious Created.
        expect(
          captured
              .whereType<AvBubbleCreated>()
              .where((e) => e.participant == 'remote-1'),
          isEmpty,
        );
      });
    });
  });
}

/// Sentinel `PositionComponent` subclass for the unknown-fallback test.
/// Not a bubble type BubbleManager knows about — exactly the case the
/// switch's wildcard arm should handle.
class _SentinelBubble extends PositionComponent {}
