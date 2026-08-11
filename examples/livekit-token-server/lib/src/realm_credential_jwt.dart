/// The Realm-issued credential JWT — the opaque token wrapped in a
/// [RealmCredential] (`packages/realm/DESIGN.md`, "Credential exchange
/// boundary").
///
/// **Asymmetric by construction (ES256).** The credential-exchange handler
/// holds the *private* key and MINTS ([RealmCredentialIssuer]); the LiveKit
/// mint handler holds only the *public* key and VERIFIES
/// ([RealmCredentialVerifier]). This is what makes DESIGN.md's claim — "the
/// signing key is scoped to the exchange handler, so a bug in the mint handler
/// cannot forge a `RealmCredential`" — structurally true rather than
/// aspirational: the mint side never possesses the signing key, so no mint-side
/// defect can produce a token that verifies. A symmetric (HMAC) scheme would
/// hand the mint handler the signing key and void that property.
///
/// The token deliberately carries only what the mint side needs to authorize:
/// the [UserId] subject and the exchange-attested [AuthProviderId] provenance.
/// PII (display name, email) never enters the credential — it stays on the
/// [RealmUser] projection inside the room, per the engine's PII posture.
library;

import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:realm/realm.dart';

/// Issuer (`iss`) claim identifying credentials minted by a Realm exchange.
const realmIssuer = 'realm';

/// Audience (`aud`) claim naming the Realm LiveKit mint endpoint. The mint
/// handler rejects any token not scoped to it, so a credential minted for one
/// Realm-internal endpoint cannot be replayed against another.
const realmLiveKitAudience = 'realm:livekit-mint';

/// Mints Realm credentials. **Exchange-side only** — holds the ES256 private
/// key. Instantiate this exclusively in the credential-exchange handler, after
/// it has verified the caller's provider-native credential (Firebase ID token,
/// etc.) against the provider's real signing authority.
class RealmCredentialIssuer {
  /// Creates an issuer signing with the ES256 [signingKey].
  ///
  /// Loading the key is the caller's concern — production parses PEM from its
  /// secret store (`ECPrivateKey(pemFromEnv)`); tests generate an ephemeral
  /// keypair. Keeping the load out of this class means no key material is ever
  /// hard-coded or committed.
  ///
  /// [ttl] is the credential lifetime; keep it short (default 1h) — revocation
  /// is by expiry, not a per-request store read (DESIGN.md, resolved 2026-08-10).
  RealmCredentialIssuer({
    required ECPrivateKey signingKey,
    this.issuer = realmIssuer,
    this.audience = realmLiveKitAudience,
    this.ttl = const Duration(hours: 1),
  }) : _key = signingKey {
    // Fail closed on a misconfigured lifetime. Guard on whole SECONDS, not just
    // `> Duration.zero`: `exp`/`iat` are integer seconds, so a sub-second ttl
    // (e.g. 999ms) would floor to `exp == iat` and mint an already-dead
    // credential while passing a naive `> zero` check.
    if (ttl.inSeconds < 1) {
      throw ArgumentError.value(ttl, 'ttl', 'must be at least one second');
    }
  }

  final ECPrivateKey _key;

  /// The `iss` claim stamped on every minted credential.
  final String issuer;

  /// The `aud` claim stamped on every minted credential.
  final String audience;

  /// How long a minted credential stays valid.
  final Duration ttl;

  /// Mints a credential attesting that [subject], vouched for by [provider],
  /// may call the Realm LiveKit mint endpoint until [RealmCredential.expiresAt].
  ///
  /// [issuedAt] is injectable for deterministic tests; defaults to now (UTC).
  RealmCredential issue({
    required UserId subject,
    required AuthProviderId provider,
    DateTime? issuedAt,
  }) {
    // Fail at the mint boundary (the sole trust-establishment point), not only
    // at verify: an empty subject/provider is a hollow claim the verifier would
    // reject anyway, so never sign one.
    if (subject.value.isEmpty) {
      throw ArgumentError.value(subject, 'subject', 'must not be empty');
    }
    if (provider.value.isEmpty) {
      throw ArgumentError.value(provider, 'provider', 'must not be empty');
    }
    // JWT `exp`/`iat` are whole-second UNIX times. Compute those integer seconds
    // FIRST and derive `expiresAt` back from the exp second, so the advertised
    // [RealmCredential.expiresAt] is byte-for-byte the token's authoritative
    // `exp` — no sub-second tail where a client believes a rejected token is
    // still live.
    final iatSeconds =
        (issuedAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000;
    final expSeconds = iatSeconds + ttl.inSeconds;
    final expiresAt =
        DateTime.fromMillisecondsSinceEpoch(expSeconds * 1000, isUtc: true);
    final jwt = JWT(
      <String, dynamic>{
        'prov': provider.value,
        'iat': iatSeconds,
        'exp': expSeconds,
      },
      issuer: issuer,
      subject: subject.value,
      audience: Audience.one(audience),
    );
    final token = jwt.sign(_key, algorithm: JWTAlgorithm.ES256, noIssueAt: true);
    return RealmCredential(token: token, expiresAt: expiresAt);
  }
}

/// Verifies Realm credentials. **Mint-side only** — holds the ES256 *public*
/// key, never the private key. A defect here cannot forge a credential; the
/// worst it can do is wrongly reject a valid one (fail-closed).
class RealmCredentialVerifier {
  /// Creates a verifier checking signatures against the ES256 [publicKey].
  /// [issuer] and [audience] must match the issuer's. The mint handler holds
  /// ONLY this public key — never the private key — so it cannot mint.
  RealmCredentialVerifier({
    required ECPublicKey publicKey,
    this.issuer = realmIssuer,
    this.audience = realmLiveKitAudience,
  }) : _key = publicKey;

