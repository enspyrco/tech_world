/// Classification of an [AppEvent] for sink-routing purposes.
///
/// Today the policy is binary (none / pii). When a second axis emerges
/// (redact-but-keep, off-device-allowed, retention-tier), add cases
/// here — every consumer with an exhaustive switch will become a
/// compile error at the moment that's needed.
///
/// **Why an enum rather than a bool.** Per `feedback_typed_primitives_at_boundary`:
/// closed-set values should be named, not primitive. A bool is a 2-element
/// closed set masquerading as a primitive — `event.piiPolicy` reads as a
/// category (honest about what's stored), while `event.containsPii` reads
/// as a yes/no answer with no semantic frame. Future cases land as one
/// new enum value plus compile errors at every exhaustive switch;
/// the bool path would touch every callsite.
///
/// See `lib/events/types.dart` (`AppEvent.piiPolicy`) for the producer
/// side and `lib/events/dispatch.dart` (`registerRemoteSink`) for the
/// gate that drops `PiiPolicy.pii` events before they reach off-device
/// sinks.
library;

enum PiiPolicy {
  /// Safe for all sinks, including off-device telemetry.
  none,

  /// Contains personally-identifiable information (user identifiers,
  /// display names, raw transcripts, free-form user content, bot reply
  /// text, room names, etc.). Dropped by [registerRemoteSink] (see
  /// `lib/events/dispatch.dart`) before reaching any off-device sink.
  pii,
  ;
}
