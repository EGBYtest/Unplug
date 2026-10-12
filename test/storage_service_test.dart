import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unplug/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().init();
  });

  group('StorageService defaults', () {
    // The native Kotlin AccessibilityService reads these same keys, so a
    // default that changes here silently changes on-device enforcement.
    test('settings lock is on by default', () {
      expect(StorageService().settingsLockEnabled, isTrue);
      expect(StorageService().settingsLockAutoEnabled, isFalse);
    });

    test('reset hour defaults to 2am', () {
      expect(StorageService().resetHour, 2);
    });

    test('ad reward defaults to 60 seconds', () {
      expect(StorageService().adRewardSeconds, 60);
    });

    test('onboarding and install reporting start incomplete', () {
      expect(StorageService().onboardingComplete, isFalse);
      expect(StorageService().installReported, isFalse);
    });
  });

  group('reset hour rounding', () {
    test('rounds down to even hours', () async {
      await StorageService().saveResetHour(7);
      expect(StorageService().resetHour, 6);
      await StorageService().saveResetHour(0);
      expect(StorageService().resetHour, 0);
      await StorageService().saveResetHour(23);
      expect(StorageService().resetHour, 22);
    });
  });

  group('dayKey', () {
    // Day boundaries are user-controlled, so a mistake here shifts every
    // user's usage counters by a day.
    test('uses the previous day before the reset hour', () async {
      await StorageService().saveResetHour(2);
      expect(
        StorageService().dayKey(DateTime(2026, 10, 12, 1, 30)),
        '2026-10-11',
      );
    });

    test('rolls over at the reset hour', () async {
      await StorageService().saveResetHour(2);
      expect(
        StorageService().dayKey(DateTime(2026, 10, 12, 2, 0)),
        '2026-10-12',
      );
    });

    test('respects a later custom reset hour', () async {
      await StorageService().saveResetHour(12);
      expect(
        StorageService().dayKey(DateTime(2026, 10, 12, 11, 59)),
        '2026-10-11',
      );
      expect(
        StorageService().dayKey(DateTime(2026, 10, 12, 12, 1)),
        '2026-10-12',
      );
    });
  });
}