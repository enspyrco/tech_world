import 'package:flutter/material.dart';
import 'package:tech_world/chat/bubble_footer.dart';
import 'package:tech_world/chat/chat_message.dart';
import 'package:tech_world/chat/composer_field.dart';
import 'package:tech_world/chat/reply_widgets.dart';
import 'package:tech_world/chat/mention_text.dart';
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

  /// The message currently being quote-replied to, or `null` when composing a
  /// fresh message.
  ChatMessage? _replyTarget;

  /// Per-message keys, by [ChatMessage.stableId], so a tapped quote can locate
  /// and scroll to the original via [Scrollable.ensureVisible].
  final Map<String, GlobalKey> _bubbleKeys = {};

  /// The [ChatMessage.stableId] currently flashing as the just-navigated-to
  /// quote target, or `null`. Cleared after a short delay.
  String? _highlightedId;

  /// True while a tap-to-quote scroll is animating, so the
  /// near-bottom auto-scroll doesn't yank the view back down mid-navigation.
  bool _navigatingToQuote = false;

  /// True while an older-history page for this DM is being fetched, so the
  /// top-of-list loading affordance shows and the scroll listener doesn't stack
  /// overlapping fetches.
  bool _loadingOlder = false;

  static const _clawdOrange = Color(0xFFD97757);

  /// How long a tapped-to quote target stays highlighted before the flash
  /// fades — long enough to catch the eye after the scroll settles, short
  /// enough not to linger as persistent state.
  static const _highlightDuration = Duration(milliseconds: 1600);

  GlobalKey _keyFor(String stableId) =>
      _bubbleKeys.putIfAbsent(stableId, () => GlobalKey());

  /// Drop keys for messages no longer rendered, so [_bubbleKeys] tracks the
  /// live message set instead of growing unbounded over the thread's lifetime.
  void _pruneBubbleKeys(Iterable<String> liveStableIds) {
    final live = liveStableIds.toSet();
    _bubbleKeys.removeWhere((stableId, _) => !live.contains(stableId));
  }

  /// Scroll to and briefly highlight the message a reply quotes.
  ///
  /// Best-effort: [Scrollable.ensureVisible] can only target a message the
  /// [ListView.builder] has actually built (on or near screen). For a target
  /// scrolled far out of view its key has no context yet, so the scroll is a
  /// no-op — acceptable for typically-short DM threads, and the same
  /// best-effort framing as the reply linkage itself.
  void _scrollToQuoted(String targetId) {
    final ctx = _bubbleKeys[targetId]?.currentContext;
    if (ctx != null) {
      _navigatingToQuote = true;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        alignment: 0.3,
        curve: Curves.easeInOut,
      ).whenComplete(() {
        if (mounted) _navigatingToQuote = false;
      });
    }
    setState(() => _highlightedId = targetId);
    Future.delayed(_highlightDuration, () {
      if (mounted && _highlightedId == targetId) {
        setState(() => _highlightedId = null);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    // Mark as read when opening.
    widget.chatService.markConversationRead(widget.conversation.id);
    // Fetch older history as the user scrolls toward the top. With a
    // reverse:true list the top is near maxScrollExtent.
    _scrollController.addListener(_maybeLoadOlder);
  }

  /// Load an older page of this DM's history when scrolled near the top.
  void _maybeLoadOlder() {
    if (_loadingOlder) return;
    final peerId = widget.conversation.peerId;
    if (peerId == null) return;
    if (!widget.chatService.hasMoreHistory(widget.conversation.id)) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels < pos.maxScrollExtent - 300) return;
    setState(() => _loadingOlder = true);
    widget.chatService.loadOlderDmMessages(peerId).whenComplete(() {
      if (mounted) setState(() => _loadingOlder = false);
    });
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

    final replyTarget = _replyTarget;
    widget.chatService.sendDm(
      peerId,
      text,
      peerDisplayName: widget.conversation.peerDisplayName ?? 'Unknown',
      replyTo: replyTarget,
    );
    _textController.clear();
    setState(() => _replyTarget = null);
    _focusNode.requestFocus();

    // Scroll to bottom. With a reverse:true list the newest message is at
    // offset 0 (the bottom), so "scroll to bottom" is animateTo(0).
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
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

  @override
  Widget build(BuildContext context) {
    final isBotDm = widget.conversation.peerId == 'bot-claude';
    final displayName = widget.conversation.peerDisplayName ?? 'Unknown';

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
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
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
                ? widget.chatService.dmMessages(widget.conversation.peerId!)
                : const Stream.empty(),
            initialData: widget.conversation.peerId != null
                ? widget.chatService
                    .dmMessagesSnapshot(widget.conversation.peerId!)
                : null,
            builder: (context, snapshot) {
              final messages = snapshot.data ?? [];
              _pruneBubbleKeys(messages.map((m) => m.stableId));

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
              // so reading history isn't interrupted. With reverse:true the
              // bottom (newest) is offset 0, so "near bottom" is a small
              // pixels value and snapping means jumpTo(0).
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_navigatingToQuote || !_scrollController.hasClients) return;
                final position = _scrollController.position;
                final isNearBottom = position.pixels <= 80;
                if (isNearBottom) {
                  _scrollController.jumpTo(0);
                }
              });

              // SelectionArea: drag-select + copy across DM messages, same
              // treatment as the group tab.
              //
              // reverse:true opens at the bottom (newest) and grows upward.
              // `messages` stays ascending; index 0 (visually the bottom) maps
              // to the last element. The trailing item (visually the TOP) is the
              // "loading older" spinner while paging back through history.
              final showOlderLoader = _loadingOlder;
              return SelectionArea(
                child: ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length + (showOlderLoader ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= messages.length) {
                      return const _DmOlderHistoryLoader();
                    }
                    final message = messages[messages.length - 1 - index];
                    return _DmBubble(
                      key: _keyFor(message.stableId),
                      message: message,
                      highlighted: message.stableId == _highlightedId,
                      onReply: () => _startReply(message),
                      onQuoteTap: message.isReply
                          ? () => _scrollToQuoted(message.replyToMessageId!)
                          : null,
                    );
                  },
                ),
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
        valueListenable: widget.chatService.botStatus,
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
    final replyTarget = _replyTarget;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (replyTarget != null)
          ReplyComposingBanner(
            target: replyTarget,
            onCancel: _cancelReply,
          ),
        if (showBanner)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.amber.shade800.withValues(alpha: 0.3),
            child: Row(
              children: [
                Icon(Icons.cloud_off, size: 16, color: Colors.amber.shade300),
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
                child: ChatComposerField(
                  controller: _textController,
                  focusNode: _focusNode,
                  enabled: !disabled,
                  hintText:
                      disabled ? 'Clawd is offline...' : 'Type a message...',
                  onSend: _sendMessage,
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

/// Top-of-list spinner shown while an older page of this DM's eternal history
/// loads. Mirrors the group tab's `_OlderHistoryLoader` (private per file).
class _DmOlderHistoryLoader extends StatelessWidget {
  const _DmOlderHistoryLoader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD97757)),
          ),
        ),
      ),
    );
  }
}

