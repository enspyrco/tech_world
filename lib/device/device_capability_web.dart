/// Web implementation: reads the browser userAgent and delegates the at-risk
/// decision to the pure heuristic.
library;

import 'package:web/web.dart' as web;

import 'low_memory_heuristic.dart';

/// `true` on a memory-constrained browser (currently: iOS Safari ≤ 16).
///
/// Defensive against a sandboxed/freezing browser that throws on
/// `navigator.userAgent` — falls back to `false` (full fidelity) rather than
/// crashing the world-entry path.
bool isLowMemoryDevice() {
  try {
    return isLowMemoryUserAgent(userAgent: web.window.navigator.userAgent);
  } catch (_) {
    return false;
  }
}
