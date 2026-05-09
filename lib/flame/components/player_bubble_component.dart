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

  double _opacity = 1.0;

  /// Set the opacity for distance-based fading (0.0 to 1.0).
  set opacity(double value) => _opacity = value.clamp(0.0, 1.0);

  // ── Cached Paints (Flyweight) ───────────────────────────────────────────

  late final Paint _shadowPaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.3)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

  late final Paint _bgPaint = Paint()..color = Colors.grey[800]!;

  late final Paint _borderPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  final Paint _layerPaint = Paint();

  // ── Cached TextPainter ──────────────────────────────────────────────────

  late final TextPainter _initialPainter = TextPainter(
    text: TextSpan(
      text: _getInitial(),
      style: TextStyle(
        color: Colors.white,
        fontSize: bubbleSize * 0.4,
        fontWeight: FontWeight.bold,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void onRemove() {
    _initialPainter.dispose();
    super.onRemove();
  }

  @override
  void render(Canvas canvas) {
    if (_opacity <= 0) return;

    final center = Offset(size.x / 2, size.y / 2);
    final radius = bubbleSize / 2;

    // Apply opacity via saveLayer when not fully opaque
    if (_opacity < 1.0) {
      _layerPaint.color =
          Color.fromARGB((_opacity * 255).round(), 255, 255, 255);
      canvas.saveLayer(
        Rect.fromCircle(center: center, radius: radius + 5),
        _layerPaint,
      );
    }

    // Draw shadow
    canvas.drawCircle(center + const Offset(0, 2), radius, _shadowPaint);

    // Draw background circle
    canvas.drawCircle(center, radius, _bgPaint);

    // Draw border
    canvas.drawCircle(center, radius, _borderPaint);

    // Draw initial
    _initialPainter.paint(
      canvas,
      Offset(
        center.dx - _initialPainter.width / 2,
        center.dy - _initialPainter.height / 2,
      ),
    );

    if (_opacity < 1.0) {
      canvas.restore();
    }
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
