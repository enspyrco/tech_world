import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:tech_world/widgets/wire_states.dart';

/// Animated circuit-board visualization showing room-join progress.
///
/// Five wires are drawn as horizontal polylines with branch/merge junctions
/// matching the dependency graph of the join operations:
///
/// ```
///   Tilesets ──────────────────────────────────────┐
///   Server  ─────────────┬── Camera ──┐            ├── Ready
///                        └── Chat ────┤            │
///   Game    ──────────────────────────────────────┘
/// ```
///
/// Each wire lights up with a travelling spark when active and a steady glow
/// when complete. Junction nodes fill when all feeding wires are done.
class CircuitBoardProgress extends StatefulWidget {
  const CircuitBoardProgress({required this.wireStates, super.key});

  final WireStates wireStates;

  @override
  State<CircuitBoardProgress> createState() => _CircuitBoardProgressState();
}

class _CircuitBoardProgressState extends State<CircuitBoardProgress>
    with TickerProviderStateMixin {
  late final Map<Wire, AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final wire in Wire.values)
        wire: AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1500),
        ),
    };
    widget.wireStates.addListener(_onStateChanged);
    // Kick off any wires already active at build time.
    _onStateChanged();
  }

  @override
  void didUpdateWidget(CircuitBoardProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wireStates != widget.wireStates) {
      oldWidget.wireStates.removeListener(_onStateChanged);
      widget.wireStates.addListener(_onStateChanged);
      _onStateChanged();
    }
  }

  @override
  void dispose() {
    widget.wireStates.removeListener(_onStateChanged);
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onStateChanged() {
    for (final wire in Wire.values) {
      final status = widget.wireStates[wire];
      final controller = _controllers[wire]!;
      if (status == WireStatus.active && !controller.isAnimating) {
        controller.repeat();
      } else if (status == WireStatus.complete || status == WireStatus.error) {
        // Jump to end to show a fully-lit wire.
        controller.stop();
        controller.value = 1.0;
      }
    }
    // Trigger repaint.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(_controllers.values.toList()),
      builder: (context, _) {
        return CustomPaint(
          painter: _CircuitBoardPainter(
            wireStates: widget.wireStates,
            sparkPositions: {
              for (final wire in Wire.values)
                wire: _controllers[wire]!.value,
            },
          ),
          size: const Size(400, 200),
        );
      },
    );
  }
}

/// Renders the PCB traces, sparks, glows, labels, and junction nodes.
class _CircuitBoardPainter extends CustomPainter {
  _CircuitBoardPainter({
    required this.wireStates,
    required this.sparkPositions,
  });

  final WireStates wireStates;
  final Map<Wire, double> sparkPositions;

  // Layout constants (fraction of canvas width / height).
  static const double _leftMargin = 0.10;
  static const double _rightMargin = 0.90;
  static const double _branchX = 0.45; // where server splits into camera/chat
  static const double _mergeX = 0.72; // where camera/chat merge back
  static const double _finalMergeX = 0.82; // where all 5 wires converge

  // Colors
  static const Color _dimColor = Color(0xFF1A3A2E);
  static const Color _activeColor = Color(0xFF4ADE80);
  static const Color _errorColor = Color(0xFFEF4444);
  static const Color _sparkColor = Colors.white;
  static const Color _labelColor = Color(0xFF94A3B8);

  // Wire vertical positions (fraction of canvas height).
  double _wireY(Wire wire, Size size) {
    return switch (wire) {
      Wire.tilesets => size.height * 0.18,
      Wire.server => size.height * 0.38,
      Wire.camera => size.height * 0.50,
      Wire.chat => size.height * 0.62,
      Wire.gameReady => size.height * 0.82,
    };
  }

