import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The transport files move to `realm_livekit`, where `package:tech_world`
/// does not exist, so their whole import closure must stay on [transportFiles].
///
/// Directives are parsed up to the `;`: the formatter splits a conditional
/// export across lines, and a line scan would miss its second URI.
void main() {
  /// Where the walk starts: the files that will move.
  const roots = [
    'lib/livekit/livekit_transport.dart',
    'lib/livekit/widgets/screen_share_overlay.dart',
    'lib/livekit/widgets/screen_share_panel.dart',
  ];

  /// Every `lib/` file the transport may reach.
  const transportFiles = {
    ...roots,
    'lib/livekit/data_channel.dart',
    'lib/livekit/set_track_volume.dart',
    'lib/livekit/set_track_volume_stub.dart',
    'lib/livekit/set_track_volume_web.dart',
  };

  test('the transport import closure stays inside the transport files', () {
    final reached = importClosure(roots);

    // Guards the guard: a walk that silently stopped at the roots would pass
    // while checking nothing. The conditional export's web arm is the hop a
    // line scan misses, so it must be reached.
    expect(reached, containsAll(transportFiles));

    final leaks = reached.difference(transportFiles);
    expect(
      leaks,
      isEmpty,
      reason: 'These files are reached from the transport but are not '
          'transport files, so the transport could not move to realm_livekit '
          'without them. Route the dependency the other way (a hook or a '
          'constructor parameter on LiveKitTransport), or, if the file really '
          'is transport, add it to transportFiles.',
    );
  });

  test('the walk follows conditional exports and ignores other packages', () {
    const source = '''
import 'dart:async';
import 'package:livekit_client/livekit_client.dart';
import 'package:tech_world/a.dart';
export 'b.dart'
    if (dart.library.js_interop) 'c.dart';
''';
    expect(
      localUris(source).toSet(),
      {'package:tech_world/a.dart', 'b.dart', 'c.dart'},
    );
  });
}

/// The `lib/` files reachable from [roots] through `package:tech_world` and
/// relative imports and exports, roots included.
Set<String> importClosure(List<String> roots) {
  final seen = <String>{};
  final pending = [...roots];
  while (pending.isNotEmpty) {
    final path = pending.removeLast();
    if (!seen.add(path)) continue;
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path does not exist');
    for (final uri in localUris(file.readAsStringSync())) {
      pending.add(resolve(path, uri));
    }
  }
  return seen;
}

/// The URIs in [source]'s import and export directives that point inside this
/// package.
Iterable<String> localUris(String source) sync* {
  final directive = RegExp(r'^\s*(?:import|export)\s[^;]*;', multiLine: true);
  final quoted = RegExp(r'''['"]([^'"]+)['"]''');
  for (final d in directive.allMatches(source)) {
    for (final q in quoted.allMatches(d[0]!)) {
      final uri = q[1]!;
      if (uri.startsWith('dart:')) continue;
      if (uri.startsWith('package:') && !uri.startsWith('package:tech_world/')) {
        continue;
      }
      yield uri;
    }
  }
}

/// [uri] as a repo-relative path, resolved against the file at [from].
String resolve(String from, String uri) {
  const self = 'package:tech_world/';
  if (uri.startsWith(self)) return 'lib/${uri.substring(self.length)}';
  return Uri.file(from).resolve(uri).toFilePath();
}
