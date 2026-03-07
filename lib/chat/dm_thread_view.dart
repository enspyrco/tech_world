import 'package:flutter/material.dart';
import 'package:tech_world/chat/chat_message.dart';
import 'package:tech_world/chat/chat_service.dart';
import 'package:tech_world/chat/conversation.dart';
import 'package:tech_world/flame/components/bot_status.dart';

/// Full-screen (within the side panel) view for a single DM conversation.
///
/// Shows a message list and input field. For bot DMs, shows an offline banner
/// when the bot is absent.
class DmThreadView extends StatefulWidget {
  const DmThreadView({
    required this.conversation,
    required this.chatService,
    required this.onBack,
    super.key,
  });

  final Conversation conversation;
  final ChatService chatService;
  final VoidCallback onBack;

  @override
  State<DmThreadView> createState() => _DmThreadViewState();
}

class _DmThreadViewState extends State<DmThreadView> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  static const _clawdOrange = Color(0xFFD97757);

  @override
  void initState() {
    super.initState();
    // Mark as read when opening.
    widget.chatService.markConversationRead(widget.conversation.id);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final peerId = widget.conversation.peerId;
    if (peerId == null) return;

    widget.chatService.sendDm(
      peerId,
      text,
      peerDisplayName: widget.conversation.peerDisplayName ?? 'Unknown',
    );
    _textController.clear();
    _focusNode.requestFocus();

    // Scroll to bottom.
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isBotDm = widget.conversation.peerId == 'bot-claude';
    final displayName =
        widget.conversation.peerDisplayName ?? 'Unknown';

    return Column(
      children: [
        // Header with back button
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: Color(0xFF2D2D2D),
            border: Border(
              bottom: BorderSide(color: Color(0xFF3D3D3D)),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
                color: Colors.grey[400],
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Back to conversations',
              ),
              const SizedBox(width: 8),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: (isBotDm ? _clawdOrange : Colors.blue)
                      .withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    displayName.isNotEmpty
                        ? displayName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: isBotDm ? _clawdOrange : Colors.blue,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        // Message list
        Expanded(
          child: StreamBuilder<List<ChatMessage>>(
            stream: widget.conversation.peerId != null
                ? widget.chatService
                    .dmMessages(widget.conversation.peerId!)
                : const Stream.empty(),
            initialData: widget.conversation.peerId != null
                ? widget.chatService
                    .dmMessagesSnapshot(widget.conversation.peerId!)
                : null,
            builder: (context, snapshot) {
              final messages = snapshot.data ?? [];

              if (messages.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No messages yet.\nSay hi!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 14,
                      ),
                    ),
                  ),
                );
              }

              // Auto-scroll only when the user is already near the bottom,
              // so reading history isn't interrupted.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!_scrollController.hasClients) return;
                final position = _scrollController.position;
                final isNearBottom =
                    position.pixels >= position.maxScrollExtent - 80;
                if (isNearBottom) {
                  _scrollController.jumpTo(position.maxScrollExtent);
                }
              });

              return ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  return _DmBubble(message: messages[index]);
                },
              );
            },
          ),
        ),

        // Input (with optional bot-offline banner)
        _buildInput(isBotDm),
      ],
    );
  }

  Widget _buildInput(bool isBotDm) {
    if (isBotDm) {
      return ValueListenableBuilder<BotStatus>(
        valueListenable: botStatusNotifier,
        builder: (context, botStatus, _) {
          final isAbsent = botStatus == BotStatus.absent;
          return _inputRow(disabled: isAbsent, showBanner: isAbsent);
        },
      );
    }
    // Player DMs — always enabled.
    return _inputRow(disabled: false, showBanner: false);
  }

  Widget _inputRow({required bool disabled, required bool showBanner}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showBanner)
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.amber.shade800.withValues(alpha: 0.3),
            child: Row(
              children: [
                Icon(Icons.cloud_off,
                    size: 16, color: Colors.amber.shade300),
                const SizedBox(width: 8),
                Text(
                  'Clawd is offline',
                  style: TextStyle(
                    color: Colors.amber.shade300,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Color(0xFF2D2D2D),
            border: Border(
              top: BorderSide(color: Color(0xFF3D3D3D)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  enabled: !disabled,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: disabled
                        ? 'Clawd is offline...'
                        : 'Type a message...',
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: disabled ? null : (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: disabled ? null : _sendMessage,
                icon: const Icon(Icons.send),
                color: disabled ? Colors.grey[600] : _clawdOrange,
                style: IconButton.styleFrom(
                  backgroundColor: disabled
                      ? Colors.grey.withValues(alpha: 0.1)
                      : _clawdOrange.withValues(alpha: 0.1),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DmBubble extends StatelessWidget {
  const _DmBubble({required this.message});

  final ChatMessage message;

  static const _clawdOrange = Color(0xFFD97757);

  @override
  Widget build(BuildContext context) {
    final isLocal = message.isLocalUser;
    final isBot = message.isBot;
    final avatarLetter = isBot
        ? 'C'
        : message.senderName.isNotEmpty
            ? message.senderName[0].toUpperCase()
            : '?';
    final avatarColor = isBot ? _clawdOrange : Colors.blue;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isLocal ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isLocal) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: avatarColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  avatarLetter,
                  style: TextStyle(
                    color: avatarColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isLocal
                    ? _clawdOrange.withValues(alpha: 0.2)
                    : const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(16),
                border: isLocal
                    ? Border.all(
                        color: _clawdOrange.withValues(alpha: 0.3))
                    : null,
              ),
              child: Text(
                message.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          if (isLocal) const SizedBox(width: 36),
        ],
      ),
    );
  }
}
