import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/editor/challenge.dart';
import 'package:tech_world/editor/predefined_challenges.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';

void main() {
  group('CodeChallengeId', () {
    test('parse round-trips every value', () {
      for (final id in CodeChallengeId.values) {
        expect(CodeChallengeId.parse(id.wireName), id,
            reason: '${id.name} wireName=${id.wireName} did not round-trip');
      }
    });

    test('parse returns null for unknown wire format', () {
      expect(CodeChallengeId.parse('not_a_challenge'), isNull);
      expect(CodeChallengeId.parse(''), isNull);
      expect(CodeChallengeId.parse('HELLO_DART'), isNull);
    });

    test('wireName is unique across values', () {
      final names = CodeChallengeId.values.map((e) => e.wireName).toSet();
      expect(names.length, CodeChallengeId.values.length);
    });

    test('wireName uses snake_case (lowercase + underscores only)', () {
      for (final id in CodeChallengeId.values) {
        expect(id.wireName, matches(RegExp(r'^[a-z]+(_[a-z]+)*$')),
            reason: '${id.name} wireName=${id.wireName} does not match');
      }
    });

    test('|CodeChallengeId.values| == |allChallenges|', () {
      expect(CodeChallengeId.values.length, allChallenges.length);
    });
  });

  group('CodeChallengeId disjoint from PromptChallengeId wire format', () {
    // The two enum namespaces share Firestore's `completedChallenges`
    // array. Disjoint wire names are what makes that safe.
    //
    // Source-of-truth-driven: pulls the prompt wire forms straight from
    // `PromptChallengeId.values`, so a future addition on either side
    // that introduces a collision fails the build automatically.
    test('no CodeChallengeId.wireName equals a PromptChallengeId.wireName',
        () {
      final promptWireForms =
          PromptChallengeId.values.map((e) => e.wireName).toSet();
      for (final id in CodeChallengeId.values) {
        expect(promptWireForms.contains(id.wireName), isFalse,
            reason: 'CodeChallengeId.${id.name} wireName=${id.wireName} '
                'collides with a PromptChallengeId wireName');
      }
    });
  });
}
