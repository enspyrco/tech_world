import 'dart:convert';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:realm/realm.dart';
import 'package:realm_firebase/realm_firebase.dart';
import 'package:test/test.dart';

void main() {
  final exchangeUrl = Uri.parse('https://realm.example/exchange');

  FirebaseAuthProvider providerWith({
    MockFirebaseAuth? auth,
    http.Client? client,
  }) =>
      FirebaseAuthProvider(
        exchangeEndpoint: exchangeUrl,
        auth: auth ?? MockFirebaseAuth(),
        // Default client fails loudly if a test reaches the network unexpectedly.
        httpClient: client ?? MockClient((_) async => http.Response('{}', 500)),
      );

  MockFirebaseAuth signedInAuth() => MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'u1', displayName: 'Ada', email: 'ada@x.io'),
      );

  group('translation (no-leak)', () {
    test('currentUser maps a signed-in Firebase user to RealmUser', () {
      final user = providerWith(auth: signedInAuth()).currentUser;
      expect(user, isNotNull);
      expect(user!.id.value, 'u1');
      expect(user.displayName, 'Ada');
      expect(user.email, 'ada@x.io');
      expect(user.providerIds, contains(AuthProviderId.firebase));
    });

    test('currentUser is null when signed out', () {
      expect(providerWith(auth: MockFirebaseAuth()).currentUser, isNull);
    });

    test('an anonymous user maps to exactly the anonymous provider id', () {
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(isAnonymous: true, uid: 'anon'),
      );
      expect(
        providerWith(auth: auth).currentUser!.providerIds,
        {AuthProviderId.anonymous},
      );
    });
  });

  group('getCredential — exchanges the ID token, never returns it', () {
    test('POSTs the Firebase ID token and returns the exchange credential',
        () async {
      String? sentBody;
      Uri? sentUrl;
      final client = MockClient((req) async {
        sentBody = req.body;
        sentUrl = req.url;
        return http.Response(
          jsonEncode({
            'token': 'realm-opaque-token',
            'expiresAt': '2026-08-10T09:00:00Z',
          }),
          200,
        );
      });

      final cred =
          await providerWith(auth: signedInAuth(), client: client).getCredential();

      expect(cred.token, 'realm-opaque-token');
      expect(cred.expiresAt, DateTime.utc(2026, 8, 10, 9));
      expect(sentUrl, exchangeUrl);
      // The native Firebase ID token was sent to the exchange, not handed back.
      expect(sentBody, contains('idToken'));
      expect(cred.token, isNot(contains('fake_iss')));
    });

    test('no signed-in user → RealmAuthCredentialInvalid', () {
      expect(
        providerWith(auth: MockFirebaseAuth()).getCredential(),
        throwsA(isA<RealmAuthCredentialInvalid>()),
      );
    });

    test('401 from exchange → RealmAuthCredentialInvalid', () {
      final client = MockClient((_) async => http.Response('no', 401));
      expect(
        providerWith(auth: signedInAuth(), client: client).getCredential(),
        throwsA(isA<RealmAuthCredentialInvalid>()),
      );
    });

    test('429 from exchange → RealmAuthRateLimited', () {
      final client = MockClient((_) async => http.Response('slow down', 429));
      expect(
        providerWith(auth: signedInAuth(), client: client).getCredential(),
        throwsA(isA<RealmAuthRateLimited>()),
      );
    });

    test('malformed 200 body (missing expiresAt) → RealmAuthCredentialInvalid',
        () {
      final client =
          MockClient((_) async => http.Response('{"token":"x"}', 200));
      expect(
        providerWith(auth: signedInAuth(), client: client).getCredential(),
        throwsA(isA<RealmAuthCredentialInvalid>()),
      );
    });

    test('valid-but-wrong-shape 200 body (JSON array) fails closed', () {
      // Regression: `jsonDecode(...) as Map` would throw an uncaught TypeError
      // on a non-object body; it must fail closed instead.
      final client = MockClient((_) async => http.Response('["nope"]', 200));
      expect(
        providerWith(auth: signedInAuth(), client: client).getCredential(),
        throwsA(isA<RealmAuthCredentialInvalid>()),
      );
    });
  });

  group('signIn', () {
    test('anonymous sign-in returns a RealmUser', () async {
      final user =
          await providerWith(auth: MockFirebaseAuth()).signIn(const Anonymous());
      expect(user.providerIds, contains(AuthProviderId.anonymous));
    });

    test('an unwired provider throws UnsupportedError, not a silent failure',
        () {
      expect(
        providerWith(auth: MockFirebaseAuth()).signIn(const GoogleAuth()),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('exchange endpoint safety', () {
    test('a non-https exchange endpoint is rejected at construction', () {
      expect(
        () => FirebaseAuthProvider(
          exchangeEndpoint: Uri.parse('http://insecure.example/exchange'),
          auth: MockFirebaseAuth(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('http is allowed only under the explicit dev flag', () {
      expect(
        () => FirebaseAuthProvider(
          exchangeEndpoint: Uri.parse('http://localhost:8080/exchange'),
          auth: MockFirebaseAuth(),
          allowInsecureExchangeEndpoint: true,
        ),
        returnsNormally,
      );
    });

    test('a stalled exchange times out as RealmAuthNetworkError', () {
      final client = MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        return http.Response('{}', 200);
      });
      final provider = FirebaseAuthProvider(
        exchangeEndpoint: exchangeUrl,
        auth: signedInAuth(),
        httpClient: client,
        exchangeTimeout: const Duration(milliseconds: 20),
      );
      expect(
        provider.getCredential(),
        throwsA(isA<RealmAuthNetworkError>()),
      );
    });
  });

  test('signOut clears currentUser', () async {
    final provider = providerWith(auth: signedInAuth());
    expect(provider.currentUser, isNotNull);
    await provider.signOut();
    expect(provider.currentUser, isNull);
  });
}
