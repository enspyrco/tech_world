import 'dart:ui';

import 'package:flame/components.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/shared/dreamfinder_territory.dart';

/// Draws Dreamfinder's territory — the square he wanders in and the only place
/// he can hear you.
///
/// This is deliberately an *affordance*, not decoration: the glowing box tells
/// players "stand in the light to talk to Dreamfinder". It reads the same
/// resolved [TerritoryRect] the bot uses to gate audio, so what you see is
/// exactly where you're heard.
///
/// Rendered beneath characters (see [_kTerritoryPriority]) and static — no
/// animation, so it costs nothing per frame and needs no reduce-motion gate.
class DreamfinderTerritoryComponent extends PositionComponent {
  DreamfinderTerritoryComponent({required TerritoryRect territory})
      : super(
          position: Vector2(
            territory.minX * gridSquareSizeDouble,
            territory.minY * gridSquareSizeDouble,
          ),
          size: Vector2(
            (territory.maxX - territory.minX + 1) * gridSquareSizeDouble,
            (territory.maxY - territory.minY + 1) * gridSquareSizeDouble,
          ),
          priority: _kTerritoryPriority,
        );

  /// Low priority so the zone renders above the floor but beneath every
  /// character (characters compute a large y-based priority in `update`).
  static const int _kTerritoryPriority = 1;

  /// Warm "hearth" amber — a place that gathers and listens.
  static const _fillColor = Color(0x14FFC15E); // alpha ~0.08
  static const _borderColor = Color(0x59FFC15E); // alpha ~0.35

  static final _fillPaint = Paint()..color = _fillColor;
  static final _borderPaint = Paint()
    ..color = _borderColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final rrect =
        RRect.fromRectAndRadius(rect, const Radius.circular(8.0));
    canvas.drawRRect(rrect, _fillPaint);
    canvas.drawRRect(rrect, _borderPaint);
  }
}
