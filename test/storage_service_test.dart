import 'dart:io';

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

    // Bonus time is never drawn down as it is spent — it raises the day's
    // limit and stays raised. So the reward per action is a multiplier on 30
    // seconds of waiting, and it has to have a ceiling or one wait can be
    // worth any amount of screen time.
    test('bonus reward is capped at 20 minutes', () async {
      expect(StorageService.maxBonusRewardSeconds, 1200);

      await StorageService().saveBonusRewardSeconds(99999);
      expect(StorageService().bonusRewardSeconds, 1200);
    });

    test('saving exactly the cap is allowed', () async {
      await StorageService().saveBonusRewardSeconds(1200);
      expect(StorageService().bonusRewardSeconds, 1200);
    });

    // Anything already stored above the cap by a previous build has to be
    // corrected on read, not only on the next save — otherwise users who set
    // it before this landed keep the old value until they next open Settings.
    test('an oversized value stored by an older build is corrected on read',
        () async {
      SharedPreferences.setMockInitialValues({'ad_reward_seconds': 86400});
      await StorageService().init();
      expect(StorageService().bonusRewardSeconds, 1200);
    });

    test('a negative value cannot be saved', () async {
      await StorageService().saveBonusRewardSeconds(-500);
      expect(StorageService().bonusRewardSeconds, 0);
    });

    // The old picker was a CupertinoTimerPicker, which has no min/max: it
    // scrolled freely and clamped on save, so the user could select a value
    // the app would then silently refuse. The replacement is an explicit
    // list, which cannot be scrolled past.
    test('the selectable options stop exactly at the cap', () {
      final options = StorageService.bonusRewardOptions();
      expect(options.first, 0);
      expect(options.last, 1200);
      expect(options.every((s) => s <= 1200), isTrue);
      expect(options.length, 21, reason: '0m to 20m in whole-minute steps');
    });

    // Whole minutes only. Sub-minute granularity was noise on a value that
    // raises a daily budget.
    test('every option is a whole minute', () {
      for (final s in StorageService.bonusRewardOptions()) {
        expect(s % 60, 0, reason: '$s is not a whole number of minutes');
      }
    });

    test('every option is itself saveable and readable unchanged', () async {
      for (final s in StorageService.bonusRewardOptions()) {
        await StorageService().saveBonusRewardSeconds(s);
        expect(StorageService().bonusRewardSeconds, s);
      }
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
    // The native AccessibilityService reads this key straight out of
    // SharedPreferences and never runs Dart. Clearing the key from Dart —
    // at launch, or on a read — is not enough: a user who does not open Unplug
    // across the reset hour keeps yesterday's bonus in force for the native
    // limiter, while the dashboard shows zero. So the day is part of the key
    // and a stale balance simply does not exist for either reader.
    //
    // The format is a cross-language contract; UsageAccessibilityService
    // .bonusSecondsFor builds the same string. The key test pins it exactly,
    // because a change here that is not matched there means earned bonus
    // silently stops being honoured, or stops expiring.

    String today() => StorageService().dayKey(DateTime.now());
    String yesterday() => StorageService()
        .dayKey(DateTime.now().subtract(const Duration(days: 1)));

    test('accumulates within the same day', () async {
      await StorageService().addBonusSeconds('Social Media', 60);
      await StorageService().addBonusSeconds('Social Media', 60);
      expect(StorageService().getBonusSeconds('Social Media'), 120);
    });

    test('keeps bonus separate per group', () async {
      await StorageService().addBonusSeconds('Social Media', 60);
      expect(StorageService().getBonusSeconds('Games'), 0);
    });

    test('the key is scoped to the current day', () async {
      await StorageService().addBonusSeconds('Social Media', 120);

      final keys = (await SharedPreferences.getInstance()).getKeys();
      expect(keys, contains('bonus_seconds_Social Media_${today()}'));
    });

    // The bug this replaced: an unscoped key was still present after the day
    // rolled over and was still being read by the native limiter.
    test("yesterday's balance is not counted today", () async {
      SharedPreferences.setMockInitialValues({
        'bonus_seconds_Social Media_${yesterday()}': 300,
      });
      await StorageService().init();

      expect(StorageService().getBonusSeconds('Social Media'), 0);
    });

    test('adding today does not inherit yesterday\'s total', () async {
      SharedPreferences.setMockInitialValues({
        'bonus_seconds_Social Media_${yesterday()}': 300,
      });
      await StorageService().init();

      await StorageService().addBonusSeconds('Social Media', 60);
      expect(StorageService().getBonusSeconds('Social Media'), 60);
    });

    // Installs from before this change carry the old unscoped key. It must not
    // be picked up, and must be cleaned up rather than left to accumulate.
    test('an old unscoped key is ignored and swept away', () async {
      SharedPreferences.setMockInitialValues({
        'bonus_seconds_Social Media': 300,
      });
      await StorageService().init();

      expect(StorageService().getBonusSeconds('Social Media'), 0);

      await StorageService().addBonusSeconds('Social Media', 60);
      final keys = (await SharedPreferences.getInstance()).getKeys();
      expect(keys, isNot(contains('bonus_seconds_Social Media')));
      expect(StorageService().getBonusSeconds('Social Media'), 60);
    });

    test('removing bonus clears today only', () async {
      SharedPreferences.setMockInitialValues({
        'bonus_seconds_Social Media_${yesterday()}': 300,
      });
      await StorageService().init();
      await StorageService().addBonusSeconds('Social Media', 120);

      await StorageService().resetBonusSeconds('Social Media');
      expect(StorageService().getBonusSeconds('Social Media'), 0);
    });

    // Dart and Kotlin each build this key independently, and nothing in the
    // build would catch them disagreeing — the native service would simply
    // stop finding bonus the user paid for, with no error anywhere. There is
    // no Kotlin test harness here, so assert the two source files agree.
    // Drop this the day the service gets real unit tests.
    test('the Kotlin side builds the same key', () {
      final source = File(
        'android/app/src/main/kotlin/com/egbytest/unplug/UsageAccessibilityService.kt',
      ).readAsStringSync();

      expect(
        source,
        contains(r'"flutter.bonus_seconds_%s_%04d-%02d-%02d"'),
        reason: 'UsageAccessibilityService must build the day-scoped key that '
            'StorageService._bonusKey writes, or earned bonus is silently '
            'ignored by the limiter',
      );
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

/// "N days ago", as a dayKey. Takes a positive count.
String _daysAgo(int days) =>
    DateTime.now().subtract(Duration(days: days)).toIso8601String().substring(0, 10);