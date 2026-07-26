// DESIGN.md ↔ live-engine doc-sync gate (step 4).
//
// WHY: DESIGN.md's `dart` code samples mirror the engine's public interfaces.
// Nothing kept them honest — during PR #521 review a stale `RealmUser? owner`
// sample on RoomDescriptor survived from round 2 to round 4 while the live type
// carried `ownerId`. Fourier's retro generalization: doc-code drift is a broken
// feedback loop, not a one-off typo. This gate closes the loop structurally, the
// same move no_leak_test made for imports and engine_deps_whitelist made for
// deps: a check that fails when DESIGN describes a member the engine doesn't
// have.
//
// HOW: for every type DESIGN declares in a ```dart block that also exists in the
// live engine, extract the public instance members DESIGN shows for it, emit a
// `void _check(T o) { o.member; ... }` reference for each, and let `dart analyze`
// be the oracle. A member DESIGN claims that the live type lacks becomes an
// `undefined_getter` error. No fragile member-set diffing — the compiler decides,
// so there are no formatting false-positives.
//
// SCOPE (deliberate, to stay high-precision / low-noise):
//   * Instance members only (fields, getters, methods). Constructors are
//     excluded structurally (UpperCamel names never match the lowerCamel member
//     pattern); statics and enum values are excluded (accessed on the type, not
//     an instance) — checking them would false-red.
//   * Types DESIGN documents that live OUTSIDE the engine package (reference
//     worlds like TechWorld, v2-reserved interfaces, the SignedRequest example)
//     are skipped — they are intentionally not in `lib/src`.
//
// Rides the workspace member-test loop into CI (no separate YAML). RED-proven:
// injecting `final RealmUser? owner;` into DESIGN's RoomDescriptor block turns
// this test red on the `owner` reference; removing it returns green.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Reserved words that can never be a member name. A record-typed field like
/// `final ({double x, double y}) center;` otherwise reads as a method `final(`.
const _keywords = {
  'final', 'const', 'var', 'void', 'get', 'set', 'static', 'late', 'required',
  'this', 'super', 'return', 'new', 'factory', 'abstract', 'class', 'enum',
  'extension', 'sealed', 'interface', 'for', 'if', 'else', 'switch', 'while',
  'in', 'is', 'as', 'import', 'export', 'library', 'typedef', 'mixin', 'on',
  'with', 'implements', 'extends', 'covariant', 'external', 'operator', 'yield',
  'async', 'await', 'rethrow', 'throw', 'try', 'catch', 'finally', 'assert',
  'break', 'continue', 'default', 'do', 'case', 'dynamic',
};

final _typeDecl = RegExp(
  r'(abstract interface class|sealed class|extension type(?: const)?|class|enum)'
  r'\s+([A-Z]\w*)',
);

/// Extract ```dart ... ``` fenced blocks from markdown.
List<String> _dartBlocks(String md) {
  final blocks = <String>[];
  var inBlock = false;
  final buf = StringBuffer();
  for (final l in md.split('\n')) {
    if (l.trimRight() == '```dart') {
      inBlock = true;
      buf.clear();
      continue;
    }
    if (inBlock && l.trimLeft().startsWith('```')) {
      inBlock = false;
      blocks.add(buf.toString());
      continue;
    }
    if (inBlock) buf.writeln(l);
  }
  return blocks;
}

String _stripComment(String line) {
  final i = line.indexOf('//');
  return i >= 0 ? line.substring(0, i) : line;
}

/// Type declarations in a block → (kind keyword, brace-matched body text).
Map<String, ({String kind, String body})> _typesIn(String block) {
  final out = <String, ({String kind, String body})>{};
  var idx = 0;
  while (idx < block.length) {
    final m = _typeDecl.firstMatch(block.substring(idx));
    if (m == null) break;
    final start = idx + m.start;
    final kind = m.group(1)!.split(' ').first;
    final name = m.group(2)!;
    final braceOpen = block.indexOf('{', start);
    if (braceOpen < 0) {
      idx = start + m.group(0)!.length;
      continue;
    }
    var depth = 0;
    var i = braceOpen;
    for (; i < block.length; i++) {
      if (block[i] == '{') depth++;
      if (block[i] == '}') {
        depth--;
        if (depth == 0) break;
      }
    }
    out[name] = (kind: kind, body: block.substring(braceOpen + 1, i));
    idx = i + 1;
  }
  return out;
}

