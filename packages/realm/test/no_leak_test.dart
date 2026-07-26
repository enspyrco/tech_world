import 'dart:io';

import 'package:test/test.dart';

/// The no-leak rule, enforced rather than asserted in prose.
///
/// The engine's whole architecture rests on one claim: `packages/realm/` knows
/// nothing about any backend, and nothing about Flutter. Every other promise —
/// that an operator can swap Firebase out, that a world can be rendered by
/// something other than Flame, that the engine could run in a text-mode bot —
/// is downstream of it.
///
/// A rule like that decays the moment it lives only in a design note. One
/// convenient `import 'package:cloud_firestore/…'` inside an implementation
/// helper, merged on a Friday, and the interface boundary is decorative. So
/// the rule reads the source.
void main() {
  group('engine package dependency isolation', () {
    /// Import prefixes that must never appear in the engine package.
    ///
    /// Flutter is banned alongside the backends on purpose: the engine's
    /// renderer-neutrality claim (`previewSnapshot()` returns bytes and shapes,
    /// never a `Widget`) is exactly what a stray `package:flutter` import would
    /// quietly repeal.
    const banned = <String>[
      'package:flutter/',
      'package:flutter_test/',
      'package:firebase_core/',
      'package:firebase_auth/',
      'package:cloud_firestore/',
      'package:cloud_functions/',
      'package:firebase_storage/',
      'package:google_sign_in/',
      'package:sign_in_with_apple/',
      'package:livekit_client/',
      'package:flame/',
      // Signing / crypto primitives: the engine must not carry them, because a
      // secret-bearing token strategy lives in a server-only package, not here
      // (see LiveKitTokenEndpoint). This is the import-side mirror of the
      // migration-step-4 transitive-deps whitelist named in DESIGN.md.
      'package:crypto/',
      'package:cryptography/',
      'package:pointycastle/',
      'dart:ui',
      'dart:html',
      'dart:js',
      'dart:js_interop',
      'dart:js_util',
      'package:web/',
    ];

    late final List<File> sources;

    setUpAll(() {
      final libDir = Directory('lib');
      expect(
        libDir.existsSync(),
        isTrue,
        reason: 'Run this test from packages/realm/, where lib/ lives.',
      );
      sources = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
    });

    test('finds engine sources to check', () {
      // Guards the guard: a glob that silently matches nothing would let this
      // whole group pass green while checking absolutely nothing. A negative
      // result only means something if the instrument had coverage.
      expect(sources, isNotEmpty);
      expect(sources.length, greaterThanOrEqualTo(9));
    });

    test('no engine source imports a backend, Flutter, or dart:ui', () {
      final violations = <String>[];

      // Scope note (Tesla's catch): this scans lines that START with `import `/
      // `export `, which assumes the URI sits on the same line as the keyword.
      // That holds for every `dart format`-normalised import — the formatter
      // never splits a directive across lines — and unformatted code fails CI's
      // analyze step before it reaches here. A hand-crafted split directive
      // (`import\n  'package:...'`) is the one form this would miss; it is
      // matched by the pubspec dependency-block check below (a backend can't be
      // imported without being a dependency) rather than parsed here, so the
      // guard stays a simple line scan instead of a comment-stripping parser
      // that would false-positive on this file's own ban-list literals.
      for (final file in sources) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (!line.startsWith('import ') && !line.startsWith('export ')) {
            continue;
          }
          for (final ban in banned) {
            if (line.contains(ban)) {
              violations.add('${file.path}:${i + 1} → $ban');
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'The engine package must not depend on any backend, on '
            'Flutter, or on dart:ui. Implementations belong in '
            'packages/realm_<backend>/; rendering belongs to the world.\n'
            'Violations:\n${violations.join('\n')}',
      );
    });

    test('engine pubspec declares no runtime dependencies', () {
      // The import scan above catches direct use. This catches the earlier
      // move: adding the dependency at all. A dependency present in the
      // pubspec but not yet imported is a loaded gun, and it is also how a
      // crypto primitive would first arrive (see the migration-step-4 deps
      // whitelist that will enforce this in CI across the transitive tree).
      final pubspec = File('pubspec.yaml').readAsStringSync();
      // Match a top-level `dependencies:` key in ANY form — block
      // (`dependencies:\n  http: any`) OR inline (`dependencies: {http: any}`)
      // — while NOT matching `dev_dependencies:` (that line starts with `dev_`,
      // so a line-anchored `^dependencies:` skips it). The earlier
      // `^dependencies:\s*$` only caught the bare-header block form and sailed
      // straight past the inline map — a load-bearing test with a shape hole
      // (Kelvin + Tesla's catch).
      final hasRuntimeDeps =
          RegExp(r'^dependencies:', multiLine: true).hasMatch(pubspec);

      expect(
        hasRuntimeDeps,
        isFalse,
        reason: 'packages/realm/pubspec.yaml declares a `dependencies:` '
            'block. The engine ships interfaces only — it should need '
            'nothing at runtime. If a dependency is genuinely required, that '
            'is an architecture decision, not a routine addition: update '
            'DESIGN.md and this test together.',
      );
    });

    test('the runtime-dependency detector catches BOTH block and inline forms',
        () {
      // Pin the fix (Kelvin + Tesla's catch): the previous `^dependencies:\s*$`
      // matched only the bare-header block form, so an inline `dependencies:
      // {http: any}` sailed through green. This asserts the detector against
      // synthetic pubspecs so a regression can't quietly reopen the hole — the
      // real-file assertion above can only ever see the (empty) real pubspec.
      bool detects(String yaml) =>
          RegExp(r'^dependencies:', multiLine: true).hasMatch(yaml);

      // Must DETECT a declared runtime dependency, however it's written:
      expect(detects('name: x\ndependencies:\n  http: any\n'), isTrue,
          reason: 'block form');
      expect(detects('name: x\ndependencies: {http: any}\n'), isTrue,
          reason: 'inline map form');

      // Must NOT fire on the legitimately-present dev_dependencies block, nor
      // on a deps-free pubspec:
      expect(detects('name: x\ndev_dependencies:\n  test: ^1.25.0\n'), isFalse,
          reason: 'dev_dependencies must not trip the runtime-deps check');
      expect(detects('name: x\nenvironment:\n  sdk: ^3.6.0\n'), isFalse,
          reason: 'no dependencies at all');
    });
  });
}
