import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/prompt/cast_result.dart';

/// CastResult.passed derivation tests.
///
/// The `passed` field is now derived from `feedback`:
///   passed == (feedback == CastFeedback.resonates)
///
/// This ensures no illegal state (passed: true, feedback: fizzled) can
/// exist. The boolean is a retract of the enum.
void main() {
  group('CastResult.passed derivation', () {
    test('resonates => passed', () {
      const result = CastResult(feedback: CastFeedback.resonates);
      expect(result.passed, isTrue);
    });

    test('fizzled => not passed', () {
      const result = CastResult(feedback: CastFeedback.fizzled);
      expect(result.passed, isFalse);
    });

    test('backfired => not passed', () {
      const result = CastResult(feedback: CastFeedback.backfired);
      expect(result.passed, isFalse);
    });

    test('unclear => not passed', () {
      const result = CastResult(feedback: CastFeedback.unclear);
      expect(result.passed, isFalse);
    });

    test('passed is consistent for all feedback values', () {
      for (final feedback in CastFeedback.values) {
        final result = CastResult(feedback: feedback);
        final expected = feedback == CastFeedback.resonates;
        expect(result.passed, equals(expected),
            reason: '$feedback should ${expected ? "" : "not "}pass');
      }
    });

    test('old constructor with passed: true is ignored (feedback wins)', () {
      // ignore: avoid_redundant_argument_values
      const result = CastResult(passed: true, feedback: CastFeedback.fizzled);
      expect(result.passed, isFalse,
          reason: 'feedback is the source of truth, not the passed parameter');
    });

    test('judgeReasoning preserved', () {
      const result = CastResult(
        feedback: CastFeedback.resonates,
        judgeReasoning: 'Well done!',
      );
      expect(result.judgeReasoning, equals('Well done!'));
      expect(result.passed, isTrue);
    });
  });
}
