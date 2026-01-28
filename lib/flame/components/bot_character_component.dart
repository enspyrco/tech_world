import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/flame.dart';
import 'package:flutter/painting.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/flame/shared/constants.dart';

/// A Flame component that renders the Clawd mascot as a character sprite.
/// Unlike PlayerComponent which uses sprite sheets, this renders a static image.
/// Tap on the bot to toggle the thinking indicator (for demo purposes).
class BotCharacterComponent extends PositionComponent with TapCallbacks {
  BotCharacterComponent({
    required Vector2 position,
    required this.id,
    required this.displayName,
  }) : super(
          position: position,
          size: Vector2.all(48), // Square size to preserve Clawd's aspect ratio
          anchor: Anchor.centerLeft, // Same anchor as PlayerComponent
        );

  final String id;
  final String displayName;

  ui.Image? _clawdImage;

  @override
  Future<void> onLoad() async {
    super.onLoad();
    _clawdImage = await Flame.images.load('claude_bot.png');
  }

  /// Returns mini grid position as Point (for proximity detection)
  Point<int> get miniGridPosition => Point(
        position.x.round() ~/ gridSquareSize,
        position.y.round() ~/ gridSquareSize,
      );

  @override
  void render(Canvas canvas) {
    if (_clawdImage == null) return;

    final srcRect = Rect.fromLTWH(
      0,
      0,
      _clawdImage!.width.toDouble(),
      _clawdImage!.height.toDouble(),
    );

    // Destination rect fills the component size
    final dstRect = Rect.fromLTWH(0, 0, size.x, size.y);

    // Use FilterQuality.none for crisp pixel art
    canvas.drawImageRect(
      _clawdImage!,
      srcRect,
      dstRect,
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  @override
  void onTapDown(TapDownEvent event) {
    // Toggle between idle and thinking status
    if (botStatusNotifier.value == BotStatus.idle) {
      botStatusNotifier.value = BotStatus.thinking;
    } else {
      botStatusNotifier.value = BotStatus.idle;
    }
  }
}
