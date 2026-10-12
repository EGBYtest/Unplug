import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

    test('options run from 30s to 5m in 30s steps', () {
      final options = StorageService.waitOptions();
      expect(options.first, StorageService.minWaitSeconds);
      expect(options.last, StorageService.maxWaitSeconds);
      expect(options.contains(30), isTrue);
      expect(options.contains(300), isTrue);
      // Nothing outside the range is ever offered.
      expect(options.every((s) => s >= 30 && s <= 300), isTrue);
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

    testWidgets('the picker shows the range and opens', (tester) async {
      await openWaitPicker(tester);
      expect(find.text('30s to 5m. A longer wait earns the same bonus.'),
          findsOneWidget);
      expect(find.byType(CupertinoPicker), findsOneWidget);
    });

    testWidgets('dragging hard past the end does not exceed the ceiling',
        (tester) async {
      await openWaitPicker(tester);

      for (var i = 0; i < 8; i++) {
        await tester.drag(find.byType(CupertinoPicker), const Offset(0, -600));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      expect(StorageService().waitSeconds, StorageService.maxWaitSeconds);
    });

    testWidgets('dragging hard past the start does not go below the floor',
        (tester) async {
      await StorageService().saveWaitSeconds(300);
      await openWaitPicker(tester);

      for (var i = 0; i < 8; i++) {
        await tester.drag(find.byType(CupertinoPicker), const Offset(0, 600));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();

      expect(StorageService().waitSeconds, StorageService.minWaitSeconds);
    });
  });
}