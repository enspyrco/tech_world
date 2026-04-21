/// Configuration for spell slot scaling per difficulty tier.
///
/// Different difficulty tiers consume different amounts of slots and
/// regenerate at different rates, making harder challenges require more
/// careful resource management.
class SpellSlotConfig {
  /// Creates a spell slot configuration.
  const SpellSlotConfig({
    required this.slotsPerCast,
    required this.baseMaxSlots,
    required this.baseRegenInterval,
  });

  /// How many slots a single cast consumes.
  final int slotsPerCast;

  /// Starting maximum slot capacity before progression bonuses.
  final int baseMaxSlots;

  /// Starting regeneration interval before progression bonuses.
  final Duration baseRegenInterval;

  /// Beginner: generous slots, fast regen, low cost per cast.
  static const beginner = SpellSlotConfig(
    slotsPerCast: 1,
    baseMaxSlots: 5,
    baseRegenInterval: Duration(minutes: 2),
  );

  /// Intermediate: standard slots, moderate regen, standard cost.
  static const intermediate = SpellSlotConfig(
    slotsPerCast: 1,
    baseMaxSlots: 3,
    baseRegenInterval: Duration(minutes: 3),
  );

  /// Advanced: fewer slots, slow regen, double cost — forces deliberate craft.
  static const advanced = SpellSlotConfig(
    slotsPerCast: 2,
    baseMaxSlots: 3,
    baseRegenInterval: Duration(minutes: 5),
  );
}
