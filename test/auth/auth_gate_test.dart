import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/auth/auth_gate.dart';

void main() {
  group('AuthGate', () {
    testWidgets('password field has textInputAction.go for Enter submit',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AuthGate()));

      // The password field is the TextField with obscureText: true.
      final passwordTextField = find.byWidgetPredicate(
        (w) => w is TextField && w.obscureText,
      );
      expect(passwordTextField, findsOneWidget,
          reason: 'Should have an obscured password TextField');

      final widget = tester.widget<TextField>(passwordTextField);
      expect(widget.textInputAction, TextInputAction.go,
          reason: 'Password field should use TextInputAction.go '
              'so Enter submits the form');
    });

    testWidgets('password field has onSubmitted callback', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AuthGate()));

      final passwordTextField = find.byWidgetPredicate(
        (w) => w is TextField && w.obscureText,
      );
      final widget = tester.widget<TextField>(passwordTextField);
      expect(widget.onSubmitted, isNotNull,
          reason: 'Password field must have onSubmitted '
              'so pressing Enter triggers sign-in');
    });
  });
}
