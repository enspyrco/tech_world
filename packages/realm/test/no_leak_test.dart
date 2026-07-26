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
      'package:firebase_storage/',
      'package:livekit_client/',
      'package:flame/',
      'dart:ui',
      'dart:html',
      'dart:js_interop',
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
      final dependenciesBlock =
          RegExp(r'^dependencies:\s*$', multiLine: true).hasMatch(pubspec);

      expect(
        dependenciesBlock,
        isFalse,
        reason: 'packages/realm/pubspec.yaml declares a `dependencies:` '
            'block. The engine ships interfaces only — it should need '
            'nothing at runtime. If a dependency is genuinely required, that '
            'is an architecture decision, not a routine addition: update '
            'DESIGN.md and this test together.',
      );
    });
  });
}
