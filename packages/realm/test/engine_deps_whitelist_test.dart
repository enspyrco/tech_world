// Engine-package transitive-deps gate (DESIGN.md, migration step 4 — the
// second structural artifact of the engine-vs-server-package boundary; the
// first is examples/livekit-token-server/ from step 2).
//
// WHY: `packages/realm/` is the ENGINE package, and the engine package is
// shipped to every Flutter web/mobile/desktop client. If a signing/HMAC/crypto
// primitive could reach the engine's *shipped* dependency closure, a client
// could mint its own LiveKit (or any Realm-internal) tokens — collapsing the
// credential-exchange trust boundary. DESIGN.md "Server-side strategies live
// outside the engine package": those live in realm_firebase or in
// examples/livekit-token-server/, never in packages/realm/.
//
// This is the dependency-graph sibling of no_leak_test.dart: no_leak keeps
// backend *types* out of the engine one layer up (imports); this keeps signing
// *capability* out of the engine one layer down (deps).
//
// SCOPE: only the engine's SHIPPED (regular) dependency closure is checked —
// seeds come from `directDependencies`, never `devDependencies`. A dev-only
// signing lib (or the test framework's own transitive graph) never reaches a
// client, so it is not a leak and must not false-positive the gate.
//
// It rides the workspace member-test loop (test.yml / deploy.yml) into CI, so
// no separate YAML wiring is required.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Signing / crypto / key-encoding primitives that must never appear in the
/// engine's shipped transitive closure. DESIGN.md names `crypto`,
/// `cryptography`, `pointycastle` explicitly ("e.g."); the set is extended to
/// the token-signing and key-material family because the *capability* being
/// fenced out is "can this package sign/mint a token", not any one library.
/// realm_firebase and examples/livekit-token-server may carry these freely.
const _forbidden = <String>{
  'crypto', // SHA/HMAC — dart:crypto community package
  'cryptography', // AEAD/signing
  'cryptography_flutter',
  'pointycastle', // full asymmetric-crypto stack (RSA/EC signing)
  'dart_jsonwebtoken', // mints/signs JWTs
  'jose', // JWS/JWE
  'jose_plus',
  'ed25519_edwards', // EdDSA signing
  'x25519',
  'webcrypto',
  'asn1lib', // ASN.1 DER — key/cert encoding, a signing-stack tell
  'basic_utils', // ships RSA/EC key + CSR helpers
};

void main() {
  test(
    'engine package `realm` ships no signing/crypto primitive '
    '(DESIGN.md transitive-deps whitelist)',
    () {
      final result = Process.runSync('dart', ['pub', 'deps', '--json']);
      expect(
        result.exitCode,
        0,
        reason: 'dart pub deps --json failed (is the workspace resolved?): '
            '${result.stderr}',
      );

      final graph = jsonDecode(result.stdout as String) as Map<String, Object?>;
      final nodes = <String, Map<String, Object?>>{
        for (final p in graph['packages']! as List)
          (p as Map<String, Object?>)['name']! as String: p,
      };

      final realm = nodes['realm'];
      expect(
        realm,
        isNotNull,
        reason: 'no `realm` node in the pub deps graph — did the package get '
            'renamed, or is this running outside the workspace?',
      );

      // Seed strictly from SHIPPED (regular) deps. devDependencies (e.g.
      // `test`) never reach a client and are deliberately excluded.
      final seeds =
          (realm!['directDependencies']! as List).cast<String>().toList();

      // BFS the transitive closure over each package's resolved `dependencies`
      // edges. Non-root packages carry only their regular deps here (pub does
      // not resolve a non-root package's dev_dependencies), so the closure is
      // exactly the shipped graph — no dev-dep bleed.
      final closure = <String>{};
      final queue = <String>[...seeds];
      while (queue.isNotEmpty) {
        final name = queue.removeLast();
        if (!closure.add(name)) continue;
        final node = nodes[name];
        if (node == null) continue;
        queue.addAll((node['dependencies']! as List).cast<String>());
      }

      final violations = closure.intersection(_forbidden);
      expect(
        violations,
        isEmpty,
        reason: 'Engine package `realm` transitively ships signing/crypto '
            'primitive(s): $violations.\n'
            'These belong in realm_firebase or examples/livekit-token-server, '
            'never in the client-shipped engine package. A signing capability '
            'in the engine lets any client mint its own tokens — see DESIGN.md '
            '"Server-side strategies live outside the engine package".',
      );
    },
  );
}
