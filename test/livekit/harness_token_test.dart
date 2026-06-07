import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/livekit/harness_token.dart';

/// Decode an unpadded base64url JWT segment back to a JSON map.
Map<String, dynamic> _decodeSegment(String seg) {
  final padded = seg + '=' * ((4 - seg.length % 4) % 4);
  return json.decode(utf8.decode(base64Url.decode(padded))) as Map<String, dynamic>;
}

void main() {
  group('buildLivekitJwt', () {
    const apiKey = 'devkey';
    const apiSecret = 'secret';
    const identity = 'player-A';
    const room = 'room-123';
    const name = 'Player A';
    const now = 1_700_000_000;

    final token = buildLivekitJwt(
      identity: identity,
      room: room,
      name: name,
      apiKey: apiKey,
      apiSecret: apiSecret,
      nowOverride: now,
    );

    test('is a three-segment JWT', () {
      expect(token.split('.'), hasLength(3));
    });

    test('header declares HS256 / JWT', () {
      final header = _decodeSegment(token.split('.')[0]);
      expect(header['alg'], 'HS256');
      expect(header['typ'], 'JWT');
    });

    test('payload carries the LiveKit join grant for this identity + room', () {
      final payload = _decodeSegment(token.split('.')[1]);
      expect(payload['iss'], apiKey, reason: 'apiKey is the issuer');
      expect(payload['sub'], identity, reason: 'identity is the subject');
      expect(payload['name'], name);
      expect(payload['nbf'], now);
      expect(payload['exp'], now + 6 * 60 * 60);

      final video = payload['video'] as Map<String, dynamic>;
      expect(video['room'], room);
      expect(video['roomJoin'], isTrue);
      expect(video['canPublish'], isTrue);
      expect(video['canSubscribe'], isTrue);
      expect(video['canPublishData'], isTrue);
    });

    test('signature verifies against the secret (what a server checks)', () {
      final parts = token.split('.');
      final signingInput = '${parts[0]}.${parts[1]}';
      final expected = base64Url
          .encode(Hmac(sha256, utf8.encode(apiSecret))
              .convert(utf8.encode(signingInput))
              .bytes)
          .replaceAll('=', '');
      expect(parts[2], expected,
          reason: 'a LiveKit server recomputes exactly this HMAC');
    });

    test('a wrong secret produces a different signature (tamper-evident)', () {
      final good = token.split('.')[2];
      final bad = buildLivekitJwt(
        identity: identity,
        room: room,
        name: name,
        apiKey: apiKey,
        apiSecret: 'not-the-secret',
        nowOverride: now,
      ).split('.')[2];
      expect(bad, isNot(good));
    });

    test('distinct identities mint distinct tokens (two-tab requirement)', () {
      final tokenB = buildLivekitJwt(
        identity: 'player-B',
        room: room,
        name: 'Player B',
        apiKey: apiKey,
        apiSecret: apiSecret,
        nowOverride: now,
      );
      expect(tokenB, isNot(token));
    });
  });
}
