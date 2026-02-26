import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:tech_world/flame/components/bot_status.dart';

/// A Flame component that renders a status indicator above the bot character.
/// Shows animated bouncing dots when thinking, hidden when idle.
class BotBubbleComponent extends PositionComponent {
  BotBubbleComponent({
    this.bubbleSize = 48,
  }) : super(
          size: Vector2.all(bubbleSize),
          anchor: Anchor.bottomCenter,
        );

  final double bubbleSize;

  // Clawd's orange color
  static const clawdOrange = Color(0xFFD97757);

  // Animation state
  double _animationTime = 0;
  BotStatus _currentStatus = BotStatus.idle;

  // Dot animation parameters
  static const _dotCount = 3;
  static const _cycleDuration = 0.5; // seconds per cycle
  static const _phaseOffset = 0.15; // seconds between each dot

  @override
  void onMount() {
    super.onMount();
    _currentStatus = botStatusNotifier.value;
    botStatusNotifier.addListener(_onStatusChanged);
  }

  @override
  void onRemove() {
    botStatusNotifier.removeListener(_onStatusChanged);
    super.onRemove();
  }

  void _onStatusChanged() {
    _currentStatus = botStatusNotifier.value;
    _animationTime = 0; // Reset animation
  }

  @override
  void update(double dt) {
    super.update(dt);
    _animationTime += dt;
  }

  @override
  void render(Canvas canvas) {
    switch (_currentStatus) {
      case BotStatus.absent:
        return; // Nothing to render when bot is absent.
      case BotStatus.idle:
        _renderSleepingZzz(canvas);
      case BotStatus.thinking:
        _renderThinkingDots(canvas);
    }
  }

  void _renderSleepingZzz(Canvas canvas) {
    // Animated floating z's rising from center
    const zCount = 3;
    const cycleDuration = 1.5; // seconds for full cycle

    final centerX = size.x / 2;
    final baseY = size.y * 0.8;

    for (int i = 0; i < zCount; i++) {
      // Stagger each z's animation phase
      final phase = ((_animationTime / cycleDuration) + (i * 0.33)) % 1.0;

      // Float upward
      final yOffset = -phase * bubbleSize * 0.8;
      // Drift right as they rise
      final xOffset = (i - 1) * 10.0 + (phase * 6);
      // Fade in then out (peak at 0.5)
      final opacity = phase < 0.5
          ? (phase * 2.0)
          : (1.0 - (phase - 0.5) * 2.0);
      // Each successive z is slightly bigger
      final scale = 0.7 + (i * 0.15);

      final fontSize = bubbleSize * 0.3 * scale;

      final textPainter = TextPainter(
        text: TextSpan(
          text: 'z',
          style: TextStyle(
            color: clawdOrange.withValues(alpha: opacity.clamp(0.2, 1.0)),
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            fontStyle: FontStyle.italic,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final x = centerX + xOffset - (textPainter.width / 2);
      final y = baseY + yOffset;

      textPainter.paint(canvas, Offset(x, y));
    }
  }

  void _renderThinkingDots(Canvas canvas) {
    final center = Offset(size.x / 2, size.y / 2);
    final pillWidth = bubbleSize * 0.85;
    final pillHeight = bubbleSize * 0.45;
    final dotRadius = pillHeight * 0.25;
    final dotSpacing = pillWidth / (_dotCount + 1);

    // Draw shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center + const Offset(0, 2),
          width: pillWidth,
          height: pillHeight,
        ),
        Radius.circular(pillHeight / 2),
      ),
      shadowPaint,
    );

    // Draw pill background
    final bgPaint = Paint()..color = const Color(0xFF2D2D2D);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: pillWidth, height: pillHeight),
        Radius.circular(pillHeight / 2),
      ),
      bgPaint,
    );

    // Draw border
    final borderPaint = Paint()
      ..color = clawdOrange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: pillWidth, height: pillHeight),
        Radius.circular(pillHeight / 2),
      ),
      borderPaint,
    );

    // Draw animated dots
    final dotPaint = Paint()..color = clawdOrange;
    final startX = center.dx - (pillWidth / 2) + dotSpacing;

    for (int i = 0; i < _dotCount; i++) {
      // Calculate phase for this dot
      final phase = (_animationTime - (i * _phaseOffset)) / _cycleDuration;
      final normalizedPhase = phase - phase.floor(); // 0 to 1

      // Smooth bounce using sine wave
      final bounce = math.sin(normalizedPhase * math.pi);
      final scale = 0.6 + (0.4 * bounce); // Scale from 0.6 to 1.0
      final yOffset = -bounce * (pillHeight * 0.2); // Bounce up

      final dotX = startX + (i * dotSpacing);
      final dotY = center.dy + yOffset;

      canvas.drawCircle(
        Offset(dotX, dotY),
        dotRadius * scale,
        dotPaint,
      );
    }
  }
}
