import '../ids.dart';

/// Identity and credentials for a Realm instance.
///
/// Sign-in operations take an [AuthMethod] rather than exposing
/// provider-specific methods (`signInWithGoogle`, `signInWithApple`, …).
/// Adding a new provider means shipping a new [AuthMethod] implementation in a
/// plugin — no engine change required. Closed-set-as-method-names is the same
/// anti-pattern as closed-set-as-Strings; this contract rejects both.
///
/// **No-leak rule**: no backend type may cross this boundary. Implementations
/// translate `firebase_auth.User`, GitHub access tokens, provider SDK
/// exceptions, etc. into the engine types below.
abstract interface class AuthProvider {
  /// The authenticated user, or `null` when signed out.
  ///
  /// Emits on every identity transition, including token refreshes that change
  /// a field of [RealmUser].
  Stream<RealmUser?> userChanges();

  /// The currently authenticated user, or `null` when signed out.
  RealmUser? get currentUser;

  /// Authenticate using [method].
  ///
  /// Throws a [RealmAuthException] subtype on failure. Implementations MUST
  /// translate provider-native exceptions rather than letting them escape.
  Future<RealmUser> signIn(AuthMethod method);

  /// Terminate the current session.
  Future<void> signOut();

  /// A short-lived, exchange-verified credential for calling Realm endpoints.
  ///
  /// See the "Credential exchange boundary" section of `DESIGN.md`: the engine
  /// never sees provider-native tokens. The plugin exchanges those server-side
  /// for the opaque token wrapped here.
  Future<RealmCredential> getCredential({bool forceRefresh = false});
}

/// How a user authenticates. Open extension point.
///
/// Deliberately `abstract interface class`, NOT `sealed` — the plugin
/// ecosystem is an open set by design. A future `realm_discord_auth` plugin
/// ships `class DiscordAuth implements AuthMethod` with no engine change.
/// Consumers branch non-exhaustively (`if (method is GoogleAuth)`, or `switch`
/// with a `default:` arm); no exhaustive switch is possible, and that is the
/// correct posture for an extension point.
///
/// Adding an implementation is non-breaking: no changelog entry, no version
/// bump. Contrast with the audience-bounded sealed surfaces ([LeaveReason],
/// [FoyerVisibility], `PeerPresence`, `RoomPreview`, `RoomRef`) where adding a
/// variant IS a break.
abstract interface class AuthMethod {}

/// Sign in with Google.
class GoogleAuth implements AuthMethod {
  /// Creates a Google sign-in method.
  const GoogleAuth();
}

/// Sign in with Apple.
class AppleAuth implements AuthMethod {
  /// Creates an Apple sign-in method.
  const AppleAuth();
}

/// Sign in with GitHub, optionally requesting OAuth [scopes].
class GitHubAuth implements AuthMethod {
  /// Creates a GitHub sign-in method requesting [scopes].
  const GitHubAuth({this.scopes = const []});

  /// OAuth scopes to request. Empty requests the provider's default scope.
  final List<String> scopes;
}

/// Sign in with an email address and password.
class EmailPassword implements AuthMethod {
  /// Creates an email/password sign-in method.
  const EmailPassword({required this.email, required this.password});

  /// The account's email address.
  final String email;

  /// The account's password. Never logged, never persisted by the engine.
  final String password;
}

/// Sign in via a one-time link sent to [email].
class MagicLink implements AuthMethod {
  /// Creates a magic-link sign-in method.
  const MagicLink({required this.email});

  /// Address the link is sent to.
  final String email;
}

/// Sign in with a platform passkey (WebAuthn).
class Passkey implements AuthMethod {
  /// Creates a passkey sign-in method.
  const Passkey();
}

/// Sign in without an identity, producing an ephemeral account.
class Anonymous implements AuthMethod {
  /// Creates an anonymous sign-in method.
  const Anonymous();
}

/// Which provider vouched for an identity. Open set.
///
/// Plugins mint their own (`AuthProviderId('discord')`,
/// `AuthProviderId('steam')`). The engine ships canonical constants for the
/// common providers but does NOT gatekeep — the set is opaque-string by
/// design, parallel to how the architecture treats world types and storage
/// backends as registry-validated open sets.
///
/// **CRITICAL: this is a display-and-routing hint, NOT a trust primitive.** A
/// malicious plugin can ship `AuthProviderId('google')` for non-Google
/// authentication; the engine does not and cannot prevent that. Trust is
/// established at the credential-exchange endpoint, which verifies native
/// credentials against the real provider's signing authority — so a plugin
/// lying about its provider fails verification and never produces a valid
/// [RealmCredential].
///
/// **Consumer policy** (engine commitment, future `realm_lints` rule (a)):
/// - Display surfaces ("Signed in with Google") MAY read
///   [RealmUser.providerIds].
/// - Trust, access-control and authorization decisions MUST NOT read it. Use
///   [RealmCredential] provenance, which IS exchange-verified.
///
/// Until `realm_lints` ships, the compensating control is cage-match grep for
/// `providerIds.contains(` in access-control paths.
extension type const AuthProviderId(String value) {
  /// Google, via any plugin that verifies against Google.
  static const google = AuthProviderId('google');

