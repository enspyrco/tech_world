import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/livekit/agent_hello.dart';

void main() {
  group('buildAgentHelloPayload', () {
    test('produces stable map for fixed inputs', () {
      final payload = buildAgentHelloPayload(
        clientSdkVersion: '2.7.0',
        buildSha: 'abc1234',
        appVersion: '0.0.0+1',
        adaptiveStream: false,
        dynacast: false,
        platform: 'macos',
        userAgent: null,
      );

      expect(payload, {
        'schemaVersion': 1,
        'clientSdk': 'flutter',
        'clientSdkVersion': '2.7.0',
        'buildSha': 'abc1234',
        'appVersion': '0.0.0+1',
        'adaptiveStream': false,
        'dynacast': false,
        'platform': 'macos',
        'userAgent': null,
      });
    });

    test('stamps current schema version', () {
      final payload = buildAgentHelloPayload(
        clientSdkVersion: '2.7.0',
        buildSha: 'dev',
        appVersion: '0.0.0+1',
        adaptiveStream: false,
        dynacast: false,
        platform: 'web',
        userAgent: 'Mozilla/5.0',
      );
      expect(payload['schemaVersion'], kAgentHelloSchemaVersion);
    });

    test('reports adaptiveStream:true truthfully (the known-bad case)', () {
      // Regression guard — if a refactor ever inverts or drops the field, the
      // bot loses its only signal for diagnosing broken video.
      final payload = buildAgentHelloPayload(
        clientSdkVersion: '2.7.0',
        buildSha: 'dev',
        appVersion: '0.0.0+1',
        adaptiveStream: true,
        dynacast: true,
        platform: 'web',
        userAgent: 'Mozilla/5.0',
      );
      expect(payload['adaptiveStream'], isTrue);
      expect(payload['dynacast'], isTrue);
    });

    test('includes userAgent when provided (web)', () {
      final payload = buildAgentHelloPayload(
        clientSdkVersion: '2.7.0',
        buildSha: 'dev',
        appVersion: '0.0.0+1',
        adaptiveStream: false,
        dynacast: false,
        platform: 'web',
        userAgent: 'Mozilla/5.0 (Macintosh)',
      );
      expect(payload['userAgent'], 'Mozilla/5.0 (Macintosh)');
    });

    test('clientSdk is always "flutter"', () {
      final payload = buildAgentHelloPayload(
        clientSdkVersion: 'anything',
        buildSha: 'dev',
        appVersion: '0.0.0+1',
        adaptiveStream: false,
        dynacast: false,
        platform: 'android',
        userAgent: null,
      );
      expect(payload['clientSdk'], 'flutter');
    });
  });

  group('encodeAgentHelloPayload', () {
    test('round-trips through JSON', () {
      final payload = buildAgentHelloPayload(
        clientSdkVersion: '2.7.0',
        buildSha: 'abc1234',
        appVersion: '0.0.0+1',
        adaptiveStream: false,
        dynacast: false,
        platform: 'macos',
        userAgent: null,
      );
      final bytes = encodeAgentHelloPayload(payload);
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(decoded, payload);
    });
  });
}
