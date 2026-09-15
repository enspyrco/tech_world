import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart' show Color, Colors;
import 'package:livekit_client/livekit_client.dart';
import 'package:logging/logging.dart';

import 'package:tech_world/bots/bot_config.dart';
import 'package:tech_world/flame/av_snapshot_reporter.dart';
import 'package:tech_world/flame/components/bot_bubble_component.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/flame/components/player_bubble_component.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:tech_world/flame/components/video_bubble_component.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/native/frame_source.dart';

final _log = Logger('BubbleFactory');

/// Builds proximity bubbles. Construction only — it decides what a bubble
/// LOOKS like, never when one should appear, be replaced or be removed.
///
/// That line is the point of the split. Bubble lifecycle stays with
/// `BubbleManager`, which is the single writer of the bubble map; this decides
/// which of three shapes to hand back when the manager has already decided a
/// bubble is needed.
///
/// The video-or-avatar decision was previously written out twice, once for
/// remote players and once for the local one, differing only in where the
/// participant comes from and what colour it glows. It is one code path here.
class BubbleFactory {
  BubbleFactory({
    required bool Function() hideVideoBubbles,
    required bool Function() reduceMotion,
    required LiveKitService? Function() liveKitService,
    required FrameSource? Function() dreamfinderCapture,
    required ValueListenable<BotStatus> Function() botStatus,
    required bool isMobileWeb,
  })  : _hideVideoBubbles = hideVideoBubbles,
        _reduceMotion = reduceMotion,
        _liveKitService = liveKitService,
        _dreamfinderCapture = dreamfinderCapture,
        _botStatus = botStatus,
        _isMobileWeb = isMobileWeb;

  final bool Function() _hideVideoBubbles;
  final bool Function() _reduceMotion;
  final LiveKitService? Function() _liveKitService;
  final FrameSource? Function() _dreamfinderCapture;
  final ValueListenable<BotStatus> Function() _botStatus;
  final bool _isMobileWeb;

  static const double _bubbleSize = 64;
  static const int _peerTargetFps = 15;

  /// Dreamfinder renders a WebGL canvas rather than a camera, and is cheaper to
  /// sample less often.
  static const int _dreamfinderTargetFps = 10;

  static const Color _dreamfinderGold = Color(0xFFDAA520);

  ui.FragmentProgram? _shaderProgram;

  Future<void> loadShader() async {
    try {
      _shaderProgram =
          await ui.FragmentProgram.fromAsset('shaders/video_bubble.frag');
    } catch (e) {
      // A missing shader degrades to an unshaded bubble, never a crash.
      _log.warning('Video bubble shader failed to load', e);
    }
  }

  void disposeShader() => _shaderProgram = null;

  /// Whether Dreamfinder can be shown as a video bubble at all on this client.
  ///
  /// Mobile web renders the embodied WebGL bubble black, so DF stays a 2D
  /// sprite there. Exposed because the manager needs the same answer when
  /// deciding whether an *existing* DF bubble is worth upgrading.
  bool get canEmbodyDreamfinder => !_hideVideoBubbles() && !_isMobileWeb;

  /// A bubble for a remote player: video when they have a live track and video
  /// bubbles are enabled, otherwise their avatar.
  PositionComponent forRemotePlayer(
      String playerId, PlayerComponent playerComponent) {
    final participant = _liveKitService()?.getParticipant(playerId);
    final video = _videoBubbleIfPossible(
      participant: participant,
      displayName: playerComponent.displayName,
    );
    if (video != null) return video;

    return PlayerBubbleComponent(
      displayName: playerComponent.displayName,
      playerId: playerId,
    );
  }

  /// A bubble for the local player. Same decision as [forRemotePlayer], with
  /// the local participant as the source and a cyan glow so you can pick
  /// yourself out of a huddle.
  PositionComponent forLocalPlayer(PlayerComponent localPlayer) {
    final participant = _liveKitService()?.localParticipant;
    final video = _videoBubbleIfPossible(
      participant: participant,
      displayName: localPlayer.displayName,
    );
    if (video != null) {
      _log.fine('Creating local VideoBubbleComponent');
      video.glowColor = Colors.cyan;
      return video;
    }

    return PlayerBubbleComponent(
      displayName: localPlayer.displayName,
      playerId: localPlayer.id,
    );
  }

  /// Dreamfinder's embodied bubble, fed by the avatar iframe's canvas rather
  /// than a camera track.
  VideoBubbleComponent forDreamfinder(Participant participant) {
    return VideoBubbleComponent(
      participant: participant,
      displayName: dreamfinderBot.displayName,
      bubbleSize: _bubbleSize,
      targetFps: _dreamfinderTargetFps,
      externalVideoCapture: _dreamfinderCapture(),
      reduceMotion: _reduceMotion(),
    )
      ..glowColor = _dreamfinderGold
      ..glowIntensity = 0.7;
  }

  /// A status bubble for a bot (including Dreamfinder when it is not embodied).
  ///
  /// [bubbleSize] defaults to `BotBubbleComponent`'s own 48. The downgrade path
  /// passes 64 — that discrepancy predates this class and is preserved rather
  /// than quietly normalised here; see the tracker issue.
  BotBubbleComponent forBot({double? bubbleSize}) => bubbleSize == null
      ? BotBubbleComponent(botStatus: _botStatus())
      : BotBubbleComponent(botStatus: _botStatus(), bubbleSize: bubbleSize);

  /// A static avatar bubble, for downgrading a video bubble whose track went
  /// away.
  PlayerBubbleComponent staticFor(String playerId, String displayName) =>
      PlayerBubbleComponent(displayName: displayName, playerId: playerId);

  /// The shared video-or-nothing decision. Returns null when a video bubble is
  /// not possible, leaving the caller to pick its own fallback.
  VideoBubbleComponent? _videoBubbleIfPossible({
    required Participant? participant,
    required String displayName,
  }) {
    if (_hideVideoBubbles()) return null;
    if (participant == null) return null;
    if (!AvSnapshotReporter.hasVideoTrack(participant)) return null;

    final bubble = VideoBubbleComponent(
      participant: participant,
      displayName: displayName,
      bubbleSize: _bubbleSize,
      targetFps: _peerTargetFps,
      reduceMotion: _reduceMotion(),
    );
    if (_shaderProgram != null) {
      bubble.setShader(_shaderProgram!.fragmentShader());
    }
    return bubble;
  }
}
