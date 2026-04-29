import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/spellbook/oracle_service.dart';

void main() {
  group('OracleService.flavorForNoMatch', () {
    late _FakeLiveKit fake;
    late OracleService oracle;

    setUp(() {
      fake = _FakeLiveKit();
      oracle = OracleService(liveKit: fake);
    });

    tearDown(() async {
      await fake.dispose();
    });

    test('publishes oracle-request to bot-claude with kind cast_no_match',
        () async {
      // Don't await — the future hangs until we synthesize a reply.
      unawaited(oracle.flavorForNoMatch(transcript: 'blarghnonsense'));

      // Let the publish microtask run.
      await Future<void>.delayed(Duration.zero);

      expect(fake.published, hasLength(1));
      final pub = fake.published.single;
      expect(pub.topic, 'oracle-request');
      expect(pub.destinationIdentities, ['bot-claude']);

      final payload = pub.payload;
      expect(payload['kind'], 'cast_no_match');
      expect(payload['requestId'], isA<String>());
      expect(payload['requestId'], isNotEmpty);

      // Wire-shape regression — `requestId` and `kind` must be primitive
      // strings so jsonEncode(payload) returns normally. (Two-axis
      // pattern from feedback_dynamic_interpolation_blindspot.md.)
      expect(() => jsonEncode(payload), returnsNormally);

      final context = payload['context'] as Map<String, dynamic>;
      expect(context['transcript'], 'blarghnonsense');
    });

    test('returns the bot-supplied text on matching response', () async {
      final flavor = oracle.flavorForNoMatch(transcript: 'frobnitz');
      // Wait for publish to capture the requestId.
      await Future<void>.delayed(Duration.zero);

      final requestId = fake.published.single.payload['requestId'] as String;

      fake.simulateResponse(<String, dynamic>{
        'requestId': requestId,
        'text': 'The void giggles, then forgets you.',
      });

      expect(await flavor, 'The void giggles, then forgets you.');
    });

    test('ignores responses with mismatched requestId', () async {
      final flavor = oracle.flavorForNoMatch(
        transcript: 'frobnitz',
        timeout: const Duration(milliseconds: 200),
      );
      await Future<void>.delayed(Duration.zero);

      // Send a reply for someone else's request — must be ignored.
      fake.simulateResponse(<String, dynamic>{
        'requestId': 'wrong-id-${DateTime.now().microsecondsSinceEpoch}',
        'text': 'this should be dropped',
      });

      // Future doesn't resolve to the wrong text — falls through to
      // timeout, returns a fallback line. The fallback is one of the
      // hand-crafted lines, so we assert by exclusion.
      final result = await flavor;
      expect(result, isNot('this should be dropped'));
      expect(result, isNotEmpty);
    });

    test('falls back when no response arrives before timeout', () async {
      final result = await oracle.flavorForNoMatch(
        transcript: 'silentfail',
        timeout: const Duration(milliseconds: 50),
      );

      // The fallback pool is non-empty, so we get a real string —
      // never empty, never null.
      expect(result, isNotEmpty);
      expect(result, isA<String>());
    });

    test('omits transcript field when null or empty', () async {
      unawaited(oracle.flavorForNoMatch(transcript: null));
      await Future<void>.delayed(Duration.zero);

      final ctx = fake.published.single.payload['context']
          as Map<String, dynamic>;
      expect(ctx.containsKey('transcript'), isFalse,
          reason: 'null transcript should not be sent on the wire');

      fake.published.clear();

      unawaited(oracle.flavorForNoMatch(transcript: ''));
      await Future<void>.delayed(Duration.zero);

      final ctx2 = fake.published.single.payload['context']
          as Map<String, dynamic>;
      expect(ctx2.containsKey('transcript'), isFalse,
          reason: 'empty transcript should not be sent on the wire');
    });

    test('different requests get different requestIds', () async {
      unawaited(oracle.flavorForNoMatch(transcript: 'a'));
      unawaited(oracle.flavorForNoMatch(transcript: 'b'));
      await Future<void>.delayed(Duration.zero);

      final ids = fake.published
          .map((p) => p.payload['requestId'] as String)
          .toSet();
      expect(ids, hasLength(2),
          reason: 'concurrent requests must not share a requestId — '
              'otherwise responses cross-contaminate');
    });

    test('ignores empty-text replies and falls back', () async {
      final flavor = oracle.flavorForNoMatch(
        transcript: 'frobnitz',
        timeout: const Duration(milliseconds: 50),
      );
      await Future<void>.delayed(Duration.zero);

      final requestId = fake.published.single.payload['requestId'] as String;

      // Bot returns an empty string (e.g. Claude refusal collapse).
      fake.simulateResponse(<String, dynamic>{
        'requestId': requestId,
        'text': '',
      });

      // Empty isn't useful flavor — fall through to timeout fallback.
      expect(await flavor, isNotEmpty);
    });

    test('survives a publish failure by returning a fallback', () async {
      fake.publishWillThrow = true;

      final result = await oracle.flavorForNoMatch(
        transcript: 'boom',
        timeout: const Duration(milliseconds: 50),
      );

      // No throw escapes — flavor is best-effort by design.
      expect(result, isNotEmpty);
    });
  });
}

/// Test double for [LiveKitService] — captures publish calls and exposes
/// a controllable `dataReceived` stream so tests can synthesize bot
/// replies. Pattern matches the `FakeLiveKitService` used in
/// `test/chat/chat_service_test.dart` and `test/map_editor/map_sync_service_test.dart`.
///
/// The `noSuchMethod` fallback is intentional and load-bearing: Dart
/// requires every member of [LiveKitService] to be implemented when
/// using `implements`, but [OracleService] only exercises
/// [dataReceived] and [publishJson], so stubbing every other member
/// would be dead code. The trade-off is that any future
/// [LiveKitService] method [OracleService] starts to call will silently
/// no-op here and the test will pass against a broken consumer — the
/// guard against that is keeping the surface [OracleService] uses
/// minimal (currently exactly two methods) and refreshing this test
/// when that surface grows.
class _FakeLiveKit implements LiveKitService {
  final List<_PublishedMessage> published = [];
  bool publishWillThrow = false;

  final _controller =
      StreamController<DataChannelMessage>.broadcast();

  @override
  Stream<DataChannelMessage> get dataReceived => _controller.stream;

  @override
  Future<void> publishJson(
    Map<String, dynamic> json, {
    bool reliable = true,
    List<String>? destinationIdentities,
    String? topic,
  }) async {
    if (publishWillThrow) {
      throw StateError('simulated publish failure');
    }
    published.add(_PublishedMessage(
      payload: json,
      topic: topic,
      destinationIdentities: destinationIdentities,
    ));
  }

  void simulateResponse(Map<String, dynamic> response) {
    _controller.add(DataChannelMessage(
      senderId: 'bot-claude',
      topic: 'oracle-response',
      data: utf8.encode(jsonEncode(response)),
    ));
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PublishedMessage {
  _PublishedMessage({
    required this.payload,
    required this.topic,
    required this.destinationIdentities,
  });

  final Map<String, dynamic> payload;
  final String? topic;
  final List<String>? destinationIdentities;
}
