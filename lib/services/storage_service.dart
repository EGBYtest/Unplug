import 'dart:async';
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

  int get resetHour => _prefs?.getInt('reset_hour') ?? 2;

  Future<void> saveResetHour(int hour) async {
    await _prefs?.setInt('reset_hour', (hour ~/ 2) * 2);
  }

  DateTime _dayStart(DateTime dt) {
    final h = resetHour;
    if (dt.hour < h) {
      dt = dt.subtract(const Duration(days: 1));
    }
    return DateTime(dt.year, dt.month, dt.day, h);
  }

  String dayKey(DateTime dt) {
    final h = resetHour;
    if (dt.hour < h) {
      dt = dt.subtract(const Duration(days: 1));
    }
    return dt.toIso8601String().substring(0, 10);
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _purgeStaleBonuses();
  }

  // ─── Onboarding ────────────────────────────────────────────────────────────

  bool get onboardingComplete => _prefs?.getBool('onboarding_complete') ?? false;

  Future<void> setOnboardingComplete() async {
    await _prefs?.setBool('onboarding_complete', true);
  }

  // ─── Bonus reward seconds ───────────────────────────────────────────────
  // How many SECONDS of bonus time a completed reward action grants.
  //
  // The on-disk key is still "ad_reward_seconds" from when this was called
  // an ad. It has never been an ad and no ad SDK exists, but renaming the
  // key would silently reset every existing user's configured reward to the
  // 60s default. Dart is the only reader, so there is no cross-language
  // contract here to keep in sync — just the stored value.

  /// Ceiling on a single reward action.
  ///
  /// Bonus time is not drawn down as it is spent — it raises the day's limit
  /// and stays raised. So the reward per action is effectively a multiplier on
  /// 30 seconds of waiting, and an uncapped picker let one wait be worth any
  /// amount of screen time at all.
  static const int maxBonusRewardSeconds = 20 * 60;

  static const int defaultBonusRewardSeconds = 60;

  /// Step between selectable reward values. Whole minutes — the reward is a
  /// budget extension, and sub-minute granularity was noise.
  static const int bonusRewardStepSeconds = 60;

  /// Every selectable reward value, from zero up to and including the cap.
  ///
  /// The settings screen builds its picker from this rather than using
  /// CupertinoTimerPicker, which has no min/max and will happily scroll past
  /// any bound and silently clamp on save. An explicit list cannot be
  /// scrolled past, so the ceiling the user sees is the ceiling enforced.
  static List<int> bonusRewardOptions() => [
        for (int s = 0; s <= maxBonusRewardSeconds; s += bonusRewardStepSeconds)
          s,
      ];

  /// Clamped on read as well as on write. Installs that already stored a
  /// larger value are corrected the moment they launch, without a migration.
  int get bonusRewardSeconds {
    final stored = _prefs?.getInt('ad_reward_seconds') ?? defaultBonusRewardSeconds;
    return stored.clamp(0, maxBonusRewardSeconds);
  }

  Future<void> saveBonusRewardSeconds(int seconds) async {
    await _prefs?.setInt(
      'ad_reward_seconds',
      seconds.clamp(0, maxBonusRewardSeconds),
    );
  }

  Future<void> resetBonusSeconds(String groupName) async {
    await _prefs?.remove(_bonusKey(groupName));
  }

  // ─── Wait duration ──────────────────────────────────────────────────────────
  // How long the bonus-time wait actually runs, in seconds.
  //
  // Distinct from bonusRewardSeconds: that is what you are PAID, this is what
  // it COSTS you. Raising the wait is the half of the trade the app does not
  // get to decide, so it has to be the user's setting and not a constant.

  /// Floor. The original hardcoded wait. Below this the friction that makes
  /// the feature work stops being friction.
  static const int minWaitSeconds = 30;

  /// Ceiling. Beyond this the wait stops being a negotiation and becomes a
  /// punishment — long enough that a user in the middle of something will just
  /// uninstall instead, which is the exact opposite of the intended outcome.
  static const int maxWaitSeconds = 5 * 60;

  static const int defaultWaitSeconds = 30;

  /// Step between selectable values. 30s granularity keeps the list short
  /// enough to be a deliberate choice rather than a scroll to be lost in.
  static const int waitStepSeconds = 30;

  /// Every selectable wait duration, from the floor up to and including the
  /// ceiling. An explicit bounded list, for the same reason
  /// [bonusRewardOptions] is one: CupertinoTimerPicker has no min/max and will
  /// scroll past any bound and silently clamp on save.
  static List<int> waitOptions() => [
        for (int s = minWaitSeconds; s <= maxWaitSeconds; s += waitStepSeconds)
          s,
      ];

  /// Clamped on read as well as on write, so a stored value outside the range
  /// is corrected the moment the app launches rather than producing an
  /// unskippable or instantly-expiring wait.
  int get waitSeconds {
    final stored =
        _prefs?.getInt('wait_seconds') ?? defaultWaitSeconds;
    return stored.clamp(minWaitSeconds, maxWaitSeconds);
  }

  Future<void> saveWaitSeconds(int seconds) async {
    await _prefs?.setInt(
      'wait_seconds',
      seconds.clamp(minWaitSeconds, maxWaitSeconds),
    );
  }

  // ─── Settings Lock ──────────────────────────────────────────────────────────

  bool get settingsLockEnabled => _prefs?.getBool('settings_lock_enabled') ?? true;

  Future<void> setSettingsLockEnabled(bool value) async {
    await _prefs?.setBool('settings_lock_enabled', value);
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
        isEnabled: false,
        contentKeywords: ['reels', 'clips', 'reels_tab', 'clips_viewer'],
        activityPattern: '.*reels.*|.*clips.*',
      ));
    }
    if (pkgs.contains('com.facebook.katana') || groupName == 'Social Media') {
      list.add(BannedFeature(
        id: 'fb_reels',
        name: 'Facebook Reels',
        packageName: 'com.facebook.katana',
        isEnabled: false,
        contentKeywords: ['reels', 'watch', 'fb_shorts', 'video_tab'],
        activityPattern: '.*reels.*|.*watch.*',
      ));
    }
    if (pkgs.contains('com.snapchat.android') || groupName == 'Social Media') {
      list.add(BannedFeature(
        id: 'snap_spotlight',
        name: 'Snapchat Spotlight',
        packageName: 'com.snapchat.android',
        isEnabled: false,
        contentKeywords: ['spotlight', 'spotlight_tab', 'discover_spotlight'],
        activityPattern: '.*spotlight.*',
      ));
    }
    if (pkgs.contains('com.google.android.youtube') || groupName == 'Entertainment') {
      list.add(BannedFeature(
        id: 'yt_shorts',
        name: 'YouTube Shorts',
        packageName: 'com.google.android.youtube',
        isEnabled: false,
        contentKeywords: ['shorts', 'reel_player', 'shorts_tab', 'shorts_player'],
        activityPattern: '.*reel.*|.*shorts.*',
      ));
    }
    if (pkgs.contains('com.reddit.frontpage') || groupName == 'News & Reading') {
      list.add(BannedFeature(
        id: 'reddit_popular',
        name: 'Reddit Popular',
        packageName: 'com.reddit.frontpage',
        isEnabled: false,
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

  /// Key for a group's bonus, scoped to the day it was earned on.
  ///
  /// Day-scoping the key rather than clearing it is what makes the daily
  /// reset hold on both sides. The native AccessibilityService reads this key
  /// straight out of SharedPreferences and never runs Dart, so a reset that
  /// depends on Dart executing — at launch, or on a read — leaves yesterday's
  /// bonus in force for the native limiter on every day the app is not opened.
  /// With the day in the key, a stale balance is simply not found. No marker,
  /// no ordering, no dependence on the app running.
  ///
  /// The key format is a cross-language contract; UsageAccessibilityService
  /// builds the same string. Keep the two in step.
  String _bonusKey(String groupName) =>
      'bonus_seconds_${groupName}_${dayKey(DateTime.now())}';

  int getBonusSeconds(String groupName) =>
      _prefs?.getInt(_bonusKey(groupName)) ?? 0;

  Future<void> addBonusSeconds(String groupName, int seconds) async {
    final key = _bonusKey(groupName);
    final current = _prefs?.getInt(key) ?? 0;
    unawaited(_purgeStaleBonuses());
    await _prefs?.setInt(key, current + seconds);
  }

  /// Removes bonus keys that are not scoped to today.
  ///
  /// Pure housekeeping — correctness does not depend on it, because the day
  /// suffix already makes a stale balance invisible to both readers. Without
  /// it these would accumulate one entry per group per day forever.
  Future<void> _purgeStaleBonuses() async {
    final today = dayKey(DateTime.now());
    final keys = _prefs?.getKeys() ?? {};
    for (final k in keys) {
      if (k.startsWith('bonus_seconds_') && !k.endsWith('-$today')) {
        await _prefs?.remove(k);
      }
    }
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

    final today = dayKey(DateTime.now());
    final cutoff = _dayStart(DateTime.now()).subtract(Duration(days: days));

    int total = 0;
    int count = 0;
    for (final entry in history.entries) {
      if (entry.key == today) continue;
      // Compare as dates, not as strings. "2026-09-12" sorts after
      // "2026-10-05" lexicographically because '9' > '1' at the month
      // position, which pulled every entry from a previous month into the
      // average and skewed it high.
      final date = DateTime.tryParse(entry.key);
      if (date == null || date.isBefore(cutoff)) continue;
      total += entry.value;
      count++;
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
              id: 'snap_spotlight',
              name: 'Snapchat Spotlight',
              packageName: 'com.snapchat.android',
              isEnabled: false,
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
              isEnabled: false,
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
              isEnabled: false,
              contentKeywords: ['popular', 'watch', 'shorts'],
            ),
          ],
        ),
      ];
}

