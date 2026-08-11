import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:realm/realm.dart';
import 'package:realm_firebase/realm_firebase.dart';
import 'package:tech_world/livekit/livekit_service.dart'
    show ConnectionResult, TokenResult;

/// The realm-backed LiveKit token source — the client half of the
/// strangler-fig cutover away from the `retrieveLiveKitToken` Cloud Function.
///
/// Two HTTP hops, both through engine types:
///   1. [AuthProvider.getCredential] exchanges the provider-native token (a
///      Firebase ID token) for an opaque [RealmCredential] at the exchange
///      endpoint. The engine never sees the native token.
///   2. This source POSTs that credential (as `Authorization: Bearer …`, per
///      the engine's [BearerCredential] strategy) to the [LiveKitTokenEndpoint],
///      which verifies it server-side and mints the LiveKit access token —
///      including the embedded agent dispatch that makes the bots auto-join.
///
/// Errors are mapped to a classified [TokenResult] so [LiveKitService]'s
/// reconnect logic can distinguish an auth failure (abort, re-sign-in) from a
/// retryable network failure — the whole reason the token seam carries a
/// [ConnectionResult] rather than a bare `String?`. This source is the only
/// place that knows about [RealmAuthException]; `livekit_service.dart` stays
/// engine-agnostic.
class RealmTokenSource {
  /// Composes an eager [authProvider] (hop 1) with [endpoint] (hop 2). Used by
  /// tests to inject a fake provider; the caller owns [authProvider]'s
  /// lifecycle (this source will not dispose it).
  ///
  /// [httpClient] is a DI seam for tests; defaults to a fresh [http.Client]
  /// owned by this source and closed by [dispose]. [timeout] bounds the hop-2
  /// POST.
  RealmTokenSource({
    required AuthProvider authProvider,
    required this.endpoint,
    required this.roomName,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
  })  : _authProvider = authProvider,
        _exchangeEndpoint = null,
        _ownsProvider = false,
        _http = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null;

  /// Production constructor: lazily builds (and owns) a [FirebaseAuthProvider]
  /// on the first [fetch], pointed at [exchangeEndpoint]. Construction touches
  /// no Firebase state, so a [RealmTokenSource] can be built before
  /// `Firebase.initializeApp` — the provider (and thus `FirebaseAuth.instance`)
  /// is only reached when a token is actually fetched, at connect time. This
  /// source disposes the provider it created.
  RealmTokenSource.firebase({
    required Uri exchangeEndpoint,
    required this.endpoint,
    required this.roomName,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
  })  : _authProvider = null,
        _exchangeEndpoint = exchangeEndpoint,
        _ownsProvider = true,
        _http = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null;

  /// Hop 2: where the credential is traded for a LiveKit access token.
  final LiveKitTokenEndpoint endpoint;

  /// The room the minted token grants access to.
  final String roomName;

  /// Upper bound on the hop-2 POST before it fails as a network error.
  final Duration timeout;

  /// Hop 1 provider. Eager (injected) in the default constructor; `null` until
  /// the first [fetch] in the `.firebase` constructor.
  AuthProvider? _authProvider;

  /// Where a lazily-built provider exchanges tokens (`.firebase` mode only).
  final Uri? _exchangeEndpoint;

  /// Whether this source built [_authProvider] itself and must dispose it.
  final bool _ownsProvider;

  final http.Client _http;
  final bool _ownsHttpClient;

  /// Releases resources this source owns: its HTTP client (unless injected) and,
  /// in `.firebase` mode, the provider it lazily built (if [fetch] ran).
  void dispose() {
    if (_ownsHttpClient) _http.close();
    final provider = _authProvider;
    if (_ownsProvider && provider is FirebaseAuthProvider) {
      provider.dispose();
    }
  }

  /// Runs both hops and returns a classified [TokenResult].
  Future<TokenResult> fetch() async {
    final authProvider = _authProvider ??=
        FirebaseAuthProvider(exchangeEndpoint: _exchangeEndpoint!);

    final RealmCredential credential;
    try {
      credential = await authProvider.getCredential();
    } on RealmAuthCredentialInvalid {
      // The exchange rejected the identity — re-auth, don't retry.
      return const TokenResult.failure(ConnectionResult.tokenAuthError);
    } on RealmAuthException {
      // Network, rate-limit, cancelled: retryable transport faults.
      return const TokenResult.failure(ConnectionResult.tokenNetworkError);
    }

    final http.Response response;
    try {
      response = await _http
          .post(
            endpoint.url,
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer ${credential.token}',
            },
            body: jsonEncode({'roomName': roomName}),
          )
          .timeout(timeout);
    } on TimeoutException {
      return const TokenResult.failure(ConnectionResult.tokenNetworkError);
    } on Exception {
      // Any transport failure (SocketException, TLS handshake, …).
      return const TokenResult.failure(ConnectionResult.tokenNetworkError);
    }

    switch (response.statusCode) {
      case 200:
        final token = _parseToken(response.body);
        return token != null
            ? TokenResult.success(token)
            : const TokenResult.failure(ConnectionResult.tokenUnknownError);
      case 401 || 403:
        // The mint rejected the credential → re-auth (don't retry forever).
        return const TokenResult.failure(ConnectionResult.tokenAuthError);
      case 400:
        // Malformed request (a client bug — roomName is always sent). Not an
        // auth failure and not meaningfully retryable.
        return const TokenResult.failure(ConnectionResult.tokenUnknownError);
      default:
        // 429 + 5xx + anything else: retryable network/server faults.
        return const TokenResult.failure(ConnectionResult.tokenNetworkError);
    }
  }

  String? _parseToken(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final token = decoded['token'];
      return (token is String && token.isNotEmpty) ? token : null;
    } on FormatException {
      return null;
    }
  }
}
