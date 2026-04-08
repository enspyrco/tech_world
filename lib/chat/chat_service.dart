import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' show RemoteParticipant;
import 'package:logging/logging.dart';
import 'package:tech_world/chat/chat_message.dart';
import 'package:tech_world/chat/chat_message_repository.dart';
import 'package:tech_world/chat/conversation.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/services/dreamfinder_client.dart';
import 'package:tech_world/services/tts_service.dart';

final _log = Logger('ChatService');

/// Service that manages shared chat with Claude bot via LiveKit data channels,
/// plus private player-to-player DMs.
///
/// All participants see group messages (questions and responses).
/// DMs are delivered via targeted LiveKit data channels and persisted to
/// Firestore when a [ChatMessageRepository] is provided.
class ChatService {
  ChatService({
    required LiveKitService liveKitService,
    ChatMessageRepository? repository,
    DreamfinderClient? dreamfinderClient,
    @visibleForTesting Duration historyTimeout = const Duration(seconds: 15),
  })  : _liveKitService = liveKitService,
        _repository = repository,
        _dreamfinderClient = dreamfinderClient,
        _historyTimeout = historyTimeout,
        _ttsService = TtsService() {
    // Seed the group conversation.
    _conversations['group'] = Conversation(
      id: 'group',
      type: ConversationType.group,
    );
    _subscribeToMessages();
    _trackBotPresence();
  }

  final LiveKitService _liveKitService;
  final ChatMessageRepository? _repository;
  final DreamfinderClient? _dreamfinderClient;
  final Duration _historyTimeout;
  final TtsService _ttsService;

  // -- Group chat state (unchanged from before) --
  final _messagesController = StreamController<List<ChatMessage>>.broadcast();
  final List<ChatMessage> _messages = [];
  final Map<String, Completer<Map<String, dynamic>?>> _pendingMessages = {};
  /// Prevents duplicate messages. Capped at [_maxSeenIds] entries; when
  /// exceeded, the oldest half is removed. Uses [LinkedHashSet] to preserve
  /// insertion order for trimming.
  final LinkedHashSet<String> _seenMessageIds = LinkedHashSet<String>();
  /// 500 accommodates ~250 round-trip messages (each user message + bot
  /// response gets an ID). Increase if sessions routinely exceed this.
  static const _maxSeenIds = 500;
  final Map<String, Completer<String?>> _pendingHelpRequests = {};
  StreamSubscription<DataChannelMessage>? _chatSubscription;
  StreamSubscription<DataChannelMessage>? _helpResponseSubscription;
  StreamSubscription<RemoteParticipant>? _botJoinedSubscription;
  StreamSubscription<RemoteParticipant>? _botLeftSubscription;

  Stream<List<ChatMessage>> get messages => _messagesController.stream;
  List<ChatMessage> get currentMessages => List.unmodifiable(_messages);

  static const _botIdentity = 'bot-claude';

  // -- Conversation / DM state --
  final Map<String, Conversation> _conversations = {};
  final Map<String, List<ChatMessage>> _dmMessagesByConversation = {};
  final _conversationsController =
      StreamController<List<Conversation>>.broadcast();
  final Map<String, StreamController<List<ChatMessage>>>
      _dmStreamControllers = {};

  /// The room ID for Firestore persistence. Set via [loadHistory].
  String? _roomId;

  /// Stream of all conversations (group + DMs), sorted by last activity.
  Stream<List<Conversation>> get conversations =>
      _conversationsController.stream;

  /// Current snapshot of all conversations.
  List<Conversation> get currentConversations =>
      List.unmodifiable(_conversations.values.toList()
        ..sort((a, b) {
          final aTime = a.lastActivity ?? DateTime(0);
          final bTime = b.lastActivity ?? DateTime(0);
          return bTime.compareTo(aTime);
        }));

  /// Stream of messages for a specific DM conversation.
  Stream<List<ChatMessage>> dmMessages(String peerId) {
    final convId =
        Conversation.conversationIdFor(_liveKitService.userId, peerId);
    _dmStreamControllers[convId] ??=
        StreamController<List<ChatMessage>>.broadcast();
    return _dmStreamControllers[convId]!.stream;
  }

