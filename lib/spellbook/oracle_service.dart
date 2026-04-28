import 'dart:async';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:tech_world/livekit/livekit_service.dart';

final _log = Logger('OracleService');

/// Generic bot-mediated generation channel — "ask the oracle, hear it speak."
///
/// Phase 2 uses this for `kind: 'cast_no_match'`: when a player speaks a
/// word that doesn't match any [WordId], the UI calls
/// [flavorForNoMatch] and shows the returned line. The bot generates
/// fresh flavor text via Claude so each miss feels different.
///
/// Designed for reuse — Phase 3's spell-combo interpretation (novel word
/// pairs → emergent effects) will go through the same channel with
/// `kind: 'spell_combo'` and a different request shape, but the same
/// request-id correlation and timeout-with-fallback semantics.
///
/// ## Wire contract
///
/// **Outgoing** on topic `oracle-request`, targeted to [botIdentity]:
/// ```json
/// {"requestId": "<unique>", "kind": "<discriminator>", "context": {...}}
/// ```
///
/// **Incoming** on topic `oracle-response`, targeted to the requester:
/// ```json
/// {"requestId": "<echoed>", "text": "<generated line>"}
/// ```
///
/// On timeout (default 5s) or error, [flavorForNoMatch] returns a
/// hand-crafted fallback line so the player never sees silence.
class OracleService {
  OracleService({
    required LiveKitService liveKit,
    this.botIdentity = 'bot-claude',
    Random? random,
  })  : _liveKit = liveKit,
        _random = random ?? Random();

  final LiveKitService _liveKit;

  /// LiveKit identity of the bot that generates flavor. Default `bot-claude`
  /// matches the active agent in production (`tech_world_bot`).
  final String botIdentity;

  final Random _random;
  int _seq = 0;

  /// Hand-crafted fallbacks used when the bot can't reply in time.
  /// Each line is in the same register as the canonical
  /// "the words swirl but find no form" so the UX degrades gracefully —
  /// the player can't tell which lines came from the LLM and which didn't.
  static const _noMatchFallbacks = <String>[
    'The words swirl but find no form.',
    'A whisper of magic, lost on the wind.',
    'Power stirs, but no shape takes hold.',
    'The aether listens, but cannot answer.',
    'Almost — but the syllables slip away.',
  ];

  /// Ask the oracle for a flavor line on a no-match cast.
  ///
  /// [transcript] is what the player actually said (may be `null` if
  /// STT was silent / cancelled). The bot uses it to riff — if it has
  /// the original utterance it can produce something playful.
  ///
  /// Returns the bot's text on success, or a randomly-chosen
  /// [_noMatchFallbacks] line on timeout / error / disconnect. Never
  /// throws — flavor is best-effort by design.
  Future<String> flavorForNoMatch({
    String? transcript,
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _request(
      kind: 'cast_no_match',
      context: <String, dynamic>{
        if (transcript != null && transcript.isNotEmpty)
          'transcript': transcript,
      },
      timeout: timeout,
      fallback: _pickFallback(_noMatchFallbacks),
    );
  }

  /// Generic request — returns the bot's `text` field, or [fallback]
  /// on timeout / parse-failure / disconnect. Never throws.
  Future<String> _request({
    required String kind,
    required Map<String, dynamic> context,
    required Duration timeout,
    required String fallback,
  }) async {
    final requestId = _nextRequestId();

    // Subscribe BEFORE publishing so we don't miss a fast reply. The
    // future is consumed in the try-block below.
    final responseFuture = _liveKit.dataReceived
        .where((m) => m.topic == 'oracle-response')
        .map((m) => m.json)
        .where((json) => json != null && json['requestId'] == requestId)
        .map((json) => json!['text'])
        .where((text) => text is String && text.isNotEmpty)
        .cast<String>()
        .first
        .timeout(
          timeout,
          onTimeout: () =>
              throw TimeoutException('oracle response timed out', timeout),
        );

    try {
      await _liveKit.publishJson(
        <String, dynamic>{
          'requestId': requestId,
          'kind': kind,
          'context': context,
        },
        topic: 'oracle-request',
        destinationIdentities: [botIdentity],
      );
    } catch (e) {
      _log.warning('Failed to publish oracle-request ($kind, $requestId): $e');
      // Drain the response listener so it doesn't leak. If the publish
      // failed we'll never get a reply, so fall through to fallback.
      unawaited(responseFuture.then((_) {}, onError: (_) {}));
      return fallback;
    }

    try {
      final text = await responseFuture;
      _log.fine('oracle reply ($kind, $requestId): "$text"');
      return text;
    } on TimeoutException {
      _log.info('oracle timeout ($kind, $requestId) — using fallback');
      return fallback;
    } catch (e) {
      _log.warning('oracle error ($kind, $requestId): $e');
      return fallback;
    }
  }

  String _nextRequestId() {
    _seq++;
    return 'oracle-${DateTime.now().microsecondsSinceEpoch}-$_seq';
  }

  String _pickFallback(List<String> pool) =>
      pool[_random.nextInt(pool.length)];
}
