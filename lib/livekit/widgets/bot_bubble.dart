import 'package:flutter/material.dart';

/// A circular bubble that displays a bot's initial.
/// Styled similarly to VideoBubble's no-video state.
class BotBubble extends StatelessWidget {
  const BotBubble({
    required this.name,
    this.size = 80,
    super.key,
  });

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.blue,
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
          color: Colors.blueGrey[700],
          child: Center(
            child: Text(
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
    );
  }

  String _getInitial() {
    if (name.isNotEmpty) {
      return name[0].toUpperCase();
    }
    return '?';
  }
}