  /// Returns the current message list for a DM conversation, for use as
  /// [StreamBuilder.initialData] so the thread view renders immediately.
  List<ChatMessage> dmMessagesSnapshot(String peerId) {
    final convId =
        Conversation.conversationIdFor(_liveKitService.userId, peerId);
    return List.from(_dmMessagesByConversation[convId] ?? []);
  }

  /// The local user's ID, exposed for computing DM conversation IDs.
  String get localUserId => _liveKitService.userId;

  /// Total unread DM count across all conversations.
  final totalUnreadNotifier = ValueNotifier<int>(0);

  /// Returns the text of the most recent message in the given conversation,
  /// or `null` if no messages exist.
  String? lastDmMessageText(String conversationId) {
    final messages = _dmMessagesByConversation[conversationId];
    if (messages == null || messages.isEmpty) return null;
    return messages.last.text;
  }

  /// Track a message ID for deduplication, trimming the oldest entries when
  /// the set exceeds [_maxSeenIds].
  void _markSeen(String id) {
    _seenMessageIds.add(id);
    if (_seenMessageIds.length > _maxSeenIds) {
      // Remove the oldest half. Collect IDs first to avoid concurrent
      // modification during iteration.
      final toRemove = _seenMessageIds.length ~/ 2;
      final oldIds = _seenMessageIds.take(toRemove).toList();
      oldIds.forEach(_seenMessageIds.remove);
    }
  }

  void _subscribeToMessages() {
    // Listen for group chat messages and bot responses
    _chatSubscription = _liveKitService.dataReceived
        .where((msg) =>
            msg.topic == 'chat' ||
            msg.topic == 'chat-response' ||
            msg.topic == 'dm' ||
            msg.topic == 'dm-response')
        .listen(_handleMessage);

    // Listen for help-response messages from the bot
    _helpResponseSubscription = _liveKitService.dataReceived
        .where((msg) => msg.topic == 'help-response')
        .listen(_handleHelpResponse);
  }

  /// Track bot presence via LiveKit participant events.
  ///
  /// Uses the "subscribe-then-check" pattern: subscriptions are created
  /// *before* the initial participant check so that events arriving in the
  /// gap between creation and check are not missed. The subsequent check is
  /// idempotent (setting idle when already idle is a no-op).
  void _trackBotPresence() {
    // Subscribe FIRST so no events are missed.
    _botJoinedSubscription = _liveKitService.participantJoined
        .where((p) => p.identity == _botIdentity)
        .listen((_) {
      botStatusNotifier.value = BotStatus.idle;
    });

    _botLeftSubscription = _liveKitService.participantLeft
        .where((p) => p.identity == _botIdentity)
        .listen((_) {
      botStatusNotifier.value = BotStatus.absent;
    });

    // THEN check current state — idempotent if subscription already fired.
    final botPresent =
        _liveKitService.remoteParticipants.containsKey(_botIdentity);
    botStatusNotifier.value = botPresent ? BotStatus.idle : BotStatus.absent;
  }

