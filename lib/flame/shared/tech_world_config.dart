import 'package:flame/components.dart';

/// Configuration constants for TechWorld.
abstract class TechWorldConfig {
  // Bot configuration
  static const String botUserId = 'bot-claude';
  static const String botDisplayName = 'Claude';

  // Bubble configuration
  static const String localPlayerBubbleKey = '_local_player_';
  static const int proximityThreshold = 3; // grid squares
  static final Vector2 bubbleOffset =
      Vector2(16, -20); // center horizontally, above sprite
  static const double defaultBubbleSize = 64;
  static const int defaultTargetFps = 15;
}
