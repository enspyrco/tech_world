import 'package:flutter/material.dart';
import 'package:tech_world/widgets/circuit_board_progress.dart';
import 'package:tech_world/widgets/wire_states.dart';

/// Full-screen overlay shown during room join, rendering the circuit-board
/// progress animation over a dark background.
///
/// The parent controls visibility via [visible] — when it flips to `false`
/// the overlay fades out over 400 ms and then stops painting entirely.
class JoinOverlay extends StatelessWidget {
  const JoinOverlay({
    required this.wireStates,
    required this.roomName,
    required this.visible,
    super.key,
  });

  final WireStates wireStates;
  final String roomName;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        child: Container(
          color: const Color(0xFF1A1A2E),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  roomName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Connecting\u2026',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: 400,
                  height: 200,
                  child: CircuitBoardProgress(wireStates: wireStates),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
