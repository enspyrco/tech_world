import 'package:livekit_token_server/livekit_token_server.dart';
import 'package:realm/realm.dart';
import 'package:test/test.dart';

import 'support/ec_keys.dart';

void main() {
  // Ephemeral keypairs, generated in-process — no committed key material.
  // `attacker` is an independent keypair used to prove a foreign signature is
  // rejected (the mint-can't-forge property).
  final keys = generateEs256KeyPair();
  final attacker = generateEs256KeyPair();

  late RealmCredentialIssuer issuer;
  late RealmCredentialVerifier verifier;

  setUp(() {
    issuer = RealmCredentialIssuer(signingKey: keys.privateKey);
    verifier = RealmCredentialVerifier(publicKey: keys.publicKey);
  });

  group('round-trip', () {
    test('a freshly minted credential verifies to its subject + provider', () {
      final cred = issuer.issue(
        subject: const UserId('user-abc'),
        provider: AuthProviderId.firebase,
      );

      final claims = verifier.verify(cred.token);

      expect(claims.subject.value, 'user-abc');
      expect(claims.provider.value, AuthProviderId.firebase.value);
    });

    test('RealmCredential.expiresAt equals the token exp exactly', () {
      final iat = DateTime.utc(2026, 8, 10, 7, 0, 0);
      final cred = issuer.issue(
        subject: const UserId('u'),
        provider: AuthProviderId.google,
        issuedAt: iat,
      );
      // Default ttl is 1h; exp is truncated to whole seconds.
      expect(cred.expiresAt, iat.add(const Duration(hours: 1)));
    });
  });

  group('rejection (fail-closed)', () {
    test('a token signed by a DIFFERENT key is rejected '
        '(mint handler cannot forge — it has no private key)', () {
      // An attacker who fully controls a mint-side issuer still cannot mint a
      // credential the real verifier accepts: the signature is over the wrong
      // key. This is the asymmetric-signing property, proven not asserted.
      final forged = RealmCredentialIssuer(signingKey: attacker.privateKey)
          .issue(
        subject: const UserId('mallory'),
        provider: AuthProviderId.firebase,
      );

      expect(
        () => verifier.verify(forged.token),
        throwsA(isA<RealmCredentialRejected>()),
      );
    });

    test('a tampered token is rejected', () {
      final cred = issuer.issue(
        subject: const UserId('u'),
        provider: AuthProviderId.firebase,
      );
      // Flip the FIRST signature char — it encodes real high bits of byte 0.
      // (The LAST char holds don't-care padding bits, so flipping it can be a
      // no-op and the tampered token would still verify.)
      final parts = cred.token.split('.');
      final sig = parts[2];
      final tampered =
          '${parts[0]}.${parts[1]}.${sig[0] == 'A' ? 'B' : 'A'}${sig.substring(1)}';

      expect(
        () => verifier.verify(tampered),
        throwsA(isA<RealmCredentialRejected>()),
      );
    });

    test('an expired credential is rejected', () {
      final expiredIssuer = RealmCredentialIssuer(
        signingKey: keys.privateKey,
        ttl: const Duration(seconds: -10), // exp already in the past
      );
      final cred = expiredIssuer.issue(
        subject: const UserId('u'),
        provider: AuthProviderId.firebase,
      );

      expect(
        () => verifier.verify(cred.token),
        throwsA(isA<RealmCredentialRejected>()),
      );
    });

    test('a credential for a different audience is rejected', () {
      final cred = RealmCredentialIssuer(
        signingKey: keys.privateKey,
        audience: 'realm:some-other-endpoint',
      ).issue(subject: const UserId('u'), provider: AuthProviderId.firebase);

      // Verifier defaults to realm:livekit-mint — the mismatched aud must fail,
      // so a token minted for one Realm endpoint can't be replayed at another.
      expect(
        () => verifier.verify(cred.token),
        throwsA(isA<RealmCredentialRejected>()),
      );
    });

    test('a credential from a different issuer is rejected', () {
      final cred = RealmCredentialIssuer(
        signingKey: keys.privateKey,
        issuer: 'not-realm',
      ).issue(subject: const UserId('u'), provider: AuthProviderId.firebase);

      expect(
        () => verifier.verify(cred.token),
        throwsA(isA<RealmCredentialRejected>()),
      );
    });

    test('garbage input is rejected, not crashed on', () {
      expect(
        () => verifier.verify('not-a-jwt'),
        throwsA(isA<RealmCredentialRejected>()),
      );
    });
  });
}
