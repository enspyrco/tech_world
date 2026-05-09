import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tech_world/services/dreamfinder_client.dart';

void main() {
  group('DreamfinderClient.isEnabled', () {
    test('false when apiKey is empty', () {
      final client = DreamfinderClient(
        baseUrl: 'https://example.com',
        apiKey: '',
        httpClient: MockClient((_) async => http.Response('', 200)),
      );
      expect(client.isEnabled, isFalse);
      client.dispose();
    });

    test('true when apiKey is non-empty', () {
      final client = DreamfinderClient(
        baseUrl: 'https://example.com',
        apiKey: 'k',
        httpClient: MockClient((_) async => http.Response('', 200)),
      );
      expect(client.isEnabled, isTrue);
      client.dispose();
    });
  });

  group('DreamfinderClient.sendEvent fail-fast when disabled', () {
    test('does not make an HTTP request when apiKey is empty', () async {
      // Regression: empty apiKey previously produced silent 401s and ChatService
      // hung 30-60s on response Completers that never resolved.
      var calls = 0;
      final mockClient = MockClient((_) async {
        calls++;
        return http.Response('', 200);
      });
      final client = DreamfinderClient(
        baseUrl: 'https://example.com',
        apiKey: '',
        httpClient: mockClient,
      );

      await client.sendEvent(
        topic: 'chat',
        roomName: 'r',
        senderId: 's',
        senderName: 'n',
        payload: const {},
      );

      expect(calls, equals(0),
          reason: 'sendEvent must fast-return without making an HTTP request '
              'when isEnabled is false');
      client.dispose();
    });

    test('makes an HTTP request when apiKey is non-empty', () async {
      var calls = 0;
      final mockClient = MockClient((req) async {
        calls++;
        expect(req.headers['Authorization'], equals('Bearer k'));
        return http.Response('', 200);
      });
      final client = DreamfinderClient(
        baseUrl: 'https://example.com',
        apiKey: 'k',
        httpClient: mockClient,
      );

      await client.sendEvent(
        topic: 'chat',
        roomName: 'r',
        senderId: 's',
        senderName: 'n',
        payload: const {},
      );

      expect(calls, equals(1));
      client.dispose();
    });
  });
}
