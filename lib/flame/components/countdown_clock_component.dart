import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/timer/countdown_timer_state.dart';

/// A countdown clock that lives *in the world*, not on the UI overlay.
///
/// Tech World's design rule is "the world is the listener / the world is the
/// thing" — a shared timer that everyone can see should read as part of the
/// room, a clock on the wall that the whole table watches, not a HUD chip that
/// floats above each player's private screen. This component renders the same
/// `mm:ss` the [_TimerOverlay] shows, but positioned in world space so it sorts
/// with the other world entities and the camera moves over it.
///
/// It is purely a *view* of [CountdownTimerState]: it owns no countdown logic
/// and never mutates the state. It listens to the state (and the alarm flag) to
/// repaint, and toggles its own visibility — hidden when idle, the time while
/// counting down, a "time's up" face while the alarm is active.
///
/// Placement: today it is positioned by whoever adds it (TechWorld drops it at
/// a sensible default near the room spawn). Map-editor placement of the clock
/// is a deferred design question (owned by Nick) — this component deliberately
/// carries no editor affordance.
class CountdownClockComponent extends PositionComponent {
  CountdownClockComponent({
    required this.state,
    required this.alarmActive,
    required Vector2 position,
  }) : super(
          position: position,
          // Two grid squares wide, one tall — a small wall clock.
          size: Vector2(gridSquareSizeDouble * 2, gridSquareSizeDouble),
          anchor: Anchor.topLeft,
        );

  /// The shared countdown this clock displays. The component reads it; it never
  /// writes. Lifecycle (start/cancel/tick) is owned by `TimerService`.
  final CountdownTimerState state;

  /// Whether the alarm/banner is currently active (countdown reached zero).
  /// Drives the "time's up" face that persists after [state] stops running.
  final ValueListenable<bool> alarmActive;

  /// Y-based depth sorting — same convention as doors, players, occlusion.
  @override
  int get priority => position.y.toInt();

  static final _bgPaint = Paint()..color = const Color(0xFF1A2A3E);
  static final _borderPaint = Paint()
    ..color = const Color(0xFF44AAFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  static final _alarmBgPaint = Paint()..color = const Color(0xFF3E1A1A);
  static final _alarmBorderPaint = Paint()
    ..color = const Color(0xFFFF4444)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  static const _textColor = Color(0xFFCCE6FF);
  static const _alarmTextColor = Color(0xFFFFCCCC);

  void _onChanged() {
    _syncVisibility();
  }

  /// Visible while counting down OR while the alarm banner is up; hidden when
  /// fully idle so an empty clock doesn't clutter the room.
  void _syncVisibility() {
    final shouldShow = state.running || alarmActive.value;
    // PositionComponent has no built-in "visible"; we gate rendering directly
    // (see render). Marking the component for a repaint is implicit in Flame's
    // render loop, so all we track here is the boolean.
    _visible = shouldShow;
  }

  bool _visible = false;

  /// Whether the clock is currently drawn — true while counting down or while
  /// the alarm banner is active, false when idle. Exposed for tests so the
  /// listener wiring can be asserted through observable behaviour.
  @visibleForTesting
  bool get isVisible => _visible;

  @override
  Future<void> onLoad() async {
    state.addListener(_onChanged);
    alarmActive.addListener(_onChanged);
    _syncVisibility();
  }

  @override
  void onRemove() {
    state.removeListener(_onChanged);
    alarmActive.removeListener(_onChanged);
    super.onRemove();
  }

  @override
  void render(Canvas canvas) {
    if (!_visible) return;

    final finished = !state.running && alarmActive.value;
    final rect = Rect.fromLTWH(2, 2, size.x - 4, size.y - 4);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

    canvas.drawRRect(rrect, finished ? _alarmBgPaint : _bgPaint);
    canvas.drawRRect(rrect, finished ? _alarmBorderPaint : _borderPaint);

    final label = finished ? "TIME'S UP" : state.formatted;
    final style = ui.TextStyle(
      color: finished ? _alarmTextColor : _textColor,
      fontSize: finished ? 11 : 18,
      fontWeight: FontWeight.bold,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
    final paragraph = (ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center,
    ))
          ..pushStyle(style)
          ..addText(label))
        .build()
      ..layout(ui.ParagraphConstraints(width: size.x));
    canvas.drawParagraph(
      paragraph,
      Offset(0, (size.y - paragraph.height) / 2),
    );
  }
}
