import 'package:flame/components.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/types.dart';
import 'package:tech_world/flame/bubble_manager.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/preferences/user_preferences.dart';

class MockLiveKitService extends Mock implements LiveKitService {}

/// Acceptance spec for the "Proximity range" preference.
///
/// Before this suite, the preference was dark: `ProximityService` held the
/// user's value and nothing in `lib/` ever called it, while [BubbleManager]
/// gated on a hardcoded 5. Setting the slider to 0 still formed bubbles at
/// ≤5 squares. These tests pin the preference to the gate that actually
/// governs what the player sees and hears.
void main() {
  // Grid squares are 32px, so grid (5,5) is pixel (160,160).
  PlayerComponent playerAt(int gx, int gy, String id) => PlayerComponent(
        position: Vector2(gx * 32.0, gy * 32.0),
        id: id,
        displayName: id,
      );

  late List<Component> added;
  late Map<String, PlayerComponent> remotePlayers;
  late MockLiveKitService liveKit;
  late ValueNotifier<bool> silenced;

  BubbleManager managerWithRadius(int radius) {
    final manager = BubbleManager(
      localPlayer: playerAt(5, 5, 'local-user'),
      addComponent: added.add,
      remotePlayers: remotePlayers,
      bots: {},
      proximityRadius: radius,
    );
    manager.setLiveKitService(liveKit);
    return manager;
  }

  setUp(() {
    added = [];
    remotePlayers = {};
    silenced = ValueNotifier<bool>(false);
    liveKit = MockLiveKitService();
    when(() => liveKit.dreamfinderSilenced).thenReturn(silenced);
    when(() => liveKit.getParticipant(any())).thenReturn(null);
    when(() => liveKit.dreamfinderIdentities()).thenReturn(const <String>[]);
    when(() => liveKit.setParticipantAudioEnabled(any(), any()))
        .thenReturn(null);
    when(() => liveKit.setParticipantAudioVolume(any(), any()))
        .thenReturn(true);
    when(() => liveKit.publishDfProximity(near: any(named: 'near')))
        .thenAnswer((_) async {});
  });

  tearDown(() => silenced.dispose());

  group('visual gate tracks the preference', () {
    test('radius 0 forms no bubble even for a co-located player', () {
      // The bug, stated as a test: the slider at 0 is documented as "no player
      // ever becomes nearby, so video bubbles never form". Distance 0 is the
      // sharpest case — a plain `distance <= radius` check would still match.
      remotePlayers['remote-1'] = playerAt(5, 5, 'remote-1'); // distance 0

      managerWithRadius(0).update(0.016);

      expect(added, isEmpty);
    });

    test('bubble forms at exactly the radius and not one square beyond', () {
      remotePlayers['at-edge'] = playerAt(7, 5, 'at-edge'); // distance 2
      remotePlayers['past-edge'] = playerAt(8, 5, 'past-edge'); // distance 3

      managerWithRadius(2).update(0.016);

      // The edge peer's bubble + the local player's own bubble. The peer one
      // square past the radius contributes nothing.
      expect(added, hasLength(2));
    });

    test('a wider radius reaches a peer the default would not', () {
      remotePlayers['far'] = playerAt(11, 5, 'far'); // distance 6

      managerWithRadius(6).update(0.016);

      expect(added, hasLength(2));
    });
  });

  group('audio gate derives from the preference', () {
    test('audio enables one square inside the radius, preserving hysteresis',
        () {
      // Radius 3 → enable at ≤2, disable only past 3. A peer at exactly 3 is
      // inside the hysteresis band: visible, but not yet audible.
      remotePlayers['band'] = playerAt(8, 5, 'band'); // distance 3

      managerWithRadius(3).update(0.016);

      verifyNever(() => liveKit.setParticipantAudioEnabled('band', true));
    });

    test('audio enables inside the derived enable threshold', () {
      remotePlayers['close'] = playerAt(7, 5, 'close'); // distance 2

      managerWithRadius(3).update(0.016);

      verify(() => liveKit.setParticipantAudioEnabled('close', true)).called(1);
    });

    test('radius 0 never enables audio for anyone', () {
      remotePlayers['remote-1'] = playerAt(5, 5, 'remote-1'); // distance 0

      managerWithRadius(0).update(0.016);

      verifyNever(() => liveKit.setParticipantAudioEnabled(any(), true));
    });

    test('hysteresis band still holds state once enabled', () {
      final peer = playerAt(6, 5, 'peer'); // distance 1 → enabled
      remotePlayers['peer'] = peer;
      final manager = managerWithRadius(3);
      manager.update(0.016);
      verify(() => liveKit.setParticipantAudioEnabled('peer', true)).called(1);

      // Drift to distance 3: past enable (2) but not past disable (3) — hold.
      peer.position = Vector2(8 * 32.0, 5 * 32.0);
      manager.update(0.016);
      verifyNever(() => liveKit.setParticipantAudioEnabled('peer', false));

      // Distance 4: past the disable threshold → cut.
      peer.position = Vector2(9 * 32.0, 5 * 32.0);
      manager.update(0.016);
      verify(() => liveKit.setParticipantAudioEnabled('peer', false)).called(1);
    });
  });

  group('proximity membership events', () {
    late List<AppEvent> captured;

    setUp(() {
      captured = [];
      clearSinks();
      registerSink(captured.add);
    });

    tearDown(clearSinks);

    test('entering the radius dispatches PlayerEnteredProximity', () {
      final peer = playerAt(20, 20, 'peer'); // far away
      remotePlayers['peer'] = peer;
      final manager = managerWithRadius(3);
      manager.update(0.016);
      expect(captured.whereType<PlayerEnteredProximity>(), isEmpty);

      peer.position = Vector2(6 * 32.0, 5 * 32.0); // distance 1
      manager.update(0.016);

      expect(
        captured.whereType<PlayerEnteredProximity>().map((e) => e.playerId),
        equals(['peer']),
      );
    });

    test('leaving the radius dispatches PlayerLeftProximity exactly once', () {
      final peer = playerAt(6, 5, 'peer'); // distance 1
      remotePlayers['peer'] = peer;
      final manager = managerWithRadius(3);
      manager.update(0.016);

      peer.position = Vector2(20 * 32.0, 20 * 32.0); // gone
      manager.update(0.016);
      manager.update(0.016); // idle frame must not re-emit

      expect(
        captured.whereType<PlayerLeftProximity>().map((e) => e.playerId),
        equals(['peer']),
      );
    });

    test('a participant disappearing from the world dispatches a leave', () {
      remotePlayers['peer'] = playerAt(6, 5, 'peer');
      final manager = managerWithRadius(3);
      manager.update(0.016);

      remotePlayers.remove('peer'); // disconnected
      manager.update(0.016);

      expect(captured.whereType<PlayerLeftProximity>(), hasLength(1));
    });

    test('the local player sentinel is never reported as a participant', () {
      remotePlayers['peer'] = playerAt(6, 5, 'peer');
      managerWithRadius(3).update(0.016);

      // Two bubbles exist (peer + local), but only the peer is a participant.
      expect(
        captured.whereType<PlayerEnteredProximity>().map((e) => e.playerId),
        equals(['peer']),
      );
    });
  });

  group('preference default', () {
    test('the default radius matches the behaviour players see today', () {
      // Two sources disagreed: UserPreferences said 3 (ProximityService's old
      // default, never reachable) while BubbleManager gated on 5. 5 is what
      // every player actually experienced, so the live default preserves it —
      // shipping 3 would have silently shrunk everyone's world.
      expect(UserPreferences.defaultProximityRadius, equals(5));
      expect(
        BubbleManager.defaultProximityRadius,
        equals(UserPreferences.defaultProximityRadius),
      );
    });

    test('the slider max is reachable by the visual gate', () {
      expect(UserPreferences.maxProximityRadius,
          greaterThanOrEqualTo(UserPreferences.defaultProximityRadius));
    });
  });
}
