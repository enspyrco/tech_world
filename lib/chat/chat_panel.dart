import 'package:flutter/material.dart';
import 'package:tech_world/chat/chat_message.dart';
import 'package:tech_world/chat/chat_service.dart';
import 'package:tech_world/chat/conversation.dart';
import 'package:tech_world/chat/conversation_list_tile.dart';
import 'package:tech_world/chat/dm_thread_view.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/services/stt_service.dart';

/// Side panel for chatting — tabbed with "Group" (Clawd + all players) and
/// "DMs" (private conversations).
class ChatPanel extends StatefulWidget {
  const ChatPanel({
    required this.chatService,
    this.onCollapse,
    this.initialDmPeerId,
    this.onDmPeerConsumed,
    super.key,
  });

  final ChatService chatService;
  final VoidCallback? onCollapse;

  /// When set, the panel auto-opens a DM thread with this peer on first build.
  final String? initialDmPeerId;

  /// Called after the initial DM peer has been consumed (so the caller can
  /// clear the notifier).
  final VoidCallback? onDmPeerConsumed;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel>
    with SingleTickerProviderStateMixin {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final _sttService = SttService();

  late TabController _tabController;

  /// When non-null, shows the DM thread view instead of the conversation list.
  Conversation? _activeDmConversation;

  // Clawd's orange color
  static const clawdOrange = Color(0xFFD97757);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // If an initial DM peer was requested, switch to DMs tab.
    if (widget.initialDmPeerId != null) {
      _tabController.index = 1;
      _openDmForPeer(widget.initialDmPeerId!);
      widget.onDmPeerConsumed?.call();
    }
  }

