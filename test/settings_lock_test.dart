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

  Future<void> openSettings(WidgetTester tester) async {
    await tester.pumpWidget(const CupertinoApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
  }

/// The settings screen builds lazily and the Security section sits below the
/// fold, so scroll to it before interacting.
Future<void> scrollToLock(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Settings Lock'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
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
    await scrollToLock(tester);

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
    await scrollToLock(tester);

    await tester.tap(lockSwitch());
    await tester.pumpAndSettle();

    expect(find.text('Confirm Change'), findsNothing);
    expect(StorageService().settingsLockEnabled, isTrue);
  });

  // Cancelling out of the challenge must leave the lock exactly as it was.
  testWidgets('cancelling the challenge leaves the lock on', (tester) async {
    await StorageService().setSettingsLockEnabled(true);
    await openSettings(tester);
    await scrollToLock(tester);

    await tester.tap(lockSwitch());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(StorageService().settingsLockEnabled, isTrue);
  });
}