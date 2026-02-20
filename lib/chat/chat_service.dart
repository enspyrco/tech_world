import 'dart:async';

import 'package:flutter/foundation.dart';
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
  }

  final LiveKitService _liveKitService;
  final TtsService _ttsService;
  final _messagesController = StreamController<List<ChatMessage>>.broadcast();
  final List<ChatMessage> _messages = [];
  final Map<String, Completer<Map<String, dynamic>?>> _pendingMessages = {};
  final Set<String> _seenMessageIds = {}; // Prevent duplicate messages
  StreamSubscription<DataChannelMessage>? _chatSubscription;

  Stream<List<ChatMessage>> get messages => _messagesController.stream;
  List<ChatMessage> get currentMessages => List.unmodifiable(_messages);

  void _subscribeToMessages() {
    // Listen for both chat messages and bot responses
    _chatSubscription = _liveKitService.dataReceived
        .where((msg) => msg.topic == 'chat' || msg.topic == 'chat-response')
        .listen(_handleMessage);
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
  /// Optional [metadata] fields are spread into the published JSON payload
  /// (e.g. `{'challengeId': 'fizzbuzz'}` for challenge evaluations).
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
    final payload = {
      'type': 'chat',
      'id': messageId,
      'text': text,
      'senderName': _liveKitService.displayName,
      'timestamp': DateTime.now().toIso8601String(),
      if (metadata != null) ...metadata,
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
          botStatusNotifier.value = BotStatus.idle;
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

  void dispose() {
    _chatSubscription?.cancel();
    _messagesController.close();
    _ttsService.dispose();
  }
}