  @override
  void didUpdateWidget(covariant ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDmPeerId != null &&
        widget.initialDmPeerId != oldWidget.initialDmPeerId) {
      _tabController.index = 1;
      _openDmForPeer(widget.initialDmPeerId!);
      widget.onDmPeerConsumed?.call();
    }
  }

  void _openDmForPeer(String peerId) {
    // Try to find an existing conversation for this peer.
    final existing = widget.chatService.currentConversations.where(
      (c) => c.peerId == peerId,
    );

    if (existing.isNotEmpty) {
      setState(() => _activeDmConversation = existing.first);
    } else {
      // Create a placeholder with the real conversation ID so that messages
      // sent before the conversation is persisted use the correct key.
      final convId = Conversation.conversationIdFor(
        widget.chatService.localUserId,
        peerId,
      );
      setState(() {
        _activeDmConversation = Conversation(
          id: convId,
          type: ConversationType.dm,
          peerId: peerId,
          peerDisplayName: peerId, // Best we can do without lookup.
        );
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _sttService.dispose();
    _tabController.dispose();
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
          // Header with tabs
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF2D2D2D),
              border: Border(
                bottom: BorderSide(color: Color(0xFF3D3D3D)),
              ),
            ),
            child: Column(
              children: [
                // Collapse button row
                if (widget.onCollapse != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4, top: 4),
                      child: IconButton(
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
                    ),
                  ),
                // Tab bar
                TabBar(
                  controller: _tabController,
                  indicatorColor: clawdOrange,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey[500],
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerHeight: 0,
                  tabs: [
                    const Tab(text: 'Group'),
                    // DMs tab with unread badge
                    Tab(
                      child: ValueListenableBuilder<int>(
                        valueListenable:
                            widget.chatService.totalUnreadNotifier,
                        builder: (context, unread, _) {
                          if (unread == 0) {
                            return const Text('DMs');
                          }
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('DMs'),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: clawdOrange,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$unread',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildGroupTab(),
                _buildDmsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Group tab (existing behavior) ----

  Widget _buildGroupTab() {
    return Column(
      children: [
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
                  return _MessageBubble(
                    message: messages[index],
                    onSenderTap: messages[index].isLocalUser ||
                            messages[index].isBot
                        ? null
                        : () {
                            // Open a DM with this sender.
                            final senderId = messages[index].senderId;
                            if (senderId == null) return;
                            _tabController.animateTo(1);
                            _openDmForPeer(senderId);
                          },
                  );
                },
              );
            },
          ),
        ),

        // Input (with offline banner)
        ValueListenableBuilder<BotStatus>(
          valueListenable: botStatusNotifier,
          builder: (context, botStatus, _) {
            final isAbsent = botStatus == BotStatus.absent;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Offline banner
                if (isAbsent)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
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
                // Input row
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
                          enabled: !isAbsent,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: isAbsent
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
                          onSubmitted:
                              isAbsent ? null : (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_sttService.isSupported)
                        ValueListenableBuilder<bool>(
                          valueListenable: _sttService.listening,
                          builder: (context, isListening, _) {
                            return IconButton(
                              onPressed:
                                  isAbsent ? null : _handleMicPress,
                              icon: Icon(isListening
                                  ? Icons.mic
                                  : Icons.mic_none),
                              color: isAbsent
                                  ? Colors.grey[600]
                                  : isListening
                                      ? Colors.red
                                      : clawdOrange,
                              style: IconButton.styleFrom(
                                backgroundColor: isAbsent
                                    ? Colors.grey.withValues(alpha: 0.1)
                                    : isListening
                                        ? Colors.red
                                            .withValues(alpha: 0.2)
                                        : clawdOrange
                                            .withValues(alpha: 0.1),
                              ),
                            );
                          },
                        ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: isAbsent ? null : _sendMessage,
                        icon: const Icon(Icons.send),
                        color:
                            isAbsent ? Colors.grey[600] : clawdOrange,
                        style: IconButton.styleFrom(
                          backgroundColor: isAbsent
                              ? Colors.grey.withValues(alpha: 0.1)
                              : clawdOrange.withValues(alpha: 0.1),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  // ---- DMs tab ----

  Widget _buildDmsTab() {
    // If a DM thread is open, show it instead of the list.
    if (_activeDmConversation != null) {
      return DmThreadView(
        conversation: _activeDmConversation!,
        chatService: widget.chatService,
        onBack: () => setState(() => _activeDmConversation = null),
      );
    }

    return StreamBuilder<List<Conversation>>(
      stream: widget.chatService.conversations,
      builder: (context, snapshot) {
        final conversations = (snapshot.data ??
                widget.chatService.currentConversations)
            .where((c) => c.type == ConversationType.dm)
            .toList();

        if (conversations.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 48, color: Colors.grey[600]),
                  const SizedBox(height: 16),
                  Text(
                    'No direct messages yet',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Tap a player's name in group chat\nto start a conversation",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          itemCount: conversations.length,
          itemBuilder: (context, index) {
            final conv = conversations[index];
            return ConversationListTile(
              conversation: conv,
              lastMessageText:
                  widget.chatService.lastDmMessageText(conv.id),
              onTap: () {
                widget.chatService.markConversationRead(conv.id);
                setState(() => _activeDmConversation = conv);
              },
            );
          },
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    this.onSenderTap,
  });

  final ChatMessage message;
  final VoidCallback? onSenderTap;

  static const clawdOrange = Color(0xFFD97757);

  @override
  Widget build(BuildContext context) {
    // Determine avatar and colors based on message type
    final isLocalUser = message.isLocalUser;
    final isBot = message.isBot;
    final avatarLetter = isBot
        ? 'C'
        : message.senderName.isNotEmpty
            ? message.senderName[0].toUpperCase()
            : '?';
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
              crossAxisAlignment: isLocalUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // Show sender name for other users (not bot, not self)
                if (!isLocalUser && !isBot)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 4),
                    child: GestureDetector(
                      onTap: onSenderTap,
                      child: Text(
                        message.senderName,
                        style: TextStyle(
                          color: onSenderTap != null
                              ? clawdOrange.withValues(alpha: 0.8)
                              : Colors.grey[400],
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          decoration: onSenderTap != null
                              ? TextDecoration.underline
                              : null,
                          decorationColor:
                              clawdOrange.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isLocalUser
                        ? clawdOrange.withValues(alpha: 0.2)
                        : const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(16),
                    border: isLocalUser
                        ? Border.all(
                            color: clawdOrange.withValues(alpha: 0.3))
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
