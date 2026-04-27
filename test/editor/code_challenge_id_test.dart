import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/editor/challenge.dart';
import 'package:tech_world/editor/predefined_challenges.dart';

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
    test('no CodeChallengeId.wireName equals a PromptChallengeId.wireName',
        () {
      // Hard-coded against the prompt-side wire forms to avoid an import
      // cycle between editor and prompt modules. If a collision is
      // introduced, this test fails loudly and we revisit the design.
      const promptWireForms = {
        'evocation_fizzbuzz',
        'evocation_countdown',
        'evocation_diamond',
        'divination_color',
        'divination_extract',
        'divination_pattern',
        'transmutation_bullets',
        'transmutation_table',
        'transmutation_json',
        'illusion_pirate',
        'illusion_child',
        'illusion_dual',
        'enchantment_brevity',
        'enchantment_formal',
        'enchantment_contradict',
        'conjuration_glorp',
        'conjuration_pattern',
        'conjuration_language',
      };
      for (final id in CodeChallengeId.values) {
        expect(promptWireForms.contains(id.wireName), isFalse,
            reason: 'CodeChallengeId.${id.name} wireName collides with '
                'a PromptChallengeId wireName');
      }
    });
  });
}
