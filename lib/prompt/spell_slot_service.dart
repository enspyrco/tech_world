import 'dart:async';

import 'package:flutter/foundation.dart';

/// Manages spell slot inventory and cooldown regeneration.
///
/// Players start with a base number of slots. Each prompt casting burns one
/// or more slots (depending on difficulty). Slots regenerate on a timer.
/// Capacity and regen rate scale with progression — more challenges completed
/// means more slots and faster recovery.
///
/// The [clock] parameter enables deterministic testing via `fakeAsync`.
class SpellSlotService extends ChangeNotifier {
  /// Creates a spell slot service with the given base parameters.
  ///
  /// [maxSlots] is the initial maximum capacity (before progression).
  /// [regenInterval] is the initial regeneration interval.
  /// [clock] provides the current time — defaults to [DateTime.now] but
  /// can be injected for testing.
  SpellSlotService({
    int maxSlots = 3,
    Duration regenInterval = const Duration(minutes: 3),
    DateTime Function()? clock,
  })  : _maxSlots = maxSlots,
        _availableSlots = maxSlots,
        _regenInterval = regenInterval,
        _clock = clock ?? DateTime.now,
        _challengesCompleted = 0;

  int _availableSlots;
  int _maxSlots;
  Duration _regenInterval;
  int _challengesCompleted;
  Timer? _regenTimer;
  DateTime? _lastRegenAt;
  final DateTime Function() _clock;

  /// Current available slots.
  int get availableSlots => _availableSlots;

  /// Maximum slot capacity (including progression bonuses).
  int get maxSlots => _maxSlots;

  /// Whether the player can cast (has at least one slot).
  ///
  /// For configs that cost more than one slot per cast, check the specific
  /// cost against [availableSlots] directly.
  bool get canCast => _availableSlots > 0;

  /// Time until next slot regenerates, or null if full.
  Duration? get timeUntilNextRegen {
    if (_availableSlots >= _maxSlots) return null;
    if (_regenTimer == null || _lastRegenAt == null) return null;
    final elapsed = _clock().difference(_lastRegenAt!);
    final remaining = _regenInterval - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Current regeneration interval (after progression scaling).
  Duration get regenInterval => _regenInterval;

  /// Number of challenges completed (drives progression).
  int get challengesCompleted => _challengesCompleted;

  /// Consume one or more slots for a casting attempt.
  ///
  /// Returns `true` if the slots were consumed, `false` if not enough
  /// slots are available. [cost] defaults to 1 but can be set higher
  /// for advanced difficulty casts.
  bool consumeSlot({int cost = 1}) {
    if (_availableSlots < cost) return false;
    _availableSlots -= cost;
    _lastRegenAt = _clock();
    _startRegenIfNeeded();
    notifyListeners();
    return true;
  }

  /// Update max capacity and regen rate based on progression.
  ///
  /// Progression scaling:
  /// - Every 3 challenges completed: +1 max slot (cap at 7)
  /// - Every 5 challenges completed: regen interval decreases by 30s
  ///   (floor at 1 minute)
  ///
  /// [baseMaxSlots] and [baseRegenInterval] can be passed to override
  /// the defaults (used when switching difficulty configs).
  void updateProgression({
    required int challengesCompleted,
    int? baseMaxSlots,
    Duration? baseRegenInterval,
  }) {
    _challengesCompleted = challengesCompleted;

    final base = baseMaxSlots ?? _maxSlots;
    final baseRegen = baseRegenInterval ?? _regenInterval;

    // +1 slot per 3 challenges, capped at 7.
    final bonusSlots = challengesCompleted ~/ 3;
    _maxSlots = (base + bonusSlots).clamp(1, 7);

    // -30s regen per 5 challenges, floored at 1 minute.
    final regenReduction = (challengesCompleted ~/ 5) * 30;
    final newRegenSeconds = baseRegen.inSeconds - regenReduction;
    _regenInterval = Duration(seconds: newRegenSeconds.clamp(60, 600));

    // If we gained max slots, check if regen timer should stop.
    if (_availableSlots >= _maxSlots) {
      _stopRegen();
    }

    notifyListeners();
  }

  /// Serializes the current state for persistence.
  Map<String, dynamic> toJson() => {
        'availableSlots': _availableSlots,
        'maxSlots': _maxSlots,
        'regenIntervalSeconds': _regenInterval.inSeconds,
        'lastRegenAt': _lastRegenAt?.toUtc().toIso8601String(),
        'challengesCompleted': _challengesCompleted,
      };

  /// Restores state from a previously serialized JSON map.
  ///
  /// Calculates how many slots should have regenerated since [lastRegenAt]
  /// and applies them, simulating offline regen.
  factory SpellSlotService.fromJson(
    Map<String, dynamic> json, {
    DateTime Function()? clock,
  }) {
    final clockFn = clock ?? DateTime.now;
    final maxSlots = json['maxSlots'] as int;
    final regenInterval =
        Duration(seconds: json['regenIntervalSeconds'] as int);
    final savedSlots = json['availableSlots'] as int;
    final challengesCompleted = json['challengesCompleted'] as int;
    final lastRegenAtStr = json['lastRegenAt'] as String?;

    var slots = savedSlots;

    // Calculate offline regeneration.
    if (lastRegenAtStr != null && slots < maxSlots) {
      final lastRegenAt = DateTime.parse(lastRegenAtStr);
      final elapsed = clockFn().difference(lastRegenAt);
      final regenned = elapsed.inSeconds ~/ regenInterval.inSeconds;
      slots = (slots + regenned).clamp(0, maxSlots);
    }

    final service = SpellSlotService(
      maxSlots: maxSlots,
      regenInterval: regenInterval,
      clock: clock,
    )
      .._availableSlots = slots
      .._challengesCompleted = challengesCompleted
      .._lastRegenAt =
          lastRegenAtStr != null ? DateTime.parse(lastRegenAtStr) : null;

    // If still below max after offline regen, start the timer.
    if (slots < maxSlots) {
      service._startRegenIfNeeded();
    }

    return service;
  }

  void _startRegenIfNeeded() {
    if (_regenTimer != null) return; // Already running.
    if (_availableSlots >= _maxSlots) return; // Already full.

    _regenTimer = Timer.periodic(_regenInterval, (_) {
      _availableSlots++;
      _lastRegenAt = _clock();
      if (_availableSlots >= _maxSlots) {
        _stopRegen();
      }
      notifyListeners();
    });
  }

  void _stopRegen() {
    _regenTimer?.cancel();
    _regenTimer = null;
  }

  @override
  void dispose() {
    _stopRegen();
    super.dispose();
  }
}
