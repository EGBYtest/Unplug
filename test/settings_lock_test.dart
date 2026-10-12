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
}