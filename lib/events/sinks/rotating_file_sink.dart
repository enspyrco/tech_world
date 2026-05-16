import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:tech_world/events/types.dart';

/// Async writer signature — abstracts over `File.writeAsString` so tests can
/// inject a slow / blocked writer to exercise backpressure paths without
/// touching real disk I/O. Default implementation delegates to the file.
typedef AsyncLineWriter = Future<void> Function(String line);

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
/// **Backpressure bound.** Every `call()` appends a closure to `_chain`
/// capturing the encoded line. If events arrive faster than disk I/O drains
/// them, both chain length and retained-closure memory grow linearly with
/// the lag. At diagnostic rates (<1000 events/sec) the chain drains as fast
/// as it fills; but a slow disk, a stalled volume, or a synthetic event
/// storm could let the chain grow unbounded. [maxPending] caps the number
/// of in-flight writes; once exceeded, additional events are dropped and
/// counted, with a single `debugPrint` summary emitted per breach (so a
/// storm doesn't itself become a log storm). Maxwell MED from PR #467
/// cage-match.
///
/// Used by [createFileSink], [createAvPipelineSink], and
/// [createErrorSink] — all three share the same rotation mechanics.
class RotatingFileSink {
  RotatingFileSink({
    required this.logFile,
    this.maxBytes = 5 * 1024 * 1024, // 5 MB
    this.maxRotations = 3,
    this.checkInterval = 100,
    this.maxPending = 1000,
    this.filter,
    this.enabledCheck,
    AsyncLineWriter? writer,
  }) : _writer = writer ??
            ((line) =>
                logFile.writeAsString('$line\n', mode: FileMode.append));

  final File logFile;
  final int maxBytes;
  final int maxRotations;
  final int checkInterval;

  /// Maximum number of writes that may be in-flight (queued on `_chain`
  /// awaiting I/O completion) before new events are dropped. Default 1000
  /// chosen as: at the project's diagnostic ceiling (~100 events/sec
  /// sustained, bursts to ~500) this is ~2-10 seconds of buffered headroom,
  /// enough to absorb a brief disk stall without dropping; beyond that,
  /// dropping is preferable to OOM on long-lived sessions.
  final int maxPending;

  /// Optional filter — when provided, only events where `filter(event)`
  /// returns true are written. Null means all events pass.
  final bool Function(AppEvent event)? filter;

  /// Optional toggle — when provided, the sink no-ops if this returns
  /// false. Checked on every call so it can be flipped at runtime.
  final bool Function()? enabledCheck;

  final AsyncLineWriter _writer;

  int _writeCount = 0;

  /// Count of write closures currently queued on `_chain` that have not yet
  /// resolved. Incremented in `call()`, decremented in the chained
  /// continuation after the write attempt (success or failure).
  int _pending = 0;

  /// Dropped-event counter since the last breach summary. Reset to zero
  /// after the summary `debugPrint`, so each new breach surfaces once.
  int _droppedSinceLastReport = 0;

  /// True while we are over [maxPending]; flipped back to false when the
  /// queue drains. Used to coalesce the debugPrint summary to one line per
  /// breach episode rather than one line per dropped event.
  bool _inBreach = false;

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

  /// Current in-flight write count. Test-only — exposed so backpressure
  /// tests can assert the queue stays bounded under load.
  @visibleForTesting
  int get pending => _pending;

  /// Total events dropped due to backpressure since the last summary.
  /// Test-only; production callers see the `debugPrint` summary instead.
  @visibleForTesting
  int get droppedSinceLastReport => _droppedSinceLastReport;

  /// The sink function to register with [registerSink].
  void call(AppEvent event) {
    if (enabledCheck != null && !enabledCheck!()) return;
    if (filter != null && !filter!(event)) return;

    // Backpressure gate: if too many writes are already in-flight, drop
    // this event rather than grow the chain unbounded. We surface a single
    // debugPrint per breach episode (not per drop) when the queue drains.
    if (_pending >= maxPending) {
      _droppedSinceLastReport++;
      _inBreach = true;
      return;
    }

    _writeCount++;
    final shouldRotate = _writeCount >= checkInterval;
    if (shouldRotate) _writeCount = 0;

    final line = jsonEncode(event.toJson());

    _pending++;
    // Queue: rotation (if due) then write. Both are awaited so the next
    // call's work begins only after this one's I/O has flushed.
    _chain = _chain.then((_) async {
      try {
        if (shouldRotate) {
          await _rotateIfNeeded();
        }
        try {
          await _writer(line);
        } catch (e) {
          debugPrint(
              '[sink:${logFile.uri.pathSegments.last}] Write failed: $e');
        }
      } finally {
        _pending--;
        // When the queue fully drains after a breach, emit one summary.
        if (_inBreach && _pending == 0) {
          final dropped = _droppedSinceLastReport;
          _droppedSinceLastReport = 0;
          _inBreach = false;
          if (dropped > 0) {
            debugPrint(
                '[sink:${logFile.uri.pathSegments.last}] dropped $dropped '
                'events under backpressure (maxPending=$maxPending)');
          }
        }
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
