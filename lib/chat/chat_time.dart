/// Compact, locale-free timestamp formatting for chat bubbles.
///
/// Group chat rehydrates from Firestore, so a message list routinely spans
/// days — "14:05" alone is ambiguous the morning after. The format is
/// relative while fresh (Andy's feature request: "if recent then say
/// 'N minutes ago'") and degrades gracefully with age:
///
/// - under a minute   → `Just now`
/// - under an hour    → `5 min ago`
/// - today            → `14:05`
/// - yesterday        → `Yesterday 14:05`
/// - this year        → `12 Jul 14:05`
/// - older            → `12 Jul 2025`
///
/// Hand-rolled (no `intl` dependency) — month abbreviations are a fixed
/// 12-entry table, and times render 24-hour zero-padded.
library;

import 'dart:async';

import 'package:flutter/material.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Format [timestamp] for display on a chat bubble, relative to [now].
///
/// [now] defaults to the wall clock; tests inject a fixed value. Day
/// comparison is by calendar day (local time), not 24-hour windows, so 23:59
/// vs 00:01 counts as "yesterday". A clock-skewed future timestamp (another
/// device's clock running ahead) renders as `Just now` rather than a negative
/// age.
String formatChatTimestamp(DateTime timestamp, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final local = timestamp.toLocal();

  final age = ref.difference(local);
  if (age.inMinutes < 1) return 'Just now';
  if (age.inMinutes < 60) return '${age.inMinutes} min ago';

  final day = DateTime(local.year, local.month, local.day);
  final today = DateTime(ref.year, ref.month, ref.day);
  final dayDiff = today.difference(day).inDays;

  if (dayDiff <= 0) return _hhmm(local);
  if (dayDiff == 1) return 'Yesterday ${_hhmm(local)}';
  if (local.year == ref.year) {
    return '${local.day} ${_months[local.month - 1]} ${_hhmm(local)}';
  }
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// How long until the label for [timestamp] could change, measured from [now].
///
/// Relative labels ("Just now", "5 min ago") tick over on minute boundaries of
/// the message's age; absolute labels never change (the day-boundary flips at
/// midnight are not worth a scheduled rebuild — any interaction rebuilds the
/// list anyway). Returns `null` once the label is absolute.
Duration? nextTimestampRefresh(DateTime timestamp, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final age = ref.difference(timestamp.toLocal());
  if (age.inMinutes >= 60) return null;
  // Clock-skewed future timestamp: it renders "Just now" and stays that way
  // until real time catches up — just check again in a minute rather than
  // computing a remainder of a negative age.
  if (age.isNegative) return const Duration(minutes: 1, seconds: 1);
  // Align to the next minute boundary of the message's age (+1s of slack so
  // the rebuild lands after the boundary, never on it).
  final intoMinute = Duration(
      microseconds: age.inMicroseconds % Duration.microsecondsPerMinute);
  return const Duration(minutes: 1, seconds: 1) - intoMinute;
}

/// The terse age form used by list rows (DM conversation tiles): `now`, `5m`,
/// `2h`, `3d`. Same clock semantics as [formatChatTimestamp] — future skew
/// renders as `now` — but a compact vocabulary for space-tight rows. Lives
/// here so the app has one home for relative-time bucketing.
String formatCompactAge(DateTime time, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final diff = ref.difference(time.toLocal());
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  return '${diff.inDays}d';
}

/// A chat-bubble timestamp label that keeps itself fresh.
///
/// While the label is relative ("Just now", "5 min ago") a one-shot timer is
/// scheduled for the next minute boundary; once the label goes absolute the
/// timer chain stops. One idle timer per visible bubble — the message lists
/// are `ListView.builder`s, so off-screen bubbles aren't mounted and carry no
/// timer.
class ChatTimestamp extends StatefulWidget {
  const ChatTimestamp({required this.timestamp, this.style, super.key});

  final DateTime timestamp;
  final TextStyle? style;

  @override
  State<ChatTimestamp> createState() => _ChatTimestampState();
}

class _ChatTimestampState extends State<ChatTimestamp> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant ChatTimestamp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timestamp != widget.timestamp) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final delay = nextTimestampRefresh(widget.timestamp);
    if (delay == null) return;
    _timer = Timer(delay, () {
      if (mounted) setState(_schedule);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      formatChatTimestamp(widget.timestamp),
      style: widget.style ??
          TextStyle(color: Colors.grey[600], fontSize: 10),
    );
  }
}