class _DmBubble extends StatelessWidget {
  const _DmBubble({
    super.key,
    required this.message,
    required this.onReply,
    this.highlighted = false,
    this.onQuoteTap,
  });

  final ChatMessage message;

  /// Invoked when the user chooses to quote-reply to this message.
  final VoidCallback onReply;

  /// Whether this bubble is the just-navigated-to quote target (brief flash).
  final bool highlighted;

  /// Invoked when the user taps this message's quote to jump to the original.
  /// `null` when this message isn't a reply.
  final VoidCallback? onQuoteTap;

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

    // Long-press anywhere on the bubble starts a quote-reply — a discoverable,
    // platform-agnostic affordance (works on touch + desktop) without adding a
    // persistent button to every row.
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
            child: GestureDetector(
              onLongPress: onReply,
              child: Column(
                crossAxisAlignment:
                    isLocal ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    // No key toggle here: changing a widget's key forces a
                    // rebuild instead of an animated update, which would defeat
                    // the fade. The findable highlight marker lives inside as a
                    // zero-size keyed child instead.
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: highlighted
                          ? _clawdOrange.withValues(alpha: 0.30)
                          : isLocal
                              ? _clawdOrange.withValues(alpha: 0.2)
                              : const Color(0xFF2D2D2D),
                      borderRadius: BorderRadius.circular(16),
                      border: highlighted
                          ? Border.all(color: _clawdOrange, width: 2)
                          : isLocal
                              ? Border.all(
                                  color: _clawdOrange.withValues(alpha: 0.3))
                              : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (highlighted)
                          const SizedBox.shrink(key: ValueKey('dm-highlight')),
                        if (message.isReply)
                          QuotedMessage(message: message, onTap: onQuoteTap),
                        MessageText(
                          message.text,
                          baseStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          mentionStyle: const TextStyle(
                            color: _clawdOrange,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          linkStyle: const TextStyle(
                            color: Color(0xFF7EB6FF),
                            fontSize: 14,
                            decoration: TextDecoration.underline,
                            decorationColor: Color(0xFF7EB6FF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Timestamp + subtle reply hint / button for
                  // discoverability.
                  BubbleFooter(
                    timestamp: message.timestamp,
                    onReply: onReply,
                  ),
                ],
              ),
            ),
          ),
          if (isLocal) const SizedBox(width: 36),
        ],
      ),
    );
  }
}
