import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_group.dart';

/// Central persistence layer. All SharedPreferences access goes through here.
/// On Android, the Flutter plugin stores values under "FlutterSharedPreferences"
/// with keys prefixed "flutter." — so the native Kotlin AccessibilityService can
/// read them directly from that file using the same key format.
class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _resetDailyBonusesIfNeeded();
  }

  // ─── Onboarding ────────────────────────────────────────────────────────────

  bool get onboardingComplete => _prefs?.getBool('onboarding_complete') ?? false;

  Future<void> setOnboardingComplete() async {
    await _prefs?.setBool('onboarding_complete', true);
  }

  // ─── Ad reward seconds ────────────────────────────────────────────────────
  // Stores how many SECONDS of bonus time each ad earns the user.

  int get adRewardSeconds => _prefs?.getInt('ad_reward_seconds') ?? 60;

  Future<void> saveAdRewardSeconds(int seconds) async {
    await _prefs?.setInt('ad_reward_seconds', seconds);
  }

  Future<void> resetBonusSeconds(String groupName) async {
    await _prefs?.remove('bonus_seconds_$groupName');
  }

  // ─── Settings Lock ──────────────────────────────────────────────────────────

  bool get settingsLockEnabled => _prefs?.getBool('settings_lock_enabled') ?? false;

  Future<void> setSettingsLockEnabled(bool value) async {
    await _prefs?.setBool('settings_lock_enabled', value);
  }

  bool get settingsLockAutoEnabled => _prefs?.getBool('settings_lock_auto_enabled') ?? false;

  Future<void> setSettingsLockAutoEnabled() async {
    await _prefs?.setBool('settings_lock_auto_enabled', true);
  }

  // ─── Global In-App Tab Blockers ────────────────────────────────────────────

  List<BannedFeature> loadGlobalTabBlockers() {
    final json = _prefs?.getString('global_tab_blockers');
    if (json == null || json.isEmpty) {
      final defaults = _defaultGlobalTabBlockers();
      saveGlobalTabBlockers(defaults);
      return defaults;
    }
    try {
      final List<dynamic> decoded = jsonDecode(json) as List<dynamic>;
      final loadedMap = <String, BannedFeature>{};
      for (final e in decoded) {
        final feat = BannedFeature.fromJson(Map<String, dynamic>.from(e as Map));
        loadedMap[feat.id] = feat;
      }
      // Merge with defaults to ensure new presets appear
      final defaults = _defaultGlobalTabBlockers();
      for (final d in defaults) {
        if (!loadedMap.containsKey(d.id)) {
          loadedMap[d.id] = d;
        }
      }
      return loadedMap.values.toList();
    } catch (_) {
      return _defaultGlobalTabBlockers();
    }
  }

  Future<void> saveGlobalTabBlockers(List<BannedFeature> blockers) async {
    final encoded = jsonEncode(blockers.map((b) => b.toJson()).toList());
    await _prefs?.setString('global_tab_blockers', encoded);
  }

  List<BannedFeature> _defaultGlobalTabBlockers() => [
        BannedFeature(
          id: 'snap_spotlight',
          name: 'Snapchat Spotlight',
          packageName: 'com.snapchat.android',
          isEnabled: false,
          contentKeywords: ['spotlight', 'spotlight_tab', 'discover_spotlight'],
          activityPattern: '.*spotlight.*',
        ),
        BannedFeature(
          id: 'yt_shorts',
          name: 'YouTube Shorts',
          packageName: 'com.google.android.youtube',
          isEnabled: false,
          contentKeywords: ['shorts', 'reel_player', 'shorts_tab', 'shorts_player'],
          activityPattern: '.*reel.*|.*shorts.*',
        ),
        BannedFeature(
          id: 'ig_reels',
          name: 'Instagram Reels',
          packageName: 'com.instagram.android',
          isEnabled: false,
          contentKeywords: ['reels', 'clips', 'reels_tab', 'clips_viewer'],
          activityPattern: '.*reels.*|.*clips.*',
        ),
        BannedFeature(
          id: 'fb_reels',
          name: 'Facebook Reels',
          packageName: 'com.facebook.katana',
          isEnabled: false,
          contentKeywords: ['reels', 'watch', 'fb_shorts', 'video_tab'],
          activityPattern: '.*reels.*|.*watch.*',
        ),
        BannedFeature(
          id: 'tiktok_feed',
          name: 'TikTok Feed',
          packageName: 'com.zhiliaoapp.musically',
          isEnabled: false,
          contentKeywords: ['tiktok', 'for_you', 'following'],
        ),
        BannedFeature(
          id: 'reddit_popular',
          name: 'Reddit Popular',
          packageName: 'com.reddit.frontpage',
          isEnabled: false,
          contentKeywords: ['popular', 'watch', 'shorts'],
        ),
      ];

  // ─── App Groups ────────────────────────────────────────────────────────────

  List<AppGroup> loadGroups() {
    final json = _prefs?.getString('app_groups');
    if (json == null || json.isEmpty) {
      final defaults = _defaultGroups();
      saveGroups(defaults);
      return defaults;
    }
    try {
      final List<dynamic> decoded = jsonDecode(json) as List<dynamic>;
      final loaded = decoded
          .map((e) => AppGroup.fromJson(e as Map<String, dynamic>))
          .toList();

      bool needSave = false;
      for (final group in loaded) {
        if (group.bannedFeatures.isEmpty) {
          final defaults = _getDefaultBannedFeaturesForGroup(group.name, group.packageNames);
          if (defaults.isNotEmpty) {
            group.bannedFeatures = defaults;
            needSave = true;
          }
        }
      }
      if (needSave) {
        saveGroups(loaded);
      }
      return loaded;
    } catch (_) {
      return _defaultGroups();
    }
  }

  List<BannedFeature> _getDefaultBannedFeaturesForGroup(String groupName, List<String> packageNames) {
    final list = <BannedFeature>[];
    final pkgs = packageNames.map((p) => p.trim()).toSet();

    if (pkgs.contains('com.instagram.android') || groupName == 'Social Media') {
      list.add(BannedFeature(
        id: 'ig_reels',
        name: 'Instagram Reels',
        packageName: 'com.instagram.android',
        contentKeywords: ['reels', 'clips', 'reels_tab', 'clips_viewer'],
        activityPattern: '.*reels.*|.*clips.*',
      ));
    }
    if (pkgs.contains('com.facebook.katana') || groupName == 'Social Media') {
      list.add(BannedFeature(
        id: 'fb_reels',
        name: 'Facebook Reels',
        packageName: 'com.facebook.katana',
        contentKeywords: ['reels', 'watch', 'fb_shorts', 'video_tab'],
        activityPattern: '.*reels.*|.*watch.*',
      ));
    }
    if (pkgs.contains('com.snapchat.android') || groupName == 'Social Media') {
      list.add(BannedFeature(
        id: 'snap_spotlight',
        name: 'Snapchat Spotlight',
        packageName: 'com.snapchat.android',
        contentKeywords: ['spotlight', 'spotlight_tab', 'discover_spotlight'],
        activityPattern: '.*spotlight.*',
      ));
    }
    if (pkgs.contains('com.google.android.youtube') || groupName == 'Entertainment') {
      list.add(BannedFeature(
        id: 'yt_shorts',
        name: 'YouTube Shorts',
        packageName: 'com.google.android.youtube',
        contentKeywords: ['shorts', 'reel_player', 'shorts_tab', 'shorts_player'],
        activityPattern: '.*reel.*|.*shorts.*',
      ));
    }
    if (pkgs.contains('com.reddit.frontpage') || groupName == 'News & Reading') {
      list.add(BannedFeature(
        id: 'reddit_popular',
        name: 'Reddit Popular',
        packageName: 'com.reddit.frontpage',
        contentKeywords: ['popular', 'watch', 'shorts'],
      ));
    }
    return list;
  }

  Future<void> saveGroups(List<AppGroup> groups) async {
    final encoded = jsonEncode(groups.map((g) => g.toJson()).toList());
    await _prefs?.setString('app_groups', encoded);
  }

  // ─── Bonus seconds ────────────────────────────────────────────────────────
  // Bonus is stored in SECONDS for precision; limits are in minutes.

  int getBonusSeconds(String groupName) =>
      _prefs?.getInt('bonus_seconds_$groupName') ?? 0;

  Future<void> addBonusSeconds(String groupName, int seconds) async {
    final current = getBonusSeconds(groupName);
    await _prefs?.setInt('bonus_seconds_$groupName', current + seconds);
  }

  Future<void> _resetDailyBonusesIfNeeded() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lastReset = _prefs?.getString('last_bonus_reset') ?? '';
    if (lastReset == today) return;

    // Clear all bonus keys (both old minutes and new seconds format)
    final keys = _prefs?.getKeys() ?? {};
    for (final key in keys) {
      if (key.startsWith('bonus_')) await _prefs?.remove(key);
    }
    await _prefs?.setString('last_bonus_reset', today);
  }

  // ─── Daily screen time history ─────────────────────────────────────────────
  // Stores daily totals (minutes) keyed by date string "YYYY-MM-DD".
  static const String _dailyHistoryKey = 'daily_screen_time';

  Map<String, int> loadDailyHistory() {
    final json = _prefs?.getString(_dailyHistoryKey);
    if (json == null || json.isEmpty) return {};
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveDailyEntry(String date, int minutes) async {
    final history = loadDailyHistory();
    history[date] = minutes;
    await _prefs?.setString(_dailyHistoryKey, jsonEncode(history));
  }

  double? getAverageDailyMinutes({int days = 7}) {
    final history = loadDailyHistory();
    if (history.isEmpty) return null;

    final today = DateTime.now().toIso8601String().substring(0, 10);
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final cutoffStr = cutoff.toIso8601String().substring(0, 10);

    int total = 0;
    int count = 0;
    for (final entry in history.entries) {
      if (entry.key == today) continue;
      if (entry.key.compareTo(cutoffStr) >= 0) {
        total += entry.value;
        count++;
      }
    }
    if (count == 0) return null;
    return total / count;
  }

  // ─── Defaults ──────────────────────────────────────────────────────────────

  List<AppGroup> _defaultGroups() => [
        AppGroup(
          name: 'Social Media',
          packageNames: [
            'com.instagram.android',
            'com.facebook.katana',
            'com.twitter.android',
            'com.zhiliaoapp.musically',
            'com.snapchat.android',
          ],
          timeLimitMinutes: 30,
          bannedFeatures: [
            BannedFeature(
              id: 'ig_reels',
              name: 'Instagram Reels',
              packageName: 'com.instagram.android',
              contentKeywords: ['reels', 'clips', 'reels_tab', 'clips_viewer'],
              activityPattern: '.*reels.*|.*clips.*',
            ),
            BannedFeature(
              id: 'fb_reels',
              name: 'Facebook Reels',
              packageName: 'com.facebook.katana',
              contentKeywords: ['reels', 'watch', 'fb_shorts', 'video_tab'],
              activityPattern: '.*reels.*|.*watch.*',
            ),
            BannedFeature(
              id: 'snap_spotlight',
              name: 'Snapchat Spotlight',
              packageName: 'com.snapchat.android',
              contentKeywords: ['spotlight', 'spotlight_tab', 'discover_spotlight'],
              activityPattern: '.*spotlight.*',
            ),
          ],
        ),
        AppGroup(
          name: 'Games',
          packageNames: [
            'com.supercell.clashofclans',
            'com.king.candycrushsaga',
          ],
          timeLimitMinutes: 60,
        ),
        AppGroup(
          name: 'Entertainment',
          packageNames: [
            'com.google.android.youtube',
            'com.netflix.mediaclient',
          ],
          timeLimitMinutes: 90,
          bannedFeatures: [
            BannedFeature(
              id: 'yt_shorts',
              name: 'YouTube Shorts',
              packageName: 'com.google.android.youtube',
              contentKeywords: ['shorts', 'reel_player', 'shorts_tab', 'shorts_player'],
              activityPattern: '.*reel.*|.*shorts.*',
            ),
          ],
        ),
        AppGroup(
          name: 'News & Reading',
          packageNames: [
            'com.google.android.apps.magazines',
            'flipboard.app',
            'com.reddit.frontpage',
          ],
          timeLimitMinutes: 45,
          bannedFeatures: [
            BannedFeature(
              id: 'reddit_popular',
              name: 'Reddit Popular',
              packageName: 'com.reddit.frontpage',
              contentKeywords: ['popular', 'watch', 'shorts'],
            ),
          ],
        ),
      ];
}

