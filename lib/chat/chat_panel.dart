import 'package:flutter/material.dart';
import 'package:tech_world/bots/bot_config.dart';
import 'package:tech_world/chat/bubble_footer.dart';
import 'package:tech_world/chat/chat_message.dart';
import 'package:tech_world/chat/composer_field.dart';
import 'package:tech_world/chat/reply_widgets.dart';
import 'package:tech_world/chat/chat_service.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/chat/conversation.dart';
import 'package:tech_world/chat/conversation_list_tile.dart';
import 'package:tech_world/chat/dm_thread_view.dart';
import 'package:tech_world/chat/mention_composer.dart';
import 'package:tech_world/chat/mention_text.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/services/stt_service.dart';

/// Side panel for chatting — tabbed with "Group" (Clawd + all players) and
/// "DMs" (private conversations).
class ChatPanel extends StatefulWidget {
  const ChatPanel({
    required this.chatService,
    required this.liveKitService,
    this.onCollapse,
    this.initialDmPeerId,
    this.onDmPeerConsumed,
    this.onOpened,
    super.key,
  });

  final ChatService chatService;
  final LiveKitService liveKitService;
  final VoidCallback? onCollapse;

  /// Called when the panel is shown — the user "seeing" chat. Used to
  /// acknowledge any `@mention` of the local user (stops their public pulse).
  final VoidCallback? onOpened;

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

  /// The group message currently being quote-replied to, or `null` when
  /// composing a fresh message. Mirrors `DmThreadView._replyTarget`.
  ChatMessage? _replyTarget;

  /// UIDs the user picked from the @-mention picker while composing, paired with
  /// the display name inserted. Filtered at send time to those whose `@Name`
  /// token still survives in the text (see [MentionComposer.survivingUids]).
  final List<MentionCandidate> _pickedMentions = [];

  /// Candidates currently shown in the @-mention picker, or empty when the
  /// picker is closed (no active `@query`).
  List<MentionCandidate> _mentionMatches = const [];

  /// The active `@query`'s anchor index, so a pick knows what span to replace.
  int? _mentionAtIndex;

