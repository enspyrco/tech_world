/// Wire-format types for the shared room countdown timer.
///
/// A single data-channel topic ([LiveKitTopic.roomTimer]) carries two kinds of
/// message, discriminated by [TimerAction]. Strings only ever appear at the
/// wire boundary; everything in-language is typed (house rule: stringly-typing
/// is a smell). Parse from the wire via [RoomTimerMessage.tryParse].
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
/// For [TimerAction.start], [durationSeconds], [startedAtMillis] (Unix epoch
/// milliseconds, sender's clock) and [startedBy] are all present. For
/// [TimerAction.cancel] only [startedBy] (the canceller) is meaningful; the
/// other fields are null.
///
/// v1 ignores clock skew: receivers start a *fresh* local countdown of
/// [durationSeconds] on receipt rather than reconciling against
/// [startedAtMillis]. [startedAtMillis] is carried anyway so a future version
/// can compensate for skew / support late-joiner catch-up without a wire change.
class RoomTimerMessage {
  const RoomTimerMessage({
    required this.action,
    this.durationSeconds,
    this.startedAtMillis,
    this.startedBy,
  });

  /// Convenience constructor for a `start` message.
  factory RoomTimerMessage.start({
    required int durationSeconds,
    required int startedAtMillis,
    required String startedBy,
  }) =>
      RoomTimerMessage(
        action: TimerAction.start,
        durationSeconds: durationSeconds,
        startedAtMillis: startedAtMillis,
        startedBy: startedBy,
      );

  /// Convenience constructor for a `cancel` message.
  factory RoomTimerMessage.cancel({required String startedBy}) =>
      RoomTimerMessage(action: TimerAction.cancel, startedBy: startedBy);

  /// Whether this is a start or cancel message.
  final TimerAction action;

  /// Countdown length in seconds (start messages only).
  final int? durationSeconds;

  /// Unix epoch milliseconds when the sender started the timer (start only).
  final int? startedAtMillis;

  /// Identity of the participant who started or cancelled the timer.
  final String? startedBy;

  /// Encode to the JSON map published on the data channel.
  Map<String, dynamic> toJson() => {
        'action': action.wire,
        if (durationSeconds != null) 'durationSeconds': durationSeconds,
        if (startedAtMillis != null) 'startedAtMillis': startedAtMillis,
        if (startedBy != null) 'startedBy': startedBy,
      };

  /// Parse a wire JSON map into a [RoomTimerMessage], or null if malformed.
  ///
  /// A `start` message is rejected unless it carries a positive integer
  /// [durationSeconds] — a start with no duration is meaningless and a
  /// non-positive duration would fire the alarm immediately, so both are
  /// dropped at the boundary rather than propagated into timer state.
  static RoomTimerMessage? tryParse(Map<String, dynamic>? json) {
    if (json == null) return null;
    final action = TimerAction.tryParse(json['action'] as String?);
    if (action == null) return null;

    final startedBy = json['startedBy'] as String?;

    switch (action) {
      case TimerAction.start:
        final duration = json['durationSeconds'];
        if (duration is! int || duration <= 0) return null;
        final startedAt = json['startedAtMillis'];
        return RoomTimerMessage(
          action: TimerAction.start,
          durationSeconds: duration,
          startedAtMillis: startedAt is int ? startedAt : null,
          startedBy: startedBy,
        );
      case TimerAction.cancel:
        return RoomTimerMessage(
          action: TimerAction.cancel,
          startedBy: startedBy,
        );
    }
  }
}
