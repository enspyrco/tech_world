import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/countdown_clock_component.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/timer/countdown_timer_state.dart';

void main() {
  group('CountdownClockComponent', () {
    late CountdownTimerState state;
    late ValueNotifier<bool> alarmActive;
    late DateTime now;

    CountdownClockComponent build({Vector2? position}) =>
        CountdownClockComponent(
          state: state,
          alarmActive: alarmActive,
          position: position ?? Vector2.zero(),
        );

    setUp(() {
      now = DateTime.fromMillisecondsSinceEpoch(0);
      state = CountdownTimerState(now: () => now);
      alarmActive = ValueNotifier<bool>(false);
    });

    tearDown(() {
      state.dispose();
      alarmActive.dispose();
    });

    test('is a world PositionComponent at the given position', () {
      final clock = build(position: Vector2(96, 128));
      expect(clock, isA<PositionComponent>());
      expect(clock.position.x, 96);
      expect(clock.position.y, 128);
    });

    test('priority tracks y for depth sorting like other world entities', () {
      final clock = build(position: Vector2(0, 200));
      expect(clock.priority, 200);
    });

    test('spans two grid squares wide by one tall', () {
      final clock = build();
      expect(clock.size.x, gridSquareSizeDouble * 2);
      expect(clock.size.y, gridSquareSizeDouble);
    });

    test('reads the shared state without mutating it', () {
      final clock = build();
      state.start(90);
      // The component is a pure view — it does not change running/remaining.
      expect(state.running, isTrue);
      expect(clock.state, same(state));
    });

    test('hidden when idle, shown while counting down', () async {
      final clock = build();
      await clock.onLoad();
      expect(clock.isVisible, isFalse);

      state.start(60);
      expect(clock.isVisible, isTrue);

      state.cancel();
      expect(clock.isVisible, isFalse);
    });

    test('stays visible while the alarm banner is active after finishing',
        () async {
      final clock = build();
      await clock.onLoad();

      state.start(1);
      alarmActive.value = true; // service flips this when the timer finishes
      now = now.add(const Duration(seconds: 1));
      state.tick(); // running -> false, but alarm still active
      expect(state.running, isFalse);
      expect(clock.isVisible, isTrue);

      alarmActive.value = false; // dismissed
      expect(clock.isVisible, isFalse);
    });

    test('after remove, state changes no longer toggle visibility', () async {
      final clock = build();
      await clock.onLoad();
      clock.onRemove();

      // If the listener were still attached this would flip isVisible true.
      state.start(60);
      expect(clock.isVisible, isFalse);
    });

    test('caches the laid-out paragraph: rebuilds only when the label changes',
        () async {
      final clock = build();
      await clock.onLoad();
      state.start(120); // visible, label "02:00"

      void renderFrame() => clock.render(Canvas(PictureRecorder()));

      renderFrame(); // first build
      expect(clock.paragraphBuildCount, 1);

      // Several frames at the same displayed second — no rebuild.
      renderFrame();
      renderFrame();
      expect(clock.paragraphBuildCount, 1);

      // Advance past a whole second so the formatted label changes.
      now = now.add(const Duration(seconds: 1));
      state.tick(); // label now "01:59"
      renderFrame();
      expect(clock.paragraphBuildCount, 2);
    });
  });
}
