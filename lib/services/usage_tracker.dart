import 'dart:async';
import 'package:usage_stats/usage_stats.dart';
import '../models/app_group.dart';
import 'app_closure_handler.dart';

class UsageTracker {
  static final UsageTracker _instance = UsageTracker._internal();
  factory UsageTracker() => _instance;
  UsageTracker._internal();

  Timer? _timer;
  final AppClosureHandler _closureHandler = AppClosureHandler();
  
  // Mock data for groups
  List<AppGroup> appGroups = [
    AppGroup(
      name: 'Social Media',
      packageNames: ['com.instagram.android', 'com.facebook.katana', 'com.twitter.android'],
      timeLimitMinutes: 30,
    ),
  ];

  /// Begins monitoring usage in the background via Dart.
  /// Throttled to check every 5 minutes.
  void startTracking() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      await _checkLimits();
    });
  }

  void stopTracking() {
    _timer?.cancel();
  }

  Future<void> _checkLimits() async {
    for (var group in appGroups) {
      int usage = await getGroupUsage(group.packageNames);
      if (usage >= group.timeLimitMinutes) {
        for (var pkg in group.packageNames) {
          _closureHandler.forceCloseApp(pkg);
        }
      }
    }
  }

  /// Returns usage time in minutes for a specific package today.
  Future<int> getUsageTime(String packageName) async {
    DateTime endDate = DateTime.now();
    DateTime startDate = DateTime(endDate.year, endDate.month, endDate.day); // Start of today

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

  /// Checks if limit is exceeded for a specific package.
  Future<bool> isLimitReached(String packageName, int limitMinutes) async {
    int usage = await getUsageTime(packageName);
    return usage >= limitMinutes;
  }
}
