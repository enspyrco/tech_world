import 'package:flutter/material.dart';
import 'package:tech_world/chat/chat_time.dart';

/// The metadata row under every chat bubble: timestamp + Reply affordance.
///
/// Shared by `_MessageBubble` (group chat) and `_DmBubble` (DM threads) so the
/// two surfaces can't drift — same reasoning as `ChatComposerField`. The
/// timestamp is `Flexible` so a long label ("Yesterday 14:05") truncates
/// rather than overflowing when the side panel is squeezed narrow; the Reply
/// affordance keeps its own padded hit area so the tap target stays generous.
class BubbleFooter extends StatelessWidget {
  const BubbleFooter({
    required this.timestamp,
    required this.onReply,
    super.key,
  });

  final DateTime timestamp;

  /// Invoked when the user chooses to quote-reply to this message.
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    // Excluded from the enclosing SelectionArea: drag-selecting a
    // conversation should copy the messages, not interleave "5 min ago
    // Reply" between every line.
    return SelectionContainer.disabled(
      child: Padding(
        padding: const EdgeInsets.only(top: 2, left: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: ChatTimestamp(timestamp: timestamp)),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onReply,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.reply, size: 12, color: Colors.grey[600]),
                    const SizedBox(width: 2),
                    Text(
                      'Reply',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
