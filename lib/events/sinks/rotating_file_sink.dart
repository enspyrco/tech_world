import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:tech_world/events/types.dart';

/// A JSONL file sink with size-based rotation.
///
/// Writes events as one JSON object per line. When the file exceeds
/// [maxBytes], rotates to `.1`, `.2`, … up to [maxRotations] (oldest
/// deleted). The size check runs every [checkInterval] writes, not on
/// every write — `stat()` is cheap but not free at event rates.
///
/// **Ordering invariant.** All writes and the rotation step are serialized
/// through a single `Future` chain (`_chain`). Without this, fire-and-forget
/// writes could complete *after* a synchronous rename, causing records to
/// land in the wrong rotation generation (or fail mid-rename on platforms
/// that hold an exclusive handle, e.g. Windows). Cost: one extra microtask
/// per write — free at diagnostic event rates.
///
/// Per `feedback_fire_and_forget_vs_rotation`: fire-and-forget is fine until
/// a state-mutation step (rotation, compaction, rename) assumes prior writes
/// finished. The moment such a step exists, the queue becomes mandatory.
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

  /// Serializes writes and rotation. Every `call()` appends to this chain
  /// so the i+1th operation only begins after the ith resolves.
  Future<void> _chain = Future.value();

  /// Test seam: returns a Future that resolves when every write enqueued
  /// **before this call** has flushed. Snapshot semantics — invoke after
  /// the final `call()` you care about, then await once. A previously-
  /// returned future does NOT wait for writes enqueued in the meantime,
  /// by design.
  ///
  /// Originally a getter; Carnot caught the footgun where reading early
  /// and awaiting late looks like a flush but isn't. Method form encodes
  /// the snapshot-at-call-time semantics in the type signature. See
  /// #467 cage-match.
  @visibleForTesting
  Future<void> flushed() => _chain;

  /// The sink function to register with [registerSink].
  void call(AppEvent event) {
    if (enabledCheck != null && !enabledCheck!()) return;
    if (filter != null && !filter!(event)) return;

    _writeCount++;
    final shouldRotate = _writeCount >= checkInterval;
    if (shouldRotate) _writeCount = 0;

    final line = jsonEncode(event.toJson());

    // Queue: rotation (if due) then write. Both are awaited so the next
    // call's work begins only after this one's I/O has flushed.
    _chain = _chain.then((_) async {
      if (shouldRotate) {
        await _rotateIfNeeded();
      }
      try {
        await logFile.writeAsString('$line\n', mode: FileMode.append);
      } catch (e) {
        debugPrint(
            '[sink:${logFile.uri.pathSegments.last}] Write failed: $e');
      }
    });
  }

  Future<void> _rotateIfNeeded() async {
    try {
      if (!await logFile.exists()) return;
      final size = await logFile.length();
      if (size < maxBytes) return;

      // Shift existing rotations: .N deleted, .{N-1}→.N, ..., .1→.2, current→.1
      for (var i = maxRotations; i >= 1; i--) {
        final older = File('${logFile.path}.$i');
        if (i == maxRotations) {
          if (await older.exists()) await older.delete();
        } else {
          final dest = File('${logFile.path}.${i + 1}');
          if (await older.exists()) await older.rename(dest.path);
        }
      }
      await logFile.rename('${logFile.path}.1');
    } catch (e) {
      debugPrint('[sink:rotate] Rotation failed: $e');
    }
  }
}
