import 'dart:async';

import 'package:flutter/foundation.dart';

/// The parallel operations tracked during room join.
enum Wire { tilesets, server, camera, chat, gameReady }

/// Lifecycle state for a single [Wire].
enum WireStatus { pending, active, complete, error }

/// Tracks the status of each [Wire] during room join.
///
/// Listeners are notified on every transition so the circuit-board overlay
/// can animate sparks and glow in real time.
class WireStates extends ChangeNotifier {
  final Map<Wire, WireStatus> _states = {
    for (final w in Wire.values) w: WireStatus.pending,
  };

  /// Transition [wire] to [WireStatus.active].
  void start(Wire wire) {
    _states[wire] = WireStatus.active;
    notifyListeners();
  }

  /// Transition [wire] to [WireStatus.complete].
  void complete(Wire wire) {
    _states[wire] = WireStatus.complete;
    notifyListeners();
  }

  /// Transition [wire] to [WireStatus.error].
  void error(Wire wire) {
    _states[wire] = WireStatus.error;
    notifyListeners();
  }

  /// Read the current status of [wire].
  WireStatus operator [](Wire wire) => _states[wire]!;

  /// True when every wire has reached [WireStatus.complete].
  bool get allComplete =>
      _states.values.every((s) => s == WireStatus.complete);
}

/// Extension on [ValueNotifier<bool>] to await a `true` value.
extension WaitForTrue on ValueNotifier<bool> {
  /// Returns a future that completes when [value] becomes `true`.
  ///
  /// Checks eagerly — if already `true`, completes synchronously via
  /// [Future.value] to avoid race conditions where the notifier fires
  /// before the listener is attached.
  Future<void> waitForTrue() {
    if (value) return Future.value();
    final completer = Completer<void>();
    void listener() {
      if (value && !completer.isCompleted) {
        completer.complete();
        removeListener(listener);
      }
    }

    addListener(listener);
    return completer.future;
  }
}
