/// Wire-format types for the shared room countdown timer.
///
/// A single data-channel topic ([LiveKitTopic.roomTimer]) carries two kinds of
/// message, modelled as a [sealed] hierarchy so a `switch` over them is
/// exhaustive and each variant carries only the fields that make sense for it
/// (no half-valid nullables). [TimerAction] is the closed set of wire
/// discriminators. Strings only ever appear at the wire boundary; everything
/// in-language is typed (house rule: stringly-typing is a smell). Parse from
/// the wire via [RoomTimerMessage.tryParse].
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
  const RoomTimerMessage({this.startedBy});

  /// Identity of the participant who started or cancelled the timer.
  final String? startedBy;

  /// Which [TimerAction] this message represents.
  TimerAction get action;

  /// Encode to the JSON map published on the data channel.
  Map<String, dynamic> toJson();

  /// Convenience constructor for a `start` message.
  factory RoomTimerMessage.start({
    required int durationSeconds,
    required int startedAtMillis,
    required String startedBy,
  }) =>
      StartRoomTimerMessage(
        durationSeconds: durationSeconds,
        startedAtMillis: startedAtMillis,
        startedBy: startedBy,
      );

  /// Convenience constructor for a `cancel` message.
  factory RoomTimerMessage.cancel({required String startedBy}) =>
      CancelRoomTimerMessage(startedBy: startedBy);

  /// Parse a wire JSON map into a [RoomTimerMessage], or null if malformed.
  ///
  /// Every field is type-checked, not cast — a hostile or newer client that
  /// sends a non-string `action`, a non-int `durationSeconds`, etc. yields a
  /// clean `null` rather than throwing a `TypeError` that would tear down the
  /// subscription stream. A `start` message is additionally rejected unless it
  /// carries a positive integer `durationSeconds` (a non-positive duration
  /// would fire the alarm immediately).
  static RoomTimerMessage? tryParse(Map<String, dynamic>? json) {
    if (json == null) return null;

    final actionWire = json['action'];
    if (actionWire is! String) return null;
    final action = TimerAction.tryParse(actionWire);
    if (action == null) return null;

    final startedByRaw = json['startedBy'];
    final startedBy = startedByRaw is String ? startedByRaw : null;

    switch (action) {
      case TimerAction.start:
        final duration = json['durationSeconds'];
        if (duration is! int || duration <= 0) return null;
        final startedAt = json['startedAtMillis'];
        return StartRoomTimerMessage(
          durationSeconds: duration,
          startedAtMillis: startedAt is int ? startedAt : null,
          startedBy: startedBy,
        );
      case TimerAction.cancel:
        return CancelRoomTimerMessage(startedBy: startedBy);
    }
  }
}

/// A `start` message: begin (or replace) the shared countdown for everyone.
///
/// v1 ignores clock skew: receivers start a *fresh* local countdown of
/// [durationSeconds] on receipt rather than reconciling against
/// [startedAtMillis]. [startedAtMillis] is carried anyway so a future version
/// can compensate for skew / support late-joiner catch-up without a wire change.
class StartRoomTimerMessage extends RoomTimerMessage {
  const StartRoomTimerMessage({
    required this.durationSeconds,
    this.startedAtMillis,
    super.startedBy,
  });

  /// Countdown length in seconds (always positive — enforced at parse).
  final int durationSeconds;

  /// Unix epoch milliseconds when the sender started the timer (sender clock).
  final int? startedAtMillis;

  @override
  TimerAction get action => TimerAction.start;

  @override
  Map<String, dynamic> toJson() => {
        'action': TimerAction.start.wire,
        'durationSeconds': durationSeconds,
        if (startedAtMillis != null) 'startedAtMillis': startedAtMillis,
        if (startedBy != null) 'startedBy': startedBy,
      };
}

/// A `cancel` message: stop any running shared countdown for everyone.
class CancelRoomTimerMessage extends RoomTimerMessage {
  const CancelRoomTimerMessage({super.startedBy});

  @override
  TimerAction get action => TimerAction.cancel;

  @override
  Map<String, dynamic> toJson() => {
        'action': TimerAction.cancel.wire,
        if (startedBy != null) 'startedBy': startedBy,
      };
}
