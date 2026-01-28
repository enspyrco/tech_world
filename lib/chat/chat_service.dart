import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tech_world/chat/chat_message.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/livekit/livekit_service.dart';

/// Service that manages chat with the Claude bot via LiveKit data channels.
class ChatService {
  ChatService({required LiveKitService liveKitService})
      : _liveKitService = liveKitService {
    _subscribeToResponses();
  }

  final LiveKitService _liveKitService;
  final _messagesController = StreamController<List<ChatMessage>>.broadcast();
  final List<ChatMessage> _messages = [];
  final Map<String, Completer<void>> _pendingMessages = {};
  StreamSubscription<DataChannelMessage>? _responseSubscription;

  Stream<List<ChatMessage>> get messages => _messagesController.stream;
  List<ChatMessage> get currentMessages => List.unmodifiable(_messages);

  void _subscribeToResponses() {
    _responseSubscription = _liveKitService.dataReceived
        .where((msg) => msg.topic == 'chat-response')
        .listen(_handleChatResponse);
  }

  void _handleChatResponse(DataChannelMessage message) {
    final json = message.json;
    if (json == null) return;

    final text = json['text'] as String?;
    final messageId = json['messageId'] as String?;

    if (text == null) return;

    debugPrint('ChatService: Received response: "${text.substring(0, text.length.clamp(0, 50))}..."');

    // Hide thinking indicator
    botStatusNotifier.value = BotStatus.idle;

    // Add bot response
    _messages.add(ChatMessage(text: text, isUser: false));
    _messagesController.add(List.from(_messages));

    // Complete the pending message future if we have one
    if (messageId != null && _pendingMessages.containsKey(messageId)) {
      _pendingMessages[messageId]!.complete();
      _pendingMessages.remove(messageId);
    }
  }

  /// Send a message to the bot and get a response.
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    if (!_liveKitService.isConnected) {
      debugPrint('ChatService: Not connected to LiveKit, cannot send message');
      _messages.add(ChatMessage(
        text: "I can't reach Clawd right now. Please check your connection.",
        isUser: false,
      ));
      _messagesController.add(List.from(_messages));
      return;
    }

    // Add user message
    _messages.add(ChatMessage(text: text, isUser: true));
    _messagesController.add(List.from(_messages));

    // Show thinking indicator
    botStatusNotifier.value = BotStatus.thinking;

    // Generate a unique message ID
    final messageId = DateTime.now().millisecondsSinceEpoch.toString();

    // Create a completer to track when we get a response
    final completer = Completer<void>();
    _pendingMessages[messageId] = completer;

    // Send message via data channel
    await _liveKitService.publishJson(
      {
        'type': 'chat',
        'id': messageId,
        'text': text,
        'timestamp': DateTime.now().toIso8601String(),
      },
      topic: 'chat',
      destinationIdentities: ['bot-claude'],
    );

    debugPrint('ChatService: Sent message to bot: "$text"');

    // Wait for response with timeout
    try {
      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('ChatService: Response timeout');
          botStatusNotifier.value = BotStatus.idle;
          _messages.add(ChatMessage(
            text: "Hmm, Clawd seems to be taking a while. Try again?",
            isUser: false,
          ));
          _messagesController.add(List.from(_messages));
          _pendingMessages.remove(messageId);
        },
      );
    } catch (e) {
      debugPrint('ChatService: Error waiting for response: $e');
    }
  }

  void dispose() {
    _responseSubscription?.cancel();
    _messagesController.close();
  }
}
