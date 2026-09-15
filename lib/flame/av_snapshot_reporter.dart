import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:livekit_client/livekit_client.dart';

import 'package:tech_world/diagnostics/diagnostics_service.dart';
import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/types.dart';
import 'package:tech_world/flame/components/bot_bubble_component.dart';
import 'package:tech_world/flame/components/bot_character_component.dart';
import 'package:tech_world/flame/components/dreamfinder_component.dart';
import 'package:tech_world/flame/components/player_bubble_component.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:tech_world/flame/components/video_bubble_component.dart';
import 'package:tech_world/livekit/livekit_service.dart';

/// Periodic observer of the audio/video pipeline, emitting one
/// [AvPipelineSnapshot] per participant every [snapshotIntervalSeconds].
///
/// Read-only with respect to bubble state: it is handed the live collections
/// `BubbleManager` owns and never mutates them. That is what makes it safe to
/// run on a timer alongside the per-frame proximity pass — a reporter that
/// wrote to those maps would be a second owner of bubble lifecycle, which is
/// exactly the tangle this extraction exists to undo.
///
/// The mutable references (Dreamfinder component, LiveKit service, DF
/// identity) arrive on `BubbleManager` after construction, so they are read
/// through suppliers rather than captured — capturing them at construction
/// would freeze `null` for the whole session.
class AvSnapshotReporter {
  AvSnapshotReporter({
    required DiagnosticsService? diagnostics,
    required PlayerComponent localPlayer,
    required Map<String, PlayerComponent> remotePlayers,
    required Map<String, BotCharacterComponent> bots,
    required Map<String, PositionComponent> bubbles,
    required bool Function(String) audioEnabled,
    required DreamfinderComponent? Function() dreamfinder,
    required String Function() dreamfinderIdentity,
    required LiveKitService? Function() liveKitService,
    required String localBubbleKey,
  })  : _diagnostics = diagnostics,
        _localPlayer = localPlayer,
        _remotePlayers = remotePlayers,
        _bots = bots,
        _bubbles = bubbles,
        _audioEnabled = audioEnabled,
        _dreamfinder = dreamfinder,
        _dreamfinderIdentity = dreamfinderIdentity,
        _liveKitService = liveKitService,
        _localBubbleKey = localBubbleKey;

  /// Single owner of the AV-diagnostics toggle. Read via [enabled] — never via
  /// a shadow field. See `feedback_cross_cutting_toggle_needs_single_owner`.
  final DiagnosticsService? _diagnostics;

  final PlayerComponent _localPlayer;
  final Map<String, PlayerComponent> _remotePlayers;
  final Map<String, BotCharacterComponent> _bots;
  final Map<String, PositionComponent> _bubbles;
  final bool Function(String) _audioEnabled;
  final DreamfinderComponent? Function() _dreamfinder;
  final String Function() _dreamfinderIdentity;
  final LiveKitService? Function() _liveKitService;
  final String _localBubbleKey;

  static const double snapshotIntervalSeconds = 5.0;

  double _timer = 0;

  /// Whether AV pipeline diagnostic events should be generated. Computed from
  /// `_diagnostics.avEnabled.value` so there is no shadow field to drift out
  /// of sync.
  bool get enabled => _diagnostics?.avEnabled.value ?? false;

  /// Advance the snapshot timer, dispatching a round when it expires.
  ///
  /// Cheap when disabled: the timer does not accumulate, so re-enabling
  /// diagnostics mid-session does not immediately fire a backlogged round.
  void update(double dt) {
    if (!enabled) return;
    _timer += dt;
    if (_timer < snapshotIntervalSeconds) return;
    _timer = 0;
    dispatchSnapshots();
  }

