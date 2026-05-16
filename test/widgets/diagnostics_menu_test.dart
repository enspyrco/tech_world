import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tech_world/diagnostics/diagnostics_service.dart';
import 'package:tech_world/widgets/diagnostics_menu.dart';

void main() {
  group('DiagnosticsMenu', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Future<void> pumpMenu(WidgetTester tester, DiagnosticsService svc) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: DiagnosticsMenu(diagnostics: svc)),
          ),
        ),
      );
    }

    testWidgets('renders a popup trigger with the bug icon', (tester) async {
      final svc = DiagnosticsService(
        avEnabled: false,
        errorLoggingEnabled: false,
      );
      addTearDown(svc.dispose);

      await pumpMenu(tester, svc);

      expect(find.byIcon(Icons.bug_report), findsOneWidget);
    });

    testWidgets('flipping AV toggle updates the service and the checkmark',
        (tester) async {
      final svc = DiagnosticsService(
        avEnabled: false,
        errorLoggingEnabled: false,
      );
      addTearDown(svc.dispose);

      await pumpMenu(tester, svc);

      // Open the menu.
      await tester.tap(find.byIcon(Icons.bug_report));
      await tester.pumpAndSettle();

      // Read initial state from the menu items.
      final avItem = tester.widget<CheckedPopupMenuItem<String>>(
        find.widgetWithText(CheckedPopupMenuItem<String>, 'AV diagnostics'),
      );
      expect(avItem.checked, isFalse);
      expect(svc.avEnabled.value, isFalse);

      // Flip it.
      await tester.tap(find.text('AV diagnostics'), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Service updated.
      expect(svc.avEnabled.value, isTrue);

      // Re-open and confirm the checkmark reflects the new state.
      await tester.tap(find.byIcon(Icons.bug_report));
      await tester.pumpAndSettle();
      final avItem2 = tester.widget<CheckedPopupMenuItem<String>>(
        find.widgetWithText(CheckedPopupMenuItem<String>, 'AV diagnostics'),
      );
      expect(avItem2.checked, isTrue);
    });

    testWidgets('flipping error-logging toggle updates the service',
        (tester) async {
      final svc = DiagnosticsService(
        avEnabled: false,
        errorLoggingEnabled: false,
      );
      addTearDown(svc.dispose);

      await pumpMenu(tester, svc);

      await tester.tap(find.byIcon(Icons.bug_report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Error logging'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(svc.errorLoggingEnabled.value, isTrue);
      expect(svc.avEnabled.value, isFalse);
    });

    testWidgets('external service changes propagate to the trigger styling',
        (tester) async {
      final svc = DiagnosticsService(
        avEnabled: false,
        errorLoggingEnabled: false,
      );
      addTearDown(svc.dispose);

      await pumpMenu(tester, svc);

      // Initially both off — icon uses the muted color.
      final initialIcon = tester.widget<Icon>(find.byIcon(Icons.bug_report));
      expect(initialIcon.color, Colors.white70);

      // External flip (not via the menu) — bind should react.
      await svc.setAvEnabled(true);
      await tester.pumpAndSettle();

      final litIcon = tester.widget<Icon>(find.byIcon(Icons.bug_report));
      expect(litIcon.color, Colors.amber.shade300);
    });
  });
}
