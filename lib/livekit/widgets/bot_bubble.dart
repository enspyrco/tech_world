import 'package:flutter/material.dart';
import 'package:tech_world/bots/bot_config.dart';

/// A circular bubble that displays a bot's sprite avatar.
/// Uses [BotConfig] for accent color, sprite asset, and fallback letter.
class BotBubble extends StatelessWidget {
  const BotBubble({
    required this.config,
    this.size = 80,
    super.key,
  });

  final BotConfig config;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: config.accentColor,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: Container(
          color: const Color(0xFF2D2D2D),
          child: Center(
            child: Image.asset(
              'assets/images/${config.spriteAsset}',
              width: size * 0.7,
              height: size * 0.7,
              filterQuality: FilterQuality.none, // Keep pixel art crisp
              errorBuilder: (context, error, stackTrace) => Text(
                config.avatarLetter,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