  /// Apple.
  static const apple = AuthProviderId('apple');

  /// GitHub.
  static const github = AuthProviderId('github');

  /// Firebase Auth acting as the verifying authority.
  static const firebase = AuthProviderId('firebase');

  /// Email and password.
  static const emailPassword = AuthProviderId('email_password');

  /// Platform passkey (WebAuthn).
  static const passkey = AuthProviderId('passkey');

  /// Anonymous / ephemeral account.
  static const anonymous = AuthProviderId('anonymous');
}

/// A user, as the engine understands one.
///
/// Several fields are PII. The engine treats them as such: they are available
/// in-room, but the foyer's cross-room presence projection cannot express
/// them. See `PresenceService`.
class RealmUser {
  /// Creates a user projection.
  const RealmUser({
    required this.id,
    required this.providerIds,
    this.displayName,
    this.email,
    this.username,
    this.avatarUrl,
    this.emailVerified = false,
    this.extraClaims = const {},
  });

  /// Stable, opaque identifier minted by the [AuthProvider].
  final UserId id;

  /// Human-readable name. **PII.**
  final String? displayName;

  /// Email address. **PII.**
  final String? email;

  /// Provider-side handle. **PII** — common across most providers.
  final String? username;

  /// Avatar image location, if the provider supplies one.
  final Uri? avatarUrl;

  /// Whether the provider asserts [email] has been verified.
  final bool emailVerified;

  /// Which providers vouched for this identity.
  ///
  /// Display-only — see [AuthProviderId] for why this must never gate access.
  final Set<AuthProviderId> providerIds;

  /// Provider-specific claims that have no engine-level meaning.
  ///
  /// The escape hatch: reading it couples the consumer to one provider's
  /// shape. Use the typed fields above where possible. Allowed only inside
  /// `packages/realm_<provider>/` plugins; flagged elsewhere by the no-leak
  /// lint once `realm_lints` ships.
  final Map<String, Object?> extraClaims;
}

/// An engine-defined credential token.
///
/// Translation from provider-native tokens (Firebase ID token, GitHub access
/// token, …) happens server-side at the credential-exchange endpoint. The
/// engine never sees provider-native tokens, so this type never carries one.
class RealmCredential {
  /// Wraps an exchange-minted opaque [token] valid until [expiresAt].
  const RealmCredential({required this.token, required this.expiresAt});

  /// Opaque bearer token minted by the exchange endpoint.
  final String token;

  /// When [token] stops being accepted.
  final DateTime expiresAt;
}

/// Base class for authentication failures.
///
/// Implementations catch provider-native exceptions and translate to one of
/// the subtypes below, so consumers never depend on a backend SDK's error
/// vocabulary.
///
/// Not `sealed`: an implementation may need to report a failure mode none of
/// the four canonical subtypes describes, and forcing every such case into a
/// wrong bucket loses information consumers need. Consumers branch
/// non-exhaustively and treat unrecognised subtypes as generic failures.
abstract class RealmAuthException implements Exception {
  /// Creates an auth exception carrying a human-readable [message].
  const RealmAuthException(this.message);

  /// Human-readable description. Never contains credentials.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The user dismissed or aborted the sign-in flow.
class RealmAuthCancelled extends RealmAuthException {
  /// Creates a cancellation.
  const RealmAuthCancelled([super.message = 'Sign-in cancelled by user']);
}

/// The sign-in attempt could not reach the provider or the exchange endpoint.
class RealmAuthNetworkError extends RealmAuthException {
  /// Creates a network failure.
  const RealmAuthNetworkError([super.message = 'Network error during sign-in']);
}

/// The provider or exchange endpoint is throttling this client.
class RealmAuthRateLimited extends RealmAuthException {
  /// Creates a rate-limit failure, optionally carrying a [retryAfter] hint.
  const RealmAuthRateLimited([
    super.message = 'Rate limited by auth provider',
    this.retryAfter,
  ]);

  /// How long to wait before retrying, if the provider said.
  final Duration? retryAfter;
}

/// The credential was rejected — expired, malformed, or failed verification.
class RealmAuthCredentialInvalid extends RealmAuthException {
  /// Creates a credential-rejection failure.
  const RealmAuthCredentialInvalid([super.message = 'Credential invalid']);
}