  void _handleMessage(DataChannelMessage message) {
    final json = message.json;
    if (json == null) return;

    final text = json['text'] as String?;
    // 'id' is the message's own ID (for deduplication)
    // 'messageId' is the ID of the message being responded to (for correlation)
    final ownId = json['id'] as String?;
    final replyToId = json['messageId'] as String?;
    final senderName =
        json['senderName'] as String? ?? message.senderId ?? 'Unknown';
    final senderId = json['senderId'] as String? ?? message.senderId;

    if (text == null) return;

    // Skip if we've already seen this message (prevents duplicates)
    if (ownId != null && _seenMessageIds.contains(ownId)) return;
    if (ownId != null) _markSeen(ownId);

    final isDm =
        message.topic == 'dm' || message.topic == 'dm-response';

    // Skip our own outgoing group messages (we add them locally).
    // DMs from self are also added locally in sendDm, so skip those too.
    final isFromSelf = message.senderId == _liveKitService.userId;
    if (isFromSelf && (message.topic == 'chat' || message.topic == 'dm')) {
      return;
    }

    _log.fine(
        'Received ${message.topic} from ${message.senderId}: '
        '"${text.substring(0, text.length.clamp(0, 50))}..."');

    if (isDm) {
      _handleDmMessage(
        text: text,
        senderName: senderName,
        senderId: senderId ?? 'unknown',
        isResponse: message.topic == 'dm-response',
      );
    } else if (message.topic == 'chat-response') {
      // Bot response
      botStatusNotifier.value = BotStatus.idle;
      _messages.add(ChatMessage(
        text: text,
        senderName: 'Clawd',
        senderId: _botIdentity,
        conversationId: 'group',
        isBot: true,
      ));
      // Speak the response
      _ttsService.speak(text);
      _messagesController.add(List.from(_messages));
    } else {
      // Message from another user (group chat)
      _messages.add(ChatMessage(
        text: text,
        senderName: senderName,
        senderId: senderId,
        conversationId: 'group',
        isLocalUser: false,
      ));
      _messagesController.add(List.from(_messages));
    }

    // Complete pending message if this is a response to one of ours
    if (replyToId != null && _pendingMessages.containsKey(replyToId)) {
      _pendingMessages[replyToId]!.complete(json);
      _pendingMessages.remove(replyToId);
    }
  }

  /// Handle an incoming DM or dm-response.
  void _handleDmMessage({
    required String text,
    required String senderName,
    required String senderId,
    required bool isResponse,
  }) {
    final localUid = _liveKitService.userId;
    final convId = Conversation.conversationIdFor(localUid, senderId);

    final chatMessage = ChatMessage(
      text: text,
      senderName: senderName,
      senderId: senderId,
      conversationId: convId,
      participants: [localUid, senderId],
      isBot: isResponse,
    );

    // Ensure conversation exists, then update with new activity.
    final existing = _conversations[convId] ??
        Conversation(
          id: convId,
          type: ConversationType.dm,
          peerId: senderId,
          peerDisplayName: senderName,
        );

    _conversations[convId] = existing.copyWith(
      peerDisplayName: senderName,
      unreadCount: existing.unreadCount + 1,
      lastActivity: chatMessage.timestamp,
    );

    _dmMessagesByConversation[convId] ??= [];
    _dmMessagesByConversation[convId]!.add(chatMessage);

    // Emit to DM stream.
    _dmStreamControllers[convId] ??=
        StreamController<List<ChatMessage>>.broadcast();
    _dmStreamControllers[convId]!
        .add(List.from(_dmMessagesByConversation[convId]!));

    _emitConversations();
    _updateTotalUnread();

    // Persist to Firestore.
    _persistMessage(chatMessage);
  }

