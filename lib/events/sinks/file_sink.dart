import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:tech_world/events/types.dart';

/// Creates an append-only JSONL file sink for native platforms
/// (macOS, iOS, Android).
///
/// All events are written to a single `events.log` file in JSONL format
/// (one JSON object per line). The file lives in the app's documents
/// directory so it survives restarts and is accessible via Finder/Files.
///
/// **Not available on web** — use conditional import with
/// `file_sink_stub.dart`:
/// ```dart
/// import 'sinks/file_sink.dart'
///     if (dart.library.js_interop) 'sinks/file_sink_stub.dart';
/// ```
///
/// Design notes:
/// - Async writes (never blocks the UI thread)
/// - JSONL format (greppable, parseable by jq / Loki / Datadog)
/// - No rotation — app storage is OS-managed
Future<void Function(AppEvent)> createFileSink() async {
  final appDir = await getApplicationDocumentsDirectory();
  final logDir = Directory('${appDir.path}/tech_world_logs');
  await logDir.create(recursive: true);
  final logFile = File('${logDir.path}/events.log');

  return (AppEvent event) {
    final line = jsonEncode(event.toJson());
    // Fire-and-forget — don't block dispatch on file I/O. Errors are
    // swallowed because a failing sink must never crash the app.
    logFile
        .writeAsString('$line\n', mode: FileMode.append)
        .then<void>((_) {}, onError: (Object e) {
      debugPrint('[sink:file] Write failed: $e');
    });
  };
}
