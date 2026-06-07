import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// Whether the integration-harness build flag is set. `const` so the
/// token-minting code below tree-shakes out of every normal (production) build.
const bool _harnessEnabled = bool.fromEnvironment('TW_HARNESS');

/// API key/secret for the LOCAL `livekit-server` the harness runs against.
/// Default to livekit-server's `--dev` credentials (`devkey` / `secret`); only
/// consulted when [_harnessEnabled] is true, against a local SFU. These are NOT
/// production secrets — production tokens are minted server-side by the
/// `retrieveLiveKitToken` Cloud Function.
const String _apiKey =
    String.fromEnvironment('LIVEKIT_API_KEY', defaultValue: 'devkey');
const String _apiSecret =
    String.fromEnvironment('LIVEKIT_API_SECRET', defaultValue: 'secret');

/// Mints a LiveKit access token client-side for the integration harness, so a
/// real client can join a local `livekit-server` without the
/// `retrieveLiveKitToken` Cloud Function (which mints only for the production
/// SFU, with a server-held secret).
///
/// Returns `null` in every normal build — see [_harnessEnabled] — so the caller
/// falls through to the Cloud Function path unchanged. Each browser tab
/// anonymous-auths to a distinct [identity], so two tabs from one served build
/// mint two distinct, room-matched tokens with no harness-side plumbing.
///
/// The token is an HS256 JWT granting join + publish + subscribe on [room] for
/// [identity]. See docs/integration-harness.md (seam S2).
String? mintHarnessToken({
  required String identity,
  required String room,
  required String name,
}) {
  if (!_harnessEnabled) return null;
  return buildLivekitJwt(
    identity: identity,
    room: room,
    name: name,
    apiKey: _apiKey,
    apiSecret: _apiSecret,
  );
}

/// Builds a LiveKit HS256 access token. Split out from [mintHarnessToken] (which
/// gates on the build flag) so the JWT construction is directly unit-testable
/// without compiling under `--dart-define=TW_HARNESS=true`. A malformed token
/// means the harness silently fails to connect, so this is worth verifying
/// against the bytes a server would check — see
/// `test/livekit/harness_token_test.dart`.
@visibleForTesting
String buildLivekitJwt({
  required String identity,
  required String room,
  required String name,
  required String apiKey,
  required String apiSecret,
  int? nowOverride,
}) {
  final now = nowOverride ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final header = {'alg': 'HS256', 'typ': 'JWT'};
  final payload = {
    'iss': apiKey,
    'sub': identity,
    'name': name,
    'nbf': now,
    'exp': now + 6 * 60 * 60, // 6h — comfortably longer than a harness run
    'video': {
      'room': room,
      'roomJoin': true,
      'canPublish': true,
      'canSubscribe': true,
      'canPublishData': true,
    },
  };

  // JWT uses unpadded base64url for every segment.
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(json.encode(m))).replaceAll('=', '');

  final signingInput = '${seg(header)}.${seg(payload)}';
  final sig =
      Hmac(sha256, utf8.encode(apiSecret)).convert(utf8.encode(signingInput));
  final sigB64 = base64Url.encode(sig.bytes).replaceAll('=', '');
  return '$signingInput.$sigB64';
}
