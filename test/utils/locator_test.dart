import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/utils/locator.dart';

void main() {
  tearDown(() {
    // Reset locator state between tests by adding null placeholders
    // This is a workaround since Locator doesn't expose a reset method
  });

  group('Locator', () {
    test('add and locate returns the same object', () {
      final testObject = _TestService('test');
      Locator.add<_TestService>(testObject);

      final located = locate<_TestService>();
      expect(located, same(testObject));
      expect(located.name, equals('test'));
    });

    test('locate throws when type not registered', () {
      expect(
        () => locate<_UnregisteredService>(),
        throwsA(contains('You attempted to locate an object with type')),
      );
    });

    test('add with overwrite true replaces existing object', () {
      final first = _TestService('first');
      final second = _TestService('second');

      Locator.add<_TestService>(first);
      Locator.add<_TestService>(second, overwrite: true);

      final located = locate<_TestService>();
      expect(located.name, equals('second'));
    });

    test('add with overwrite false throws when type already registered', () {
      final first = _TestService('first');
      final second = _TestService('second');

      Locator.add<_TestService>(first);

      expect(
        () => Locator.add<_TestService>(second, overwrite: false),
        throwsA(contains('type that has already been added')),
      );
    });

    test('can register multiple different types', () {
      final service1 = _TestService('service1');
      final service2 = _AnotherService(42);

      Locator.add<_TestService>(service1);
      Locator.add<_AnotherService>(service2);

      expect(locate<_TestService>().name, equals('service1'));
      expect(locate<_AnotherService>().value, equals(42));
    });

    test('remove removes registered object', () {
      final testObject = _RemovableService('removable');
      Locator.add<_RemovableService>(testObject);

      // Verify it's registered
      expect(Locator.maybeLocate<_RemovableService>(), same(testObject));

      // Remove it
      Locator.remove<_RemovableService>();

      // Verify it's gone
      expect(Locator.maybeLocate<_RemovableService>(), isNull);
    });

    test('remove does not throw when type not registered', () {
      // Should not throw
      expect(() => Locator.remove<_NeverRegisteredService>(), returnsNormally);
    });

    test('maybeLocate returns object when registered', () {
      final testObject = _MaybeService('maybe');
      Locator.add<_MaybeService>(testObject);

      final located = Locator.maybeLocate<_MaybeService>();
      expect(located, same(testObject));
    });

    test('maybeLocate returns null when not registered', () {
      final located = Locator.maybeLocate<_NotRegisteredService>();
      expect(located, isNull);
    });
  });
}

class _TestService {
  _TestService(this.name);
  final String name;
}

class _AnotherService {
  _AnotherService(this.value);
  final int value;
}

class _UnregisteredService {}

class _RemovableService {
  _RemovableService(this.name);
  final String name;
}

class _NeverRegisteredService {}

class _MaybeService {
  _MaybeService(this.name);
  final String name;
}

class _NotRegisteredService {}
