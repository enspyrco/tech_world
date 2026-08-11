import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:realm/realm.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/livekit/realm_token_source.dart';

/// Minimal [AuthProvider] fake: hop 1 either yields a credential or throws.
class _FakeAuthProvider implements AuthProvider {
  _FakeAuthProvider.credential(this._credential) : _error = null;
  _FakeAuthProvider.throwing(this._error) : _credential = null;

  final RealmCredential? _credential;
  final Object? _error;
  int getCredentialCalls = 0;

  @override
  Future<RealmCredential> getCredential({bool forceRefresh = false}) async {
    getCredentialCalls++;
    if (_error != null) throw _error;
    return _credential!;
  }

  @override
  RealmUser? get currentUser => throw UnimplementedError();
  @override
  Future<RealmUser> signIn(AuthMethod method) => throw UnimplementedError();
  @override
  Future<void> signOut() => throw UnimplementedError();
  @override
  Stream<RealmUser?> userChanges() => throw UnimplementedError();
}

/// A non-Bearer strategy — the engine ships none client-side, so the source
/// must fail closed rather than send a bearer against it.
class _UnknownStrategy implements TokenEndpointAuthStrategy {
  const _UnknownStrategy();
}

void main() {
  final endpoint = LiveKitTokenEndpoint(
    url: Uri.parse('https://realm.example/livekit-token'),
    authStrategy: const BearerCredential(),
  );
  final credential = RealmCredential(
    token: 'opaque-realm-cred',
    expiresAt: DateTime.utc(2999),
  );

  RealmTokenSource sourceWith({
    required AuthProvider auth,
    required http.Client client,
    String roomName = 'l_room',
  }) =>
      RealmTokenSource(
        authProvider: auth,
        endpoint: endpoint,
        roomName: roomName,
        httpClient: client,
      );

  group('hop 2 — trades the credential for a LiveKit token', () {
    test('200 → success, carrying bearer credential + roomName', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(jsonEncode({'token': 'lk-token'}), 200);
      });

      final result = await sourceWith(
        auth: _FakeAuthProvider.credential(credential),
        client: client,
        roomName: 'l_room',
      ).fetch();

      expect(result.connectionResult, ConnectionResult.connected);
      expect(result.token, 'lk-token');
      // The opaque credential is the bearer — never the Firebase ID token.
      expect(captured.headers['authorization'], 'Bearer opaque-realm-cred');
      expect(jsonDecode(captured.body), {'roomName': 'l_room'});
      expect(captured.url, endpoint.url);
    });

    test('200 with no token field → tokenUnknownError', () async {
      final result = await sourceWith(
        auth: _FakeAuthProvider.credential(credential),
        client: MockClient((_) async => http.Response('{}', 200)),
      ).fetch();
      expect(result.connectionResult, ConnectionResult.tokenUnknownError);
      expect(result.token, isNull);
    });

    test('200 with non-JSON body → tokenUnknownError', () async {
      final result = await sourceWith(
        auth: _FakeAuthProvider.credential(credential),
        client: MockClient((_) async => http.Response('not json', 200)),
      ).fetch();
      expect(result.connectionResult, ConnectionResult.tokenUnknownError);
    });

    test('401 → tokenAuthError (mint rejected the credential)', () async {
      final result = await sourceWith(
        auth: _FakeAuthProvider.credential(credential),
        client: MockClient((_) async => http.Response('nope', 401)),
      ).fetch();
      expect(result.connectionResult, ConnectionResult.tokenAuthError);
    });

    test('403 → tokenAuthError', () async {
      final result = await sourceWith(
        auth: _FakeAuthProvider.credential(credential),
        client: MockClient((_) async => http.Response('nope', 403)),
      ).fetch();
      expect(result.connectionResult, ConnectionResult.tokenAuthError);
    });

    test('400 → tokenUnknownError (client bug, not auth, not retry-network)',
        () async {
      final result = await sourceWith(
        auth: _FakeAuthProvider.credential(credential),
        client: MockClient((_) async => http.Response('bad', 400)),
      ).fetch();
      expect(result.connectionResult, ConnectionResult.tokenUnknownError);
    });

    test('404/415 → tokenUnknownError (permanent, not a retry-loop)', () async {
      for (final code in [404, 415]) {
        final result = await sourceWith(
          auth: _FakeAuthProvider.credential(credential),
          client: MockClient((_) async => http.Response('nope', code)),
        ).fetch();
        expect(result.connectionResult, ConnectionResult.tokenUnknownError,
            reason: 'HTTP $code should be unknown, not network');
      }
    });

    test('429 → tokenNetworkError (retryable)', () async {
      final result = await sourceWith(
        auth: _FakeAuthProvider.credential(credential),
        client: MockClient((_) async => http.Response('slow down', 429)),
      ).fetch();
      expect(result.connectionResult, ConnectionResult.tokenNetworkError);
    });

    test('500/503 → tokenNetworkError (retryable server fault)', () async {
      for (final code in [500, 503]) {
        final result = await sourceWith(
          auth: _FakeAuthProvider.credential(credential),
          client: MockClient((_) async => http.Response('boom', code)),
        ).fetch();
        expect(result.connectionResult, ConnectionResult.tokenNetworkError,
            reason: 'HTTP $code should be retryable network');
      }
    });

    test('transport exception → tokenNetworkError', () async {
      final result = await sourceWith(
        auth: _FakeAuthProvider.credential(credential),
        client: MockClient((_) async => throw http.ClientException('down')),
      ).fetch();
      expect(result.connectionResult, ConnectionResult.tokenNetworkError);
    });
  });

  group('auth-strategy guard — fail closed on anything but Bearer', () {
    test('non-Bearer strategy → tokenUnknownError, hop 1 never runs', () async {
      final auth = _FakeAuthProvider.credential(credential);
      var hopCalled = false;
      final result = await RealmTokenSource(
        authProvider: auth,
        endpoint: LiveKitTokenEndpoint(
          url: Uri.parse('https://realm.example/livekit-token'),
          authStrategy: const _UnknownStrategy(),
        ),
        roomName: 'l_room',
        httpClient: MockClient((_) async {
          hopCalled = true;
          return http.Response('{}', 200);
        }),
      ).fetch();
      expect(result.connectionResult, ConnectionResult.tokenUnknownError);
      expect(hopCalled, isFalse);
      expect(auth.getCredentialCalls, 0);
    });
  });

  group('TokenResult illegal-state guard', () {
    test('failure(connected) is unrepresentable (assert)', () {
      expect(
        () => TokenResult.failure(ConnectionResult.connected),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('hop 1 — credential exchange failures map before hop 2 runs', () {
    test('RealmAuthCredentialInvalid → tokenAuthError, hop 2 never called',
        () async {
      final auth = _FakeAuthProvider.throwing(
        const RealmAuthCredentialInvalid('bad id token'),
      );
      var hop2Called = false;
      final result = await sourceWith(
        auth: auth,
        client: MockClient((_) async {
          hop2Called = true;
          return http.Response('{}', 200);
        }),
      ).fetch();
      expect(result.connectionResult, ConnectionResult.tokenAuthError);
      expect(hop2Called, isFalse);
      expect(auth.getCredentialCalls, 1);
    });

    test('RealmAuthNetworkError → tokenNetworkError', () async {
      final result = await sourceWith(
        auth: _FakeAuthProvider.throwing(
          const RealmAuthNetworkError('offline'),
        ),
        client: MockClient((_) async => http.Response('{}', 200)),
      ).fetch();
      expect(result.connectionResult, ConnectionResult.tokenNetworkError);
    });

    test('RealmAuthRateLimited → tokenNetworkError', () async {
      final result = await sourceWith(
        auth: _FakeAuthProvider.throwing(
          const RealmAuthRateLimited('too many'),
        ),
        client: MockClient((_) async => http.Response('{}', 200)),
      ).fetch();
      expect(result.connectionResult, ConnectionResult.tokenNetworkError);
    });
  });
}
