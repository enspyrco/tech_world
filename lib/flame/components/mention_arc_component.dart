import 'dart:math' show pi, sin;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';
import 'package:tech_world/flame/components/mention_beacon_component.dart'
    show kMentionColor;

// ── Tunable feel ─────────────────────────────────────────────────────────────
/// How long the light arc lingers before fully fading. Cosmetic.
const Duration kMentionArcDuration = Duration(milliseconds: 1400);

/// Peak stroke width (px) of the arc thread at its brightest.
const double kMentionArcStrokeWidth = 3.0;

/// How high (px) the arc bows above the straight line between the two avatars.
const double kMentionArcBowHeight = 28.0;
// ─────────────────────────────────────────────────────────────────────────────

/// A brief light thread drawn from the mentioner's avatar to a named avatar
/// when an `@mention` lands — the "the call travelled across the room" beat.
///
/// Lives in the World (not as a child of either avatar) because it spans two
/// positions. It samples [from] / [to] each frame so it tracks if either avatar
/// drifts, fades over [kMentionArcDuration], then removes itself. Purely
/// cosmetic — it carries no state and no lifecycle authority; the bloom/pulse
/// on the named avatar is owned by `MentionPulseController`.
///
/// If either endpoint isn't present locally (the avatar isn't in the room or
/// hasn't spawned), the caller simply doesn't create the arc — degrade
/// gracefully, still bloom the named one if it's present.
class MentionArcComponent extends PositionComponent {
  MentionArcComponent({
    required this.from,
    required this.to,
  }) {
    anchor = Anchor.topLeft;
    position = Vector2.zero();
  }

  /// World-space position of the mentioner's avatar, sampled live each frame.
  final Vector2 Function() from;

  /// World-space position of the named avatar, sampled live each frame.
  final Vector2 Function() to;

  double _time = 0;

  /// Drawn above most world entities so the thread reads on top.
  @override
  int get priority => 1 << 20;

  static final Paint _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2);

  /// Progress 0→1 through the arc's lifetime.
  double get _progress =>
      (_time / (kMentionArcDuration.inMilliseconds / 1000.0)).clamp(0.0, 1.0);

  @override
  void update(double dt) {
    _time += dt;
    if (_progress >= 1.0) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final p = _progress;
    // Fade out over the lifetime; brightest at onset.
    final alpha = (1.0 - p).clamp(0.0, 1.0);
    if (alpha <= 0) return;

    final a = from();
    final b = to();
    // A quadratic bow so the thread arcs up over the room rather than a flat
    // line. Control point is the midpoint lifted by the bow height.
    final mid = Offset((a.x + b.x) / 2, (a.y + b.y) / 2 - kMentionArcBowHeight);

    final path = Path()
      ..moveTo(a.x, a.y)
      ..quadraticBezierTo(mid.dx, mid.dy, b.x, b.y);

    // A faint travelling brightness pulse along the thread as it fades.
    final shimmer = 0.6 + 0.4 * sin(_time * 2 * pi);
    _paint
      ..color = kMentionColor.withValues(alpha: alpha * shimmer)
      ..strokeWidth = kMentionArcStrokeWidth * alpha;
    canvas.drawPath(path, _paint);
  }
}
