import 'package:flutter/foundation.dart';

/// Owns the multiplayer state lifecycle of an `@mention` world-pulse,
/// independent of any rendering.
///
/// Every client runs one of these. When a mention arrives (parsed from a chat
/// payload by `ChatService` and delivered via the `PlayersMentioned` event),
/// `onMention` starts a pulse on the named avatar — visible to everyone. The
/// pulse is bounded by THREE independent stop conditions, so it can never get
/// stuck on:
///
///  1. **Ack** — the named player's OWN client broadcasts a `mention-ack` when
///     it opens the chat panel; all clients call [onAck] and stop that pulse.
///  2. **Auto-timeout** — [pulseTimeout] after the (most recent) mention, the
///     pulse stops everywhere even if no ack ever arrives. Driven by [tick],
///     which the owning Flame component calls each frame against an injected
///     clock (so tests use a fake clock, not wall time).
///  3. A re-mention of the same player **refreshes** both the timeout deadline
///     and the active `messageId`.
///
/// The active `messageId` is the match key: an ack only cancels when it carries
/// the messageId of the *currently-live* mention. This stops a stale ack (for
/// an already-superseded mention) from silencing a fresh pulse, and stops
/// concurrent mentions of the same player from cross-cancelling.
///
/// A [ChangeNotifier] so the rendering layer (and tests) can observe start /
/// ack / timeout transitions; it notifies only on an actual state change.
class MentionPulseController extends ChangeNotifier {
  MentionPulseController({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// How long a pulse persists with no acknowledgement before auto-stopping.
  /// Bounded so an un-answered mention is a slow public pulse, never permanent.
  static const Duration pulseTimeout = Duration(seconds: 45);

  /// Active pulses keyed by the mentioned player's UID. Only the most recent
  /// mention per player is tracked (a re-mention overwrites).
  final Map<String, _ActivePulse> _active = {};

  /// Whether [uid]'s avatar is currently pulsing.
  bool isPulsing(String uid) => _active.containsKey(uid);

  /// The UID of whoever raised the *current* live mention of [uid], for drawing
  /// the light arc from mentioner → named. Null if [uid] isn't pulsing.
  String? mentionerOf(String uid) => _active[uid]?.mentionerUid;

  /// The messageId of the *current* live mention of [uid] — the value to put in
  /// an ack so it matches. Null if [uid] isn't pulsing.
  String? activeMessageId(String uid) => _active[uid]?.messageId;

  /// UIDs of all players currently pulsing — a snapshot for the renderer.
  Iterable<String> get pulsingUids => _active.keys;

  /// Start (or refresh) a pulse on [mentionedUid]. Records [mentionerUid] for
  /// the arc and [messageId] as the ack-match key, and resets the timeout
  /// deadline to [pulseTimeout] from now.
  void onMention({
    required String mentionedUid,
    required String mentionerUid,
    required String messageId,
  }) {
    _active[mentionedUid] = _ActivePulse(
      mentionerUid: mentionerUid,
      messageId: messageId,
      deadline: _clock().add(pulseTimeout),
    );
    notifyListeners();
  }

  /// Stop [mentionedUid]'s pulse IFF [messageId] matches the currently-live
  /// mention. A mismatched or stale messageId, or an ack for a non-pulsing
  /// player, is a no-op (no notification).
  void onAck({required String mentionedUid, required String messageId}) {
    final pulse = _active[mentionedUid];
    if (pulse == null || pulse.messageId != messageId) return;
    _active.remove(mentionedUid);
    notifyListeners();
  }

  /// Drive auto-timeout. Called each frame by the owning component (or directly
  /// in tests after advancing the fake clock). Removes every pulse whose
  /// deadline has passed and notifies once if anything expired.
  void tick() {
    final now = _clock();
    final expired = _active.entries
        .where((e) => !now.isBefore(e.value.deadline))
        .map((e) => e.key)
        .toList();
    if (expired.isEmpty) return;
    for (final uid in expired) {
      _active.remove(uid);
    }
    notifyListeners();
  }

  /// Drop all pulses without notifying — for teardown on room leave.
  void clear() => _active.clear();
}

/// One live mention pulse: who raised it, which message it belongs to (the
/// ack-match key), and when it auto-expires.
class _ActivePulse {
  _ActivePulse({
    required this.mentionerUid,
    required this.messageId,
    required this.deadline,
  });

  final String mentionerUid;
  final String messageId;
  final DateTime deadline;
}
