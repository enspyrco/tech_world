/// Pure-Dart state machine owning the two leading-edge latches that gate
/// `AvCaptureInitFailed` and `AvFrameDecodeError` dispatch from
/// `VideoBubbleComponent`.
///
/// Extracted so the latch logic is testable without `flutter_webrtc`,
/// `livekit_client`, or a Flame canvas — all of which keep
/// `video_bubble_component.dart` outside the coverage gate.
///
/// ## Why latches at all
///
/// Per `feedback_error_rate_is_a_data_dimension`: a failure that recurs
/// at frame rate must dispatch on the **leading edge** only, not 1:1
/// with occurrences. A 30fps decode loop hitting an exception in every
/// frame would otherwise emit 30 events/sec/participant into
/// `errors.jsonl` — a self-inflicted denial of service against our own
/// observability pipeline. Each latch fires once on the
/// healthy→broken transition and clears on the next success, so the
/// next failure burst is a new leading edge.
///
/// ## Symmetry invariant (cage-match consensus, #467)
///
/// Every successful capture MUST clear both latches together. Without
/// symmetric reset, a transient init failure that exhausted retries
/// would suppress all future terminal-failure events for the rest of
/// the component's lifetime — even if a later capture cycle rebuilt
/// the pipeline and broke again. `markCaptureSucceeded` is the single
/// owner of that transition.
class CaptureLatchStateMachine {
  bool _captureFailedDispatched = false;
  bool _decodeErrorReported = false;

  /// Whether the next `AvCaptureInitFailed` should fire. True means the
  /// caller is on a leading edge (healthy or never-failed → exhausted).
  bool get shouldDispatchCaptureFailed => !_captureFailedDispatched;

  /// Whether the next `AvFrameDecodeError` should fire. True means the
  /// caller is on a leading edge (decoding fine or never-failed → broken).
  bool get shouldDispatchDecodeError => !_decodeErrorReported;

  // Test-visibility accessors (also document the underlying state shape).
  bool get captureFailedDispatched => _captureFailedDispatched;
  bool get decodeErrorReported => _decodeErrorReported;

  /// Record that `AvCaptureInitFailed` has been dispatched. Subsequent
  /// calls to [shouldDispatchCaptureFailed] return false until cleared
  /// by [markCaptureSucceeded] or [reset].
  void markCaptureFailedDispatched() {
    _captureFailedDispatched = true;
  }

  /// Record that `AvFrameDecodeError` has been dispatched. Subsequent
  /// calls to [shouldDispatchDecodeError] return false until cleared
  /// by [markCaptureSucceeded], [markFrameDecoded], or [reset].
  void markDecodeErrorDispatched() {
    _decodeErrorReported = true;
  }

  /// Capture pipeline initialized successfully — clear both latches so
  /// a fresh failure burst can re-emit terminal events on its leading
  /// edge. This is the *only* code path that should flip
  /// `_captureInitialized` from false to true on the component.
  void markCaptureSucceeded() {
    _captureFailedDispatched = false;
    _decodeErrorReported = false;
  }

  /// A frame decoded successfully. Clears the decode-error latch so the
  /// next decode failure is a new leading edge. Does NOT clear the
  /// capture-init latch — init success is a separate signal handled by
  /// [markCaptureSucceeded].
  void markFrameDecoded() {
    _decodeErrorReported = false;
  }

  /// Capture torn down (component disposal, track resubscription). Both
  /// latches reset so the next capture cycle starts from a clean slate.
  void reset() {
    _captureFailedDispatched = false;
    _decodeErrorReported = false;
  }
}
