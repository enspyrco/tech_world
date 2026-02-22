import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' show RemoteParticipant;
import 'package:tech_world/chat/chat_message.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/services/tts_service.dart';

/// Service that manages shared chat with Claude bot via LiveKit data channels.
/// All participants see all messages (questions and responses).
class ChatService {
  ChatService({required LiveKitService liveKitService})
      : _liveKitService = liveKitService,
        _ttsService = TtsService() {
    _subscribeToMessages();
    _trackBotPresence();
  }

  final LiveKitService _liveKitService;
  final TtsService _ttsService;
  final _messagesController = StreamController<List<ChatMessage>>.broadcast();
  final List<ChatMessage> _messages = [];
  final Map<String, Completer<Map<String, dynamic>?>> _pendingMessages = {};
  final Set<String> _seenMessageIds = {}; // Prevent duplicate messages
  final Map<String, Completer<String?>> _pendingHelpRequests = {};
  StreamSubscription<DataChannelMessage>? _chatSubscription;
  StreamSubscription<DataChannelMessage>? _helpResponseSubscription;
  StreamSubscription<RemoteParticipant>? _botJoinedSubscription;
  StreamSubscription<RemoteParticipant>? _botLeftSubscription;

  Stream<List<ChatMessage>> get messages => _messagesController.stream;
  List<ChatMessage> get currentMessages => List.unmodifiable(_messages);

  static const _botIdentity = 'bot-claude';

  void _subscribeToMessages() {
    // Listen for both chat messages and bot responses
    _chatSubscription = _liveKitService.dataReceived
        .where((msg) => msg.topic == 'chat' || msg.topic == 'chat-response')
        .listen(_handleMessage);

    // Listen for help-response messages from the bot
    _helpResponseSubscription = _liveKitService.dataReceived
        .where((msg) => msg.topic == 'help-response')
        .listen(_handleHelpResponse);
  }

  /// Track bot presence via LiveKit participant events.
  void _trackBotPresence() {
    // Set initial status based on whether bot is already in the room.
    final botPresent =
        _liveKitService.remoteParticipants.containsKey(_botIdentity);
    botStatusNotifier.value = botPresent ? BotStatus.idle : BotStatus.absent;

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
  }

  void _handleMessage(DataChannelMessage message) {
    final json = message.json;
    if (json == null) return;

    final text = json['text'] as String?;
    // 'id' is the message's own ID (for deduplication)
    // 'messageId' is the ID of the message being responded to (for correlation)
    final ownId = json['id'] as String?;
    final replyToId = json['messageId'] as String?;
    final senderName = json['senderName'] as String? ?? message.senderId ?? 'Unknown';

    if (text == null) return;

    // Skip if we've already seen this message (prevents duplicates)
    // Only check the message's own ID, not the ID it's replying to
    if (ownId != null && _seenMessageIds.contains(ownId)) return;
    if (ownId != null) _seenMessageIds.add(ownId);

    // Skip our own outgoing messages (we add them locally)
    final isFromSelf = message.senderId == _liveKitService.userId;
    if (message.topic == 'chat' && isFromSelf) return;

    debugPrint('ChatService: Received ${message.topic} from ${message.senderId}: "${text.substring(0, text.length.clamp(0, 50))}..."');

    if (message.topic == 'chat-response') {
      // Bot response
      botStatusNotifier.value = BotStatus.idle;
      _messages.add(ChatMessage(
        text: text,
        senderName: 'Clawd',
        isBot: true,
      ));
      // Speak the response
      _ttsService.speak(text);
    } else {
      // Message from another user
      _messages.add(ChatMessage(
        text: text,
        senderName: senderName,
        isLocalUser: false,
      ));
    }

    _messagesController.add(List.from(_messages));

    // Complete pending message if this is a response to one of ours
    if (replyToId != null && _pendingMessages.containsKey(replyToId)) {
      _pendingMessages[replyToId]!.complete(json);
      _pendingMessages.remove(replyToId);
    }
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
      debugPrint('ChatService: Not connected to LiveKit, cannot send message');
      _messages.add(ChatMessage(
        text: "I can't reach Clawd right now. Please check your connection.",
        senderName: 'System',
        isBot: true,
      ));
      _messagesController.add(List.from(_messages));
      return null;
    }

    if (botStatusNotifier.value == BotStatus.absent) {
      debugPrint('ChatService: Bot is not in the room');
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
    _seenMessageIds.add(messageId); // Mark as seen so we don't duplicate

    // Add user message locally
    _messages.add(ChatMessage(
      text: text,
      senderName: _liveKitService.displayName,
      isLocalUser: true,
    ));
    _messagesController.add(List.from(_messages));

    // Show thinking indicator
    botStatusNotifier.value = BotStatus.thinking;

    // Create a completer to track when we get a response
    final completer = Completer<Map<String, dynamic>?>();
    _pendingMessages[messageId] = completer;

    // Send message to all participants (no destinationIdentities = broadcast)
    const reservedKeys = {'type', 'id', 'text', 'senderName', 'timestamp'};
    final safeMetadata = metadata?.entries
        .where((e) => !reservedKeys.contains(e.key));

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

    debugPrint('ChatService: Sent message: "$text"');

    // Wait for response with timeout
    try {
      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('ChatService: Response timeout');
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
      debugPrint('ChatService: Error waiting for response: $e');
      return null;
    }
  }

  /// Handle a help-response message from the bot.
  void _handleHelpResponse(DataChannelMessage message) {
    final json = message.json;
    if (json == null) return;

    final requestId = json['requestId'] as String?;
    final hint = json['hint'] as String?;
    if (requestId == null || hint == null) return;

    debugPrint('ChatService: Received help-response for $requestId');

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
      debugPrint('ChatService: Not connected, cannot request help');
      return null;
    }

    if (botStatusNotifier.value == BotStatus.absent) {
      debugPrint('ChatService: Bot is absent, cannot request help');
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

    debugPrint('ChatService: Sent help-request $requestId');

    try {
      return await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          debugPrint('ChatService: Help request timeout');
          _pendingHelpRequests.remove(requestId);
          return null;
        },
      );
    } catch (e) {
      debugPrint('ChatService: Error waiting for help response: $e');
      _pendingHelpRequests.remove(requestId);
      return null;
    }
  }

  void dispose() {
    _chatSubscription?.cancel();
    _helpResponseSubscription?.cancel();
    _botJoinedSubscription?.cancel();
    _botLeftSubscription?.cancel();
    _messagesController.close();
    _ttsService.dispose();
  }
}
