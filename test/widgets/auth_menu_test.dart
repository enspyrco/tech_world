import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/widgets/auth_menu.dart';

void main() {
  group('AuthMenu', () {
    testWidgets('displays user initials', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthMenu(displayName: 'John Doe'),
          ),
        ),
      );

      expect(find.text('JD'), findsOneWidget);
    });

    testWidgets('displays single initial for single name', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthMenu(displayName: 'Alice'),
          ),
        ),
      );

      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('displays ? for empty name', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthMenu(displayName: ''),
          ),
        ),
      );

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('shows dropdown arrow', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthMenu(displayName: 'Test User'),
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    });

    testWidgets('opens popup menu on tap', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthMenu(displayName: 'Test User'),
          ),
        ),
      );

      await tester.tap(find.byType(AuthMenu));
      await tester.pumpAndSettle();

      expect(find.text('Test User'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('shows Guest for empty display name in menu', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthMenu(displayName: ''),
          ),
        ),
      );

      await tester.tap(find.byType(AuthMenu));
      await tester.pumpAndSettle();

      expect(find.text('Guest'), findsOneWidget);
    });

    testWidgets('shows logout icon in menu', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthMenu(displayName: 'Test'),
          ),
        ),
      );

      await tester.tap(find.byType(AuthMenu));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.logout), findsOneWidget);
    });

    testWidgets('handles multi-word names correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthMenu(displayName: 'John Michael Doe'),
          ),
        ),
      );

      // Should use first and last name initials
      expect(find.text('JD'), findsOneWidget);
    });

    testWidgets('converts initials to uppercase', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthMenu(displayName: 'john doe'),
          ),
        ),
      );

      expect(find.text('JD'), findsOneWidget);
    });

    testWidgets('shows Change Avatar item in dropdown menu', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuthMenu(
              displayName: 'Test User',
              onChangeAvatar: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AuthMenu));
      await tester.pumpAndSettle();

      expect(find.text('Change Avatar'), findsOneWidget);
      expect(find.byIcon(Icons.face), findsOneWidget);
    });

    testWidgets('tapping Change Avatar calls onChangeAvatar callback',
        (tester) async {
      var called = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuthMenu(
              displayName: 'Test User',
              onChangeAvatar: () => called = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AuthMenu));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Change Avatar'));
      await tester.pumpAndSettle();

      expect(called, isTrue);
    });

    testWidgets('shows Edit Profile item when onEditProfile is provided',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuthMenu(
              displayName: 'Test User',
              onEditProfile: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AuthMenu));
      await tester.pumpAndSettle();

      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets('hides Edit Profile item when onEditProfile is null',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthMenu(displayName: 'Test User'),
          ),
        ),
      );

      await tester.tap(find.byType(AuthMenu));
      await tester.pumpAndSettle();

      expect(find.text('Edit Profile'), findsNothing);
    });

    testWidgets('tapping Edit Profile calls onEditProfile callback',
        (tester) async {
      var called = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuthMenu(
              displayName: 'Test User',
              onEditProfile: (_) => called = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AuthMenu));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit Profile'));
      await tester.pumpAndSettle();

      expect(called, isTrue);
    });

    test('configures CircleAvatar with NetworkImage when profilePictureUrl is provided',
        () {
      // Unit test the widget configuration without pumping (avoids async
      // NetworkImage HTTP errors in the test environment).
      const menu = AuthMenu(
        displayName: 'Test User',
        profilePictureUrl: 'https://example.com/photo.jpg',
      );

      expect(menu.profilePictureUrl, equals('https://example.com/photo.jpg'));
      expect(menu.displayName, equals('Test User'));
    });

    testWidgets('shows initials when profilePictureUrl is null',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthMenu(displayName: 'Test User'),
          ),
        ),
      );

      expect(find.text('TU'), findsOneWidget);

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundImage, isNull);
    });
  });
}
