import 'package:flutter/material.dart';

/// A circular bubble that displays the Claude bot mascot (Clawd).
/// Styled similarly to VideoBubble's no-video state.
class BotBubble extends StatelessWidget {
  const BotBubble({
    required this.name,
    this.size = 80,
    super.key,
  });

  final String name;
  final double size;

  // Clawd's orange color
  static const clawdOrange = Color(0xFFD97757);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: clawdOrange,
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
              'assets/images/claude_bot.png',
              width: size * 0.7,
              height: size * 0.7,
              filterQuality: FilterQuality.none, // Keep pixel art crisp
              errorBuilder: (context, error, stackTrace) => Text(
                _getInitial(),
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

  String _getInitial() {
    if (name.isNotEmpty) {
      return name[0].toUpperCase();
    }
    return '?';
  }
}
