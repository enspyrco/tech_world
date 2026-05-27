import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tech_world/diagnostics/diagnostics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DiagnosticsService', () {
    test('defaults: AV on, error-logging on', () async {
      final svc = await DiagnosticsService.load();
      expect(svc.avEnabled.value, isTrue);
      expect(svc.errorLoggingEnabled.value, isTrue);
    });

    test('setAvEnabled propagates to listenable and persists', () async {
      final svc = await DiagnosticsService.load();
      var notifications = 0;
      svc.avEnabled.addListener(() => notifications++);

      // Default is true, so flip to false to observe propagation.
      await svc.setAvEnabled(false);

      expect(svc.avEnabled.value, isFalse);
      expect(notifications, 1);

      // Persistence: a fresh service constructed afterward sees the same value.
      final reloaded = await DiagnosticsService.load();
      expect(reloaded.avEnabled.value, isFalse);
    });

    test('setErrorLoggingEnabled propagates and persists', () async {
      final svc = await DiagnosticsService.load();
      await svc.setErrorLoggingEnabled(false);
      expect(svc.errorLoggingEnabled.value, isFalse);

      final reloaded = await DiagnosticsService.load();
      expect(reloaded.errorLoggingEnabled.value, isFalse);
    });

    test('AV and error-logging toggles are independent', () async {
      final svc = await DiagnosticsService.load();
      await svc.setAvEnabled(true);
      // error-logging unchanged.
      expect(svc.errorLoggingEnabled.value, isTrue);
      await svc.setErrorLoggingEnabled(false);
      // AV unchanged.
      expect(svc.avEnabled.value, isTrue);
    });

    test('explicit constructor seeds initial values without persistence', () {
      final svc = DiagnosticsService(
        avEnabled: true,
        errorLoggingEnabled: false,
      );
      expect(svc.avEnabled.value, isTrue);
      expect(svc.errorLoggingEnabled.value, isFalse);
    });
  });
}
