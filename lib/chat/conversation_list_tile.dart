import 'package:flutter/material.dart';
import 'package:tech_world/chat/conversation.dart';

/// A list tile showing a DM conversation summary: avatar initial, display name,
/// last message preview, unread badge, and timestamp.
class ConversationListTile extends StatelessWidget {
  const ConversationListTile({
    required this.conversation,
    required this.lastMessageText,
    required this.onTap,
    super.key,
  });

  final Conversation conversation;
  final String? lastMessageText;
  final VoidCallback onTap;

  static const _clawdOrange = Color(0xFFD97757);

  @override
  Widget build(BuildContext context) {
    final isBot = conversation.peerId == 'bot-claude';
    final displayName = conversation.peerDisplayName ?? 'Unknown';
    final initial =
        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    final avatarColor = isBot ? _clawdOrange : Colors.blue;
    final hasUnread = conversation.unreadCount > 0;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFF3D3D3D), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: avatarColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: isBot
                    ? Border.all(color: _clawdOrange, width: 1.5)
                    : null,
              ),
              child: Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    color: avatarColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Name + last message
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight:
                          hasUnread ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (lastMessageText != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      lastMessageText!,
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // Unread badge + timestamp
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (conversation.lastActivity != null)
                  Text(
                    _formatTime(conversation.lastActivity!),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 11,
                    ),
                  ),
                if (hasUnread) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _clawdOrange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${conversation.unreadCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
