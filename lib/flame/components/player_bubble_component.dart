import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// A Flame component that renders a circular bubble with a player's initial.
/// This is rendered in the game world so it moves correctly with the camera.
class PlayerBubbleComponent extends PositionComponent {
  PlayerBubbleComponent({
    required this.displayName,
    required this.playerId,
    this.bubbleSize = 48,
  }) : super(
          size: Vector2.all(bubbleSize),
          anchor: Anchor.bottomCenter,
        );

  final String displayName;
  final String playerId;
  final double bubbleSize;

  @override
  void render(Canvas canvas) {
    final center = Offset(size.x / 2, size.y / 2);
    final radius = bubbleSize / 2;

    // Draw shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(center + const Offset(0, 2), radius, shadowPaint);

    // Draw background circle
    final bgPaint = Paint()..color = Colors.grey[800]!;
    canvas.drawCircle(center, radius, bgPaint);

    // Draw border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, borderPaint);

    // Draw initial
    final textPainter = TextPainter(
      text: TextSpan(
        text: _getInitial(),
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

  String _getInitial() {
    if (displayName.isNotEmpty) {
      return displayName[0].toUpperCase();
    }
    if (playerId.isNotEmpty) {
      return playerId[0].toUpperCase();
    }
    return '?';
  }
}
