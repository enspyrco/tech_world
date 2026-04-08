import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

final _log = Logger('DreamfinderClient');

/// HTTP client for forwarding game events to the Dreamfinder agent.
///
/// Fire-and-forget: sends events and does not wait for the AI response.
/// Responses arrive asynchronously via LiveKit data channels. If Dreamfinder
/// is unreachable, the game continues to work — events are silently dropped.
/// Topics for game events forwarded to Dreamfinder.
///
/// These match the LiveKit data channel topics used throughout the game.
abstract final class GameEventTopic {
  static const chat = 'chat';
  static const helpRequest = 'help-request';
  static const playerJoin = 'player-join';
  static const playerLeave = 'player-leave';
}

class DreamfinderClient {
  DreamfinderClient({
    required this.baseUrl,
    required this.apiKey,
    http.Client? httpClient,
  }) : _client = httpClient ?? http.Client();

  /// Base URL of the Dreamfinder HTTP server (e.g., `https://dreamfinder.imagineering.cc`).
  final String baseUrl;

  /// Bearer token for API authentication.
  final String apiKey;

  final http.Client _client;

  /// Forwards a game event to Dreamfinder.
  ///
  /// Fire-and-forget — network and timeout errors are silently logged so
  /// the game never breaks due to Dreamfinder being unreachable. Auth and
  /// format errors are logged at a higher level since they indicate
  /// misconfiguration rather than transient issues.
  Future<void> sendEvent({
    required String topic,
    required String roomName,
    required String senderId,
    required String senderName,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final response = await _client
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

      if (response.statusCode == 401 || response.statusCode == 403) {
        _log.severe('Dreamfinder auth failed (${response.statusCode}) '
            '— check DREAMFINDER_API_KEY');
      } else if (response.statusCode >= 400) {
        _log.warning('Dreamfinder returned ${response.statusCode}: '
            '${response.body}');
      }
    } on SocketException catch (e) {
      _log.warning('Dreamfinder unreachable: $e');
    } on TimeoutException {
      _log.warning('Dreamfinder request timed out');
    } on http.ClientException catch (e) {
      _log.warning('Dreamfinder HTTP error: $e');
    } catch (e) {
      _log.severe('Unexpected error sending to Dreamfinder: $e');
    }
  }

  void dispose() => _client.close();
}
