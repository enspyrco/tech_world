import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';
import 'package:tech_world/flame/maps/door_data.dart';
import 'package:tech_world/flame/shared/constants.dart';

/// A door that blocks passage when locked and becomes passable when unlocked.
///
/// Renders as a dark rectangle with a lock icon when locked, or a faded
/// open-door icon when unlocked. Uses the same grid-based positioning and
/// y-priority depth sorting as other world components.
class DoorComponent extends PositionComponent {
  DoorComponent({
    required Vector2 position,
    required this.doorData,
  }) : super(
          position: position,
          size: Vector2.all(gridSquareSizeDouble),
          anchor: Anchor.topLeft,
        );

  /// The door data this component represents.
  final DoorData doorData;

  // Locked state paints.
  static final _lockedBgPaint = Paint()..color = const Color(0xFF2A1A3E);
  static final _lockedBorderPaint = Paint()
    ..color = const Color(0xFFAA44FF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  static final _lockIconStyle = ui.TextStyle(
    color: const Color(0xFFAA44FF),
    fontSize: 14,
    fontWeight: FontWeight.bold,
  );

  // Unlocked state paints.
  static final _unlockedBgPaint = Paint()..color = const Color(0x401A3E1A);
  static final _unlockedBorderPaint = Paint()
    ..color = const Color(0x8044AA44)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  static final _unlockIconStyle = ui.TextStyle(
    color: const Color(0x8044AA44),
    fontSize: 14,
    fontWeight: FontWeight.bold,
  );

  @override
  void render(Canvas canvas) {
    final isLocked = !doorData.isUnlocked;
    final rect = Rect.fromLTWH(2, 2, size.x - 4, size.y - 4);

    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      isLocked ? _lockedBgPaint : _unlockedBgPaint,
    );

    // Border
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      isLocked ? _lockedBorderPaint : _unlockedBorderPaint,
    );

    // Icon — lock when locked, open symbol when unlocked
    final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center,
    ))
      ..pushStyle(isLocked ? _lockIconStyle : _unlockIconStyle)
      ..addText(isLocked ? '\u{1F512}' : '\u{1F513}');
    final paragraph = paragraphBuilder.build()
      ..layout(ui.ParagraphConstraints(width: size.x));
    canvas.drawParagraph(paragraph, Offset(0, (size.y - 16) / 2));
  }
}
