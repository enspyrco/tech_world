/// Schools of prompt magic, each teaching a different prompt engineering skill.
///
/// Players specialize in schools as they progress, learning that different
/// problems demand different prompting strategies.
enum SpellSchool {
  /// Clear, precise instruction — getting exactly what you ask for.
  evocation,

  /// Information extraction — drawing out hidden knowledge.
  divination,

  /// Data format conversion — reshaping output structure.
  transmutation,

  /// Perspective and persona prompting — shifting the voice.
  illusion,

  /// Constraint negotiation — bending or overriding rules.
  enchantment,

  /// Few-shot and example-based creation — teaching by showing.
  conjuration,
}

extension SpellSchoolDisplay on SpellSchool {
  /// Title-case label for UI rendering (e.g. `'Evocation'`).
  String get label => switch (this) {
        SpellSchool.evocation => 'Evocation',
        SpellSchool.divination => 'Divination',
        SpellSchool.transmutation => 'Transmutation',
        SpellSchool.illusion => 'Illusion',
        SpellSchool.enchantment => 'Enchantment',
        SpellSchool.conjuration => 'Conjuration',
      };
}
