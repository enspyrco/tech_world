import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tech_world/diagnostics/diagnostics_service.dart';
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

      test('disables audio beyond threshold', () {
        when(() => mockLiveKit.setParticipantAudioEnabled(any(), any()))
            .thenReturn(null);
        when(() => mockLiveKit.getParticipant(any())).thenReturn(null);

        // Place player 4 squares away (beyond audio threshold)
        remotePlayers['remote-1'] = PlayerComponent(
          position: Vector2(288, 160), // 4 away
          id: 'remote-1',
          displayName: 'Remote',
        );

        manager.update(0.016);

        verifyNever(() =>
            mockLiveKit.setParticipantAudioEnabled('remote-1', true));
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
  });
}

/// Sentinel `PositionComponent` subclass for the unknown-fallback test.
/// Not a bubble type BubbleManager knows about — exactly the case the
/// switch's wildcard arm should handle.
class _SentinelBubble extends PositionComponent {}
