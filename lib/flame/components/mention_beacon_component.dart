import 'dart:math' show cos, pi, sin;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';
import 'package:tech_world/flame/mention/mention_pulse_controller.dart';

// ── Tunable feel ─────────────────────────────────────────────────────────────
// All visual constants live here so Nick can tune the look LIVE after merge.
// The STRUCTURE/WIRE/STATE below is correct; these numbers are the dials.

/// How long the initial expanding bloom lasts before settling into the slow
/// public pulse. Purely cosmetic onset.
const Duration kMentionBloomDuration = Duration(milliseconds: 2500);

/// Radius (px) the beacon ring reaches at the peak of the bloom.
const double kMentionBloomMaxRadius = 46.0;

/// Resting radius (px) the slow public pulse oscillates around once settled.
const double kMentionPulseBaseRadius = 26.0;

/// Peak extra radius (px) added at the top of each slow-pulse breath.
const double kMentionPulseAmplitude = 5.0;

/// Seconds per slow-pulse breath while a mention waits to be acknowledged.
const double kMentionPulsePeriodSeconds = 1.6;

/// Number of soft lobes around the ring (organic, non-circular edge).
const int kMentionRippleLobes = 6;

/// Edge wobble amplitude (px) of the lobes.
const double kMentionRippleAmplitude = 2.5;

/// The beacon's colour. A warm gold/amber so it reads as "someone called you",
/// distinct from the green speaking-glow on video bubbles.
const Color kMentionColor = Color(0xFFFFC247);

/// Whether to draw the floating name label during the bloom.
const bool kMentionShowNameLabel = true;

/// Vertical offset (px, local space) of the name label above the avatar.
const double kMentionLabelOffsetY = -54.0;

// ─────────────────────────────────────────────────────────────────────────────

/// A world beacon that blooms on a player's AVATAR when they are `@mention`ed
/// in chat — witnessed by everyone in the room.
///
/// **Why the avatar, not the video bubble:** video bubbles are proximity-gated
/// and hideable, but a mention crosses the whole room to someone you may be
/// nowhere near. The avatar ([PlayerComponent]) is always present at the
/// player's world position, so the beacon is attached as a CHILD of it and
/// auto-follows movement.
///
/// It is purely a *view* of [MentionPulseController]: it owns no lifecycle
/// state. While the controller reports [MentionPulseController.isPulsing] for
/// [mentionedUid] it renders — first an expanding bloom + name label, then a
/// slow public pulse — and it removes itself when the pulse stops (ack or
/// timeout). The ripple/glow technique is lifted from
/// `video_bubble_component.dart` (the lobed [_buildRingPath] + the
/// [MaskFilter.blur] glow pulse) so the two read as the same visual family.
class MentionBeaconComponent extends PositionComponent {
  MentionBeaconComponent({
    required this.mentionedUid,
    required this.controller,
    required this.displayName,
    required this.reduceMotion,
    Vector2? localCenter,
  }) : _localCenter = localCenter ?? Vector2(16, 32) {
    // Cover the avatar; positioned by the parent's local coordinate space.
    anchor = Anchor.topLeft;
    position = Vector2.zero();
  }

  /// UID of the player this beacon belongs to — its key into [controller].
  final String mentionedUid;

  /// The shared pulse-state machine. Read-only here.
  final MentionPulseController controller;

  /// Cosmetic label shown during the bloom ("Alice").
  final String displayName;

  /// Honour the accessibility preference: when true, the bloom snaps to its
  /// final ring and the slow pulse / ripple hold still (no animation).
  final bool reduceMotion;

  /// Where, in the parent avatar's local space, the beacon centres. Defaults to
  /// the middle of the 32×64 sprite.
  final Vector2 _localCenter;

  double _time = 0;

  static final Paint _glowPaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
  static final Paint _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;

  ui.Paragraph? _labelParagraph;

  @override
  Future<void> onLoad() async {
    if (kMentionShowNameLabel && displayName.isNotEmpty) {
      _labelParagraph = _buildLabel(displayName);
    }
  }

  /// Whether this beacon is still wanted — exposed so a test can assert the
  /// view follows the controller's lifecycle.
  bool get active => controller.isPulsing(mentionedUid);

  @override
  void update(double dt) {
    _time += dt;
    // Self-remove once the controller stops pulsing this player (ack/timeout).
    if (!active) {
      removeFromParent();
    }
  }

  /// Progress through the bloom phase, 0→1, clamped. 1.0 means settled into the
  /// slow public pulse. With reduce-motion the bloom is instantaneous.
  double get _bloomProgress {
    if (reduceMotion) return 1.0;
    final t = _time / (kMentionBloomDuration.inMilliseconds / 1000.0);
    return t.clamp(0.0, 1.0);
  }

  @override
  void render(Canvas canvas) {
    final center = Offset(_localCenter.x, _localCenter.y);
    final bloom = _bloomProgress;

    final double radius;
    final double alpha;
    if (bloom < 1.0) {
      // Bloom: a ring expanding outward, brightest at onset, easing to rest.
      radius = kMentionPulseBaseRadius +
          (kMentionBloomMaxRadius - kMentionPulseBaseRadius) * bloom;
      alpha = 0.85 * (1.0 - bloom) + 0.5 * bloom;
    } else {
      // Settled: a slow public pulse around the resting radius.
      final breath = reduceMotion
          ? 0.0
          : sin(_time * (2 * pi / kMentionPulsePeriodSeconds));
      radius = kMentionPulseBaseRadius + kMentionPulseAmplitude * breath;
      alpha = 0.45 + 0.15 * (reduceMotion ? 0.0 : breath);
    }

    // Soft radial glow under the ring.
    _glowPaint.color = kMentionColor.withValues(alpha: 0.4 * alpha);
    canvas.drawCircle(center, radius, _glowPaint);

    // Lobed ring on top (the organic ripple edge from the video bubble).
    _ringPaint.color = kMentionColor.withValues(alpha: alpha.clamp(0.0, 1.0));
    canvas.drawPath(_buildRingPath(center, radius), _ringPaint);

    // Name label during the bloom only.
    if (bloom < 1.0) {
      final label = _labelParagraph;
      if (label != null) {
        canvas.drawParagraph(
          label,
          Offset(center.dx - label.width / 2, center.dy + kMentionLabelOffsetY),
        );
      }
    }
  }

  /// A circle with soft animated lobes — the same two-wave technique as
  /// `VideoBubbleComponent._buildBubblePath`, so the beacon edge ripples like
  /// the speaking bubble rather than being a hard circle.
  Path _buildRingPath(Offset center, double radius) {
    if (reduceMotion) {
      return Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    }
    final path = Path();
    const segments = 64;
    for (int i = 0; i <= segments; i++) {
      final angle = (i / segments) * 2.0 * pi;
      final wave1 =
          sin(angle * kMentionRippleLobes + _time * 5.0) * kMentionRippleAmplitude;
      final wave2 =
          sin(angle * (kMentionRippleLobes + 3) - _time * 3.0) *
              kMentionRippleAmplitude *
              0.4;
      final r = radius + wave1 + wave2;
      final x = center.dx + cos(angle) * r;
      final y = center.dy + sin(angle) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  ui.Paragraph _buildLabel(String name) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: 11,
      fontWeight: FontWeight.bold,
    ))
      ..pushStyle(ui.TextStyle(color: kMentionColor))
      ..addText(name);
    return builder.build()
      ..layout(const ui.ParagraphConstraints(width: 120));
  }
}