  // Clawd's orange color
  static const clawdOrange = Color(0xFFD97757);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // The panel mounting means the user is now looking at chat — acknowledge
    // any mention of them. Deferred to after the first frame so the ack fires
    // outside build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onOpened?.call();
    });

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

  void _openDmForPeer(String peerId, {String? displayName}) {
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
          peerDisplayName: displayName ?? peerId,
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
    final transcript = result.transcript;
    if (transcript != null && transcript.isNotEmpty) {
      _textController.text = transcript;
      _sendMessage();
    }
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    // Keep only the picked mentions whose `@Name` token still survives in the
    // text (the user may have deleted one after inserting it). The structured
    // UID list is the trust anchor; the inline `@Name` text is display-only.
    final mentions = MentionComposer.survivingUids(text, _pickedMentions);

    final replyTarget = _replyTarget;
    widget.chatService.sendMessage(
      text,
      replyTo: replyTarget,
      mentions: mentions,
    );
    _textController.clear();
    setState(() {
      _replyTarget = null;
      _pickedMentions.clear();
      _mentionMatches = const [];
      _mentionAtIndex = null;
    });
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

  void _startReply(ChatMessage message) {
    setState(() => _replyTarget = message);
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyTarget = null);
  }

  /// Everyone you can `@mention`: the remote participants plus yourself. The UID
  /// (LiveKit identity) is the trust anchor; the display name is cosmetic.
  List<MentionCandidate> _mentionCandidates() {
    final candidates = <MentionCandidate>[
      MentionCandidate(
        uid: widget.liveKitService.userId,
        displayName: widget.liveKitService.displayName,
      ),
    ];
    for (final p in widget.liveKitService.remoteParticipants.values) {
      final name = (p.name.isNotEmpty ? p.name : p.identity);
      candidates.add(MentionCandidate(uid: p.identity, displayName: name));
    }
    return candidates;
  }

  /// React to composer edits: open/refresh the @-mention picker when the cursor
  /// sits in an unfinished `@token`, otherwise close it.
  void _onComposerChanged() {
    final value = _textController.value;
    final cursor = value.selection.baseOffset;
    final active = MentionComposer.activeQuery(value.text, cursor);
    if (active == null) {
      if (_mentionMatches.isNotEmpty || _mentionAtIndex != null) {
        setState(() {
          _mentionMatches = const [];
          _mentionAtIndex = null;
        });
      }
      return;
    }
    final matches = MentionComposer.filter(_mentionCandidates(), active.query);
    setState(() {
      _mentionMatches = matches;
      _mentionAtIndex = active.atIndex;
    });
  }

  /// Insert the chosen mention, recording its UID for the structured wire list.
  void _pickMention(MentionCandidate chosen) {
    final atIndex = _mentionAtIndex;
    if (atIndex == null) return;
    final cursor = _textController.selection.baseOffset;
    final ins = MentionComposer.insert(
      text: _textController.text,
      atIndex: atIndex,
      cursor: cursor < 0 ? _textController.text.length : cursor,
      chosen: chosen,
    );
    _textController.value = TextEditingValue(
      text: ins.text,
      selection: TextSelection.collapsed(offset: ins.cursor),
    );
    setState(() {
      _pickedMentions.add(chosen);
      _mentionMatches = const [];
      _mentionAtIndex = null;
    });
    _focusNode.requestFocus();
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
                  final message = messages[index];
                  return _MessageBubble(
                    message: message,
                    onReply: () => _startReply(message),
                    onSenderTap: message.isLocalUser || message.isBot
                        ? null
                        : () {
                            // Open a DM with this sender.
                            final senderId = message.senderId;
                            if (senderId == null) return;
                            _tabController.animateTo(1);
                            _openDmForPeer(
                              senderId,
                              displayName: message.senderName,
                            );
                          },
                  );
                },
              );
            },
          ),
        ),

        // Input (with offline banner)
        ValueListenableBuilder<BotStatus>(
          valueListenable: widget.chatService.botStatus,
          builder: (context, botStatus, _) {
            final isAbsent = botStatus == BotStatus.absent;
            final replyTarget = _replyTarget;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // @-mention picker — a filterable list of room participants
                // shown while the cursor is inside an unfinished `@token`.
                if (_mentionMatches.isNotEmpty)
                  _MentionPicker(
                    candidates: _mentionMatches,
                    onPick: _pickMention,
                    accentColor: clawdOrange,
                  ),
                // "Replying to X" banner while composing a reply.
                if (replyTarget != null)
                  ReplyComposingBanner(
                    target: replyTarget,
                    onCancel: _cancelReply,
                  ),
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
                        child: ChatComposerField(
                          controller: _textController,
                          focusNode: _focusNode,
                          enabled: !isAbsent,
                          hintText: isAbsent
                              ? 'Clawd is offline...'
                              : 'Type a message...',
                          onSend: _sendMessage,
                          onChanged: (_) => _onComposerChanged(),
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

    return Stack(
      children: [
        StreamBuilder<List<Conversation>>(
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
                        "Tap a player's name in group chat\nor use + to start a conversation",
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
        ),
        // "New message" FAB
        Positioned(
          right: 12,
          bottom: 12,
          child: FloatingActionButton.small(
            onPressed: _showPlayerPicker,
            backgroundColor: clawdOrange,
            tooltip: 'New message',
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ),
      ],
    );
  }

  /// Shows a dialog listing remote participants to start a DM with.
  void _showPlayerPicker() {
    final participants = widget.liveKitService.remoteParticipants.values
        .where((p) => p.identity != 'bot-claude')
        .toList();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D4D),
        title:
            const Text('New message', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: participants.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No other players in the room',
                    style: TextStyle(color: Colors.grey[400]),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: participants.length,
                  itemBuilder: (context, index) {
                    final p = participants[index];
                    final name = p.name.isNotEmpty ? p.name : p.identity;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.withValues(alpha: 0.2),
                        child: Text(
                          name[0].toUpperCase(),
                          style: const TextStyle(color: Colors.blue),
                        ),
                      ),
                      title: Text(name,
                          style: const TextStyle(color: Colors.white)),
                      onTap: () {
                        Navigator.pop(ctx);
                        _openDmForPeer(p.identity, displayName: name);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.onReply,
    this.onSenderTap,
  });

  final ChatMessage message;

  /// Invoked when the user chooses to quote-reply to this message.
  final VoidCallback onReply;

  final VoidCallback? onSenderTap;

  static const clawdOrange = Color(0xFFD97757);
  static const dreamfinderPurple = Color(0xFF9B72CF);

  @override
  Widget build(BuildContext context) {
    // Determine avatar and colors based on message type
    final isLocalUser = message.isLocalUser;
    final isBot = message.isBot;
    final isDreamfinder =
        message.senderId != null && isDreamfinderIdentity(message.senderId!);
    final avatarLetter = message.senderName.isNotEmpty
        ? message.senderName[0].toUpperCase()
        : '?';
    final avatarColor =
        isBot ? (isDreamfinder ? dreamfinderPurple : clawdOrange) : Colors.blue;

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
                // Long-press anywhere on the bubble starts a quote-reply — a
                // discoverable, platform-agnostic affordance (touch + desktop)
                // without a persistent button on every row. Mirrors the DM view.
                GestureDetector(
                  onLongPress: onReply,
                  child: Container(
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (message.isReply) QuotedMessage(message: message),
                        Text.rich(
                          TextSpan(
                            children: buildMentionSpans(
                              message.text,
                              baseStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              mentionStyle: const TextStyle(
                                color: clawdOrange,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Timestamp + subtle reply hint / button for discoverability.
                BubbleFooter(
                  timestamp: message.timestamp,
                  onReply: onReply,
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

/// A compact, filterable list of room participants shown above the composer
/// while the user is typing an `@mention`. Tapping a row inserts `@Name` and
/// records the participant's UID (see `_ChatPanelState._pickMention`).
class _MentionPicker extends StatelessWidget {
  const _MentionPicker({
    required this.candidates,
    required this.onPick,
    required this.accentColor,
  });

  final List<MentionCandidate> candidates;
  final ValueChanged<MentionCandidate> onPick;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: const BoxDecoration(
        color: Color(0xFF252525),
        border: Border(top: BorderSide(color: Color(0xFF3D3D3D))),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: candidates.length,
        itemBuilder: (context, i) {
          final c = candidates[i];
          final initial =
              c.displayName.isNotEmpty ? c.displayName[0].toUpperCase() : '?';
          return InkWell(
            onTap: () => onPick(c),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: accentColor.withValues(alpha: 0.25),
                    child: Text(
                      initial,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      c.displayName,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text('@',
                      style: TextStyle(
                          color: accentColor.withValues(alpha: 0.6),
                          fontSize: 14)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
