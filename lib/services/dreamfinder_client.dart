import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

final _log = Logger('DreamfinderClient');

/// HTTP client for forwarding game events to the Dreamfinder agent.
///
/// Fire-and-forget: sends events and does not wait for the AI response.
/// Responses arrive asynchronously via LiveKit data channels. If Dreamfinder
/// is unreachable, the game continues to work — events are silently dropped.
class DreamfinderClient {
  DreamfinderClient({
    required this.baseUrl,
    required this.apiKey,
    http.Client? httpClient,
  }) : _client = httpClient ?? http.Client();

  /// Base URL of the Dreamfinder HTTP server (e.g., `https://game.imagineering.cc`).
  final String baseUrl;

  /// Bearer token for API authentication.
  final String apiKey;

  final http.Client _client;

  /// Forwards a game event to Dreamfinder.
  ///
  /// Fire-and-forget — catches all errors so the game never breaks due to
  /// Dreamfinder being unreachable. The AI response comes back via LiveKit
  /// data channels, not via this HTTP call.
  Future<void> sendEvent({
    required String topic,
    required String roomName,
    required String senderId,
    required String senderName,
    required Map<String, dynamic> payload,
  }) async {
    try {
      await _client
          .post(
            Uri.parse('$baseUrl/api/game/event'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'topic': topic,
              'roomName': roomName,
              'senderId': senderId,
              'senderName': senderName,
              'payload': payload,
            }),
          )
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      // Fire-and-forget: don't rethrow. The game should not break
      // if Dreamfinder is unreachable.
      _log.warning('Failed to send event to Dreamfinder: $e');
    }
  }

  void dispose() => _client.close();
}
