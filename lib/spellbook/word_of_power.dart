import 'package:flutter/painting.dart' show Color;
import 'package:tech_world/prompt/spell_school.dart';

/// Single source of truth for the spellbook accent colour. Used by the
/// spellbook panel, the toolbar toggle button, and any future spell VFX.
const arcaneColor = Color(0xFFAA44FF);

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
    required this.displayName,
    required this.meaning,
    required this.school,
    required this.element,
    required this.intensity,
    required this.role,
    required this.challengeId,
  });

  /// Lowercase canonical id, e.g. `'ignis'`. Used as Firestore array entry,
  /// map key, and STT match target.
  final String id;

  /// Uppercase incantation form, e.g. `'IGNIS'`. Display + speech prompt.
  final String displayName;

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

  /// The [PromptChallenge.id] that earns this word.
  final String challengeId;

  @override
  String toString() => 'WordOfPower($id)';
}
