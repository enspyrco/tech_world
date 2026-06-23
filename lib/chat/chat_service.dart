import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' show RemoteParticipant;
import 'package:logging/logging.dart';
import 'package:tech_world/chat/chat_message.dart';
import 'package:tech_world/chat/chat_message_repository.dart';
import 'package:tech_world/chat/conversation.dart';
import 'package:tech_world/bots/bot_config.dart';
import 'package:tech_world/editor/challenge.dart' show CodeChallengeId;
import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/types.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/livekit/livekit_topic.dart';
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

  /// Bot presence state — owned by this service, exposed as read-only.
  final _botStatus = ValueNotifier<BotStatus>(BotStatus.absent);

  /// Read-only view of the bot's presence state. UI consumers listen to this
  /// instead of the former global `botStatusNotifier`.
  ValueListenable<BotStatus> get botStatus => _botStatus;

  /// Mark the bot as absent. Called by [RoomSession] on connection loss
  /// and by the UI layer on room leave.
  void markBotAbsent() {
    _botStatus.value = BotStatus.absent;
  }

  /// Test-only: force bot status to [status] without simulating LiveKit events.
  @visibleForTesting
  void setBotStatusForTest(BotStatus status) {
    _botStatus.value = status;
  }

  // -- Group chat state (unchanged from before) --
  final _messagesController = StreamController<List<ChatMessage>>.broadcast();
  final List<ChatMessage> _messages = [];
  final Map<String, Completer<Map<String, dynamic>?>> _pendingMessages = {};

  /// Submissions queued for retry after bot disconnect during evaluation.
  /// Keyed by challengeId so only the latest attempt per challenge is kept.
  /// Stores the text + metadata needed to reconstruct a [sendMessage] call,
  /// plus a retry counter (max [_maxRetries]).
  final Map<String, ({String text, Map<String, dynamic>? metadata, int attempts})>
      _pendingRetries = {};

  /// Maximum number of retry attempts before dropping a submission.
  static const _maxRetries = 2;

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

  /// The active bot identity in the room. Updated dynamically when a bot
  /// participant joins — supports both fixed identities ('bot-claude') and
  /// LiveKit agent auto-identities ('agent-AJ_xxxxx').
  String _activeBotIdentity = 'bot-claude';

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

  /// Generate a unique message ID using microsecond resolution.
  ///
  /// Microsecond timestamps make collisions astronomically unlikely even for
  /// rapid back-to-back calls (unlike milliseconds, which can collide within
  /// the same tick and cause silent deduplication via [_seenMessageIds]).
  String _nextMessageId() =>
      DateTime.now().microsecondsSinceEpoch.toString();

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
            msg.topic == LiveKitTopic.chat.wire ||
            msg.topic == LiveKitTopic.chatResponse.wire ||
            msg.topic == LiveKitTopic.dm.wire ||
            msg.topic == LiveKitTopic.dmResponse.wire)
        .listen(_handleMessage);

    // Listen for help-response messages from the bot
    _helpResponseSubscription = _liveKitService.dataReceived
        .where((msg) => msg.topic == LiveKitTopic.helpResponse.wire)
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
        .where((p) => isBotIdentity(p.identity))
        .listen((p) {
      _activeBotIdentity = p.identity;
      final wasAbsent = _botStatus.value == BotStatus.absent;
      _botStatus.value = BotStatus.idle;
      dispatch([BotJoined(identity: p.identity)]);
      if (wasAbsent) {
        retryPendingSubmissions();
      }
    });

    _botLeftSubscription = _liveKitService.participantLeft
        .where((p) => isBotIdentity(p.identity))
        .listen((_) {
      // Only go absent if no other bots remain.
      final anyBotLeft = _liveKitService.remoteParticipants.values
          .any((r) => isBotIdentity(r.identity));
      if (!anyBotLeft) {
        _botStatus.value = BotStatus.absent;
        dispatch([BotLeft()]);
      }
    });

    // THEN check current state — idempotent if subscription already fired.
    final activeBot = _liveKitService.remoteParticipants.values
        .where((p) => isBotIdentity(p.identity))
        .firstOrNull;
    if (activeBot != null) {
      _activeBotIdentity = activeBot.identity;
      _botStatus.value = BotStatus.idle;
    } else {
      _botStatus.value = BotStatus.absent;
    }
  }

  void _handleMessage(DataChannelMessage message) {
    final json = message.json;
    if (json == null) return;

    // Every field is coerced via asStringOrNull rather than an `as String?`
    // cast: a present-but-wrong-type value (e.g. `text: 123`) would make the
    // cast throw *inside* this stream callback and tear down the chat
    // subscription — the `as`-cast-in-stream-teardown failure class (#364/#366).
    // asStringOrNull drops a malformed field to null instead of throwing.
    final text = ChatMessage.asStringOrNull(json['text']);
    // 'id' is the message's own ID (for deduplication)
    // 'messageId' is the ID of the message being responded to (for correlation)
    final ownId = ChatMessage.asStringOrNull(json['id']);
    final replyToId = ChatMessage.asStringOrNull(json['messageId']);
    // senderName is cosmetic — payload value is acceptable for display.
    final senderName = ChatMessage.asStringOrNull(json['senderName']) ??
        message.senderId ??
        'Unknown';
    // payloadSenderId is read from the JSON payload, which the bot uses to
    // advertise its specific identity in chat-response messages. Bots are
    // trusted LiveKit participants so payload-sourced senderId is safe THERE.
    // Never use payloadSenderId for DMs or group chat from regular users —
    // a malicious participant could spoof another user's UID via the payload.
    // For those paths, use message.senderId (LiveKit transport, server-verified).
    final payloadSenderId =
        ChatMessage.asStringOrNull(json['senderId']) ?? message.senderId;

    if (text == null) return;

    // Skip if we've already seen this message (prevents duplicates)
    if (ownId != null && _seenMessageIds.contains(ownId)) return;
    if (ownId != null) _markSeen(ownId);

    final isDm =
        message.topic == LiveKitTopic.dm.wire ||
        message.topic == LiveKitTopic.dmResponse.wire;

    // Skip our own outgoing group messages (we add them locally).
    // DMs from self are also added locally in sendDm, so skip those too.
    final isFromSelf = message.senderId == _liveKitService.userId;
    if (isFromSelf &&
        (message.topic == LiveKitTopic.chat.wire ||
            message.topic == LiveKitTopic.dm.wire)) {
      return;
    }

    _log.fine(
        'Received ${message.topic} from ${message.senderId}: '
        '"${text.substring(0, text.length.clamp(0, 50))}..."');

    if (isDm) {
      // Reply linkage + quote snapshot are display-only and parsed defensively
      // AND atomically (all three together or none — a half-reply from a
      // malformed / hostile payload is rejected wholesale). They do NOT affect
      // the trust boundary below — the reply's sender is still the transport
      // identity.
      final reply = ChatMessage.parseReplySnapshot(json);

      // Trust the transport-verified identity over the payload — prevents
      // a malicious peer from filing a DM under another user's UID by
      // spoofing senderId in the payload.
      _handleDmMessage(
        text: text,
        senderName: senderName,
        senderId: message.senderId ?? 'unknown',
        isResponse: message.topic == LiveKitTopic.dmResponse.wire,
        replyToMessageId: reply.messageId,
        replyToText: reply.text,
        replyToSenderName: reply.senderName,
      );
    } else if (message.topic == LiveKitTopic.chatResponse.wire) {
      // Bot response — use sender info from payload (supports multiple bots).
      _botStatus.value = BotStatus.idle;
      _messages.add(ChatMessage(
        text: text,
        senderName: senderName,
        senderId: payloadSenderId ?? _activeBotIdentity,
        conversationId: 'group',
        isBot: true,
      ));
      // Speak the response
      _ttsService.speak(text);
      dispatch([BotSpoke(text: text, context: BotSpokeContext.group)]);
      _messagesController.add(List.from(_messages));
    } else {
      // Message from another user (group chat) — use transport-verified
      // identity. Never trust payload senderId from a regular participant;
      // they could spoof another user's UID.
      //
      // Reply linkage + quote snapshot are display-only and parsed defensively
      // AND atomically (all three together or none — a half-reply from a
      // malformed / hostile payload is rejected wholesale). They do NOT affect
      // the trust boundary above — the message's sender is still the transport
      // identity, never the payload. Same discipline as the DM branch.
      final reply = ChatMessage.parseReplySnapshot(json);

      _messages.add(ChatMessage(
        text: text,
        senderName: senderName,
        senderId: message.senderId ?? 'unknown',
        conversationId: 'group',
        isLocalUser: false,
        replyToMessageId: reply.messageId,
        replyToText: reply.text,
        replyToSenderName: reply.senderName,
      ));
      _messagesController.add(List.from(_messages));

      // Structured @mention list — the trust anchor for the world beacon.
      // Parsed defensively (malformed → empty, no throw). The mentioner is the
      // TRANSPORT-verified sender, never the payload's self-reported senderId —
      // a peer can name victims but cannot forge who sent the mention. Only
      // dispatch when at least one valid UID survives parsing.
      final mentionedUids = ChatMessage.parseMentions(json['mentions']);
      if (mentionedUids.isNotEmpty) {
        dispatch([PlayersMentioned(
          mentionedUids: mentionedUids,
          mentionerUid: message.senderId ?? 'unknown',
          messageId: ownId ?? _nextMessageId(),
        )]);
      }
    }

    // Complete pending message if this is a response to one of ours
    if (replyToId != null && _pendingMessages.containsKey(replyToId)) {
      _pendingMessages[replyToId]!.complete(json);
      _pendingMessages.remove(replyToId);
    }
  }

  /// Handle an incoming DM or dm-response.
  ///
  /// [replyToMessageId] / [replyToText] / [replyToSenderName] are the optional
  /// quote-reply snapshot, already coerced to `String?` at the wire seam by
  /// the caller. They are display-only and never influence [senderId], which
  /// remains the transport-verified identity.
  void _handleDmMessage({
    required String text,
    required String senderName,
    required String senderId,
    required bool isResponse,
    String? replyToMessageId,
    String? replyToText,
    String? replyToSenderName,
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
      replyToMessageId: replyToMessageId,
      replyToText: replyToText,
      replyToSenderName: replyToSenderName,
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
  /// (e.g. `{'promptChallengeId': 'evocation_fizzbuzz'}` for cast
  /// evaluations). All values must be JSON-serializable — the
  /// `Map<String, dynamic>` signature accepts anything at compile time,
  /// but typed enums and other non-primitives must be converted to their
  /// wire form (e.g. `PromptChallengeId.evocationFizzbuzz.wireName`)
  /// before being put into this map.
  ///
  /// Reserved keys (`type`, `id`, `text`, `senderName`, `timestamp`) are
  /// silently stripped from [metadata] to prevent protocol corruption.
  ///
  /// To quote-reply to an earlier message, pass [replyTo] — the single message
  /// being replied to. Its ID ([ChatMessage.localKey]) and display snapshot
  /// ([ChatMessage.replyToText] / [ChatMessage.replyToSenderName]) are derived
  /// from it together, so the "half-reply" state (an ID with no snapshot, or
  /// vice-versa) is unrepresentable. The snapshot is display-only — the
  /// *sender* of this reply is still derived from the authenticated local
  /// identity, never from the quoted message.
  Future<Map<String, dynamic>?> sendMessage(
    String text, {
    Map<String, dynamic>? metadata,
    ChatMessage? replyTo,
    List<String> mentions = const [],
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

    if (_botStatus.value == BotStatus.absent) {
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
    final messageId = _nextMessageId();
    _markSeen(messageId); // Mark as seen so we don't duplicate

    // Reply linkage + quote snapshot, all derived from the single [replyTo] so
    // they're always consistent (both present or both absent). Display-only.
    final replyToMessageId = replyTo?.localKey;
    final replyText = replyTo?.text;
    final replySenderName = replyTo?.senderName;

    // Add user message locally
    final userMessage = ChatMessage(
      text: text,
      senderName: _liveKitService.displayName,
      senderId: _liveKitService.userId,
      conversationId: 'group',
      isLocalUser: true,
      replyToMessageId: replyToMessageId,
      replyToText: replyText,
      replyToSenderName: replySenderName,
    );
    _messages.add(userMessage);
    _messagesController.add(List.from(_messages));

    // Show thinking indicator
    _botStatus.value = BotStatus.thinking;

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
      if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
      if (replyText != null) 'replyToText': replyText,
      if (replySenderName != null) 'replyToSenderName': replySenderName,
      // The structured @mention UID list — the trust anchor for the world
      // beacon. Inline `@Name` text in [text] is display-only. Omitted entirely
      // when empty so a plain message carries no `mentions` key.
      if (mentions.isNotEmpty) 'mentions': mentions,
      'timestamp': DateTime.now().toIso8601String(),
      if (safeMetadata != null) ...Map.fromEntries(safeMetadata),
    };

    await _liveKitService.publishJson(
      payload,
      topic: LiveKitTopic.chat.wire,
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

    // Dispatch the mention locally too — LiveKit does NOT loop our own
    // publishData back to us, so without this the SENDER never witnesses their
    // own mention bloom/arc (breaking "witnessed by everyone"). Mirrors the
    // optimistic local-add of the chat message above. The mentioner is our own
    // authenticated identity. The receive path dispatches the same event for
    // remote participants, so both routes funnel through one world consumer.
    if (mentions.isNotEmpty) {
      dispatch([PlayersMentioned(
        mentionedUids: mentions,
        mentionerUid: _liveKitService.userId,
        messageId: messageId,
      )]);
    }

    _log.info('Sent message (id=$messageId, len=${text.length})');
    final challengeWire = metadata?['challengeId'] as String?;
    dispatch([GroupMessageSent(
      messageId: messageId,
      challengeId: challengeWire == null ? null : ChallengeRef.parse(challengeWire),
    )]);

    // Persist to Firestore.
    _persistMessage(userMessage);

    // Wait for response with timeout
    try {
      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _log.warning('Response timeout');
          _pendingMessages.remove(messageId);

          // Bot disconnected during evaluation — queue for retry.
          if (_botStatus.value == BotStatus.absent) {
            final challengeId = metadata?['challengeId'] as String?;
            if (challengeId != null) {
              // Preserve existing attempt count if re-queuing, otherwise
              // start at 0. The counter is incremented in
              // retryPendingSubmissions when the retry is actually sent.
              final existing = _pendingRetries[challengeId];
              final attempts = existing?.attempts ?? 0;
              _pendingRetries[challengeId] = (
                text: text,
                metadata: metadata,
                attempts: attempts,
              );
              _log.info('Queued retry for challenge $challengeId '
                  '(attempt $attempts)');
            }
            _messages.add(ChatMessage(
              text: "Clawd disconnected \u2014 your submission will be "
                  "retried when Clawd returns.",
              senderName: 'System',
              isBot: true,
            ));
            _messagesController.add(List.from(_messages));
            return null;
          }

          // Bot still present but slow — normal timeout.
          _botStatus.value = BotStatus.idle;
          _messages.add(ChatMessage(
            text: "Hmm, Clawd seems to be taking a while. Try again?",
            senderName: 'System',
            isBot: true,
          ));
          _messagesController.add(List.from(_messages));
          return null;
        },
      );
    } catch (e) {
      _log.severe('Error waiting for response', e);
      _pendingMessages.remove(messageId);
      // Reset bot status so the UI doesn't stay in "thinking" state.
      if (_botStatus.value == BotStatus.thinking) {
        _botStatus.value = BotStatus.idle;
      }
      return null;
    }
  }

  /// Re-send all submissions that were queued while Clawd was disconnected.
  ///
  /// Called automatically when bot transitions from [BotStatus.absent] to
  /// [BotStatus.idle]. Each queued submission is sent through [sendMessage]
  /// which provides proper timeout handling. After [_maxRetries] attempts a
  /// submission is dropped with a user-visible message.
  void retryPendingSubmissions() {
    if (_pendingRetries.isEmpty) return;

    _log.info('Retrying ${_pendingRetries.length} queued submission(s)');

    // Snapshot and clear so re-entrant timeouts can re-queue safely.
    final retries = Map<String,
        ({String text, Map<String, dynamic>? metadata, int attempts})>.from(
        _pendingRetries);
    _pendingRetries.clear();

    for (final entry in retries.entries) {
      final challengeId = entry.key;
      final (:text, :metadata, :attempts) = entry.value;

      if (attempts >= _maxRetries) {
        _log.warning('Dropping submission for challenge $challengeId '
            'after $_maxRetries retries');
        _messages.add(ChatMessage(
          text: 'Submission could not be delivered after multiple attempts.',
          senderName: 'System',
          isBot: true,
        ));
        _messagesController.add(List.from(_messages));
        continue;
      }

      _log.info('Retrying submission for challenge $challengeId '
          '(attempt ${attempts + 1}/$_maxRetries)');

      _messages.add(ChatMessage(
        text: 'Clawd is back \u2014 retrying your submission\u2026',
        senderName: 'System',
        isBot: true,
      ));
      _messagesController.add(List.from(_messages));

      // Pre-populate the retry entry with incremented attempt count so that
      // if sendMessage times out and re-queues, the new entry carries the
      // incremented count. Removed on success so a reconnect doesn't re-send
      // an already-succeeded challenge.
      _pendingRetries[challengeId] = (
        text: text,
        metadata: metadata,
        attempts: attempts + 1,
      );

      // Route through sendMessage for proper timeout + completer handling.
      // On success, remove the pre-populated entry so a future reconnect
      // doesn't re-send an already-delivered submission.
      unawaited(
        sendMessage(text, metadata: metadata).then(
          (_) => _pendingRetries.remove(challengeId),
        ),
      );
    }
  }


  /// Send a private direct message to another user.
  ///
  /// Uses targeted LiveKit data channels so only the recipient sees it.
  ///
  /// To quote-reply to an earlier message, pass [replyTo] — the single message
  /// being replied to. Its ID ([ChatMessage.localKey]) and display snapshot
  /// ([ChatMessage.replyToText] / [ChatMessage.replyToSenderName]) are derived
  /// from it together, so the "half-reply" state (an ID with no snapshot, or
  /// vice-versa) is unrepresentable. The snapshot is display-only — the
  /// *sender* of this reply is still derived from the authenticated local
  /// identity, never from the quoted message.
  Future<void> sendDm(
    String peerId,
    String text, {
    required String peerDisplayName,
    ChatMessage? replyTo,
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

    final messageId = _nextMessageId();
    _markSeen(messageId);

    // Reply linkage + quote snapshot, all derived from the single [replyTo] so
    // they're always consistent (both present or both absent). Display-only.
    final replyToMessageId = replyTo?.localKey;
    final replyText = replyTo?.text;
    final replySenderName = replyTo?.senderName;

    final localUid = _liveKitService.userId;
    final chatMessage = ChatMessage(
      text: text,
      senderName: _liveKitService.displayName,
      senderId: localUid,
      conversationId: convId,
      participants: [localUid, peerId],
      isLocalUser: true,
      replyToMessageId: replyToMessageId,
      replyToText: replyText,
      replyToSenderName: replySenderName,
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
      if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
      if (replyText != null) 'replyToText': replyText,
      if (replySenderName != null) 'replyToSenderName': replySenderName,
      'timestamp': DateTime.now().toIso8601String(),
    };

    await _liveKitService.publishJson(
      payload,
      topic: LiveKitTopic.dm.wire,
      destinationIdentities: [peerId],
    );

    _log.info('Sent DM to $peerId: "$text"');
    dispatch([DmSent(peerId: peerId, conversationId: convId)]);

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
          // These are re-constructed (rather than reusing `msg`) only to
          // recompute the locally-derived flags isLocalUser/isBot, which are
          // not persisted. Every PERSISTED field must be carried through —
          // dropping one here silently loses it on reload (the reply-field
          // rehydration bug). Keep this in sync with the DM mapping below.
          _messages.add(ChatMessage(
            text: msg.text,
            senderName: msg.senderName,
            senderId: msg.senderId,
            conversationId: 'group',
            isLocalUser: msg.senderId == _liveKitService.userId,
            isBot: msg.senderId != null && isBotIdentity(msg.senderId!),
            replyToMessageId: msg.replyToMessageId,
            replyToText: msg.replyToText,
            replyToSenderName: msg.replyToSenderName,
            timestamp: msg.timestamp,
          ));
        }
        _messagesController.add(List.from(_messages));
      } else {
        // DM conversation — figure out peer from the conversation ID.
        // See the group mapping above: carry every persisted field through so a
        // persisted reply still has its linkage + quote snapshot after reload.
        _dmMessagesByConversation[convId] = messages.map((msg) {
          return ChatMessage(
            text: msg.text,
            senderName: msg.senderName,
            senderId: msg.senderId,
            conversationId: convId,
            isLocalUser: msg.senderId == _liveKitService.userId,
            isBot: msg.senderId != null && isBotIdentity(msg.senderId!),
            replyToMessageId: msg.replyToMessageId,
            replyToText: msg.replyToText,
            replyToSenderName: msg.replyToSenderName,
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

    // Defensive parse (same seam totality as _handleMessage): a wrong-type
    // field must drop to null, never throw and tear down the help-response
    // subscription.
    final requestId = ChatMessage.asStringOrNull(json['requestId']);
    final hint = ChatMessage.asStringOrNull(json['hint']);
    if (requestId == null || hint == null) return;

    _log.fine('Received help-response for $requestId');

    // Speak the hint aloud so Clawd "says" it when arriving (web only)
    _ttsService.speak(hint);
    dispatch([BotSpoke(text: hint, context: BotSpokeContext.help)]);

    final completer = _pendingHelpRequests.remove(requestId);
    completer?.complete(hint);
  }

  /// Request a hint from Clawd for the current coding challenge.
  ///
  /// Publishes a `help-request` message targeted to the bot and waits for a
  /// `help-response` containing a hint. Returns `null` on timeout or error.
  ///
  /// [challengeId] is [CodeChallengeId] because help requests only fire
  /// from the code editor (prompt challenges use voice-cast / spellbook,
  /// not a hint affordance).
  Future<String?> requestHelp({
    required CodeChallengeId challengeId,
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

    if (_botStatus.value == BotStatus.absent) {
      _log.warning('Bot is absent, cannot request help');
      return null;
    }

    final requestId = 'help-${DateTime.now().microsecondsSinceEpoch}';
    final completer = Completer<String?>();
    _pendingHelpRequests[requestId] = completer;

    final payload = {
      'type': 'help-request',
      'id': requestId,
      'challengeId': challengeId.wireName,
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
      topic: LiveKitTopic.helpRequest.wire,
      destinationIdentities: [_activeBotIdentity],
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
    dispatch([HelpRequested(challengeId: CodeRef(challengeId))]);

    try {
      return await completer.future.timeout(
        const Duration(seconds: 30),
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

  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _chatSubscription?.cancel();
    _helpResponseSubscription?.cancel();
    _botJoinedSubscription?.cancel();
    _botLeftSubscription?.cancel();
    _pendingRetries.clear();
    _messagesController.close();
    _conversationsController.close();
    for (final controller in _dmStreamControllers.values) {
      controller.close();
    }
    _dreamfinderClient?.dispose();
    _ttsService.dispose();
    _botStatus.dispose();
  }
}
