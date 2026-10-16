import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unplug/models/app_group.dart';
import 'package:unplug/services/storage_service.dart';
import 'package:unplug/settings_screen.dart';

/// The settings lock is the gate in front of every other setting, so it must
/// not be able to open itself. Turning it ON is free — locking yourself in is
/// not a way around it — but turning it OFF costs the same 30-second wait or
/// 50-word challenge as everything else.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().init();
  });

  /// The screen builds lazily and the sections under test sit below the
  /// default 800x600 test viewport. A tall surface lays the whole screen out
  /// so every target is genuinely hit-testable, instead of trying to scroll a
  /// lazily-built list into range.
  Future<void> openSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const CupertinoApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
  }

  /// The tab-blocker section has switches too, so target the one belonging to
  /// the Settings Lock tile.
  Finder lockSwitch() => find.descendant(
        of: find.ancestor(
          of: find.text('Settings Lock'),
          matching: find.byType(CupertinoListTile),
        ),
        matching: find.byType(CupertinoSwitch),
      );

  testWidgets('turning the settings lock OFF is gated, not instant',
      (tester) async {
    await StorageService().setSettingsLockEnabled(true);
    await openSettings(tester);

    await tester.tap(lockSwitch());
    await tester.pumpAndSettle();

    // A challenge was offered rather than the change being applied.
    expect(find.text('Confirm Change'), findsOneWidget);
    expect(StorageService().settingsLockEnabled, isTrue,
        reason: 'the lock must not drop before the challenge is met');
  });

  testWidgets('turning the settings lock ON needs no challenge',
      (tester) async {
    await StorageService().setSettingsLockEnabled(false);
    await openSettings(tester);

    await tester.tap(lockSwitch());
    await tester.pumpAndSettle();

    expect(find.text('Confirm Change'), findsNothing);
    expect(StorageService().settingsLockEnabled, isTrue);
  });

  // Cancelling out of the challenge must leave the lock exactly as it was.
  testWidgets('cancelling the challenge leaves the lock on', (tester) async {
    await StorageService().setSettingsLockEnabled(true);
    await openSettings(tester);

    await tester.tap(lockSwitch());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(StorageService().settingsLockEnabled, isTrue);
  });

  group('the two interstitials gate the direction that removes friction', () {
    // Matches the in-app tab blockers, which is the precedent: Snapchat
    // Spotlight switches on free and asks a challenge to switch off.
    //
    // Both: on free, off challenged.
    // Break reminder only: retuning the interval of one that is already on
    // is challenged too, since it loosens a live setting without turning it
    // off.

    /// Both features live behind a group's action sheet, and the sheet also
    /// holds "Edit Time Limit", so the row is targeted by its own label.
    Finder groupRow(String label) => find.text(label).first;

    Future<void> openFirstGroupSheet(WidgetTester tester) async {
      await openSettings(tester);
      await tester.tap(find.text('Social Media').first);
      await tester.pumpAndSettle();
    }

    /// The settings screen behind the sheet has its own Save button, so the
    /// sheet's is targeted by the blue one — the screen's is green.
    Finder sheetSave() => find.widgetWithText(
          CupertinoButton,
          'Save',
        ).last;

    testWidgets('turning the open gate ON is free', (tester) async {
      await StorageService().setSettingsLockEnabled(true);
      await openFirstGroupSheet(tester);

      await tester.tap(groupRow('Open Gate: Off'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm Change'), findsNothing);
      expect(
        StorageService().loadGroups().first.openGateEnabled,
        isTrue,
        reason: 'arming a guard on yourself must not cost a wait, same as the '
            'in-app tab blockers',
      );
    });

    testWidgets('turning the open gate OFF is gated', (tester) async {
      await StorageService().setSettingsLockEnabled(true);
      await StorageService().saveGroups([
        AppGroup(
          name: 'Social Media',
          packageNames: const ['com.instagram.android'],
          timeLimitMinutes: 30,
          openGateEnabled: true,
        ),
      ]);
      await openFirstGroupSheet(tester);

      await tester.tap(groupRow('Open Gate: On'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm Change'), findsOneWidget);
      expect(
        StorageService().loadGroups().first.openGateEnabled,
        isTrue,
        reason: 'the gate must not drop before the challenge is met',
      );
    });

    testWidgets('turning the break reminder ON is free', (tester) async {
      await StorageService().setSettingsLockEnabled(true);
      await openFirstGroupSheet(tester);

      await tester.tap(groupRow('Break Reminder: Off'));
      await tester.pumpAndSettle();
      expect(find.text('Break Reminder'), findsOneWidget);
      await tester.tap(find.byType(CupertinoSwitch).last);
      await tester.pumpAndSettle();
      await tester.tap(sheetSave());
      await tester.pumpAndSettle();

      expect(find.text('Confirm Change'), findsNothing);
      expect(StorageService().loadGroups().first.breakReminderEnabled, isTrue);
    });

    testWidgets('retuning a running reminder is gated', (tester) async {
      await StorageService().setSettingsLockEnabled(true);
      await StorageService().saveGroups([
        AppGroup(
          name: 'Social Media',
          packageNames: const ['com.instagram.android'],
          timeLimitMinutes: 30,
          breakReminderEnabled: true,
          breakReminderMinutes: 10,
        ),
      ]);
      await openFirstGroupSheet(tester);

      await tester.tap(groupRow('Break Reminder: On (10m)'));
      await tester.pumpAndSettle();

      // Scroll the minute wheel off 10 and save.
      await tester.drag(find.byType(CupertinoPicker).last, const Offset(0, -40));
      await tester.pumpAndSettle();
      await tester.tap(sheetSave());
      await tester.pumpAndSettle();

      expect(
        find.text('Confirm Change'),
        findsOneWidget,
        reason: 'the interval is how long use can continue before the '
            'reminder interrupts, so retuning a live one is weakening it',
      );
      expect(
        StorageService().loadGroups().first.breakReminderMinutes,
        equals(10),
        reason: 'the old interval must stand until the challenge is met',
      );
    });

    // Saving the sheet without touching anything must not open a challenge.
    // Otherwise a user who opens the sheet, looks at it and closes it with
    // Save pays a wait for having changed nothing.
    testWidgets('saving an untouched reminder is not a change', (tester) async {
      await StorageService().setSettingsLockEnabled(true);
      await StorageService().saveGroups([
        AppGroup(
          name: 'Social Media',
          packageNames: const ['com.instagram.android'],
          timeLimitMinutes: 30,
          breakReminderEnabled: true,
          breakReminderMinutes: 10,
        ),
      ]);
      await openFirstGroupSheet(tester);

      await tester.tap(groupRow('Break Reminder: On (10m)'));
      await tester.pumpAndSettle();
      await tester.tap(sheetSave());
      await tester.pumpAndSettle();

      expect(find.text('Confirm Change'), findsNothing);
      expect(StorageService().loadGroups().first.breakReminderMinutes, equals(10));
    });

    // Turning it off is the direction that removes the guard, so it asks.
    testWidgets('turning the break reminder OFF is gated', (tester) async {
      await StorageService().setSettingsLockEnabled(true);
      await StorageService().saveGroups([
        AppGroup(
          name: 'Social Media',
          packageNames: const ['com.instagram.android'],
          timeLimitMinutes: 30,
          breakReminderEnabled: true,
          breakReminderMinutes: 25,
        ),
      ]);
      await openFirstGroupSheet(tester);

      await tester.tap(groupRow('Break Reminder: On (25m)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CupertinoSwitch).last);
      await tester.pumpAndSettle();
      await tester.tap(sheetSave());
      await tester.pumpAndSettle();

      expect(find.text('Confirm Change'), findsOneWidget);
      expect(
        StorageService().loadGroups().first.breakReminderEnabled,
        isTrue,
        reason: 'the reminder must not drop before the challenge is met',
      );
    });

    // Creating a group only arms a limit — it starts with both interstitials
    // off and the default limit, so it cannot loosen anything. Charging for it
    // put a wait on the ordinary first-run path.
    testWidgets('creating a group needs no challenge', (tester) async {
      await StorageService().setSettingsLockEnabled(true);
      await openSettings(tester);

      await tester.tap(find.text('Add Group'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm Change'), findsNothing);
      expect(find.text('New Group'), findsOneWidget);
    });
  });

  group('reward per wait is capped', () {
    // The picker must not offer a value above the ceiling. A scrollable that
    // can be dragged past the bound and silently clamped on save tells the
    // user one thing and does another.
    Future<void> openRewardPicker(WidgetTester tester) async {
      // The tile sits behind the settings lock, which is on by default. Turn
      // it off so the picker opens directly rather than behind a challenge.
      await StorageService().setSettingsLockEnabled(false);
      await openSettings(tester);
      await tester.tap(find.text('Reward per Wait').first);
      await tester.pumpAndSettle();
    }

    testWidgets('the picker shows the ceiling and opens', (tester) async {
      await StorageService().saveBonusRewardSeconds(60);
      await openRewardPicker(tester);

      expect(find.text('Maximum 20m'), findsOneWidget);
      expect(find.byType(CupertinoPicker), findsOneWidget);
    });

    testWidgets('dragging hard past the end does not exceed the cap',
        (tester) async {
      await StorageService().saveBonusRewardSeconds(60);
      await openRewardPicker(tester);

      // Slam the picker toward the end repeatedly; it has nowhere to go.
      for (var i = 0; i < 8; i++) {
        await tester.drag(find.byType(CupertinoPicker), const Offset(0, -600));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      expect(StorageService().bonusRewardSeconds, 1200);
    });
  });

  group('wait duration is bounded', () {
    // The wait is the friction the whole feature rests on. If it can be set
    // below the floor the friction stops being friction; if it can be set
    // above the ceiling it stops being a negotiation and starts being a
    // punishment, and the user uninstalls instead — the opposite of the point.
    Future<void> openWaitPicker(WidgetTester tester) async {
      await StorageService().setSettingsLockEnabled(false);
      await openSettings(tester);
      await tester.tap(find.text('Wait Duration').first);
      await tester.pumpAndSettle();
    }

    test('options run from 30s to 3m59s at every second', () {
      final options = StorageService.waitOptions();
      expect(options.first, StorageService.minWaitSeconds);
      expect(options.last, StorageService.maxWaitSeconds);
      expect(options.last, 3 * 60 + 59);
      expect(options.contains(30), isTrue);
      expect(options.contains(239), isTrue);
      // Every second is reachable — a coarse grid would defeat the point of
      // choosing the precise amount of friction.
      expect(options.length, 3 * 60 + 59 - 30 + 1);
      expect(options.every((s) => s >= 30 && s <= 239), isTrue);
    });

    test('defaults to the original 30s wait', () async {
      expect(StorageService().waitSeconds, 30);
    });

    test('a stored value below the floor is corrected on read', () async {
      // A value out of range can only get there by tampering or a future
      // schema change. It must not produce a wait that costs nothing.
      await StorageService().saveWaitSeconds(5);
      expect(StorageService().waitSeconds, StorageService.minWaitSeconds);
    });

    test('a stored value above the ceiling is corrected on read', () async {
      await StorageService().saveWaitSeconds(99999);
      expect(StorageService().waitSeconds, StorageService.maxWaitSeconds);
    });

    test('a value inside the range round-trips', () async {
      await StorageService().saveWaitSeconds(120);
      expect(StorageService().waitSeconds, 120);
    });

    testWidgets('the picker shows two wheels and the range hint',
        (tester) async {
      await openWaitPicker(tester);
      // One wheel for minutes, one for seconds.
      expect(find.byType(CupertinoPicker), findsNWidgets(2));
    });

    testWidgets('both wheels are labelled with their unit', (tester) async {
      await openWaitPicker(tester);

      // The bare numbers were ambiguous: 3 next to 59 reads as a pair rather
      // than as a duration. Every row carries its unit, matching how the
      // Daily Time Limit picker labels its hours and minutes.
      expect(find.text('min'), findsWidgets);
      expect(find.text('sec'), findsWidgets);
    });

    testWidgets('the wheels match the Daily Time Limit picker styling',
        (tester) async {
      await openWaitPicker(tester);

      // Same item extent as CupertinoTimerPicker uses, so the two wheels in
      // Settings line up row for row instead of looking like different
      // controls.
      final pickers = tester.widgetList<CupertinoPicker>(find.byType(CupertinoPicker));
      for (final p in pickers) {
        expect(p.itemExtent, 32.0);
      }
    });

    testWidgets('dragging the minute wheel past the end stops at 3 minutes',
        (tester) async {
      await StorageService().saveWaitSeconds(150);
      await openWaitPicker(tester);

      // Minutes top out at 3. Seconds are left at 30, so the ceiling is
      // 3m30s — the two wheels cannot combine to reach 3m59s by dragging
      // minutes alone, which is why the second wheel exists.
      final minuteWheel = find.byType(CupertinoPicker).first;
      for (var i = 0; i < 8; i++) {
        await tester.drag(minuteWheel, const Offset(0, -600));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      expect(StorageService().waitSeconds, 3 * 60 + 30);
    });

    testWidgets('the ceiling 3m59s is reachable and is the maximum',
        (tester) async {
      await StorageService().saveWaitSeconds(239);
      await openWaitPicker(tester);

      // Start at the ceiling and push both wheels up. The minute wheel is
      // already at its maximum, so nothing can exceed it.
      final minuteWheel = find.byType(CupertinoPicker).first;
      final secondWheel = find.byType(CupertinoPicker).at(1);
      for (var i = 0; i < 4; i++) {
        await tester.drag(minuteWheel, const Offset(0, -600));
        await tester.pumpAndSettle();
        await tester.drag(secondWheel, const Offset(0, -600));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      expect(StorageService().waitSeconds, StorageService.maxWaitSeconds);
    });

    testWidgets('dragging the second wheel below the floor bounces back',
        (tester) async {
      // Start at 0m30s: the only way under the floor is to spin the seconds
      // wheel down while minutes sit at 0.
      await StorageService().saveWaitSeconds(30);
      await openWaitPicker(tester);

      final secondWheel = find.byType(CupertinoPicker).at(1);
      for (var i = 0; i < 10; i++) {
        await tester.drag(secondWheel, const Offset(0, 600));
        await tester.pumpAndSettle();
      }

      expect(find.text('Minimum wait is 30 seconds'), findsOneWidget);

      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      expect(StorageService().waitSeconds, StorageService.minWaitSeconds);
    });
  });
}