/// The single public instance member declared on a body line, or null.
///
/// The negative lookbehind (?<![\w$.]) forces the identifier to start at a real
/// word boundary — without it `[a-z]\w*` latches mid-word onto `GoogleAuth`→
/// `oogleAuth`, `Function`→`unction`, `_registered`→`registered`; the `.`
/// excludes `this.token`. UpperCamel constructors start [A-Z] so never match.
/// Candidates are tried getter→method→field; a keyword hit (e.g. `final` from a
/// record-typed field) is skipped so the real member on the line is recovered.
String? _memberOf(String line) {
  if (line.startsWith('//') || line == '{' || line == '}') return null;
  final candidates = <String?>[
    RegExp(r'(?<![\w$])get\s+([a-z]\w*)').firstMatch(line)?.group(1),
    RegExp(r'(?<![\w$.])([a-z]\w*)\s*\(').firstMatch(line)?.group(1),
    RegExp(r'(?<![\w$.])([a-z]\w*)\s*[;=]').firstMatch(line)?.group(1),
  ];
  for (final c in candidates) {
    if (c != null && !_keywords.contains(c)) return c;
  }
  return null;
}

/// Public instance member names declared at the top level of a type body.
/// Brace depth is tracked so method-body locals (`final factory = ...`) at
/// depth > 0 are never mistaken for members.
List<String> _members(String body) {
  final members = <String>[];
  var depth = 0;
  for (final raw in body.split('\n')) {
    final line = _stripComment(raw).trim();
    if (line.isEmpty) continue;
    if (depth == 0 && !line.contains('static')) {
      final m = _memberOf(line);
      if (m != null) members.add(m);
    }
    for (final ch in line.split('')) {
      if (ch == '{') depth++;
      if (ch == '}') depth--;
    }
    if (depth < 0) depth = 0;
  }
  return members;
}

/// Live engine type names → kind, read from lib/src (doc-comment lines skipped).
Map<String, String> _liveTypes() {
  final types = <String, String>{};
  for (final f in Directory('lib/src')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))) {
    final src = f.readAsStringSync();
    for (final m in _typeDecl.allMatches(src)) {
      final lineStart = src.lastIndexOf('\n', m.start) + 1;
      final prefix = src.substring(lineStart, m.start).trimLeft();
      if (prefix.startsWith('//')) continue; // decl inside a comment
      types[m.group(2)!] = m.group(1)!.split(' ').first;
    }
  }
  return types;
}

void main() {
  test(
    'DESIGN.md code samples reference only members the live engine defines',
    () {
      final design = File('DESIGN.md');
      expect(
        design.existsSync(),
        isTrue,
        reason: 'DESIGN.md not found at ${design.absolute.path} — this test '
            'must run with the realm package root as CWD (the member-test loop '
            'does `cd packages/realm && flutter test`).',
      );

      final live = _liveTypes();
      final gen = StringBuffer()
        ..writeln('// GENERATED by design_doc_sync_test — do not edit / commit.')
        ..writeln('// ignore_for_file: unused_element, unused_local_variable, '
            'non_constant_identifier_names, prefer_typing_uninitialized_variables')
        ..writeln("import 'package:realm/realm.dart';")
        ..writeln();

      final skipped = <String>[];
      for (final block in _dartBlocks(design.readAsStringSync())) {
        for (final entry in _typesIn(block).entries) {
          final name = entry.key;
          if (entry.value.kind == 'enum') continue; // values are static-shaped
          if (!live.containsKey(name)) {
            skipped.add(name); // documented type that lives outside the engine
            continue;
          }
          final members = _members(entry.value.body);
          if (members.isEmpty) continue;
          gen.writeln('void _check_$name($name o) {');
          for (final m in members) {
            gen.writeln('  o.$m;');
          }
          gen.writeln('}');
          gen.writeln();
        }
      }

      // .dart_tool is analyzer-excluded and gitignored; the file resolves
      // package:realm via the package's own package_config.json.
      final genFile = File('.dart_tool/doc_sync/refs.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(gen.toString());

      try {
        final result = Process.runSync('dart', ['analyze', genFile.path]);
        final out = '${result.stdout}\n${result.stderr}';
        // Fail on ERROR severity only (info/warning are suppressed in-file);
        // an undefined_getter on `o.<member>` is exactly the doc-drift signal.
        final errors = const LineSplitter()
            .convert(out)
            .where((l) => l.contains(' error '))
            .toList();
        expect(
          errors,
          isEmpty,
          reason: 'DESIGN.md references engine members that do not exist '
              '(doc-code drift). Fix the sample in DESIGN.md or the interface:\n'
              '${errors.join('\n')}',
        );
      } finally {
        if (genFile.existsSync()) genFile.deleteSync();
      }
    },
  );
}
