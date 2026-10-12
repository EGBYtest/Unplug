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
    });

    test('reset hour defaults to 2am', () {
      expect(StorageService().resetHour, 2);
    });

    test('bonus reward defaults to 60 seconds', () {
      expect(StorageService().bonusRewardSeconds, 60);
    });

    test('onboarding starts incomplete', () {
      expect(StorageService().onboardingComplete, isFalse);
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

  group('bonus seconds day rollover', () {
    // The native service reads bonus_seconds_* directly out of
    // SharedPreferences and never runs Dart. The reset therefore cannot live
    // only in init() — a user who does not open Unplug for a day would keep
    // yesterday's bonus silently raising today's limit.

    test('accumulates within the same day', () async {
      await StorageService().addBonusSeconds('Social Media', 60);
      await StorageService().addBonusSeconds('Social Media', 60);
      expect(StorageService().getBonusSeconds('Social Media'), 120);
    });

    test('keeps bonus separate per group', () async {
      await StorageService().addBonusSeconds('Social Media', 60);
      expect(StorageService().getBonusSeconds('Games'), 0);
    });

    test('reads zero when the stored day marker is stale', () async {
      await StorageService().addBonusSeconds('Social Media', 120);
      expect(StorageService().getBonusSeconds('Social Media'), 120);

      // Simulate the app not being launched across a day boundary. The
      // marker still names the old day, so the read must refuse to return
      // the stale value rather than hand it to the dashboard.
      final stale = DateTime.now().subtract(const Duration(days: 2));
      SharedPreferences.setMockInitialValues({'last_bonus_reset': _keyFor(stale)});
      await StorageService().init();
      SharedPreferences.setMockInitialValues({
        'last_bonus_reset': _keyFor(stale),
        'bonus_seconds_Social Media': 120,
      });
      await StorageService().init();

      expect(StorageService().getBonusSeconds('Social Media'), 0);
    });

    test('adding after a rollover starts from zero, not the stale total', () async {
      final stale = DateTime.now().subtract(const Duration(days: 2));
      SharedPreferences.setMockInitialValues({
        'last_bonus_reset': _keyFor(stale),
        'bonus_seconds_Social Media': 120,
      });
      await StorageService().init();

      await StorageService().addBonusSeconds('Social Media', 60);
      expect(StorageService().getBonusSeconds('Social Media'), 60);
    });
  });

  group('getAverageDailyMinutes', () {
    // Feeds the dashboard subtitle. The cutoff is derived by subtracting from
    // the reset-hour day start rather than from midnight, so a wrong result
    // shows up as a wrong comparison against today.

    test('returns null with no history', () {
      expect(StorageService().getAverageDailyMinutes(), isNull);
    });

    test('averages prior days and excludes today', () async {
      final today = StorageService().dayKey(DateTime.now());
      final prior = _daysAgo(1);
      await StorageService().saveDailyEntry(prior, 40);
      await StorageService().saveDailyEntry(_daysAgo(2), 20);
      await StorageService().saveDailyEntry(today, 999);

      expect(StorageService().getAverageDailyMinutes(), 30);
    });

    test('ignores days older than the window', () async {
      await StorageService().saveDailyEntry(_daysAgo(30), 500);
      expect(StorageService().getAverageDailyMinutes(), isNull);
    });
  });
}

// Mirrors StorageService.dayKey for the default reset hour, which the tests
// above leave at 2am.
String _keyFor(DateTime dt) => dt.toIso8601String().substring(0, 10);

/// "N days ago", as a dayKey. Takes a positive count.
String _daysAgo(int days) =>
    DateTime.now().subtract(Duration(days: days)).toIso8601String().substring(0, 10);