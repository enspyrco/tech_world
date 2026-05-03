import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/spellbook/free_cast_result.dart';
import 'package:tech_world/spellbook/predefined_combinations.dart';
import 'package:tech_world/spellbook/spell_algebra.dart';
import 'package:tech_world/spellbook/spell_effect.dart';
import 'package:tech_world/spellbook/word_of_power.dart';

/// Convenience: every WordId is "learned" — most algebra tests don't
/// care about the un-learned path, which has its own dedicated group.
final _allLearned = WordId.values.toSet();

void main() {
  group('classifyFreeCast — confidence gates', () {
    test('confidence below noise floor returns null (silence)', () {
      final result = classifyFreeCast(
        transcript: 'ignis lumen',
        confidence: castNoiseFloor - 0.01,
        learnedWords: _allLearned,
      );
      expect(result, isNull,
          reason: 'sub-noise utterances are not casts at all');
    });

    test('null confidence treated as zero (fail-safe) returns null', () {
      final result = classifyFreeCast(
        transcript: 'ignis',
        confidence: null,
        learnedWords: _allLearned,
      );
      expect(result, isNull);
    });

    test('NaN confidence rejected (Dart NaN comparisons are always false)', () {
      // Without an explicit isFinite check, `NaN < castNoiseFloor` is false,
      // which would let NaN slip past the noise gate and be classified as
      // low-confidence. Explicit guard keeps NaN out of the lattice.
      final result = classifyFreeCast(
        transcript: 'ignis',
        confidence: double.nan,
        learnedWords: _allLearned,
      );
      expect(result, isNull);
    });

    test('infinity confidence rejected (also non-finite)', () {
      final result = classifyFreeCast(
        transcript: 'ignis',
        confidence: double.infinity,
        learnedWords: _allLearned,
      );
      expect(result, isNull);
    });

    test('confidence at noise floor (0.3) is the lowest accepted cast', () {
      final result = classifyFreeCast(
        transcript: 'ignis',
        confidence: castNoiseFloor,
        learnedWords: _allLearned,
      );
      expect(result, isNotNull,
          reason: 'castNoiseFloor is inclusive — exactly 0.3 must cast');
    });

    test('null transcript at confident level → FreeCastNoMatch(null)', () {
      final result = classifyFreeCast(
        transcript: null,
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      expect(result, isA<FreeCastNoMatch>());
      expect((result! as FreeCastNoMatch).transcript, isNull);
    });

    test('transcript with no recognised words → FreeCastNoMatch(transcript)', () {
      final result = classifyFreeCast(
        transcript: 'and the of',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      expect(result, isA<FreeCastNoMatch>());
      expect((result! as FreeCastNoMatch).transcript, equals('and the of'));
    });

    test('any unknown token in a multi-word cast rejects the whole cast', () {
      // Hardened against the "ignis garbage lumen" silent-cherry-pick
      // failure mode: even one unrecognised token short-circuits to
      // FreeCastNoMatch, rather than dropping the unknown and casting the
      // recognisable subset.
      final result = classifyFreeCast(
        transcript: 'ignis garbage lumen',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      expect(result, isA<FreeCastNoMatch>());
    });

    test('punctuation around words is stripped (clean utterances pass)', () {
      // STT engines sometimes emit "ignis." or "ignis," — punctuation is
      // a cosmetic artifact, not a meaning shift; strip and parse.
      final result = classifyFreeCast(
        transcript: 'ignis.',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      expect(result, isA<CastComboNovel>());
    });
  });

  group('classifyFreeCast — un-learned words', () {
    test('first un-learned word in combo → FreeCastNotLearned(that word)', () {
      final result = classifyFreeCast(
        transcript: 'ignis lumen',
        confidence: 0.9,
        learnedWords: const {WordId.ignis}, // lumen NOT learned
      );
      expect(result, isA<FreeCastNotLearned>());
      expect((result! as FreeCastNotLearned).wordId, equals(WordId.lumen));
    });

    test('un-learned word check happens before combo lookup', () {
      // ignis+lumen IS a known combo, but if lumen isn't learned the
      // result must be FreeCastNotLearned, not CastComboKnown.
      final result = classifyFreeCast(
        transcript: 'ignis lumen',
        confidence: 0.95,
        learnedWords: const {WordId.ignis},
      );
      expect(result, isA<FreeCastNotLearned>());
    });
  });

  group('classifyFreeCast — 2x2 lattice', () {
    test('known combo + high confidence → CastComboKnown(effect)', () {
      final result = classifyFreeCast(
        transcript: 'ignis lumen',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      expect(result, isA<CastComboKnown>());
      expect((result! as CastComboKnown).effect.id,
          equals(SpellEffectId('blazing_sight')));
    });

    test('known combo + low confidence → CastComboKnownPartial(effect)', () {
      final result = classifyFreeCast(
        transcript: 'ignis lumen',
        confidence: 0.5, // between noise floor and high boundary
        learnedWords: _allLearned,
      );
      expect(result, isA<CastComboKnownPartial>());
      expect((result! as CastComboKnownPartial).effect.id,
          equals(SpellEffectId('blazing_sight')));
    });

    test('novel combo + high confidence → CastComboNovel(words)', () {
      // umbra + speculum is not in predefinedCombinations.
      final result = classifyFreeCast(
        transcript: 'umbra speculum',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      expect(result, isA<CastComboNovel>());
      expect((result! as CastComboNovel).words,
          equals([WordId.umbra, WordId.speculum]));
    });

    test('novel combo + low confidence → FreeCastNoMatch (fail-cheap)', () {
      final result = classifyFreeCast(
        transcript: 'umbra speculum',
        confidence: 0.5,
        learnedWords: _allLearned,
      );
      expect(result, isA<FreeCastNoMatch>(),
          reason: 'low-conf novel falls back rather than spending an '
              'oracle call on a likely mishear');
    });

    test('high-confidence boundary (0.7) is inclusive of "high"', () {
      final result = classifyFreeCast(
        transcript: 'ignis lumen',
        confidence: castHighConfidenceBoundary,
        learnedWords: _allLearned,
      );
      expect(result, isA<CastComboKnown>(),
          reason: 'exactly 0.7 must be treated as high confidence');
    });

    test('just below boundary stays low-conf', () {
      final result = classifyFreeCast(
        transcript: 'ignis lumen',
        confidence: castHighConfidenceBoundary - 0.0001,
        learnedWords: _allLearned,
      );
      expect(result, isA<CastComboKnownPartial>());
    });
  });

  group('classifyFreeCast — order independence', () {
    test('"ignis lumen" and "lumen ignis" hit the same combo', () {
      final a = classifyFreeCast(
        transcript: 'ignis lumen',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      final b = classifyFreeCast(
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
      final a = classifyFreeCast(
        transcript: 'ignis muta forma',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      final b = classifyFreeCast(
        transcript: 'forma ignis muta',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      expect((a! as CastComboKnown).effect.id,
          equals(SpellEffectId('pyric_reshape')));
      expect((b! as CastComboKnown).effect.id,
          equals(SpellEffectId('pyric_reshape')));
    });
  });

  group('classifyFreeCast — single-word combos', () {
    test('single learned word with no predefined combo → CastComboNovel', () {
      // A single word that isn't a "combo" by itself just goes through
      // the same lattice. Phase 2's door-cast path is separate.
      final result = classifyFreeCast(
        transcript: 'umbra',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      expect(result, isA<CastComboNovel>());
    });
  });

  group('classifyFreeCast — transcript normalisation', () {
    test('mixed case transcript still matches', () {
      final result = classifyFreeCast(
        transcript: 'IGNIS Lumen',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      expect(result, isA<CastComboKnown>());
    });

    test('extra whitespace tolerated', () {
      final result = classifyFreeCast(
        transcript: '  ignis    lumen  ',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      expect(result, isA<CastComboKnown>());
    });

    test('filler word "and" between real words rejects the whole cast', () {
      // Earlier design ignored unrecognised tokens (treating "and" as a
      // filler). Carnot flagged: "ignis garbage lumen" silently casting
      // ignis+lumen is a real failure mode. Tightened to reject any
      // unknown token, including would-be fillers — players speak the
      // words back-to-back; if STT inserted "and" the player should
      // know the cast didn't take.
      final result = classifyFreeCast(
        transcript: 'ignis and lumen',
        confidence: 0.9,
        learnedWords: _allLearned,
      );
      expect(result, isA<FreeCastNoMatch>());
    });
  });

  group('predefinedCombinations integrity', () {
    test('every key parses back to a list of valid WordIds', () {
      for (final key in predefinedCombinations.keys) {
        final parts = key.value.split(',');
        for (final part in parts) {
          expect(WordId.parse(part), isNotNull,
              reason: 'combo key "${key.value}" contains unknown '
                  'wire-name "$part"');
        }
      }
    });

    test('every effect has a non-empty name and description', () {
      for (final effect in predefinedCombinations.values) {
        expect(effect.name, isNotEmpty);
        expect(effect.description, isNotEmpty);
        expect(effect.id.value, isNotEmpty);
      }
    });

    test('effect ids are unique across the predefined set', () {
      final ids = predefinedCombinations.values.map((e) => e.id).toList();
      expect(ids.toSet().length, equals(ids.length),
          reason: 'duplicate id collides on Firestore cache key (PR 2)');
    });

    test('ComboKey.of is order-independent', () {
      expect(ComboKey.of(const [WordId.ignis, WordId.lumen]),
          equals(ComboKey.of(const [WordId.lumen, WordId.ignis])));
      expect(ComboKey.of(const [WordId.ignis, WordId.muta, WordId.forma]),
          equals(ComboKey.of(const [WordId.forma, WordId.muta, WordId.ignis])));
    });

    test('ComboKey equality is structural', () {
      expect(ComboKey.of(const [WordId.ignis, WordId.lumen]),
          equals(ComboKey.fromCanonical('ignis,lumen')));
      expect(ComboKey.of(const [WordId.ignis, WordId.lumen]).hashCode,
          equals(ComboKey.fromCanonical('ignis,lumen').hashCode));
    });

    test('ComboKey.fromCanonical rejects empty input', () {
      expect(() => ComboKey.fromCanonical(''),
          throwsA(isA<FormatException>()));
    });

    test('ComboKey.fromCanonical rejects unknown WordId wire-names', () {
      expect(() => ComboKey.fromCanonical('ignis,garbage'),
          throwsA(isA<FormatException>()));
    });

    test('ComboKey.fromCanonical rejects unsorted input', () {
      // 'lumen,ignis' is alphabetically out of order; canonical form is
      // 'ignis,lumen'. Hydrating from the unsorted form would produce a
      // ComboKey that doesn't equal the same combo built via .of(),
      // breaking map lookup. Reject at the boundary.
      expect(() => ComboKey.fromCanonical('lumen,ignis'),
          throwsA(isA<FormatException>()));
    });
  });

  group('SpellEffectId — non-empty invariant', () {
    test('empty id throws FormatException', () {
      expect(() => SpellEffectId(''), throwsA(isA<FormatException>()));
    });
  });

  group('SpellEffect — disjoint id namespace', () {
    test('SpellEffectId is type-distinct from WordId.name strings', () {
      // The branded SpellEffectId type prevents accidental mixing with
      // raw WordId.name strings at compile time. The earlier
      // string-collision regression test is now redundant, but we keep
      // a runtime assertion that the wrapped String values also don't
      // collide — the Firestore on-disk format is still String, and a
      // future writer that round-trips through `id.value` could still
      // collide if the namespaces drifted.
      final wordNames = WordId.values.map((w) => w.name).toSet();
      for (final effect in predefinedCombinations.values) {
        expect(wordNames.contains(effect.id.value), isFalse,
            reason:
                'SpellEffectId.value "${effect.id.value}" collides with a '
                'WordId wire-name — disambiguate before they share a '
                'persistence boundary');
      }
    });

    test('SpellEffectId equality is structural, not identity', () {
      expect(SpellEffectId('blazing_sight'),
          equals(SpellEffectId('blazing_sight')));
      expect(SpellEffectId('blazing_sight').hashCode,
          equals(SpellEffectId('blazing_sight').hashCode));
    });
  });

  group('SpellEffect — magnitude invariant', () {
    test('magnitude < 1 throws RangeError (release-safe, not assert-stripped)', () {
      expect(
        () => SpellEffect(
          id: SpellEffectId('zero_strength'),
          name: 'Zero',
          description: 'invalid',
          type: SpellEffectType.unknown,
          magnitude: 0,
        ),
        throwsA(isA<RangeError>()),
      );
    });

    test('magnitude > 10 throws RangeError', () {
      expect(
        () => SpellEffect(
          id: SpellEffectId('over_strength'),
          name: 'Over',
          description: 'invalid',
          type: SpellEffectType.unknown,
          magnitude: 11,
        ),
        throwsA(isA<RangeError>()),
      );
    });
  });

  group('CastComboNovel.words — unmodifiable', () {
    test('mutating the words list throws (defends against consumer leaks)', () {
      final mutable = [WordId.umbra, WordId.speculum];
      final result = CastComboNovel(mutable);
      expect(() => result.words.add(WordId.ignis),
          throwsA(isA<UnsupportedError>()));
    });

    test('mutating the original list does not affect the result', () {
      // Pin defensive-copy semantics — if the constructor only stored a
      // reference to the input list, mutating it after construction
      // would leak through. List.unmodifiable copies.
      final mutable = [WordId.umbra, WordId.speculum];
      final result = CastComboNovel(mutable);
      mutable.add(WordId.ignis);
      expect(result.words.length, equals(2));
    });
  });
}
