import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../lock_screen_popup.dart';

class AppClosureHandler {
  static final AppClosureHandler _instance = AppClosureHandler._internal();
  factory AppClosureHandler() => _instance;
  AppClosureHandler._internal();

  static const MethodChannel _channel = MethodChannel('app_closure');

  /// Calls native code to redirect user to home screen (blocking the limited app)
  Future<bool> forceCloseApp(String packageName) async {
    try {
      final bool success =
          await _channel.invokeMethod('forceCloseApp', {'packageName': packageName});
      return success;
    } on PlatformException catch (e) {
      debugPrint("Failed to force close app: '${e.message}'.");
      return false;
    }
  }

  /// Opens the Android Accessibility Settings page
  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } on PlatformException catch (e) {
      debugPrint("Failed to open Accessibility Settings: '${e.message}'.");
    }
  }

  /// Opens the Android Usage Access Settings page
  Future<void> openUsageAccessSettings() async {
    try {
      await _channel.invokeMethod('openUsageAccessSettings');
    } on PlatformException catch (e) {
      debugPrint("Failed to open Usage Access Settings: '${e.message}'.");
    }
  }

  /// Checks if Usage Access permission is granted
  Future<bool> hasUsageAccess() async {
    try {
      return await _channel.invokeMethod('hasUsageAccess') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Checks if Accessibility Service is enabled
  Future<bool> hasAccessibilityEnabled() async {
    try {
      return await _channel.invokeMethod('hasAccessibilityEnabled') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Displays the LockScreen as full-screen route.
  /// Returns when lock screen is dismissed.
  Future<void> showLockScreen(BuildContext context, String appName, {String? bannedFeature}) {
    return Navigator.of(context).push<void>(
      CupertinoPageRoute(
        builder: (_) => LockScreenPopup(appName: appName, bannedFeature: bannedFeature),
        settings: const RouteSettings(name: 'lock_screen'),
      ),
    );
  }
}
