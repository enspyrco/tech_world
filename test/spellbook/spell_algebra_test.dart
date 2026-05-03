import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/spellbook/cast_result.dart';
import 'package:tech_world/spellbook/predefined_combinations.dart';
import 'package:tech_world/spellbook/spell_algebra.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

/// Convenience: every WordId is "learned" — most algebra tests don't
/// care about the un-learned path, which has its own dedicated group.
final _allLearned = WordId.values.toSet();

void main() {
  group('classifyComboCast — confidence gates', () {
    test('confidence below noise floor returns null (silence)', () {
      final result = classifyComboCast(
        transcript: 'ignis lumen',
        confidence: castNoiseFloor - 0.01,
        learnedWords: _allLearned,
      );
      expect(result, isNull,
          reason: 'sub-noise utterances are not casts at all');
    });

    test('null confidence treated as zero (fail-safe) returns null', () {
      final result = classifyComboCast(
        transcript: 'ignis',
        confidence: null,
        learnedWords: _allLearned,
      );
      expect(result, isNull);
    });

    test('confidence at noise floor (0.3) is the lowest accepted cast', () {
      final result = classifyComboCast(
        transcript: 'ignis',
        confidence: castNoiseFloor,
        learnedWords: _allLearned,
      );
      expect(result, isNotNull,
          reason: 'castNoiseFloor is inclusive — exactly 0.3 must cast');
    });

    test('null transcript at confident level → CastNoMatch(null)', () {
      final result = classifyComboCast(
        transcript: null,
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      expect(result, isA<CastNoMatch>());
      expect((result! as CastNoMatch).transcript, isNull);
    });

    test('transcript with no recognised words → CastNoMatch(transcript)', () {
      final result = classifyComboCast(
        transcript: 'and the of',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      expect(result, isA<CastNoMatch>());
      expect((result! as CastNoMatch).transcript, equals('and the of'));
    });
  });

  group('classifyComboCast — un-learned words', () {
    test('first un-learned word in combo → CastNotLearned(that word)', () {
      final result = classifyComboCast(
        transcript: 'ignis lumen',
        confidence: 0.9,
        learnedWords: const {WordId.ignis}, // lumen NOT learned
      );
      expect(result, isA<CastNotLearned>());
      expect((result! as CastNotLearned).wordId, equals(WordId.lumen));
    });

    test('un-learned word check happens before combo lookup', () {
      // ignis+lumen IS a known combo, but if lumen isn't learned the
      // result must be CastNotLearned, not CastComboKnown.
      final result = classifyComboCast(
        transcript: 'ignis lumen',
        confidence: 0.95,
        learnedWords: const {WordId.ignis},
      );
      expect(result, isA<CastNotLearned>());
    });
  });

  group('classifyComboCast — 2x2 lattice', () {
    test('known combo + high confidence → CastComboKnown(effect)', () {
      final result = classifyComboCast(
        transcript: 'ignis lumen',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      expect(result, isA<CastComboKnown>());
      expect((result! as CastComboKnown).effect.id, equals('blazing_sight'));
    });

    test('known combo + low confidence → CastComboKnownPartial(effect)', () {
      final result = classifyComboCast(
        transcript: 'ignis lumen',
        confidence: 0.5, // between noise floor and high boundary
        learnedWords: _allLearned,
      );
      expect(result, isA<CastComboKnownPartial>());
      expect((result! as CastComboKnownPartial).effect.id,
          equals('blazing_sight'));
    });

    test('novel combo + high confidence → CastComboNovel(words)', () {
      // umbra + speculum is not in predefinedCombinations.
      final result = classifyComboCast(
        transcript: 'umbra speculum',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      expect(result, isA<CastComboNovel>());
      expect((result! as CastComboNovel).words,
          equals([WordId.umbra, WordId.speculum]));
    });

    test('novel combo + low confidence → CastNoMatch (fail-cheap)', () {
      final result = classifyComboCast(
        transcript: 'umbra speculum',
        confidence: 0.5,
        learnedWords: _allLearned,
      );
      expect(result, isA<CastNoMatch>(),
          reason: 'low-conf novel falls back rather than spending an '
              'oracle call on a likely mishear');
    });

    test('high-confidence boundary (0.7) is inclusive of "high"', () {
      final result = classifyComboCast(
        transcript: 'ignis lumen',
        confidence: castHighConfidenceBoundary,
        learnedWords: _allLearned,
      );
      expect(result, isA<CastComboKnown>(),
          reason: 'exactly 0.7 must be treated as high confidence');
    });

    test('just below boundary stays low-conf', () {
      final result = classifyComboCast(
        transcript: 'ignis lumen',
        confidence: castHighConfidenceBoundary - 0.0001,
        learnedWords: _allLearned,
      );
      expect(result, isA<CastComboKnownPartial>());
    });
  });

  group('classifyComboCast — order independence', () {
    test('"ignis lumen" and "lumen ignis" hit the same combo', () {
      final a = classifyComboCast(
        transcript: 'ignis lumen',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      final b = classifyComboCast(
        transcript: 'lumen ignis',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      expect(a, isA<CastComboKnown>());
      expect(b, isA<CastComboKnown>());
      expect((a! as CastComboKnown).effect.id,
          equals((b! as CastComboKnown).effect.id));
    });

    test('three-word combo is order-independent', () {
      final a = classifyComboCast(
        transcript: 'ignis muta forma',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      final b = classifyComboCast(
        transcript: 'forma ignis muta',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      expect((a! as CastComboKnown).effect.id, equals('pyric_reshape'));
      expect((b! as CastComboKnown).effect.id, equals('pyric_reshape'));
    });
  });

  group('classifyComboCast — single-word combos', () {
    test('single learned word with no predefined combo → CastComboNovel', () {
      // A single word that isn't a "combo" by itself just goes through
      // the same lattice. Phase 2's door-cast path is separate.
      final result = classifyComboCast(
        transcript: 'umbra',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      expect(result, isA<CastComboNovel>());
    });
  });

  group('classifyComboCast — transcript normalisation', () {
    test('mixed case transcript still matches', () {
      final result = classifyComboCast(
        transcript: 'IGNIS Lumen',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      expect(result, isA<CastComboKnown>());
    });

    test('extra whitespace tolerated', () {
      final result = classifyComboCast(
        transcript: '  ignis    lumen  ',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      expect(result, isA<CastComboKnown>());
    });

    test('filler words ignored, real words still find combo', () {
      final result = classifyComboCast(
        transcript: 'ignis and lumen',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      expect(result, isA<CastComboKnown>());
    });
  });

  group('predefinedCombinations integrity', () {
    test('every key parses back to a list of valid WordIds', () {
      for (final key in predefinedCombinations.keys) {
        final parts = key.split(',');
        for (final part in parts) {
          expect(WordId.parse(part), isNotNull,
              reason: 'combo key "$key" contains unknown wire-name "$part"');
        }
      }
    });

    test('every effect has a non-empty name and description', () {
      for (final effect in predefinedCombinations.values) {
        expect(effect.name, isNotEmpty);
        expect(effect.description, isNotEmpty);
        expect(effect.id, isNotEmpty);
      }
    });

    test('effect ids are unique across the predefined set', () {
      final ids = predefinedCombinations.values.map((e) => e.id).toList();
      expect(ids.toSet().length, equals(ids.length),
          reason: 'duplicate id collides on Firestore cache key (PR 2)');
    });

    test('comboKey is order-independent', () {
      expect(comboKey(const [WordId.ignis, WordId.lumen]),
          equals(comboKey(const [WordId.lumen, WordId.ignis])));
      expect(comboKey(const [WordId.ignis, WordId.muta, WordId.forma]),
          equals(comboKey(const [WordId.forma, WordId.muta, WordId.ignis])));
    });

    test('lookupCombo finds known and misses unknown', () {
      expect(lookupCombo(const [WordId.ignis, WordId.lumen]), isNotNull);
      expect(lookupCombo(const [WordId.umbra, WordId.speculum]), isNull);
    });
  });

  group('SpellEffect — disjoint id namespace', () {
    test('SpellEffect.id values do not collide with WordId.name values', () {
      // Critical for the Firestore cache (PR 2): SpellEffect ids and
      // WordId wire-names share a string namespace if a future writer
      // dumps both into the same array. Pin disjointness now.
      final wordNames = WordId.values.map((w) => w.name).toSet();
      for (final effect in predefinedCombinations.values) {
        expect(wordNames.contains(effect.id), isFalse,
            reason: 'SpellEffect id "${effect.id}" collides with a WordId '
                'wire-name — disambiguate before they share a namespace');
      }
    });
  });
}
