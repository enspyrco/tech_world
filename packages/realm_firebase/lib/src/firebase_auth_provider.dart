import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:http/http.dart' as http;
import 'package:realm/realm.dart';

/// Firebase implementation of [AuthProvider].
///
/// **No-leak**: the public surface returns only engine types. A
/// `firebase_auth.User` is translated to [RealmUser] at the boundary and a
/// `FirebaseAuthException` is translated to a [RealmAuthException] subtype;
/// neither Firebase type ever escapes.
///
/// **Credential exchange**: [getCredential] does NOT return the Firebase ID
/// token. It sends that native token to the Realm credential-exchange endpoint
/// ([exchangeEndpoint]), which verifies it server-side (Firebase Admin SDK) and
/// mints an opaque [RealmCredential]. This is what keeps the engine and the
/// LiveKit-mint endpoint provider-agnostic — see `packages/realm/DESIGN.md`,
/// "Credential exchange boundary" (resolved 2026-08-10).
///
/// **Scope note**: [signIn] currently implements the Firebase-native flows
/// ([Anonymous], [EmailPassword]); provider flows that need a platform sign-in
/// plugin (Google, Apple, GitHub, magic-link, passkey) throw
/// [UnsupportedError] until wired. The credential path is fully implemented —
/// this is additive per-provider work, not a stubbed trust boundary.
class FirebaseAuthProvider implements AuthProvider {
  /// Creates a provider over [auth] (defaults to `FirebaseAuth.instance`),
  /// exchanging Firebase ID tokens for [RealmCredential]s at [exchangeEndpoint].
  ///
  /// [httpClient] is a DI seam for tests; defaults to a fresh [http.Client].
  FirebaseAuthProvider({
    required this.exchangeEndpoint,
    fb.FirebaseAuth? auth,
    http.Client? httpClient,
  })  : _auth = auth ?? fb.FirebaseAuth.instance,
        _http = httpClient ?? http.Client();

  /// The Realm credential-exchange endpoint. Receives the Firebase ID token,
  /// returns `{"token": <opaque>, "expiresAt": <ISO-8601>}`.
  final Uri exchangeEndpoint;

  final fb.FirebaseAuth _auth;
  final http.Client _http;

  @override
  RealmUser? get currentUser {
    final u = _auth.currentUser;
    return u == null ? null : _toRealmUser(u);
  }

  @override
  Stream<RealmUser?> userChanges() =>
      _auth.userChanges().map((u) => u == null ? null : _toRealmUser(u));

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<RealmUser> signIn(AuthMethod method) async {
    try {
      final fb.UserCredential cred;
      switch (method) {
        case Anonymous():
          cred = await _auth.signInAnonymously();
        case EmailPassword(:final email, :final password):
          cred = await _auth.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
        default:
          // Google/Apple/GitHub/MagicLink/Passkey need a platform sign-in
          // plugin; additive per-provider work, tracked separately.
          throw UnsupportedError(
            '${method.runtimeType} sign-in is not yet wired in '
            'FirebaseAuthProvider',
          );
      }
      final user = cred.user;
      if (user == null) {
        throw const RealmAuthCredentialInvalid(
          'sign-in returned no user',
        );
      }
      return _toRealmUser(user);
    } on fb.FirebaseAuthException catch (e) {
      throw _translateAuthException(e);
    }
  }

  @override
  Future<RealmCredential> getCredential({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const RealmAuthCredentialInvalid('no signed-in user');
    }

    final String idToken;
    try {
      final token = await user.getIdToken(forceRefresh);
      if (token == null || token.isEmpty) {
        throw const RealmAuthCredentialInvalid('Firebase returned no ID token');
      }
      idToken = token;
    } on fb.FirebaseAuthException catch (e) {
      throw _translateAuthException(e);
    }

    final http.Response response;
    try {
      response = await _http.post(
        exchangeEndpoint,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({'idToken': idToken}),
      );
    } on http.ClientException catch (e) {
      throw RealmAuthNetworkError('exchange request failed: ${e.message}');
    }

    switch (response.statusCode) {
      case 200:
        return _parseCredential(response.body);
      case 401 || 403:
        throw const RealmAuthCredentialInvalid(
          'exchange endpoint rejected the ID token',
        );
      case 429:
        throw const RealmAuthRateLimited('exchange endpoint rate-limited');
      default:
        throw RealmAuthNetworkError(
          'exchange endpoint returned HTTP ${response.statusCode}',
        );
    }
  }

  RealmCredential _parseCredential(String body) {
    try {
      final decoded = jsonDecode(body);
      // A 200 with valid-but-wrong-shape JSON (an array, a bare string) must
      // fail closed, not throw an uncaught cast error.
      if (decoded is! Map) {
        throw const RealmAuthCredentialInvalid(
          'exchange response was not a JSON object',
        );
      }
      final token = decoded['token'];
      final expiresRaw = decoded['expiresAt'];
      if (token is! String || token.isEmpty || expiresRaw is! String) {
        throw const RealmAuthCredentialInvalid(
          'exchange response missing token or expiresAt',
        );
      }
      return RealmCredential(
        token: token,
        expiresAt: DateTime.parse(expiresRaw),
      );
    } on FormatException catch (e) {
      throw RealmAuthCredentialInvalid('malformed exchange response: ${e.message}');
    }
  }

  RealmUser _toRealmUser(fb.User u) => RealmUser(
        id: UserId(u.uid),
        providerIds: _providerIds(u),
        displayName: _nullIfEmpty(u.displayName),
        email: _nullIfEmpty(u.email),
        avatarUrl: u.photoURL == null ? null : Uri.tryParse(u.photoURL!),
        emailVerified: u.emailVerified,
      );

  /// Maps Firebase's provider strings to engine [AuthProviderId]s.
  ///
  /// Display-only — [AuthProviderId] must never gate access (a provider string
  /// is forgeable; trust comes from the exchange-verified [RealmCredential]).
  Set<AuthProviderId> _providerIds(fb.User u) {
    if (u.isAnonymous) return {AuthProviderId.anonymous};
    final ids = <AuthProviderId>{};
    for (final info in u.providerData) {
      switch (info.providerId) {
        case 'google.com':
          ids.add(AuthProviderId.google);
        case 'apple.com':
          ids.add(AuthProviderId.apple);
        case 'github.com':
          ids.add(AuthProviderId.github);
        case 'password':
          ids.add(AuthProviderId.emailPassword);
      }
    }
    // Firebase is always the verifying authority for this plugin.
    ids.add(AuthProviderId.firebase);
    return ids;
  }

  RealmAuthException _translateAuthException(fb.FirebaseAuthException e) {
    switch (e.code) {
      case 'network-request-failed':
        return RealmAuthNetworkError(e.message ?? 'network error');
      case 'too-many-requests':
        return RealmAuthRateLimited(e.message ?? 'rate limited');
      case 'user-disabled' ||
            'wrong-password' ||
            'user-not-found' ||
            'invalid-credential' ||
            'invalid-email':
        return RealmAuthCredentialInvalid(e.message ?? 'credential invalid');
      default:
        return RealmAuthCredentialInvalid(e.message ?? e.code);
    }
  }

  static String? _nullIfEmpty(String? s) =>
      (s == null || s.isEmpty) ? null : s;
}
