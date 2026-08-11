import 'dart:math';
import 'dart:typed_data';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:pointycastle/export.dart' as pc;

/// A test ES256 keypair, in the form the credential issuer/verifier accept.
typedef EcKeyPair = ({ECPrivateKey privateKey, ECPublicKey publicKey});

/// Generates an ephemeral ES256 (P-256) keypair in-process.
///
/// Key material is created at test time and never touches disk or git — the
/// gitleaks pre-commit gate blocks committed PEMs, so fixtures are generated,
/// not stored. Each call yields an independent keypair, which is exactly what
/// the "a foreign signature is rejected" test needs.
EcKeyPair generateEs256KeyPair() {
  final seed = Uint8List.fromList(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  );
  final rnd = pc.SecureRandom('Fortuna')..seed(pc.KeyParameter(seed));
  final generator = pc.ECKeyGenerator()
    ..init(
      pc.ParametersWithRandom(
        pc.ECKeyGeneratorParameters(pc.ECCurve_secp256r1()),
        rnd,
      ),
    );
  final pair = generator.generateKeyPair();
  return (
    privateKey: ECPrivateKey.raw(pair.privateKey),
    publicKey: ECPublicKey.raw(pair.publicKey),
  );
}
