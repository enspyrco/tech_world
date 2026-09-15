import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kReleaseMode, visibleForTesting;
import 'package:logging/logging.dart';

final _log = Logger('Autopilot');

/// Drives a client through sign-in, room entry and a walking route with nobody
/// at the keyboard.
///
/// Live two-client verification is the only instrument that can see whole
/// classes of defect here — proximity churn, merge membership, capture
/// starvation — because they need a second camera-publishing participant and
/// real frame latency, which unit tests construct their way around. Every one
/// of those runs has needed a human to drive one window, which is why they
/// happen rarely and why `_updateMergedVideo` went the life of the feature
/// without once being observed. This removes the hands from the loop, not the
/// eyes: the log is still the evidence.
///
/// Inert unless `--dart-define=AUTOPILOT=...` is passed, and refused outright in
/// release builds — a shipped binary that can sign itself in anonymously and
/// walk around is a capability nobody asked for.
final class Autopilot {
  Autopilot._();

  static const String _spec = String.fromEnvironment('AUTOPILOT');

  static bool _resolved = false;
  static AutopilotPlan? _plan;

  /// The plan this build was launched with, or null when not autopiloting.
  static AutopilotPlan? get plan {
    if (_resolved) return _plan;
    _resolved = true;
    if (_spec.isEmpty) return _plan = null;
    if (kReleaseMode) {
      // Fail closed and say so. Silently ignoring it would leave an operator
      // watching a release build for behaviour that can never arrive.
      _log.severe('AUTOPILOT is set but refused: release build');
      return _plan = null;
    }
    final parsed = AutopilotPlan.parse(_spec);
    if (parsed == null) {
      _log.severe('AUTOPILOT could not be parsed, ignoring: "$_spec"');
    } else {
      _log.info('Autopilot armed: $parsed');
    }
    return _plan = parsed;
  }

  static bool get enabled => plan != null;

  @visibleForTesting
  static void resetForTest() {
    _resolved = false;
    _plan = null;
  }
}

/// What an autopiloted client should do once it is signed in.
final class AutopilotPlan {
  const AutopilotPlan({
    required this.roomName,
    required this.route,
    required this.dwell,
  });

  /// Room to enter, matched case-insensitively against the room's name.
  final String roomName;

  /// Mini-grid cells to walk between, in order, looping. Empty means "join and
  /// stand still" — which is a real role: the merge cases need one participant
  /// holding position while the other crosses the threshold.
  final List<Point<int>> route;

  /// How long to wait at each waypoint before requesting the next.
  final Duration dwell;

  /// Parses `room=<name>;route=<x,y>[>x,y...];dwell=<ms>`.
  ///
  /// Returns null rather than throwing on anything malformed: this runs at
  /// startup from a build flag, and a typo should degrade to "no autopilot"
  /// with a logged reason, not to a client that will not start.
  static AutopilotPlan? parse(String spec) {
    String? roomName;
    var route = const <Point<int>>[];
    var dwell = const Duration(milliseconds: 2000);

    for (final part in spec.split(';')) {
      if (part.trim().isEmpty) continue;
      final eq = part.indexOf('=');
      if (eq < 0) return null;
      final key = part.substring(0, eq).trim();
      final value = part.substring(eq + 1).trim();
      switch (key) {
        case 'room':
          if (value.isEmpty) return null;
          roomName = value;
        case 'route':
          final points = <Point<int>>[];
          for (final cell in value.split('>')) {
            final xy = cell.split(',');
            if (xy.length != 2) return null;
            final x = int.tryParse(xy[0].trim());
            final y = int.tryParse(xy[1].trim());
            if (x == null || y == null) return null;
            points.add(Point(x, y));
          }
          route = points;
        case 'dwell':
          final ms = int.tryParse(value);
          // A zero or negative period would spin Timer.periodic as fast as the
          // event loop allows and issue move requests faster than a cell-move
          // can complete.
          if (ms == null || ms <= 0) return null;
          dwell = Duration(milliseconds: ms);
        default:
          return null;
      }
    }

    if (roomName == null) return null;
    return AutopilotPlan(roomName: roomName, route: route, dwell: dwell);
  }

  /// Whether [name] is the room this plan means.
  bool matchesRoom(String name) =>
      name.trim().toLowerCase() == roomName.trim().toLowerCase();

  @override
  String toString() =>
      'AutopilotPlan(room: "$roomName", route: $route, dwell: ${dwell.inMilliseconds}ms)';
}

/// Issues the plan's move requests on a timer.
///
/// Takes the move function rather than reaching for `TechWorld`, so the walking
/// RULE is testable without a game loop — the same split that makes
/// `mergeTransitions` provable without a shader.
final class AutopilotWalker {
  AutopilotWalker({
    required AutopilotPlan plan,
    required void Function(int x, int y) moveTo,
  })  : _plan = plan,
        _moveTo = moveTo;

  final AutopilotPlan _plan;
  final void Function(int x, int y) _moveTo;

  Timer? _timer;
  int _next = 0;

  bool get isRunning => _timer != null;

  /// Begins walking. A route of fewer than two points is not a walk, so this is
  /// a no-op rather than a timer that re-requests one cell forever.
  void start() {
    if (_plan.route.length < 2 || _timer != null) return;
    _step();
    _timer = Timer.periodic(_plan.dwell, (_) => _step());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  @visibleForTesting
  void debugStep() => _step();

  void _step() {
    final target = _plan.route[_next];
    _next = (_next + 1) % _plan.route.length;
    _moveTo(target.x, target.y);
  }
}
