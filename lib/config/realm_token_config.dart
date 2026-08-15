/// Configuration for the realm-token-server — the service that exchanges a
/// Firebase ID token for a [RealmCredential] and mints LiveKit access tokens.
///
/// The base URL is overridable at build time via
/// `--dart-define=REALM_TOKEN_BASE=https://…` so staging / local dev can point
/// elsewhere without a code change. Defaults to the production dark deployment.
library;

const String _kRealmTokenBaseRaw = String.fromEnvironment(
  'REALM_TOKEN_BASE',
  defaultValue: 'https://realm-token.imagineering.cc',
);

/// Base URL of the realm-token-server, with any trailing slash(es) stripped so
/// `'$kRealmTokenBase/exchange'` can never become `'…//exchange'` (a
/// `--dart-define` with a trailing slash is an easy footgun at an auth boundary).
final String kRealmTokenBase =
    _kRealmTokenBaseRaw.replaceAll(RegExp(r'/+$'), '');

/// Hop 1: `POST` a Firebase ID token, receive an opaque `RealmCredential`.
Uri get realmExchangeEndpoint => Uri.parse('$kRealmTokenBase/exchange');

/// Hop 2: `POST` a `RealmCredential` (bearer), receive a LiveKit access token.
Uri get realmLiveKitTokenEndpoint => Uri.parse('$kRealmTokenBase/livekit-token');