  /// Send a message to the shared chat (visible to all participants).
  ///
  /// Returns the bot's response JSON when a response arrives, or `null` on
  /// timeout or error. The caller can inspect fields like `challengeResult`.
  ///
  /// Optional [metadata] fields are merged into the published JSON payload
  /// (e.g. `{'challengeId': 'fizzbuzz'}` for challenge evaluations).
  ///
  /// Reserved keys (`type`, `id`, `text`, `senderName`, `timestamp`) are
  /// silently stripped from [metadata] to prevent protocol corruption.
  Future<Map<String, dynamic>?> sendMessage(
    String text, {
    Map<String, dynamic>? metadata,
  }) async {
    if (text.trim().isEmpty) return null;

    if (!_liveKitService.isConnected) {
      _log.warning('Not connected to LiveKit, cannot send message');
      _messages.add(ChatMessage(
        text: "I can't reach Clawd right now. Please check your connection.",
        senderName: 'System',
        isBot: true,
      ));
      _messagesController.add(List.from(_messages));
      return null;
    }

    if (botStatusNotifier.value == BotStatus.absent) {
      _log.warning('Bot is not in the room');
      _messages.add(ChatMessage(
        text: "Clawd isn't in the room right now. Try again in a moment!",
        senderName: 'System',
        isBot: true,
      ));
      _messagesController.add(List.from(_messages));
      return null;
    }

    // Generate a unique message ID
    final messageId = DateTime.now().millisecondsSinceEpoch.toString();
    _markSeen(messageId); // Mark as seen so we don't duplicate

    // Add user message locally
    final userMessage = ChatMessage(
      text: text,
      senderName: _liveKitService.displayName,
      senderId: _liveKitService.userId,
      conversationId: 'group',
      isLocalUser: true,
    );
    _messages.add(userMessage);
    _messagesController.add(List.from(_messages));

    // Show thinking indicator
    botStatusNotifier.value = BotStatus.thinking;

    // Create a completer to track when we get a response
    final completer = Completer<Map<String, dynamic>?>();
    _pendingMessages[messageId] = completer;

    // Send message to all participants (no destinationIdentities = broadcast)
    const reservedKeys = {'type', 'id', 'text', 'senderName', 'timestamp'};
    final safeMetadata =
        metadata?.entries.where((e) => !reservedKeys.contains(e.key));

    final payload = {
      'type': 'chat',
      'id': messageId,
      'text': text,
      'senderName': _liveKitService.displayName,
      'timestamp': DateTime.now().toIso8601String(),
      if (safeMetadata != null) ...Map.fromEntries(safeMetadata),
    };

    await _liveKitService.publishJson(
      payload,
      topic: 'chat',
      // No destinationIdentities = broadcast to all
    );

    // Forward to Dreamfinder for AI processing (fire-and-forget).
    unawaited(_dreamfinderClient?.sendEvent(
      topic: GameEventTopic.chat,
      roomName: _liveKitService.roomName,
      senderId: _liveKitService.userId,
      senderName: _liveKitService.displayName,
      payload: payload,
    ));

    _log.info('Sent message: "$text"');

    // Persist to Firestore.
    _persistMessage(userMessage);

    // Wait for response with timeout
    try {
      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _log.warning('Response timeout');
          // Only reset to idle if bot is still present; if it left during
          // the wait the participantLeft handler already set absent.
          if (botStatusNotifier.value != BotStatus.absent) {
            botStatusNotifier.value = BotStatus.idle;
          }
          _messages.add(ChatMessage(
            text: "Hmm, Clawd seems to be taking a while. Try again?",
            senderName: 'System',
            isBot: true,
          ));
          _messagesController.add(List.from(_messages));
          _pendingMessages.remove(messageId);
          return null;
        },
      );
    } catch (e) {
      _log.severe('Error waiting for response', e);
      _pendingMessages.remove(messageId);
      // Reset bot status so the UI doesn't stay in "thinking" state.
      if (botStatusNotifier.value == BotStatus.thinking) {
        botStatusNotifier.value = BotStatus.idle;
      }
      return null;
    }
  }

  /// Send a private direct message to another user.
  ///
  /// Uses targeted LiveKit data channels so only the recipient sees it.
  Future<void> sendDm(
    String peerId,
    String text, {
    required String peerDisplayName,
  }) async {
    if (text.trim().isEmpty) return;

    if (!_liveKitService.isConnected) {
      _log.warning('Not connected, cannot send DM');
      return;
    }

    final convId = Conversation.conversationIdFor(
      _liveKitService.userId,
      peerId,
    );

    final messageId = DateTime.now().millisecondsSinceEpoch.toString();
    _markSeen(messageId);

    final localUid = _liveKitService.userId;
    final chatMessage = ChatMessage(
      text: text,
      senderName: _liveKitService.displayName,
      senderId: localUid,
      conversationId: convId,
      participants: [localUid, peerId],
      isLocalUser: true,
    );

    // Ensure conversation exists, then update last activity.
    final existing = _conversations[convId] ??
        Conversation(
          id: convId,
          type: ConversationType.dm,
          peerId: peerId,
          peerDisplayName: peerDisplayName,
        );
    _conversations[convId] = existing.copyWith(
      lastActivity: chatMessage.timestamp,
    );

    _dmMessagesByConversation[convId] ??= [];
    _dmMessagesByConversation[convId]!.add(chatMessage);

    // Emit to DM stream.
    _dmStreamControllers[convId] ??=
        StreamController<List<ChatMessage>>.broadcast();
    _dmStreamControllers[convId]!
        .add(List.from(_dmMessagesByConversation[convId]!));

    _emitConversations();

    // Send via LiveKit targeted data channel.
    final payload = {
      'type': 'dm',
      'id': messageId,
      'text': text,
      'senderName': _liveKitService.displayName,
      'senderId': _liveKitService.userId,
      'timestamp': DateTime.now().toIso8601String(),
    };

    await _liveKitService.publishJson(
      payload,
      topic: 'dm',
      destinationIdentities: [peerId],
    );

    _log.info('Sent DM to $peerId: "$text"');

    // Persist to Firestore.
    _persistMessage(chatMessage);
  }

  /// Mark a conversation as read, resetting its unread count.
  void markConversationRead(String conversationId) {
    final conv = _conversations[conversationId];
    if (conv == null) return;

    _conversations[conversationId] = conv.copyWith(unreadCount: 0);
    _emitConversations();
    _updateTotalUnread();
  }

  /// Load chat history from Firestore for the given room.
  ///
  /// This is called on the critical sign-in path, so it must never throw.
  /// A single overall timeout caps total wall-clock time regardless of how
  /// many conversations exist. Partially loaded DMs are still emitted via
  /// the `finally` block so the UI shows whatever was fetched before failure.
  Future<void> loadHistory(String roomId) async {
    _roomId = roomId;
    final repository = _repository;
    if (repository == null) return;

    try {
      await _fetchAndCacheHistory(roomId, repository).timeout(_historyTimeout);
    } catch (e) {
      _log.warning('Failed to load history', e);
      // Don't rethrow — allow the room to load without history.
    } finally {
      _emitConversations();
    }
  }

  /// Loads conversation IDs and their messages from Firestore.
  ///
  /// Extracted so [loadHistory] can wrap the entire operation in a single
  /// timeout rather than per-query timeouts that can accumulate.
  Future<void> _fetchAndCacheHistory(
    String roomId,
    ChatMessageRepository repository,
  ) async {
    final conversationIds =
        await repository.loadConversationIds(roomId, _liveKitService.userId);

    for (final convId in conversationIds) {
      final messages = await repository.loadMessages(roomId, convId);
      if (messages.isEmpty) continue;

      if (convId == 'group') {
        for (final msg in messages) {
          _messages.add(ChatMessage(
            text: msg.text,
            senderName: msg.senderName,
            senderId: msg.senderId,
            conversationId: 'group',
            isLocalUser: msg.senderId == _liveKitService.userId,
            isBot: msg.senderId == _botIdentity,
            timestamp: msg.timestamp,
          ));
        }
        _messagesController.add(List.from(_messages));
      } else {
        // DM conversation — figure out peer from the conversation ID.
        _dmMessagesByConversation[convId] = messages.map((msg) {
          return ChatMessage(
            text: msg.text,
            senderName: msg.senderName,
            senderId: msg.senderId,
            conversationId: convId,
            isLocalUser: msg.senderId == _liveKitService.userId,
            isBot: msg.senderId == _botIdentity,
            timestamp: msg.timestamp,
          );
        }).toList();

        // Determine peer info from the most recent message not from us.
        final peerMsg = messages.lastWhere(
          (m) => m.senderId != _liveKitService.userId,
          orElse: () => messages.last,
        );

        _conversations[convId] ??= Conversation(
          id: convId,
          type: ConversationType.dm,
          peerId: peerMsg.senderId,
          peerDisplayName: peerMsg.senderName,
          lastActivity: messages.last.timestamp,
        );
      }
    }
  }

  /// Handle a help-response message from the bot.
  void _handleHelpResponse(DataChannelMessage message) {
    final json = message.json;
    if (json == null) return;

    final requestId = json['requestId'] as String?;
    final hint = json['hint'] as String?;
    if (requestId == null || hint == null) return;

    _log.fine('Received help-response for $requestId');

    // Speak the hint aloud so Clawd "says" it when arriving (web only)
    _ttsService.speak(hint);

    final completer = _pendingHelpRequests.remove(requestId);
    completer?.complete(hint);
  }

  /// Request a hint from Clawd for the current coding challenge.
  ///
  /// Publishes a `help-request` message targeted to the bot and waits for a
  /// `help-response` containing a hint. Returns `null` on timeout or error.
  Future<String?> requestHelp({
    required String challengeId,
    required String challengeTitle,
    required String challengeDescription,
    required String code,
    required int terminalX,
    required int terminalY,
  }) async {
    if (!_liveKitService.isConnected) {
      _log.warning('Not connected, cannot request help');
      return null;
    }

    if (botStatusNotifier.value == BotStatus.absent) {
      _log.warning('Bot is absent, cannot request help');
      return null;
    }

    final requestId = 'help-${DateTime.now().millisecondsSinceEpoch}';
    final completer = Completer<String?>();
    _pendingHelpRequests[requestId] = completer;

    final payload = {
      'type': 'help-request',
      'id': requestId,
      'challengeId': challengeId,
      'challengeTitle': challengeTitle,
      'challengeDescription': challengeDescription,
      'code': code,
      'terminalX': terminalX,
      'terminalY': terminalY,
      'senderName': _liveKitService.displayName,
      'timestamp': DateTime.now().toIso8601String(),
    };

    await _liveKitService.publishJson(
      payload,
      topic: 'help-request',
      destinationIdentities: const [_botIdentity],
    );

    // Forward to Dreamfinder for AI processing (fire-and-forget).
    unawaited(_dreamfinderClient?.sendEvent(
      topic: GameEventTopic.helpRequest,
      roomName: _liveKitService.roomName,
      senderId: _liveKitService.userId,
      senderName: _liveKitService.displayName,
      payload: payload,
    ));

    _log.info('Sent help-request $requestId');

    try {
      return await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          _log.warning('Help request timeout');
          _pendingHelpRequests.remove(requestId);
          return null;
        },
      );
    } catch (e) {
      _log.severe('Error waiting for help response', e);
      _pendingHelpRequests.remove(requestId);
      return null;
    }
  }

  void _emitConversations() {
    _conversationsController.add(currentConversations);
  }

  void _updateTotalUnread() {
    var total = 0;
    for (final conv in _conversations.values) {
      if (conv.type == ConversationType.dm) {
        total += conv.unreadCount;
      }
    }
    totalUnreadNotifier.value = total;
  }

  /// Persist a message to Firestore if a repository and room ID are available.
  ///
  /// Also upserts conversation metadata for DMs so that
  /// [ChatMessageRepository.loadConversationIds] can use an efficient query.
  void _persistMessage(ChatMessage message) {
    final repository = _repository;
    final roomId = _roomId;
    if (repository == null || roomId == null) return;

    // Fire-and-forget — don't block on Firestore writes.
    repository.saveMessage(roomId, message).catchError((Object e) {
      _log.warning('Failed to persist message', e);
    });

    // Upsert conversation metadata for DMs.
    final convId = message.conversationId;
    final participants = message.participants;
    if (convId != null && convId != 'group' && participants != null) {
      repository
          .saveConversation(
        roomId,
        conversationId: convId,
        participants: participants,
        type: 'dm',
        lastMessageText: message.text,
      )
          .catchError((Object e) {
        _log.warning('Failed to persist conversation', e);
      });
    }
  }

  void dispose() {
    _chatSubscription?.cancel();
    _helpResponseSubscription?.cancel();
    _botJoinedSubscription?.cancel();
    _botLeftSubscription?.cancel();
    _messagesController.close();
    _conversationsController.close();
    for (final controller in _dmStreamControllers.values) {
      controller.close();
    }
    _dreamfinderClient?.dispose();
    _ttsService.dispose();
  }
}
