import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart';
import 'package:tech_world/flame/shared/constants.dart';

/// A coding terminal station that players can interact with.
/// Renders as a dark rectangle with a green terminal prompt.
/// When [isCompleted] is true, renders with a gold border and checkmark.
/// Tap triggers [onInteract] callback.
class TerminalComponent extends PositionComponent with TapCallbacks {
  TerminalComponent({
    required Vector2 position,
    required this.onInteract,
    this.isCompleted = false,
  }) : super(
          position: position,
          size: Vector2.all(gridSquareSizeDouble),
          anchor: Anchor.topLeft,
        );

  final void Function() onInteract;

  /// Whether the challenge at this terminal has been completed.
  bool isCompleted;

  static final _bgPaint = Paint()..color = const Color(0xFF1A1A2E);
  static final _borderPaint = Paint()
    ..color = const Color(0xFF00FF41)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  static final _completedBorderPaint = Paint()
    ..color = const Color(0xFFFFD700)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  static final _promptStyle = ui.TextStyle(
    color: const Color(0xFF00FF41),
    fontSize: 14,
    fontWeight: FontWeight.bold,
  );
  static final _checkmarkStyle = ui.TextStyle(
    color: const Color(0xFFFFD700),
    fontSize: 12,
    fontWeight: FontWeight.bold,
  );

  @override
  void render(Canvas canvas) {
    // Dark background
    final rect = Rect.fromLTWH(2, 2, size.x - 4, size.y - 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      _bgPaint,
    );

    // Border — gold when completed, green otherwise
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      isCompleted ? _completedBorderPaint : _borderPaint,
    );

    // Center text — checkmark when completed, terminal prompt otherwise
    final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center,
    ))
      ..pushStyle(isCompleted ? _checkmarkStyle : _promptStyle)
      ..addText(isCompleted ? '\u2714' : '>_');
    final paragraph = paragraphBuilder.build()
      ..layout(ui.ParagraphConstraints(width: size.x));
    canvas.drawParagraph(paragraph, Offset(0, (size.y - 16) / 2));
  }

  @override
  void onTapDown(TapDownEvent event) {
    onInteract();
  }
}
