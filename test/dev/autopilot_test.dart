import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/dev/autopilot.dart';

void main() {
  group('AutopilotPlan.parse', () {
    test('a full spec round-trips into typed fields', () {
      final plan = AutopilotPlan.parse('room=Wizards Tower;route=20,20>24,20;dwell=1500');
      expect(plan, isNotNull);
      expect(plan!.roomName, 'Wizards Tower');
      expect(plan.route, [const Point(20, 20), const Point(24, 20)]);
      expect(plan.dwell, const Duration(milliseconds: 1500));
    });

    test('room alone is a valid plan — standing still is a role', () {
      final plan = AutopilotPlan.parse('room=Foyer');
      expect(plan, isNotNull);
      expect(plan!.route, isEmpty);
      expect(plan.dwell, const Duration(milliseconds: 2000));
    });

    test('a route may have more than two waypoints', () {
      final plan = AutopilotPlan.parse('room=F;route=1,1>2,2>3,3');
      expect(plan!.route, [const Point(1, 1), const Point(2, 2), const Point(3, 3)]);
    });

    test('room matching ignores case and surrounding space', () {
      final plan = AutopilotPlan.parse('room=Wizards Tower')!;
      expect(plan.matchesRoom('  wizards tower '), isTrue);
      expect(plan.matchesRoom('Wizards Towers'), isFalse);
    });

    // Every arm below must return null rather than throw: this parses a build
    // flag at startup, where a typo must not stop the client from running.
    test('malformed specs are refused, not thrown on', () {
      for (final bad in [
        '',                          // no room
        'route=1,1>2,2',             // route without a room
        'room=',                     // empty room name
        'room=F;route=1',            // waypoint missing an ordinate
        'room=F;route=1,2,3',        // waypoint with too many
        'room=F;route=a,b',          // non-numeric ordinates
        'room=F;dwell=0',            // would spin the timer
        'room=F;dwell=-5',
        'room=F;dwell=soon',
        'room=F;colour=blue',        // unknown key
        'roomF',                     // no separator
      ]) {
        expect(AutopilotPlan.parse(bad), isNull, reason: 'should refuse: "$bad"');
      }
    });
  });

  group('AutopilotWalker', () {
    test('walks the route in order and loops', () {
      final moves = <Point<int>>[];
      final walker = AutopilotWalker(
        plan: AutopilotPlan.parse('room=F;route=1,1>2,2>3,3')!,
        moveTo: (x, y) { moves.add(Point(x, y)); return true; },
      );

      for (var i = 0; i < 4; i++) {
        walker.debugStep();
      }

      expect(moves, [
        const Point(1, 1),
        const Point(2, 2),
        const Point(3, 3),
        const Point(1, 1),
      ]);
    });

    test('a single-waypoint route does not start — it is not a walk', () {
      var moves = 0;
      final walker = AutopilotWalker(
        plan: AutopilotPlan.parse('room=F;route=5,5')!,
        moveTo: (_, __) { moves++; return true; },
      );
      walker.start();
      expect(walker.isRunning, isFalse);
      expect(moves, 0);
      walker.stop();
    });

    test('an empty route does not start', () {
      final walker = AutopilotWalker(
        plan: AutopilotPlan.parse('room=F')!,
        moveTo: (_, __) { fail('should not move'); },
      );
      walker.start();
      expect(walker.isRunning, isFalse);
      walker.stop();
    });

    test('start moves immediately rather than waiting out the first dwell',
        () async {
      final moves = <Point<int>>[];
      final walker = AutopilotWalker(
        plan: AutopilotPlan.parse('room=F;route=7,7>8,8;dwell=60000')!,
        moveTo: (x, y) { moves.add(Point(x, y)); return true; },
      );
      walker.start();
      // Without the leading step this would be empty for a full minute — long
      // enough for an operator to conclude the autopilot was not armed.
      expect(moves, [const Point(7, 7)]);
      walker.stop();
    });

    test('start is idempotent — a second call does not add a second timer', () {
      final moves = <Point<int>>[];
      final walker = AutopilotWalker(
        plan: AutopilotPlan.parse('room=F;route=1,1>2,2')!,
        moveTo: (x, y) { moves.add(Point(x, y)); return true; },
      );
      walker.start();
      walker.start();
      expect(moves, [const Point(1, 1)], reason: 'only the first start steps');
      walker.stop();
    });

    test('a refused move is RETRIED, not skipped', () {
      final attempts = <Point<int>>[];
      var accept = false;
      final walker = AutopilotWalker(
        plan: AutopilotPlan.parse('room=F;route=1,1>2,2')!,
        moveTo: (x, y) {
          attempts.add(Point(x, y));
          return accept;
        },
      );

      // The world is not ready: three ticks, all refused, all the SAME cell.
      walker.debugStep();
      walker.debugStep();
      walker.debugStep();
      expect(attempts, [const Point(1, 1), const Point(1, 1), const Point(1, 1)]);
      expect(walker.refusals, 3);

      // Once it accepts, the route advances from where it was — waypoint 1 is
      // not lost. Advancing on refusal is the bug this pins: it would walk the
      // entire route into a world that discarded every step.
      accept = true;
      walker.debugStep();
      walker.debugStep();
      expect(attempts.sublist(3), [const Point(1, 1), const Point(2, 2)]);
      expect(walker.refusals, 0);
    });

    test('refusals reset once a move lands', () {
      var accept = false;
      final walker = AutopilotWalker(
        plan: AutopilotPlan.parse('room=F;route=3,3>4,4')!,
        moveTo: (_, __) => accept,
      );
      walker.debugStep();
      expect(walker.refusals, 1);
      accept = true;
      walker.debugStep();
      expect(walker.refusals, 0);
    });

    test('stop halts the timer', () async {
      final moves = <Point<int>>[];
      final walker = AutopilotWalker(
        plan: AutopilotPlan.parse('room=F;route=1,1>2,2;dwell=10')!,
        moveTo: (x, y) { moves.add(Point(x, y)); return true; },
      );
      walker.start();
      walker.stop();
      final after = moves.length;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(moves.length, after);
      expect(walker.isRunning, isFalse);
    });
  });

  group('Autopilot', () {
    test('is disabled when no AUTOPILOT define was given', () {
      // The suite runs without --dart-define, so this pins the default-off
      // contract: the module must be inert in every ordinary build.
      Autopilot.resetForTest();
      expect(Autopilot.enabled, isFalse);
      expect(Autopilot.plan, isNull);
    });
  });
}
