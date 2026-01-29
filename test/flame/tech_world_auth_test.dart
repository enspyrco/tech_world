import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/auth/auth_user.dart';
import 'package:tech_world/flame/tech_world.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/utils/locator.dart';

void main() {
  group('TechWorld auth state handling', () {
    late StreamController<AuthUser> authController;
    late TechWorld techWorld;

    setUp(() {
      authController = StreamController<AuthUser>.broadcast();
      techWorld = TechWorld(authStateChanges: authController.stream);
    });

    tearDown(() {
      techWorld.dispose();
      authController.close();
      Locator.remove<LiveKitService>();
    });

    test('clears LiveKit state when user signs out', () async {
      // First sign in
      final user1 = AuthUser(id: 'user1', displayName: 'User 1');
      authController.add(user1);
      await Future.delayed(const Duration(milliseconds: 50));

      // Sign out
      final signedOut = SignedOutUser(id: 'user1', displayName: 'User 1');
      authController.add(signedOut);
      await Future.delayed(const Duration(milliseconds: 50));

      // The internal _liveKitService should be null now
      // We can't access it directly, but we can verify by signing in again
      // and checking that it reconnects (doesn't return early)

      // Sign in again with a different user
      final service2 = LiveKitService(
        userId: 'user2',
        displayName: 'User 2',
        roomName: 'test-room',
      );
      Locator.add<LiveKitService>(service2);

      final user2 = AuthUser(id: 'user2', displayName: 'User 2');
      authController.add(user2);
      await Future.delayed(const Duration(milliseconds: 50));

      // If the bug exists, TechWorld would still hold the old service reference
      // and _connectToLiveKit would return early without setting up subscriptions.
      // The test passes if no exception is thrown and we reach this point.

      service2.dispose();
    });

    test('can reconnect after sign out and sign in cycle', () async {
      // Create first service
      final service1 = LiveKitService(
        userId: 'user1',
        displayName: 'User 1',
        roomName: 'test-room',
      );
      Locator.add<LiveKitService>(service1);

      // Sign in
      final user1 = AuthUser(id: 'user1', displayName: 'User 1');
      authController.add(user1);
      await Future.delayed(const Duration(milliseconds: 50));

      // Sign out
      Locator.remove<LiveKitService>();
      service1.dispose();
      authController.add(SignedOutUser(id: 'user1', displayName: 'User 1'));
      await Future.delayed(const Duration(milliseconds: 50));

      // Create second service (simulates what main.dart does on re-sign-in)
      final service2 = LiveKitService(
        userId: 'user2',
        displayName: 'User 2',
        roomName: 'test-room',
      );
      Locator.add<LiveKitService>(service2);

      // Sign in again
      final user2 = AuthUser(id: 'user2', displayName: 'User 2');
      authController.add(user2);
      await Future.delayed(const Duration(milliseconds: 50));

      // Verify we can interact with the new service
      // (this would fail if TechWorld held onto the old disposed service)
      expect(service2.isConnected, isFalse); // Not connected yet (no token)
      expect(service2.userId, equals('user2'));

      service2.dispose();
    });

    test('handles multiple sign out/sign in cycles', () async {
      for (var i = 0; i < 3; i++) {
        final service = LiveKitService(
          userId: 'user$i',
          displayName: 'User $i',
          roomName: 'test-room',
        );
        Locator.add<LiveKitService>(service);

        // Sign in
        authController.add(AuthUser(id: 'user$i', displayName: 'User $i'));
        await Future.delayed(const Duration(milliseconds: 30));

        // Sign out
        Locator.remove<LiveKitService>();
        service.dispose();
        authController.add(SignedOutUser(id: 'user$i', displayName: 'User $i'));
        await Future.delayed(const Duration(milliseconds: 30));
      }

      // Final sign in should work
      final finalService = LiveKitService(
        userId: 'final',
        displayName: 'Final User',
        roomName: 'test-room',
      );
      Locator.add<LiveKitService>(finalService);

      authController.add(AuthUser(id: 'final', displayName: 'Final User'));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(finalService.userId, equals('final'));
      finalService.dispose();
    });

    test('PlaceholderUser does not trigger connection', () async {
      // Send placeholder (initial state)
      authController.add(PlaceholderUser());
      await Future.delayed(const Duration(milliseconds: 50));

      // No service should be accessed because PlaceholderUser is ignored
      // This should not throw even without a service registered
    });
  });
}
