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

/// A composed spell effect — the result of combining multiple
/// [WordOfPower]s. Predefined combos are handcrafted; novel combos
/// arrive asynchronously via the oracle channel and become predefined
/// for that user via [SpellCacheService] (Phase 3 PR 2).
///
/// Pure data — no rendering responsibility. The cast pipeline returns
/// a [SpellEffect] inside a [CastComboKnown] / [CastComboKnownPartial]
/// variant; the UI / VFX layer maps that to particles, sound, etc.
class SpellEffect {
  const SpellEffect({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    this.magnitude = 5,
  });

  /// Stable identifier — snake_case, used as a Firestore doc key for
  /// per-user cache (Phase 3 PR 2). Disjoint from [WordId.name] to
  /// avoid collisions on the same persistence boundary.
  final String id;

  /// Display name — the spell's evocative title, e.g. 'Blazing Sight'.
  final String name;

  /// One-line flavor — what the spell does, in-fiction.
  final String description;

  /// Visual category — drives particle / shader selection.
  final SpellEffectType type;

  /// 1–10. Determines visual scale (particle count, glow radius) and
  /// later, gameplay magnitude. Half-strength casts visually halve this.
  final int magnitude;

  @override
  String toString() => 'SpellEffect($id)';
}
