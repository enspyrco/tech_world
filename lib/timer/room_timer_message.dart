/// Wire-format types for the shared room countdown timer.
///
/// A single data-channel topic ([LiveKitTopic.roomTimer]) carries two kinds of
/// message, modelled as a [sealed] hierarchy so a `switch` over them is
/// exhaustive and each variant carries only the fields that make sense for it
/// (no half-valid nullables). [TimerAction] is the closed set of wire
/// discriminators. Strings only ever appear at the wire boundary; everything
/// in-language is typed (house rule: stringly-typing is a smell). Parse from
/// the wire via [RoomTimerMessage.tryParse].
///
/// ## Two design decisions baked into the wire
///
/// **Relative remaining, not an absolute timestamp.** A `start` carries
/// [StartRoomTimerMessage.remainingSeconds] — the time left *as of send* — not
/// an absolute end instant. Each receiver computes its own
/// `endsAt = itsOwnNow + remainingSeconds`, so the timer is immune to
/// wall-clock skew between participants (a sender whose clock is minutes off no
/// longer corrupts everyone else's countdown — only network latency, ~ms,
/// matters). This is also what makes republish-on-join correct: a peer
/// republishing a running timer simply sends the *current* remaining, and the
/// joiner lands on the right value through the same code path as a fresh start.
///
/// **A monotonic [generation].** Every message carries the generation of the
/// timer it refers to. A fresh `start` mints a new (higher) generation; a
/// `cancel` carries the generation it is cancelling. Receivers track the
/// highest generation they have applied and ignore anything older, so an
/// out-of-order delivery (a stale `cancel` arriving after a newer `start`, or a
/// resync `start` arriving after a `cancel`) can never wipe or resurrect the
/// wrong timer. Republished messages reuse the *same* generation, so they are
/// idempotent — multiple peers republishing the one running timer all agree.
library;

/// The closed set of actions a shared-timer message can express.
///
/// Wire forms are single tokens, so `name` matches the wire — but we store the
/// wire string explicitly to stay robust if a multi-word action is ever added.
enum TimerAction {
  /// Start (or replace) the shared countdown for everyone.
  start('start'),

  /// Cancel any running shared countdown for everyone.
  cancel('cancel');

  const TimerAction(this.wire);

  /// The wire-format string transmitted over the LiveKit data channel.
  final String wire;

  /// Parse a wire string to its [TimerAction], returning null for unknown input.
  static TimerAction? tryParse(String? wire) {
    if (wire == null) return null;
    for (final action in values) {
      if (action.wire == wire) return action;
    }
    return null;
  }
}

/// A parsed shared-timer message off the [LiveKitTopic.roomTimer] channel.
///
/// Sealed so [TimerService] can `switch` over the two concrete variants
/// ([StartRoomTimerMessage], [CancelRoomTimerMessage]) with compile-time
/// exhaustiveness, and so neither variant carries fields that are only
/// meaningful for the other.
sealed class RoomTimerMessage {
  const RoomTimerMessage({required this.generation, this.startedBy});

  /// Identity of the participant who started or cancelled the timer.
  final String? startedBy;

  /// Monotonic generation of the timer this message refers to. Receivers drop
  /// any message whose generation is older than the highest they have applied,
  /// which resolves arrival-order races (a stale cancel vs a newer start).
  final int generation;

  /// Which [TimerAction] this message represents.
  TimerAction get action;

  /// Encode to the JSON map published on the data channel.
  Map<String, dynamic> toJson();

  /// Convenience constructor for a `start` message.
  factory RoomTimerMessage.start({
    required int remainingSeconds,
    required int generation,
    required String startedBy,
  }) =>
      StartRoomTimerMessage(
        remainingSeconds: remainingSeconds,
        generation: generation,
        startedBy: startedBy,
      );

  /// Convenience constructor for a `cancel` message.
  factory RoomTimerMessage.cancel({
    required int generation,
    required String startedBy,
  }) =>
      CancelRoomTimerMessage(generation: generation, startedBy: startedBy);

  /// Parse a wire JSON map into a [RoomTimerMessage], or null if malformed.
  ///
  /// Every field is type-checked, not cast — a hostile or newer client that
  /// sends a non-string `action`, a non-int `remainingSeconds`, etc. yields a
  /// clean `null` rather than throwing a `TypeError` that would tear down the
  /// subscription stream. A `start` message is additionally rejected unless it
  /// carries a positive integer `remainingSeconds` (a non-positive remaining
  /// would fire the alarm immediately). A missing/invalid `generation` is
  /// rejected too — it is load-bearing for race resolution, not optional.
  static RoomTimerMessage? tryParse(Map<String, dynamic>? json) {
    if (json == null) return null;

    final actionWire = json['action'];
    if (actionWire is! String) return null;
    final action = TimerAction.tryParse(actionWire);
    if (action == null) return null;

    final generation = json['generation'];
    if (generation is! int) return null;

    final startedByRaw = json['startedBy'];
    final startedBy = startedByRaw is String ? startedByRaw : null;

    switch (action) {
      case TimerAction.start:
        final remaining = json['remainingSeconds'];
        if (remaining is! int || remaining <= 0) return null;
        return StartRoomTimerMessage(
          remainingSeconds: remaining,
          generation: generation,
          startedBy: startedBy,
        );
      case TimerAction.cancel:
        return CancelRoomTimerMessage(
          generation: generation,
          startedBy: startedBy,
        );
    }
  }
}

/// A `start` message: begin (or replace) the shared countdown for everyone.
///
/// Carries [remainingSeconds] — the time left *as of send*, relative to the
/// sender's clock — NOT an absolute end instant. The receiver reconstructs the
/// end as `itsOwnNow + remainingSeconds`, making the countdown skew-immune. A
/// fresh start sends the full duration as the remaining; a republish-on-join
/// sends the *current* remaining of the already-running timer.
class StartRoomTimerMessage extends RoomTimerMessage {
  const StartRoomTimerMessage({
    required this.remainingSeconds,
    required super.generation,
    super.startedBy,
  });

  /// Seconds left on the countdown as of send (always positive — enforced at
  /// parse). The receiver adds this to its OWN now to get the end instant.
  final int remainingSeconds;

  @override
  TimerAction get action => TimerAction.start;

  @override
  Map<String, dynamic> toJson() => {
        'action': TimerAction.start.wire,
        'remainingSeconds': remainingSeconds,
        'generation': generation,
        if (startedBy != null) 'startedBy': startedBy,
      };
}

/// A `cancel` message: stop any running shared countdown for everyone.
///
/// Carries the [generation] it is cancelling so a stale cancel (one referring
/// to a timer that has since been replaced by a newer start) is ignored.
class CancelRoomTimerMessage extends RoomTimerMessage {
  const CancelRoomTimerMessage({
    required super.generation,
    super.startedBy,
  });

  @override
  TimerAction get action => TimerAction.cancel;

  @override
  Map<String, dynamic> toJson() => {
        'action': TimerAction.cancel.wire,
        'generation': generation,
        if (startedBy != null) 'startedBy': startedBy,
      };
}
