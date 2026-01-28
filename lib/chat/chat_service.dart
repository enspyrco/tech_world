import 'dart:async';
import 'dart:math';

import 'package:tech_world/chat/chat_message.dart';
import 'package:tech_world/flame/components/bot_status.dart';

/// Service that manages chat with the Claude bot.
/// Currently uses mocked responses - replace with real Claude API later.
class ChatService {
  final _messagesController = StreamController<List<ChatMessage>>.broadcast();
  final List<ChatMessage> _messages = [];
  final _random = Random();

  Stream<List<ChatMessage>> get messages => _messagesController.stream;
  List<ChatMessage> get currentMessages => List.unmodifiable(_messages);

  /// Send a message to the bot and get a response.
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    // Add user message
    _messages.add(ChatMessage(text: text, isUser: true));
    _messagesController.add(List.from(_messages));

    // Show thinking indicator
    botStatusNotifier.value = BotStatus.thinking;

    // Simulate API delay
    await Future.delayed(Duration(milliseconds: 800 + _random.nextInt(1200)));

    // Generate mock response
    final response = _generateMockResponse(text);

    // Hide thinking indicator
    botStatusNotifier.value = BotStatus.idle;

    // Add bot response
    _messages.add(ChatMessage(text: response, isUser: false));
    _messagesController.add(List.from(_messages));
  }

  String _generateMockResponse(String userMessage) {
    final lowerMessage = userMessage.toLowerCase();

    // Context-aware mock responses
    if (lowerMessage.contains('hello') || lowerMessage.contains('hi')) {
      return _randomChoice([
        "Hey there! I'm Clawd, your friendly coding companion. What would you like to learn about today?",
        "Hello! Welcome to Tech World. I'm here to help you on your coding adventure!",
        "Hi! Great to see you. Ready to explore some programming concepts?",
      ]);
    }

    if (lowerMessage.contains('help')) {
      return "I can help you with:\n\n"
          "- Explaining programming concepts\n"
          "- Reviewing your code\n"
          "- Giving hints on challenges\n"
          "- Answering questions about Tech World\n\n"
          "What would you like to know?";
    }

    if (lowerMessage.contains('dart') || lowerMessage.contains('flutter')) {
      return _randomChoice([
        "Dart is a great language! It's designed to be easy to learn while being powerful enough for complex apps. What specifically would you like to know?",
        "Flutter and Dart make a fantastic combo for building cross-platform apps. Are you working on something specific?",
        "I love talking about Dart! It has some really elegant features like null safety and async/await. Want me to explain any of these?",
      ]);
    }

    if (lowerMessage.contains('?')) {
      return _randomChoice([
        "That's a great question! In a real implementation, I'd connect to Claude's API to give you a thoughtful answer. For now, this is a placeholder response.",
        "Interesting question! Once the Claude API is connected, I'll be able to provide much more helpful answers.",
        "Good thinking! This mock response will be replaced with real AI-powered answers when the API key is configured.",
      ]);
    }

    // Default responses
    return _randomChoice([
      "I hear you! Once Claude's API is connected, I'll be able to have much more meaningful conversations.",
      "Thanks for chatting! This is a mock response for now - the real magic happens when we connect to Claude.",
      "Interesting! I'm currently in demo mode. Connect the Claude API to unlock my full potential!",
      "Got it! I'm just a placeholder for now, but soon I'll be powered by Claude to help you learn and code.",
    ]);
  }

  String _randomChoice(List<String> options) {
    return options[_random.nextInt(options.length)];
  }

  void dispose() {
    _messagesController.close();
  }
}