  /// Build the polyline points for a given wire.
  List<Offset> _wirePoints(Wire wire, Size size) {
    final y = _wireY(wire, size);
    final left = size.width * _leftMargin;
    final right = size.width * _rightMargin;
    final branchX = size.width * _branchX;
    final mergeX = size.width * _mergeX;
    final finalMerge = size.width * _finalMergeX;
    final readyX = right;
    final readyY = size.height * 0.50;

    return switch (wire) {
      // Straight across, then angle to merge point, then to Ready.
      Wire.tilesets => [
          Offset(left, y),
          Offset(finalMerge, y),
          Offset(readyX, readyY),
        ],
      // Straight to branch point.
      Wire.server => [
          Offset(left, y),
          Offset(branchX, y),
        ],
      // From branch point down to camera Y, across to merge, then to final merge.
      Wire.camera => [
          Offset(branchX, _wireY(Wire.server, size)),
          Offset(branchX + size.width * 0.03, y),
          Offset(mergeX, y),
          Offset(finalMerge, _wireY(Wire.tilesets, size)),
          Offset(readyX, readyY),
        ],
      // From branch point down to chat Y, across to merge.
      Wire.chat => [
          Offset(branchX, _wireY(Wire.server, size)),
          Offset(branchX + size.width * 0.03, y),
          Offset(mergeX, y),
          Offset(finalMerge, _wireY(Wire.gameReady, size)),
          Offset(readyX, readyY),
        ],
      // Straight across, then angle to merge point, then to Ready.
      Wire.gameReady => [
          Offset(left, y),
          Offset(finalMerge, y),
          Offset(readyX, readyY),
        ],
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Draw each wire.
    for (final wire in Wire.values) {
      _drawWire(canvas, size, wire);
    }

    // Draw junction nodes.
    _drawJunction(canvas, size, size.width * _branchX,
        _wireY(Wire.server, size), [Wire.server]);
    _drawJunction(canvas, size, size.width * _mergeX,
        _wireY(Wire.camera, size), [Wire.camera, Wire.chat]);
    _drawJunction(canvas, size, size.width * _finalMergeX,
        size.height * 0.50, Wire.values.toList());

    // Draw labels.
    _drawLabel(canvas, size, 'Tilesets', Wire.tilesets, isLeft: true);
    _drawLabel(canvas, size, 'Server', Wire.server, isLeft: true);
    _drawLabel(canvas, size, 'Camera', Wire.camera, isLeft: false,
        xOffset: size.width * (_branchX + 0.05));
    _drawLabel(canvas, size, 'Chat', Wire.chat, isLeft: false,
        xOffset: size.width * (_branchX + 0.05));
    _drawLabel(canvas, size, 'Game', Wire.gameReady, isLeft: true);

    // "Ready" label at the end.
    _drawReadyLabel(canvas, size);
  }

  void _drawWire(Canvas canvas, Size size, Wire wire) {
    final points = _wirePoints(wire, size);
    if (points.length < 2) return;

    final status = wireStates[wire];
    final isComplete = status == WireStatus.complete;
    final isActive = status == WireStatus.active;
    final isError = status == WireStatus.error;

    // Dim base trace.
    final dimPaint = Paint()
      ..color = _dimColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, dimPaint);

    // Glow trace when complete.
    if (isComplete || isError) {
      final glowColor = isError ? _errorColor : _activeColor;
      final glowPaint = Paint()
        ..color = glowColor
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 4);
      canvas.drawPath(path, glowPaint);

      final solidPaint = Paint()
        ..color = glowColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, solidPaint);
    }

    // Travelling spark when active.
    if (isActive) {
      final t = sparkPositions[wire] ?? 0.0;
      final sparkPos = _interpolateAlongPath(points, t);

      // Green partial trace up to spark position.
      final partialPath = _partialPath(points, t);
      final partialPaint = Paint()
        ..color = _activeColor.withValues(alpha: 0.6)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(partialPath, partialPaint);

      // Spark dot with glow.
      canvas.drawCircle(
        sparkPos,
        5,
        Paint()
          ..color = _sparkColor.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawCircle(
        sparkPos,
        3,
        Paint()..color = _sparkColor,
      );
    }
  }

  /// Interpolate a position along the polyline at parameter [t] ∈ [0, 1].
  Offset _interpolateAlongPath(List<Offset> points, double t) {
    if (points.length < 2) return points.first;

    // Compute cumulative segment lengths.
    final segLengths = <double>[];
    var totalLength = 0.0;
    for (var i = 1; i < points.length; i++) {
      final len = (points[i] - points[i - 1]).distance;
      segLengths.add(len);
      totalLength += len;
    }
    if (totalLength == 0) return points.first;

    final targetDist = t * totalLength;
    var accumulated = 0.0;
    for (var i = 0; i < segLengths.length; i++) {
      if (accumulated + segLengths[i] >= targetDist) {
        final segT = (targetDist - accumulated) / segLengths[i];
        return Offset.lerp(points[i], points[i + 1], segT)!;
      }
      accumulated += segLengths[i];
    }
    return points.last;
  }

  /// Build a partial path from the start of [points] up to parameter [t].
  Path _partialPath(List<Offset> points, double t) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    if (points.length < 2) return path;

    final segLengths = <double>[];
    var totalLength = 0.0;
    for (var i = 1; i < points.length; i++) {
      final len = (points[i] - points[i - 1]).distance;
      segLengths.add(len);
      totalLength += len;
    }
    if (totalLength == 0) return path;

    final targetDist = t * totalLength;
    var accumulated = 0.0;
    for (var i = 0; i < segLengths.length; i++) {
      if (accumulated + segLengths[i] >= targetDist) {
        final segT = (targetDist - accumulated) / segLengths[i];
        final p = Offset.lerp(points[i], points[i + 1], segT)!;
        path.lineTo(p.dx, p.dy);
        return path;
      }
      path.lineTo(points[i + 1].dx, points[i + 1].dy);
      accumulated += segLengths[i];
    }
    return path;
  }

  /// Draw a junction node that lights up when all [requiredWires] are complete.
  void _drawJunction(
    Canvas canvas,
    Size size,
    double x,
    double y,
    List<Wire> requiredWires,
  ) {
    final allDone =
        requiredWires.every((w) => wireStates[w] == WireStatus.complete);
    final anyActive =
        requiredWires.any((w) => wireStates[w] == WireStatus.active);

    final color =
        allDone ? _activeColor : (anyActive ? _activeColor.withValues(alpha: 0.4) : _dimColor);

    if (allDone) {
      // Glow
      canvas.drawCircle(
        Offset(x, y),
        6,
        Paint()
          ..color = _activeColor.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    // Filled circle.
    canvas.drawCircle(
      Offset(x, y),
      4,
      Paint()..color = color,
    );

    // Ring.
    canvas.drawCircle(
      Offset(x, y),
      4,
      Paint()
        ..color = allDone ? _activeColor : _dimColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawLabel(
    Canvas canvas,
    Size size,
    String text,
    Wire wire, {
    required bool isLeft,
    double? xOffset,
  }) {
    final status = wireStates[wire];
    final color = switch (status) {
      WireStatus.complete => _activeColor,
      WireStatus.active => Colors.white,
      WireStatus.error => _errorColor,
      WireStatus.pending => _labelColor,
    };

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight:
              status == WireStatus.complete ? FontWeight.w600 : FontWeight.w400,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    final y = _wireY(wire, size) - tp.height / 2;
    final x = xOffset ?? (isLeft ? size.width * _leftMargin - tp.width - 8 : 0);
    tp.paint(canvas, Offset(x, y));
  }

  void _drawReadyLabel(Canvas canvas, Size size) {
    final allDone = wireStates.allComplete;
    final color = allDone ? _activeColor : _labelColor;

    final tp = TextPainter(
      text: TextSpan(
        text: 'Ready',
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    final x = size.width * _rightMargin + 10;
    final y = size.height * 0.50 - tp.height / 2;
    tp.paint(canvas, Offset(x, y));

    if (allDone) {
      // Pulse glow behind "Ready".
      canvas.drawCircle(
        Offset(size.width * _rightMargin, size.height * 0.50),
        8,
        Paint()
          ..color = _activeColor.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
  }

  @override
  bool shouldRepaint(_CircuitBoardPainter oldDelegate) => true;
}
