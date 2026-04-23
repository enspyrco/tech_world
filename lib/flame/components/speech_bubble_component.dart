import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// A Flame component that renders speech text below a character with a
/// per-letter fade-in effect (typewriter style).
///
/// Each letter fades from transparent to opaque in sequence, creating a
/// flowing reveal effect. The bubble auto-removes after the text is fully
/// revealed and a display duration has elapsed.
class SpeechBubbleComponent extends PositionComponent {
  SpeechBubbleComponent({
    required this.text,
    this.textColor = Colors.white,
    this.backgroundColor = const Color(0xCC1A1A2E),
    this.borderColor,
    this.maxWidth = 160.0,
    this.fontSize = 10.0,
    this.letterRevealRate = 30.0,
    this.letterFadeDuration = 0.15,
    this.displayDuration = 4.0,
    this.fadeOutDuration = 0.5,
  }) : super(anchor: Anchor.topCenter);

  /// The text to display.
  final String text;

  /// Text color when fully revealed.
  final Color textColor;

  /// Background color of the speech bubble.
  final Color backgroundColor;

  /// Optional border color. If null, no border is drawn.
  final Color? borderColor;

  /// Maximum width before text wraps.
  final double maxWidth;

  /// Font size for the speech text.
  final double fontSize;

  /// Letters revealed per second.
  final double letterRevealRate;

  /// Duration (seconds) for each letter to fade from 0 to full opacity.
  final double letterFadeDuration;

  /// Seconds to display the full text before fading out.
  final double displayDuration;

  /// Duration of the fade-out animation.
  final double fadeOutDuration;

  // Internal state
  double _elapsed = 0;
  double _overallOpacity = 1.0;
  bool _fadingOut = false;
  double _fadeOutStart = 0;

  // Pre-computed character layout
  final List<_CharLayout> _chars = [];
  double _totalHeight = 0;
  bool _layoutDone = false;

  @override
  void onMount() {
    super.onMount();
    _computeLayout();
  }

  /// Pre-compute the position of every character using TextPainter.
  void _computeLayout() {
    if (_layoutDone) return;
    _layoutDone = true;

    // Use TextPainter to get line breaks and character positions.
    final style = TextStyle(
      fontSize: fontSize,
      color: textColor,
      height: 1.3,
    );

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: null,
    );
    textPainter.layout(maxWidth: maxWidth - 16); // 8px padding each side

    // Extract character positions from the text painter.
    for (int i = 0; i < text.length; i++) {
      final offset = textPainter.getOffsetForCaret(
        TextPosition(offset: i),
        Rect.zero,
      );
      _chars.add(_CharLayout(
        char: text[i],
        offset: offset + const Offset(8, 6), // padding
        index: i,
      ));
    }

    _totalHeight = textPainter.height + 12; // 6px padding top + bottom
    final bubbleWidth = (textPainter.width + 16).clamp(0.0, maxWidth);
    size = Vector2(bubbleWidth, _totalHeight);

    textPainter.dispose();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;

    // Check if all letters revealed + display time elapsed.
    final totalRevealTime = text.length / letterRevealRate;
    if (!_fadingOut && _elapsed > totalRevealTime + displayDuration) {
      _fadingOut = true;
      _fadeOutStart = _elapsed;
    }

    if (_fadingOut) {
      final fadeProgress =
          ((_elapsed - _fadeOutStart) / fadeOutDuration).clamp(0.0, 1.0);
      _overallOpacity = 1.0 - fadeProgress;
      if (_overallOpacity <= 0) {
        removeFromParent();
      }
    }
  }

  @override
  void render(Canvas canvas) {
    if (!_layoutDone || _chars.isEmpty) return;

    // Draw background with rounded corners.
    final bgRect = Rect.fromLTWH(0, 0, size.x, size.y);
    final rrect = RRect.fromRectAndRadius(bgRect, const Radius.circular(6));

    final bgPaint = Paint()
      ..color = backgroundColor.withValues(alpha: _overallOpacity * 0.8);
    canvas.drawRRect(rrect, bgPaint);

    if (borderColor != null) {
      final borderPaint = Paint()
        ..color = borderColor!.withValues(alpha: _overallOpacity * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRRect(rrect, borderPaint);
    }

    // Draw each character with individual opacity.
    for (final charLayout in _chars) {
      if (charLayout.char == ' ' || charLayout.char == '\n') continue;

      // When does this character start revealing?
      final revealStart = charLayout.index / letterRevealRate;
      final charAge = _elapsed - revealStart;

      if (charAge <= 0) continue; // Not revealed yet.

      final charOpacity =
          (charAge / letterFadeDuration).clamp(0.0, 1.0) * _overallOpacity;

      final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textDirection: TextDirection.ltr,
      ));
      paragraphBuilder.pushStyle(ui.TextStyle(
        color: textColor.withValues(alpha: charOpacity),
        fontSize: fontSize,
        height: 1.3,
      ));
      paragraphBuilder.addText(charLayout.char);
      final paragraph = paragraphBuilder.build();
      paragraph.layout(const ui.ParagraphConstraints(width: 50));

      canvas.drawParagraph(paragraph, charLayout.offset);
      paragraph.dispose();
    }
  }
}

/// Layout data for a single character.
class _CharLayout {
  _CharLayout({
    required this.char,
    required this.offset,
    required this.index,
  });

  final String char;
  final Offset offset;
  final int index;
}
