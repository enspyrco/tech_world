import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/capture_latch_state_machine.dart';

/// Regression coverage for the leading-edge latches that gate
/// `AvCaptureInitFailed` and `AvFrameDecodeError` dispatch in
/// `VideoBubbleComponent`. The component file is coverage-excluded
/// because it imports `flutter_webrtc`, so the state machine was
/// extracted as a pure-Dart seam to keep this invariant testable.
///
/// **Spiral termini F4/F5 of PR #465.** If either latch guard is
/// removed, these tests must fail — verify locally per
/// `feedback_verify_regression_test_by_breaking_code` before relying
/// on this suite.
void main() {
  group('CaptureLatchStateMachine — initial state', () {
    test('both latches start clear (next failure is a leading edge)', () {
      final m = CaptureLatchStateMachine();
      expect(m.shouldDispatchCaptureFailed, isTrue);
      expect(m.shouldDispatchDecodeError, isTrue);
      expect(m.captureFailedDispatched, isFalse);
      expect(m.decodeErrorReported, isFalse);
    });
  });

  group('CaptureLatchStateMachine — capture-init failure latch', () {
    test('first dispatch fires; subsequent attempts are suppressed', () {
      final m = CaptureLatchStateMachine();

      // Simulate the per-update-tick "should I dispatch?" check at
      // sustained failure. Without the latch, every tick would dispatch.
      var dispatchCount = 0;
      for (var i = 0; i < 100; i++) {
        if (m.shouldDispatchCaptureFailed) {
          m.markCaptureFailedDispatched();
          dispatchCount++;
        }
      }

      expect(dispatchCount, 1,
          reason: 'leading-edge latch must bound dispatch to 1 across '
              '100 sustained-failure ticks');
    });

    test('markCaptureSucceeded clears the latch — next failure re-fires', () {
      final m = CaptureLatchStateMachine();

      m.markCaptureFailedDispatched();
      expect(m.shouldDispatchCaptureFailed, isFalse);

      // Capture cycle recovers (e.g. track resubscribed and init worked).
      m.markCaptureSucceeded();
      expect(m.shouldDispatchCaptureFailed, isTrue,
          reason: 'symmetric reset on success: a fresh failure burst is '
              'a new leading edge');

      // Second failure burst dispatches once and then latches again.
      var dispatchCount = 0;
      for (var i = 0; i < 50; i++) {
        if (m.shouldDispatchCaptureFailed) {
          m.markCaptureFailedDispatched();
          dispatchCount++;
        }
      }
      expect(dispatchCount, 1);
    });

    test('reset() clears the latch (tear-down path)', () {
      final m = CaptureLatchStateMachine();
      m.markCaptureFailedDispatched();
      m.reset();
      expect(m.shouldDispatchCaptureFailed, isTrue);
    });
  });

  group('CaptureLatchStateMachine — frame-decode error latch', () {
    test('first dispatch fires; subsequent failures are suppressed', () {
      final m = CaptureLatchStateMachine();

      // 900 ticks ≈ 30 seconds at 30fps with every frame throwing.
      // The point of the latch is that this still emits exactly one
      // event instead of flooding errors.jsonl.
      var dispatchCount = 0;
      for (var i = 0; i < 900; i++) {
        if (m.shouldDispatchDecodeError) {
          m.markDecodeErrorDispatched();
          dispatchCount++;
        }
      }

      expect(dispatchCount, 1,
          reason: 'leading-edge latch must bound dispatch to 1 across '
              '900 sustained-failure ticks (30s at 30fps)');
    });

    test('markFrameDecoded clears the latch — next failure re-fires', () {
      final m = CaptureLatchStateMachine();

      m.markDecodeErrorDispatched();
      expect(m.shouldDispatchDecodeError, isFalse);

      // A frame decoded cleanly between failure bursts.
      m.markFrameDecoded();
      expect(m.shouldDispatchDecodeError, isTrue,
          reason: 'success-then-failure is a new leading edge');

      // Second burst latches independently.
      var dispatchCount = 0;
      for (var i = 0; i < 50; i++) {
        if (m.shouldDispatchDecodeError) {
          m.markDecodeErrorDispatched();
          dispatchCount++;
        }
      }
      expect(dispatchCount, 1);
    });

    test('markCaptureSucceeded also clears the decode latch (symmetry)', () {
      final m = CaptureLatchStateMachine();
      m.markDecodeErrorDispatched();
      m.markCaptureSucceeded();
      expect(m.shouldDispatchDecodeError, isTrue,
          reason: 'capture rebuild must reset BOTH latches together — '
              'cage-match #467 symmetry invariant');
    });
  });

  group('CaptureLatchStateMachine — independence + symmetry', () {
    test('markFrameDecoded does NOT clear the capture-init latch', () {
      final m = CaptureLatchStateMachine();
      m.markCaptureFailedDispatched();

      // A frame somehow decodes (defensive scenario) but capture is
      // still considered failed. The init latch must stay set.
      m.markFrameDecoded();
      expect(m.shouldDispatchCaptureFailed, isFalse,
          reason: 'frame-decode success is a finer-grained signal than '
              'capture-init success — they must not alias');
    });

    test('markCaptureSucceeded resets both latches symmetrically', () {
      final m = CaptureLatchStateMachine();
      m.markCaptureFailedDispatched();
      m.markDecodeErrorDispatched();

      m.markCaptureSucceeded();

      expect(m.shouldDispatchCaptureFailed, isTrue);
      expect(m.shouldDispatchDecodeError, isTrue);
    });

    test('mixed-failure trajectory: sustained both → bounded total dispatch',
        () {
      final m = CaptureLatchStateMachine();

      var captureFailedCount = 0;
      var decodeErrorCount = 0;

      // Simulate 1000 ticks of "everything is on fire".
      for (var i = 0; i < 1000; i++) {
        if (m.shouldDispatchCaptureFailed) {
          m.markCaptureFailedDispatched();
          captureFailedCount++;
        }
        if (m.shouldDispatchDecodeError) {
          m.markDecodeErrorDispatched();
          decodeErrorCount++;
        }
      }

      expect(captureFailedCount, lessThanOrEqualTo(1));
      expect(decodeErrorCount, lessThanOrEqualTo(1));
    });
  });
}
