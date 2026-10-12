import 'dart:developer' show log;
import 'package:usage_stats/usage_stats.dart';
import 'storage_service.dart';

/// Reads foreground usage from Android's UsageStats API.
///
/// This class is display-only. It powers the dashboard numbers and nothing
/// else — enforcement lives entirely in the native AccessibilityService,
/// which reads the same limits straight out of SharedPreferences and acts on
/// them without any Dart involvement.
///
/// This distinction used to be blurred: a Dart Timer polled limits here and
/// fired a "force close" MethodChannel call when a group was over budget. That
/// path could not do its job. It redirected to the launcher without checking
/// which app was in the foreground, so a stale timer firing while the user was
/// reading email would throw them to the home screen. It also never ran in
/// practice — every block relaunches Dart with FLAG_ACTIVITY_CLEAR_TASK, which
/// destroys the isolate and restarts the timer before it could reach five
/// minutes. The result was a mechanism that could only misfire, and silently
/// did nothing otherwise.
class UsageTracker {
  static final UsageTracker _instance = UsageTracker._internal();
  factory UsageTracker() => _instance;
  UsageTracker._internal();

  /// Returns usage time in minutes for a specific package today (reset hour configurable).
  Future<int> getUsageTime(String packageName) async {
    final h = StorageService().resetHour;
    final endDate = DateTime.now();
    final startDate = endDate.hour < h
        ? DateTime(endDate.year, endDate.month, endDate.day - 1, h)
        : DateTime(endDate.year, endDate.month, endDate.day, h);
    log('UsageTracker: $packageName start=${startDate.toIso8601String()} end=${endDate.toIso8601String()} resetHour=$h');

    List<UsageInfo> usageStats = await UsageStats.queryUsageStats(startDate, endDate);
    for (var info in usageStats) {
      if (info.packageName == packageName) {
        // Convert milliseconds to minutes
        int totalTimeInForeground = int.parse(info.totalTimeInForeground ?? '0');
        return totalTimeInForeground ~/ 60000;
      }
    }
    return 0;
  }

  /// Returns cumulative usage for a group in minutes.
  Future<int> getGroupUsage(List<String> packageNames) async {
    int total = 0;
    for (var pkg in packageNames) {
      total += await getUsageTime(pkg);
    }
    return total;
  }
}