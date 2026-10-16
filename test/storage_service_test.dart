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

    test('the Kotlin side builds the same anchor key', () {
      // The anchor is half of the consumption arithmetic. Dart writes it, the
      // limiter reads it, and a mismatch means the limiter subtracts the wrong
      // baseline — which reads as bonus that never runs out, or bonus that is
      // gone before it is used.
      final source = File(
        'android/app/src/main/kotlin/com/egbytest/unplug/UsageAccessibilityService.kt',
      ).readAsStringSync();

      expect(
        source,
        contains(r'"flutter.bonus_anchor_%s_%04d-%02d-%02d"'),
        reason: 'UsageAccessibilityService must build the same anchor key that '
            'StorageService._bonusAnchorKey writes',
      );
    });

    test('the Kotlin side reads the interstitial group keys by name', () {
      // Same hazard as the bonus keys, with a quieter failure: Dart writes
      // breakReminderEnabled / openGateEnabled into app_groups JSON and the
      // limiter is the only reader. Rename either side and the switches keep
      // toggling in Settings while the overlay never once appears — which
      // looks exactly like the feature being broken, not like a typo.
      final source = File(
        'android/app/src/main/kotlin/com/egbytest/unplug/UsageAccessibilityService.kt',
      ).readAsStringSync();

      for (final key in [
        'breakReminderEnabled',
        'openGateEnabled',
        'breakReminderMinutes',
      ]) {
        expect(
          source,
          contains('"$key"'),
          reason: 'UsageAccessibilityService must read "$key", the key '
              'AppGroup.toJson writes it under',
        );
      }
    });

    test('the Kotlin side reads the new keys as optional', () {
      // An install whose stored groups predate these fields must load as "off"
      // rather than throwing inside the accessibility event handler, where the
      // exception would be swallowed by the catch-all and silently disable
      // enforcement for that event.
      final source = File(
        'android/app/src/main/kotlin/com/egbytest/unplug/UsageAccessibilityService.kt',
      ).readAsStringSync();

      expect(
        source,
        contains('optBoolean("openGateEnabled", false)'),
        reason: 'must default to off, matching AppGroup.fromJson, so an older '
            'stored group cannot throw in the event handler',
      );
      expect(
        source,
        contains('optBoolean("breakReminderEnabled", false)'),
      );
    });

    // The exact bug the user reported: at 50m used against a 40m limit, a 5m
    // bonus used to raise the ceiling to 45m — still under the usage, so it
    // appeared to do nothing and had to be earned three times over.
    test('a bonus buys its face value when already over the limit', () async {
      await StorageService().addBonusSeconds(
        'Social Media',
        5 * 60,
        usageMinutes: 50,
      );

      // Ceiling is 50m (over the 40m limit) plus the 5m just earned.
      expect(
        StorageService().effectiveLimitMinutes('Social Media', 40, 50),
        55,
      );
      // 50 used against 55 available: allowed.
      expect(50 < StorageService().effectiveLimitMinutes('Social Media', 40, 50),
          isTrue);
    });

    test('credit is drawn down as it is used', () async {
      await StorageService().addBonusSeconds(
        'Social Media',
        5 * 60,
        usageMinutes: 50,
      );

      // The ceiling stays at 55m while the user climbs towards it; what falls
      // is the remaining credit. A ceiling that shrank as they spent would put
      // them under it the instant they started.
      expect(
        StorageService().effectiveLimitMinutes('Social Media', 40, 53),
        55,
      );
      expect(
        StorageService().remainingBonusSeconds('Social Media', 53),
        2 * 60,
      );
    });

    test('credit runs out exactly when the usage catches up', () async {
      await StorageService().addBonusSeconds(
        'Social Media',
        5 * 60,
        usageMinutes: 50,
      );

      // The ceiling stays where it was put — 55m. It is a budget the user
      // spends towards, not a balance that shrinks as they spend. What runs
      // out is the credit itself.
      expect(
        StorageService().remainingBonusSeconds('Social Media', 55),
        0,
      );
      expect(
        StorageService().effectiveLimitMinutes('Social Media', 40, 55),
        55,
      );
      // And at the ceiling the group is blocked again.
      expect(
        55 >= StorageService().effectiveLimitMinutes('Social Media', 40, 55),
        isTrue,
      );
    });

    test('credit never goes negative when usage overshoots', () async {
      await StorageService().addBonusSeconds(
        'Social Media',
        5 * 60,
        usageMinutes: 50,
      );

      // Usage jumped past the credit in one go.
      expect(
        StorageService().remainingBonusSeconds('Social Media', 80),
        0,
      );
    });

    // The anchor does move on a second grant, but only after the balance has
    // been settled, so nothing already spent comes back. anchor + credit is
    // unchanged by the round trip: 50 + 10 == 53 + 7.
    test('a second grant re-anchors without refunding what was spent',
        () async {
      await StorageService()
          .addBonusSeconds('Social Media', 5 * 60, usageMinutes: 50);
      await StorageService()
          .addBonusSeconds('Social Media', 5 * 60, usageMinutes: 53);

      expect(StorageService().getBonusAnchorMinutes('Social Media'), 53);
      // Credit reaches anchor + both grants = 53 + 7 = 60m, the same ceiling
      // the pinned anchor produced. Usage at 53m has all 7m of it left.
      expect(
        StorageService().effectiveLimitMinutes('Social Media', 40, 53),
        60,
      );
      expect(
        StorageService().remainingBonusSeconds('Social Media', 53),
        7 * 60,
      );
    });

    // The bug this replaced: the anchor was written on the first grant of the
    // day and never moved, so every minute spent since was subtracted from the
    // running total forever — retroactively cancelling credit earned later.
    // The reward landed, the dashboard read "no bonus time" straight after,
    // and the ceiling stayed under the usage so the group stayed blocked.
    test('a grant is not eaten by usage that predates it', () async {
      await StorageService()
          .addBonusSeconds('Doomscroll', 6 * 60, usageMinutes: 30);
      // 25 minutes of use since that first grant.
      await StorageService()
          .addBonusSeconds('Doomscroll', 3 * 60, usageMinutes: 55);

      // The exhausted 6 minutes are written off, and the 3 just earned are
      // measured from where the user actually is.
      expect(
        StorageService().remainingBonusSeconds('Doomscroll', 55),
        3 * 60,
      );
      // 55 + 3 = 58. The pinned anchor would have said 30 + 9 = 39, which is
      // under 55m of usage, so the group stayed blocked on a reward the user
      // had just sat through a full minute to earn.
      expect(
        StorageService().effectiveLimitMinutes('Doomscroll', 50, 55),
        58,
      );
      expect(
          55 < StorageService().effectiveLimitMinutes('Doomscroll', 50, 55),
          isTrue);
    });

    // A usage reading that comes back wrong must not be able to confiscate
    // credit. Anchoring to a failed query's 0 would put the ceiling at the
    // granted total alone and silently destroy every bonus the user holds.
    test('a bad usage reading cannot take the credit with it', () async {
      await StorageService()
          .addBonusSeconds('Social Media', 5 * 60, usageMinutes: 50);

      // Usage access failed and reported nothing.
      await StorageService().addBonusSeconds('Social Media', 5 * 60);

      expect(StorageService().getBonusAnchorMinutes('Social Media'), 50);
      expect(
        StorageService().effectiveLimitMinutes('Social Media', 40, 50),
        60,
      );
      expect(
        StorageService().remainingBonusSeconds('Social Media', 50),
        10 * 60,
      );
    });

    test('usage below the anchor does not inflate the credit', () async {
      await StorageService().addBonusSeconds(
        'Social Media',
        5 * 60,
        usageMinutes: 50,
      );

      // Usage read lower than it was at grant time — a usage-access hiccup
      // returning a partial total, or a reset hour changed mid-day. Crediting
      // that 40 minute gap back would hand out 45 minutes of free screen time
      // that nobody earned, so the gap is simply not counted as spending.
      expect(
        StorageService().remainingBonusSeconds('Social Media', 10),
        5 * 60,
      );
      // The ceiling is unaffected either way.
      expect(
        StorageService().effectiveLimitMinutes('Social Media', 40, 10),
        55,
      );
    });

    test('a pre-model grant with no anchor keeps the additive ceiling',
        () async {
      // Installs upgrading from the old model carry a granted total and no
      // anchor. Reading the absent anchor as 0 would compute a ceiling of
      // granted/60 — 5m instead of 45m — silently confiscating bonus the user
      // had already paid for.
      final today = StorageService().dayKey(DateTime.now());
      SharedPreferences.setMockInitialValues({
        'bonus_seconds_Social Media_$today': 5 * 60,
      });
      await StorageService().init();

      expect(StorageService().getBonusAnchorMinutesOrNull('Social Media'),
          isNull);
      expect(
        StorageService().effectiveLimitMinutes('Social Media', 40, 40),
        45,
      );
      // Nothing has been spent, so it reads as fully available.
      expect(
        StorageService().remainingBonusSeconds('Social Media', 40),
        5 * 60,
      );
    });

    test('a zero limit stays zero even with credit', () async {
      await StorageService().addBonusSeconds(
        'Social Media',
        5 * 60,
        usageMinutes: 50,
      );

      expect(
        StorageService().effectiveLimitMinutes('Social Media', 0, 50),
        0,
      );
    });

    test('resetting clears the anchor as well as the grant', () async {
      await StorageService().addBonusSeconds(
          'Social Media', 300, usageMinutes: 50);
      await StorageService().resetBonusSeconds('Social Media');

      expect(StorageService().getBonusSeconds('Social Media'), 0);
      expect(StorageService().getBonusAnchorMinutes('Social Media'), 0);
    });

    test('stale anchors are swept with the stale grants', () async {
      SharedPreferences.setMockInitialValues({
        'bonus_anchor_Social Media_${yesterday()}': 50,
      });
      await StorageService().init();

      await StorageService()
          .addBonusSeconds('Social Media', 60, usageMinutes: 10);
      final keys = (await SharedPreferences.getInstance()).getKeys();

      expect(keys, isNot(contains('bonus_anchor_Social Media_${yesterday()}')));
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