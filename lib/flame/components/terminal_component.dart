import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart';
import 'package:tech_world/flame/shared/constants.dart';

/// A coding terminal station that players can interact with.
/// Renders as a dark rectangle with a green terminal prompt.
/// Tap triggers [onInteract] callback.
class TerminalComponent extends PositionComponent with TapCallbacks {
  TerminalComponent({
    required Vector2 position,
    required this.onInteract,
  }) : super(
          position: position,
          size: Vector2.all(gridSquareSizeDouble),
          anchor: Anchor.topLeft,
        );

  final void Function() onInteract;

  static final _bgPaint = Paint()..color = const Color(0xFF1A1A2E);
  static final _borderPaint = Paint()
    ..color = const Color(0xFF00FF41)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  static final _promptStyle = ui.TextStyle(
    color: const Color(0xFF00FF41),
    fontSize: 14,
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

    // Green border
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      _borderPaint,
    );

    // Terminal prompt ">_"
    final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center,
    ))
      ..pushStyle(_promptStyle)
      ..addText('>_');
    final paragraph = paragraphBuilder.build()
      ..layout(ui.ParagraphConstraints(width: size.x));
    canvas.drawParagraph(paragraph, Offset(0, (size.y - 16) / 2));
  }

  @override
  void onTapDown(TapDownEvent event) {
    onInteract();
  }
}
