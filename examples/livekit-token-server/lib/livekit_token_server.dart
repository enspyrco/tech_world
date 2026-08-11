import 'package:realm/realm.dart';

export 'src/realm_credential_jwt.dart';

/// Reference LiveKit token endpoint skeleton (migration step 2).
///
/// This file exists to pin the engine-vs-server dependency direction: the
/// token server depends on the engine (`import 'package:realm/realm.dart'`),
/// and the engine never depends on the server. Server-side auth strategies
/// (HMAC-signed request, mTLS) live HERE, never in `packages/realm/`, because
/// the engine package ships to every client. The real HTTP implementation
/// lands in a later migration step.
String tokenServerBanner() =>
    'livekit-token-server reference impl for realm $realmEngineVersion';
