import 'package:flutter/material.dart';
import 'package:tech_world/chat/chat_message.dart';
import 'package:tech_world/chat/chat_service.dart';
import 'package:tech_world/services/stt_service.dart';

/// Side panel for chatting with Clawd the bot.
class ChatPanel extends StatefulWidget {
  const ChatPanel({
    required this.chatService,
    this.onCollapse,
    super.key,
  });

  final ChatService chatService;
  final VoidCallback? onCollapse;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final _sttService = SttService();

  // Clawd's orange color
  static const clawdOrange = Color(0xFFD97757);

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _sttService.dispose();
    super.dispose();
  }

  Future<void> _handleMicPress() async {
    if (_sttService.listening.value) {
      _sttService.stop();
      return;
    }

    final result = await _sttService.listen();
    if (result != null && result.isNotEmpty) {
      _textController.text = result;
      _sendMessage();
    }
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    widget.chatService.sendMessage(text);
    _textController.clear();
    _focusNode.requestFocus();

    // Scroll to bottom after message is added
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
    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF2D2D2D),
              border: Border(
                bottom: BorderSide(color: Color(0xFF3D3D3D)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: clawdOrange.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: clawdOrange, width: 2),
                  ),
                  child: const Center(
                    child: Text(
                      'C',
                      style: TextStyle(
                        color: clawdOrange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Chat with Clawd',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.onCollapse != null) ...[
                  const Spacer(),
                  IconButton(
                    onPressed: widget.onCollapse,
                    icon: const Icon(Icons.chevron_right),
                    color: Colors.grey[400],
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    tooltip: 'Collapse chat',
                  ),
                ],
              ],
            ),
          ),

          // Messages
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: widget.chatService.messages,
              initialData: widget.chatService.currentMessages,
              builder: (context, snapshot) {
                final messages = snapshot.data ?? [];

                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: clawdOrange.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Text(
                                'C',
                                style: TextStyle(
                                  color: clawdOrange,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Hey! I\'m Clawd.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your friendly coding companion.\nAsk me anything!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    return _MessageBubble(message: messages[index]);
                  },
                );
              },
            ),
          ),

          // Input
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
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
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
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                if (_sttService.isSupported)
                  ValueListenableBuilder<bool>(
                    valueListenable: _sttService.listening,
                    builder: (context, isListening, _) {
                      return IconButton(
                        onPressed: _handleMicPress,
                        icon: Icon(isListening ? Icons.mic : Icons.mic_none),
                        color: isListening ? Colors.red : clawdOrange,
                        style: IconButton.styleFrom(
                          backgroundColor: isListening
                              ? Colors.red.withValues(alpha: 0.2)
                              : clawdOrange.withValues(alpha: 0.1),
                        ),
                      );
                    },
                  ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send),
                  color: clawdOrange,
                  style: IconButton.styleFrom(
                    backgroundColor: clawdOrange.withValues(alpha: 0.1),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  static const clawdOrange = Color(0xFFD97757);

  @override
  Widget build(BuildContext context) {
    // Determine avatar and colors based on message type
    final isLocalUser = message.isLocalUser;
    final isBot = message.isBot;
    final avatarLetter = isBot ? 'C' : message.senderName.isNotEmpty ? message.senderName[0].toUpperCase() : '?';
    final avatarColor = isBot ? clawdOrange : Colors.blue;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isLocalUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isLocalUser) ...[
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
            child: Column(
              crossAxisAlignment: isLocalUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Show sender name for other users (not bot, not self)
                if (!isLocalUser && !isBot)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 4),
                    child: Text(
                      message.senderName,
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isLocalUser
                        ? clawdOrange.withValues(alpha: 0.2)
                        : const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(16),
                    border: isLocalUser
                        ? Border.all(color: clawdOrange.withValues(alpha: 0.3))
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
              ],
            ),
          ),
          if (isLocalUser) const SizedBox(width: 36),
        ],
      ),
    );
  }
}
