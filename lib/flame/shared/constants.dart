import 'dart:ui';

const int gridSize = 50;
const int gridSquareSize = 32;
const double gridSquareSizeDouble = 32;

/// Stride between depth-sort rows for Flame component priority.
///
/// Priorities are `row * kPriorityStride + tieBreaker` where tieBreaker is
/// in [0, kPriorityStride). Must be large enough that bubbles (+1) never
/// cross the row boundary: kPriorityStride > 1. Using 1000 leaves 999 slots
/// for intra-row ordering.
const int kPriorityStride = 1000;

/// Gold accent used for completed-challenge indicators (terminals, editor
/// badge, etc.).
const Color completedGold = Color(0xFFFFD700);
