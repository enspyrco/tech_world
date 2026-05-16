import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:tech_world/events/types.dart';

/// A JSONL file sink with size-based rotation.
///
/// Writes events as one JSON object per line. When the file exceeds
/// [maxBytes], rotates to `.1`, `.2`, … up to [maxRotations] (oldest
/// deleted). The size check runs every [checkInterval] writes, not on
/// every write — `stat()` is cheap but not free at event rates.
///
/// Used by [createFileSink], [createAvPipelineSink], and
/// [createErrorSink] — all three share the same rotation mechanics.
class RotatingFileSink {
  RotatingFileSink({
    required this.logFile,
    this.maxBytes = 5 * 1024 * 1024, // 5 MB
    this.maxRotations = 3,
    this.checkInterval = 100,
    this.filter,
    this.enabledCheck,
  });

  final File logFile;
  final int maxBytes;
  final int maxRotations;
  final int checkInterval;

  /// Optional filter — when provided, only events where `filter(event)`
  /// returns true are written. Null means all events pass.
  final bool Function(AppEvent event)? filter;

  /// Optional toggle — when provided, the sink no-ops if this returns
  /// false. Checked on every call so it can be flipped at runtime.
  final bool Function()? enabledCheck;

  int _writeCount = 0;

  /// The sink function to register with [registerSink].
  void call(AppEvent event) {
    if (enabledCheck != null && !enabledCheck!()) return;
    if (filter != null && !filter!(event)) return;

    _writeCount++;
    if (_writeCount >= checkInterval) {
      _writeCount = 0;
      _rotateIfNeeded();
    }

    final line = jsonEncode(event.toJson());
    logFile
        .writeAsString('$line\n', mode: FileMode.append)
        .then<void>((_) {}, onError: (Object e) {
      debugPrint('[sink:${logFile.uri.pathSegments.last}] Write failed: $e');
    });
  }

  void _rotateIfNeeded() {
    try {
      if (!logFile.existsSync()) return;
      final size = logFile.lengthSync();
      if (size < maxBytes) return;

      // Shift existing rotations: .3 deleted, .2→.3, .1→.2, current→.1
      for (var i = maxRotations; i >= 1; i--) {
        final older = File('${logFile.path}.$i');
        if (i == maxRotations) {
          if (older.existsSync()) older.deleteSync();
        } else {
          final dest = File('${logFile.path}.${i + 1}');
          if (older.existsSync()) older.renameSync(dest.path);
        }
      }
      logFile.renameSync('${logFile.path}.1');
    } catch (e) {
      debugPrint('[sink:rotate] Rotation failed: $e');
    }
  }
}
