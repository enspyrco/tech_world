import 'package:flutter/painting.dart' show Color;
import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/prompt/spell_school.dart';

/// Single source of truth for the spellbook accent colour. Used by the
/// spellbook panel, the toolbar toggle button, and any future spell VFX.
const arcaneColor = Color(0xFFAA44FF);

/// The closed set of words a player can ever learn.
///
/// `WordId` is the **domain type** for words throughout the codebase.
/// Strings only appear at boundaries — Firestore on-disk format and STT
/// transcripts — and parse via [WordId.parse]. Internally everything
/// (services, UI, tests, the algebra in Phase 3) operates on `WordId`,
/// so the compiler enforces what would otherwise be runtime invariants:
///
/// * No typo can refer to a non-existent word — it won't compile.
/// * Switch expressions over `WordId` must be exhaustive — adding a 19th
///   word in a later phase fails the build at every site that hasn't
///   handled it.
/// * The bijection with [allPromptChallenges] reduces from a dozen tests
///   to one length assertion.
///
/// On-disk format: `WordId.ignis.name` → `'ignis'` (the enum identifier
/// is the wire format). Existing Firestore data parses unchanged.
enum WordId {
  ignis,
  tempus,
  crystallum,
  lumen,
  verum,
  oraculum,
  forma,
  structura,
  muta,
  umbra,
  speculum,
  phantasma,
  vinculum,
  libera,
  dominus,
  genesis,
  exemplar,
  lexicon;

  /// Parse a wire-format string into a `WordId`, or `null` if unknown.
  /// Use at boundaries (Firestore reads, STT results) and decide what to
  /// do with `null` at the call site.
  static WordId? parse(String wire) {
    for (final w in WordId.values) {
      if (w.name == wire) return w;
    }
    return null;
  }
}

extension WordIdDisplay on WordId {
  /// Uppercase incantation form, e.g. `WordId.ignis.displayName == 'IGNIS'`.
  String get displayName => name.toUpperCase();
}

/// Elemental affinity of a word — drives visual treatment and (later) algebra.
///
/// Six elements correspond 1:1 with the six [SpellSchool]s:
/// evocation→fire, divination→water, transmutation→earth,
/// illusion→air, enchantment→spirit, conjuration→void.
enum SpellElement {
  fire,
  water,
  earth,
  air,
  spirit,
  void_,
}

/// Grammatical role of a word inside a compound spell.
///
/// Used by Phase 3's algebra engine to decide composition rules.
/// In Phase 1 it's purely informational — every word still casts
/// fine on its own.
enum WordRole {
  /// Names a thing or essence (e.g. IGNIS, LUMEN, FORMA). Most words.
  substance,

  /// Names a transformation (e.g. MUTA, GENESIS).
  action,

  /// Modifies another word (e.g. VERUM = "true X", UMBRA = "shadowed X").
  modifier,
}

/// A "word of power" earned by completing a [PromptChallenge].
///
/// Each word is freely reusable — once learned, it stays in the spellbook
/// and can be spoken aloud (Phase 2) or composed with other words (Phase 3).
/// The spellbook is a vocabulary, not an inventory.
class WordOfPower {
  const WordOfPower({
    required this.id,
    required this.meaning,
    required this.school,
    required this.element,
    required this.intensity,
    required this.role,
    required this.challengeId,
  });

  /// Strongly-typed identifier — see [WordId].
  final WordId id;

  /// Plain-English gloss, e.g. `'fire'`.
  final String meaning;

  /// School of magic this word belongs to.
  final SpellSchool school;

  /// Elemental affinity — drives bubble/door colour theme.
  final SpellElement element;

  /// 1–3, mirroring the underlying challenge's difficulty.
  final int intensity;

  /// Grammatical role — see [WordRole].
  final WordRole role;

  /// The [PromptChallenge.id] that earns this word. Strongly-typed —
  /// the bijection between `WordId` and `PromptChallengeId` is now
  /// largely a compile-time fact (uniqueness within each enum, no
  /// typos), with a single length-equality test enforcing the cross-
  /// module count match.
  final PromptChallengeId challengeId;

  /// Convenience pass-through to [WordIdDisplay.displayName].
  String get displayName => id.displayName;

  @override
  String toString() => 'WordOfPower(${id.name})';
}
