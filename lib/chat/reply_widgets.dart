import 'package:flutter/material.dart';
import 'package:tech_world/chat/chat_message.dart';

/// Quote-reply UI shared by the group chat panel and the DM thread view.
///
/// Both surfaces render an identical quoted-message bubble and "Replying to X"
/// compose banner. They lived as byte-for-byte private duplicates in
/// `chat_panel.dart` and `dm_thread_view.dart` (flagged in the #490 cage-match
/// by Maxwell, Kelvin, and Carnot) — a drift vector where a visual change had
/// to be made twice. Extracted here so both consumers share one definition.

/// Clawd's accent orange, used for the reply quote bar and sender label.
const _clawdOrange = Color(0xFFD97757);

/// The inline quote bubble rendered above a message that is a reply, showing
/// the quoted sender + a one-line snippet of the original.
///
/// When [onTap] is provided, the bubble becomes tappable — the DM thread view
/// uses this to scroll to and briefly highlight the quoted original. The group
/// chat panel passes no [onTap] (navigation not wired there yet), so the bubble
/// stays display-only.
class QuotedMessage extends StatelessWidget {
  const QuotedMessage({super.key, required this.message, this.onTap});

  final ChatMessage message;

  /// Invoked when the user taps the quote to jump to the original message.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final quotedSender = message.replyToSenderName ?? 'Unknown';
    final quotedText = message.replyToText ?? '';

    final bubble = Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: _clawdOrange, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            quotedSender,
            style: const TextStyle(
              color: _clawdOrange,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (quotedText.isNotEmpty)
            Text(
              quotedText,
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );

    if (onTap == null) return bubble;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: bubble,
      ),
    );
  }
}

/// The "Replying to X" banner shown above the input while composing a reply.
class ReplyComposingBanner extends StatelessWidget {
  const ReplyComposingBanner({
    super.key,
    required this.target,
    required this.onCancel,
  });

  final ChatMessage target;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF1E1E1E),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 32,
            color: _clawdOrange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to ${target.senderName}',
                  style: const TextStyle(
                    color: _clawdOrange,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  target.text,
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close),
            iconSize: 18,
            color: Colors.grey[400],
            tooltip: 'Cancel reply',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}
