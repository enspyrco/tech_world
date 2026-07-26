/// Where the engine goes to trade a credential for a LiveKit access token.
///
/// This is a **deployment-shape contract** surfaced as a Dart config value.
/// The engine never calls a Dart method on it — it sends an HTTP request — but
/// the URL and auth strategy must be configurable in Dart, so they live here.
///
/// The engine sends the current user's `RealmCredential` to the endpoint; the
/// endpoint validates it server-side and returns a LiveKit access token. Token
/// contents — room grants, embedded agent dispatch, metadata — are entirely
/// the endpoint's concern.
///
/// Reference implementations live in `examples/livekit-token-server/`.
class LiveKitTokenEndpoint {
  /// Points the engine at [url], authenticating with [authStrategy].
  const LiveKitTokenEndpoint({required this.url, required this.authStrategy});

  /// The endpoint's location.
  final Uri url;

  /// How the engine authenticates to it.
  final TokenEndpointAuthStrategy authStrategy;
}

/// How the engine authenticates to a token endpoint. Open extension point.
///
/// **The engine ships exactly one concrete strategy — [BearerCredential] —
/// because it is the only one safe to instantiate in client code.** Anything
/// declared in `packages/realm/` is shipped to every Flutter web, mobile and
/// desktop client; a secret-bearing strategy declared here would be extractable
/// from any bundle. Server-side strategies (HMAC-signed request, mTLS,
/// IP-allowlist) therefore ship in server-only packages — see
/// `examples/livekit-token-server/`.
///
/// The interface is deliberately NOT sealed. Sealing would force every variant
/// into the engine's library, and the engine's library is the client bundle —
/// so unsealing makes this a *package* boundary rather than a *prose*
/// annotation, which is the only kind of boundary that actually holds.
///
/// Two artifacts make that boundary structural rather than aspirational:
/// `examples/livekit-token-server/` as a workspace member that imports the
/// engine and is never imported by it (**shipped**, migration step 2), and a
/// CI check on the engine's resolved transitive dependencies that fails the
/// build if any signing or crypto primitive appears (**pending**, migration
/// step 4). Until the second lands, the compensating control is cage-match
/// grep: reviewers reject any secret-bearing `TokenEndpointAuthStrategy` in a
/// Flutter-reachable path.
abstract interface class TokenEndpointAuthStrategy {}

/// Sends `Authorization: Bearer <RealmCredential.token>` with each request.
///
/// The only strategy the engine ships. The bearer is the per-user credential,
/// which is short-lived and scoped — extracting it from a client gives an
/// attacker at most that one user's session, which is the same exposure as
/// having the client itself.
class BearerCredential implements TokenEndpointAuthStrategy {
  /// Creates the bearer-credential strategy.
  const BearerCredential();
}