  /// Emit one snapshot per known participant: every remote player, Dreamfinder
  /// if present, every bot, and the local player.
  @visibleForTesting
  void dispatchSnapshots() {
    final playerGrid = _localPlayer.miniGridPosition;
    final liveKit = _liveKitService();
    final events = <AppEvent>[];

    for (final entry in _remotePlayers.entries) {
      events.add(_snapshotFor(
        playerId: entry.key,
        bubble: _bubbles[entry.key],
        participant: liveKit?.getParticipant(entry.key),
        distance: _distance(playerGrid, entry.value.miniGridPosition),
        isLocal: false,
      ));
    }

    final df = _dreamfinder();
    if (df != null) {
      final dfId = _dreamfinderIdentity();
      events.add(_snapshotFor(
        playerId: dfId,
        bubble: _bubbles[dfId],
        participant: liveKit?.getParticipant(dfId),
        distance: _distance(playerGrid, df.miniGridPosition),
        isLocal: false,
      ));
    }

    for (final entry in _bots.entries) {
      events.add(_snapshotFor(
        playerId: entry.key,
        bubble: _bubbles[entry.key],
        participant: liveKit?.getParticipant(entry.key),
        distance: _distance(playerGrid, entry.value.miniGridPosition),
        isLocal: false,
      ));
    }

    // Local player snapshot (publish state). Emit the real LiveKit identity in
    // `participant` rather than the internal local-bubble sentinel — the
    // sentinel is a private map key, not a wire identity. `isLocal: true`
    // already disambiguates for consumers. Falls back to the sentinel only
    // when localParticipant has not yet attached.
    final localParticipant = liveKit?.localParticipant;
    events.add(_snapshotFor(
      playerId: localParticipant?.identity ?? _localBubbleKey,
      bubble: _bubbles[_localBubbleKey],
      participant: localParticipant,
      distance: 0,
      isLocal: true,
    ));

    if (events.isNotEmpty) dispatch(events);
  }

  static int _distance(Point<int> a, Point<int> b) =>
      max((a.x - b.x).abs(), (a.y - b.y).abs());

  AvPipelineSnapshot _snapshotFor({
    required String playerId,
    required PositionComponent? bubble,
    required Participant? participant,
    required int distance,
    required bool isLocal,
  }) {
    AvCaptureMethod? captureMethod;
    int captureRetryCount = 0;
    int framesCaptured = 0;
    int framesDropped = 0;

    if (bubble is VideoBubbleComponent) {
      captureMethod = bubble.diagnosticCaptureMethod;
      captureRetryCount = bubble.diagnosticCaptureRetryCount;
      framesCaptured = bubble.diagnosticFramesCaptured;
      framesDropped = bubble.diagnosticFramesDropped;
    }

    return AvPipelineSnapshot(
      participant: playerId,
      hasVideoTrack: participant != null && hasVideoTrack(participant),
      captureMethod: captureMethod,
      captureRetryCount: captureRetryCount,
      framesCaptured: framesCaptured,
      framesDropped: framesDropped,
      bubbleType: bubble == null ? null : classifyBubble(bubble),
      audioEnabled: _audioEnabled(playerId),
      distance: distance,
      isLocal: isLocal,
    );
  }

  /// Whether [participant] has a video track this client can actually render.
  ///
  /// A remote publication must be *subscribed*, not merely published — an
  /// unsubscribed track has no frames to draw. The local participant is exempt
  /// because it never subscribes to itself.
  static bool hasVideoTrack(Participant participant) {
    for (final publication in participant.videoTrackPublications) {
      if (publication.track == null) continue;
      if (participant is LocalParticipant) return true;
      if (publication.subscribed) return true;
    }
    return false;
  }

  /// Maps a bubble `PositionComponent` to its [AvBubbleType] for AV diagnostic
  /// events. The three known concrete bubble types map to their named enum
  /// values; anything else flows to [AvBubbleType.unknown] rather than
  /// silently being misreported as [AvBubbleType.player] (the pre-#466
  /// catch-all).
  static AvBubbleType classifyBubble(PositionComponent bubble) =>
      switch (bubble) {
        VideoBubbleComponent() => AvBubbleType.video,
        PlayerBubbleComponent() => AvBubbleType.player,
        BotBubbleComponent() => AvBubbleType.bot,
        _ => AvBubbleType.unknown,
      };
}
