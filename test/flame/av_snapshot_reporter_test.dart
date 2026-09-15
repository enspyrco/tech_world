import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/diagnostics/diagnostics_service.dart';
import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/types.dart';
import 'package:tech_world/flame/av_snapshot_reporter.dart';
import 'package:tech_world/flame/components/bot_bubble_component.dart';
import 'package:tech_world/flame/components/bot_character_component.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/flame/components/player_bubble_component.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;

/// Sentinel bubble type the reporter has never heard of, for the
/// `AvBubbleType.unknown` fallback.
class _UnknownBubble extends PositionComponent {}

void main() {
  // Snapshot generation had NO test before this file existed:
  // `AvPipelineSnapshot` appeared in the suite only as a type inside the PII
  // and dispatch exhaustiveness switches, so nothing ever asserted a snapshot
  // was produced or that its fields were right. It only became testable when
  // it moved out of BubbleManager behind a private 5-second timer.

  const localKey = '_local_player_';

  late List<AppEvent> captured;
  late PlayerComponent localPlayer;
  late Map<String, PlayerComponent> remotePlayers;
  late Map<String, BotCharacterComponent> bots;
  late Map<String, PositionComponent> bubbles;
  late Set<String> audioEnabled;

  /// Builds a reporter over the shared fixtures. [avEnabled] is the null-arm
  /// control: false must produce exactly zero events.
  AvSnapshotReporter build({bool avEnabled = true}) => AvSnapshotReporter(
        diagnostics: DiagnosticsService(
          avEnabled: avEnabled,
          errorLoggingEnabled: true,
        ),
        localPlayer: localPlayer,
        remotePlayers: remotePlayers,
        bots: bots,
        bubbles: bubbles,
        audioEnabled: audioEnabled.contains,
        dreamfinder: () => null,
        dreamfinderIdentity: () => 'bot-dreamfinder',
        liveKitService: () => null,
        localBubbleKey: localKey,
      );

  List<AvPipelineSnapshot> snapshots() =>
      captured.whereType<AvPipelineSnapshot>().toList();

  setUp(() {
    captured = [];
    clearSinks();
    registerSink(captured.add);

    // Grid (5, 5) at 32px squares.
    localPlayer = PlayerComponent(
      position: Vector2(160, 160),
      id: 'local-user',
      displayName: 'Local',
    );
    remotePlayers = {};
    bots = {};
    bubbles = {};
    audioEnabled = {};
  });

  tearDown(clearSinks);

  group('AvSnapshotReporter — controls', () {
    test('disabled reporter emits nothing, however long it runs', () {
      remotePlayers['remote-1'] = PlayerComponent(
        position: Vector2(256, 160),
        id: 'remote-1',
        displayName: 'Remote',
      );
      final reporter = build(avEnabled: false);

      // Ten intervals' worth of frames.
      for (var i = 0; i < 10; i++) {
        reporter.update(AvSnapshotReporter.snapshotIntervalSeconds);
      }

      expect(reporter.enabled, isFalse);
      expect(snapshots(), isEmpty);
    });

    test('enabled reporter emits on the same input — the arm that must go red',
        () {
      remotePlayers['remote-1'] = PlayerComponent(
        position: Vector2(256, 160),
        id: 'remote-1',
        displayName: 'Remote',
      );

      build().update(AvSnapshotReporter.snapshotIntervalSeconds);

      expect(snapshots(), isNotEmpty);
    });
  });

  group('AvSnapshotReporter — timing', () {
    test('holds off until the interval elapses, then fires once', () {
      final reporter = build();

      // One frame short of the interval.
      reporter.update(AvSnapshotReporter.snapshotIntervalSeconds - 0.1);
      expect(snapshots(), isEmpty,
          reason: 'fired before the interval elapsed');

      reporter.update(0.1);
      final afterFirst = snapshots().length;
      expect(afterFirst, greaterThan(0));

      // Timer resets — the next frame must not re-fire.
      reporter.update(0.016);
      expect(snapshots().length, equals(afterFirst));
    });
  });

  group('AvSnapshotReporter — coverage of participants', () {
    test('emits one snapshot per remote player, bot, and the local player',
        () {
      remotePlayers['remote-1'] = PlayerComponent(
        position: Vector2(256, 160),
        id: 'remote-1',
        displayName: 'Remote',
      );
      bots['bot-claude'] = BotCharacterComponent(
        position: Vector2(192, 160),
        id: 'bot-claude',
        displayName: 'Clawd',
      );

      build().dispatchSnapshots();

      expect(
        snapshots().map((s) => s.participant).toSet(),
        equals({'remote-1', 'bot-claude', localKey}),
      );
      expect(snapshots().where((s) => s.isLocal).length, equals(1));
    });

    test('reports distance out of visual range, not just inside it', () {
      // Beyond any plausible proximity radius. The reporter is an observer,
      // not a gate — it must describe far participants too, otherwise the
      // diagnostic stream goes silent exactly when someone is debugging a
      // "why can't I see them" problem.
      remotePlayers['far'] = PlayerComponent(
        position: Vector2(160 + 32 * 12, 160),
        id: 'far',
        displayName: 'Far',
      );

      build().dispatchSnapshots();

      final far = snapshots().firstWhere((s) => s.participant == 'far');
      expect(far.distance, equals(12));
    });

    test('local player snapshot reports distance 0', () {
      build().dispatchSnapshots();
      expect(snapshots().single.distance, equals(0));
      expect(snapshots().single.isLocal, isTrue);
    });
  });

  group('AvSnapshotReporter — field derivation', () {
    test('audioEnabled mirrors the live set it was handed', () {
      remotePlayers['remote-1'] = PlayerComponent(
        position: Vector2(256, 160),
        id: 'remote-1',
        displayName: 'Remote',
      );
      final reporter = build();

      reporter.dispatchSnapshots();
      expect(
        snapshots().firstWhere((s) => s.participant == 'remote-1').audioEnabled,
        isFalse,
      );

      // Mutating the set after construction must be visible — the reporter
      // holds the reference, not a copy.
      captured.clear();
      audioEnabled.add('remote-1');
      reporter.dispatchSnapshots();
      expect(
        snapshots().firstWhere((s) => s.participant == 'remote-1').audioEnabled,
        isTrue,
      );
    });

    test('bubbleType is null with no bubble, and classified when present', () {
      remotePlayers['remote-1'] = PlayerComponent(
        position: Vector2(256, 160),
        id: 'remote-1',
        displayName: 'Remote',
      );
      final reporter = build();

      reporter.dispatchSnapshots();
      expect(
        snapshots().firstWhere((s) => s.participant == 'remote-1').bubbleType,
        isNull,
      );

      captured.clear();
      bubbles['remote-1'] = PlayerBubbleComponent(
        playerId: 'remote-1',
        displayName: 'Remote',
      );
      reporter.dispatchSnapshots();
      expect(
        snapshots().firstWhere((s) => s.participant == 'remote-1').bubbleType,
        equals(AvBubbleType.player),
      );
    });

    test('hasVideoTrack is false when no LiveKit service is attached', () {
      remotePlayers['remote-1'] = PlayerComponent(
        position: Vector2(256, 160),
        id: 'remote-1',
        displayName: 'Remote',
      );

      build().dispatchSnapshots();

      expect(
        snapshots().firstWhere((s) => s.participant == 'remote-1').hasVideoTrack,
        isFalse,
      );
    });
  });

  group('AvSnapshotReporter.classifyBubble', () {
    test('maps the three known bubble types', () {
      expect(
        AvSnapshotReporter.classifyBubble(
            PlayerBubbleComponent(playerId: 'p', displayName: 'P')),
        equals(AvBubbleType.player),
      );
      expect(
        AvSnapshotReporter.classifyBubble(
            BotBubbleComponent(botStatus: ValueNotifier(BotStatus.idle))),
        equals(AvBubbleType.bot),
      );
    });

    test('falls back to unknown rather than misreporting as player', () {
      expect(
        AvSnapshotReporter.classifyBubble(_UnknownBubble()),
        equals(AvBubbleType.unknown),
      );
    });
  });
}
