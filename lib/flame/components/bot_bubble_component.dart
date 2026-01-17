import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:tech_world/flame/shared/tech_world_config.dart';

/// A Flame component that renders a circular bubble with an initial above a player.
/// This is rendered in the game world so it moves correctly with the camera.
class BotBubbleComponent extends PositionComponent {
  BotBubbleComponent({
    required this.name,
    required this.target,
    this.bubbleSize = 80,
  }) : super(
          size: Vector2.all(bubbleSize),
          anchor: Anchor.bottomCenter,
        );

  final String name;
  final double bubbleSize;

  /// The component this bubble follows.
  final PositionComponent target;

  @override
  void update(double dt) {
    super.update(dt);
    position = target.position + TechWorldConfig.bubbleOffset;
  }

  @override
  void render(Canvas canvas) {
    final center = Offset(size.x / 2, size.y / 2);
    final radius = bubbleSize / 2;

    // Draw shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center + const Offset(0, 2), radius, shadowPaint);

    // Draw background circle
    final bgPaint = Paint()..color = Colors.blueGrey[700]!;
    canvas.drawCircle(center, radius, bgPaint);

    // Draw border
    final borderPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, borderPaint);

    // Draw initial
    final textPainter = TextPainter(
      text: TextSpan(
        text: name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          color: Colors.white,
          fontSize: bubbleSize * 0.4,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }
}