  final ECPublicKey _key;

  /// The `iss` claim required on an accepted credential.
  final String issuer;

  /// The `aud` claim required on an accepted credential.
  final String audience;

  /// Verifies [token] and returns the exchange-attested claims.
  ///
  /// Throws [RealmCredentialRejected] on ANY failure — bad signature (including
  /// a token signed by a different key), expiry, wrong issuer/audience,
  /// malformed structure, or missing required claims. There is no partial
  /// acceptance: the caller either gets trustworthy claims or an exception.
  VerifiedRealmClaims verify(String token) {
    // Pin the algorithm. dart_jsonwebtoken's verify dispatches on the token
    // HEADER's `alg` (`JWTAlgorithm.fromName(header['alg'])`), not the key type,
    // and exposes no algorithm parameter — so reject anything but ES256 before
    // verifying, closing the algorithm-confusion surface and matching the Node
    // verifier's explicit `algorithms: ['ES256']` pin.
    if (_headerAlg(token) != 'ES256') {
      throw const RealmCredentialRejected('unexpected or missing algorithm');
    }

    final JWT jwt;
    try {
      jwt = JWT.verify(
        token,
        _key,
        issuer: issuer,
        audience: Audience.one(audience),
      );
    } on JWTException catch (e) {
      // JWTExpiredException, JWTInvalidException (bad sig / wrong iss / wrong
      // aud), JWTParseException — all collapse to one fail-closed outcome.
      throw RealmCredentialRejected(e.message);
    }

    final payload = jwt.payload;
    // Require an `exp` claim. dart_jsonwebtoken only CHECKS exp when present, so
    // a validly-signed token that omits it would never expire — breaking the
    // revocation-by-expiry invariant. Reject a missing/non-numeric exp so no
    // immortal credential can pass, even from a buggy exchange.
    final exp = payload is Map ? payload['exp'] : null;
    if (exp is! int) {
      throw const RealmCredentialRejected('missing or non-numeric exp claim');
    }
    // Extract with type CHECKS, never `as` casts: a validly-signed token can
    // still carry a non-string `sub`/`prov` (e.g. a number), and `x as String`
    // would throw a raw TypeError that escapes the fail-closed contract. Every
    // malformed-claim shape must collapse to RealmCredentialRejected.
    final sub = jwt.subject ?? (payload is Map ? payload['sub'] : null);
    final prov = payload is Map ? payload['prov'] : null;
    if (sub is! String || sub.isEmpty) {
      throw const RealmCredentialRejected('missing or non-string subject claim');
    }
    if (prov is! String || prov.isEmpty) {
      throw const RealmCredentialRejected('missing or non-string provider claim');
    }
    return VerifiedRealmClaims(
      subject: UserId(sub),
      provider: AuthProviderId(prov),
    );
  }

  /// The `alg` from the token's JWS header, or null if the token is malformed.
  /// Any decode failure returns null (→ rejected), never throws.
  static String? _headerAlg(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final decoded =
          jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))));
      final alg = decoded is Map ? decoded['alg'] : null;
      return alg is String ? alg : null;
    } catch (_) {
      return null;
    }
  }
}

/// The trustworthy claims a [RealmCredentialVerifier] extracts from a valid
/// credential. Provenance here IS exchange-verified — unlike
/// [RealmUser.providerIds], it is safe to gate authorization on.
class VerifiedRealmClaims {
  /// Creates a verified-claims value.
  const VerifiedRealmClaims({required this.subject, required this.provider});

  /// The authenticated user the credential vouches for.
  final UserId subject;

  /// Which provider the exchange verified when it minted the credential.
  final AuthProviderId provider;
}

/// A credential failed verification. Carries a non-sensitive [reason] for logs;
/// never echo it to an unauthenticated caller as anything but a generic 401.
class RealmCredentialRejected implements Exception {
  /// Creates a rejection carrying a short, credential-free [reason].
  const RealmCredentialRejected(this.reason);

  /// Why verification failed. Contains no token bytes or key material.
  final String reason;

  @override
  String toString() => 'RealmCredentialRejected: $reason';
}
