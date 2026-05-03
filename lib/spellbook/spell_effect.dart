/// Categories of spell effect — drives visual treatment and (later)
/// gameplay impact. Kept small and extensible; novel oracle-interpreted
/// effects fall back to [SpellEffectType.unknown] until categorisation.
enum SpellEffectType {
  /// Sudden burst of fire / heat — IGNIS-rooted combos.
  fireBurst,

  /// Illumination / sight enhancement — LUMEN-rooted combos.
  illumination,

  /// Defensive ward / barrier — VINCULUM-rooted combos.
  protection,

  /// Movement / passage — TEMPUS / LIBERA-rooted combos.
  passage,

  /// Revelation / divination — VERUM / ORACULUM-rooted combos.
  revelation,

  /// Unknown / oracle-interpreted — placeholder until the bot
  /// categorises a novel-combo result.
  unknown,
}

/// Strongly-typed identifier for a [SpellEffect]. Branded value type so
/// the analyzer rejects accidental mixing with [WordId.name] strings —
/// both share the Firestore persistence boundary in PR 2's cache.
///
/// The wire format is the wrapped [String]; on-disk Firestore reads
/// parse via [SpellEffectId.new] from a String column. The `wireName`
/// pattern used by [PromptChallengeId] / [CodeChallengeId] is overkill
/// here because effect ids aren't drawn from a closed enum — novel
/// oracle-interpreted effects mint fresh ids at runtime.
class SpellEffectId {
  const SpellEffectId(this.value);

  /// The wire-form / canonical string — `'blazing_sight'`,
  /// `'oracle_truth'`, etc.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpellEffectId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'SpellEffectId($value)';
}

/// A composed spell effect — the result of combining multiple
/// [WordOfPower]s. Predefined combos are handcrafted; novel combos
/// arrive asynchronously via the oracle channel and become predefined
/// for that user via [SpellCacheService] (Phase 3 PR 2).
///
/// Pure data — no rendering responsibility. The cast pipeline returns
/// a [SpellEffect] inside a [CastComboKnown] / [CastComboKnownPartial]
/// variant; the UI / VFX layer maps that to particles, sound, etc.
class SpellEffect {
  /// Throws [RangeError] when [magnitude] falls outside `[1, 10]`.
  /// Use a throwing constructor rather than `assert` because asserts
  /// are stripped in release builds — oracle-interpreted novel effects
  /// (PR 2) construct `SpellEffect` at runtime from network input, so
  /// the invariant must hold in release mode too.
  SpellEffect({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    this.magnitude = 5,
  }) {
    if (magnitude < 1 || magnitude > 10) {
      throw RangeError.range(magnitude, 1, 10, 'magnitude',
          'SpellEffect magnitude must be in [1, 10]');
    }
  }

  /// Stable identifier. Branded as [SpellEffectId] so it can't be
  /// confused with raw strings (e.g. `WordId.name` values) at the
  /// Firestore persistence boundary in PR 2.
  final SpellEffectId id;

  /// Display name — the spell's evocative title, e.g. 'Blazing Sight'.
  final String name;

  /// One-line flavor — what the spell does, in-fiction.
  final String description;

  /// Visual category — drives particle / shader selection.
  final SpellEffectType type;

  /// 1–10 (enforced by constructor assert). Determines visual scale
  /// (particle count, glow radius) and later, gameplay magnitude.
  /// Half-strength casts visually halve this.
  final int magnitude;

  @override
  String toString() => 'SpellEffect(${id.value})';
}
