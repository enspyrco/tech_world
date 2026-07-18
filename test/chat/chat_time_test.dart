import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/chat/chat_time.dart';

void main() {
  // A fixed "now" — mid-afternoon so same-day cases don't straddle midnight.
  final now = DateTime(2026, 7, 18, 15, 30);

  group('formatChatTimestamp', () {
    test('under a minute → Just now', () {
      expect(
        formatChatTimestamp(now.subtract(const Duration(seconds: 59)),
            now: now),
        'Just now',
      );
    });

    test('future timestamp (clock skew) → Just now, not negative', () {
      expect(
        formatChatTimestamp(now.add(const Duration(minutes: 5)), now: now),
        'Just now',
      );
    });

    test('under an hour → N min ago', () {
      expect(
        formatChatTimestamp(now.subtract(const Duration(minutes: 1)),
            now: now),
        '1 min ago',
      );
      expect(
        formatChatTimestamp(now.subtract(const Duration(minutes: 59)),
            now: now),
        '59 min ago',
      );
    });

    test('earlier today (over an hour) → HH:mm', () {
      expect(
        formatChatTimestamp(DateTime(2026, 7, 18, 9, 5), now: now),
        '09:05',
      );
    });

    test('yesterday → Yesterday HH:mm', () {
      expect(
        formatChatTimestamp(DateTime(2026, 7, 17, 23, 59), now: now),
        'Yesterday 23:59',
      );
    });

    test('crossing midnight counts calendar days, not 24h windows', () {
      final justAfterMidnight = DateTime(2026, 7, 18, 0, 1);
      final lateYesterday = DateTime(2026, 7, 17, 22, 0);
      expect(
        formatChatTimestamp(lateYesterday, now: justAfterMidnight),
        'Yesterday 22:00',
      );
    });

    test('this year → D Mon HH:mm', () {
      expect(
        formatChatTimestamp(DateTime(2026, 1, 2, 8, 15), now: now),
        '2 Jan 08:15',
      );
    });

    test('previous year → D Mon YYYY', () {
      expect(
        formatChatTimestamp(DateTime(2025, 12, 31, 8, 15), now: now),
        '31 Dec 2025',
      );
    });
  });

  group('nextTimestampRefresh', () {
    test('relative label schedules a refresh within ~a minute', () {
      final refresh = nextTimestampRefresh(
        now.subtract(const Duration(minutes: 5, seconds: 30)),
        now: now,
      );
      expect(refresh, isNotNull);
      expect(refresh!, lessThanOrEqualTo(const Duration(minutes: 1, seconds: 1)));
      expect(refresh, greaterThan(Duration.zero));
    });

    test('absolute label schedules nothing', () {
      expect(
        nextTimestampRefresh(now.subtract(const Duration(hours: 2)), now: now),
        isNull,
      );
    });
  });
}
