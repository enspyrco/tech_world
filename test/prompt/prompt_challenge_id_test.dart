import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/prompt/predefined_prompt_challenges.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';

void main() {
  group('PromptChallengeId', () {
    test('parse round-trips every value', () {
      for (final id in PromptChallengeId.values) {
        expect(PromptChallengeId.parse(id.wireName), id,
            reason: '${id.name} wireName=${id.wireName} did not round-trip');
      }
    });

    test('parse returns null for unknown wire format', () {
      expect(PromptChallengeId.parse('not_a_challenge'), isNull);
      expect(PromptChallengeId.parse(''), isNull);
      expect(PromptChallengeId.parse('EVOCATION_FIZZBUZZ'), isNull);
    });

    test('wireName is unique across values', () {
      final names = PromptChallengeId.values.map((e) => e.wireName).toSet();
      expect(names.length, PromptChallengeId.values.length);
    });

    test('wireName follows snake_case school_subject pattern', () {
      for (final id in PromptChallengeId.values) {
        expect(id.wireName, matches(RegExp(r'^[a-z]+_[a-z]+$')),
            reason: '${id.name} wireName=${id.wireName} does not match');
      }
    });

    test('|PromptChallengeId.values| == |allPromptChallenges|', () {
      // Cross-module bijection: every PromptChallengeId has exactly one
      // PromptChallenge instance, and vice versa. Once PromptChallenge.id
      // becomes typed, this collapses to the same length assertion plus
      // a totality check via the type.
      expect(PromptChallengeId.values.length, allPromptChallenges.length);
    });
  });
}
