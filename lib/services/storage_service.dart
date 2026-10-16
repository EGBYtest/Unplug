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
  ///
  /// 3m59s rather than a round 5m: the second wheel can reach 59, so a round
  /// ceiling would make the last four minutes unreachable and 4:00 would read
  /// as "the end" while sitting visibly above 3:59. The wheel should end where
  /// it looks like it ends.
  static const int maxWaitSeconds = 3 * 60 + 59;

  static const int defaultWaitSeconds = 30;

  /// Step between selectable values. Every second is meaningful here — the
  /// whole point of the setting is choosing the precise amount of friction, so
  /// a coarse grid would defeat it.
  static const int waitStepSeconds = 1;

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
  //
  // MODEL: bonus is a *credit*, not a raise of the daily limit.
  //
  // It used to be added to the limit: totalLimit = limit + bonus. That reads
  // naturally but behaves badly. A user at 50 minutes against a 40 minute
  // limit who wants 5 more minutes has to clear 50 before a 5 minute bonus
  // lifts the ceiling to 45 — which is still under 50, so it does nothing.
  // They watch three bonuses to get the ceiling to 55 and end up with 5
  // minutes of headroom for three waits' effort. The number the user picked
  // and the number they got are not the same number.
  //
  // Now the ceiling is: limit + remainingCredit, where credit is drawn down as
  // it is spent. Spending is measured against an anchor — the usage reading at
  // the moment the bonus was granted — so the credit always buys exactly the
  // amount the user chose, no matter how far over the limit they already were.
  //
  // The anchor is what makes this a pure read. Neither side writes on
  // consumption: the balance is (granted - spent), and spent is derived as
  // (usageNow - anchor). The native service therefore still only reads
  // SharedPreferences, which is what keeps enforcement working while the app
  // is closed.

  /// Key for a group's granted credit, scoped to the day it was earned on.
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

  /// Usage reading captured when credit was granted. Same day scoping and
  /// same cross-language contract as [_bonusKey].
  String _bonusAnchorKey(String groupName) =>
      'bonus_anchor_${groupName}_${dayKey(DateTime.now())}';

  /// Total credit granted today, before consumption. This is what
  /// [addBonusSeconds] accumulates and what the native service reads.
  int getBonusSeconds(String groupName) =>
      _prefs?.getInt(_bonusKey(groupName)) ?? 0;

/// Usage reading captured when credit was granted, or null if there is none.
  ///
  /// Null is distinct from zero. Installs upgrading from the old additive
  /// model carry a granted total with no anchor beside it, and reading that as
  /// an anchor of 0 would compute a ceiling of granted/60 — for a user with a
  /// 40 minute limit and 5 minutes of bonus, 5 rather than 45. They would
  /// silently lose bonus they had paid for. [effectiveLimitMinutes] falls back
  /// to the old arithmetic for those.
  int? getBonusAnchorMinutesOrNull(String groupName) =>
      _prefs?.getInt(_bonusAnchorKey(groupName));

  int getBonusAnchorMinutes(String groupName) =>
      getBonusAnchorMinutesOrNull(groupName) ?? 0;

  /// Grants [seconds] of credit, settling what was already spent first.
  ///
  /// The anchor moves to [usageMinutes] on every grant, but only *after* the
  /// balance has been settled against it. Order matters, and getting it wrong
  /// fails in both directions:
  ///
  ///  * Re-anchoring without settling refunds everything used since the last
  ///    grant, silently doubling the payout.
  ///  * Never re-anchoring is worse, and is what this replaced. The anchor
  ///    stayed pinned to the first grant of the day, so every minute spent
  ///    after it was subtracted from the running total forever — including
  ///    credit earned much later. Observed on device: anchor pinned at 30m,
  ///    25 minutes used since, then a 3 minute reward granted. Credit was 9
  ///    minutes, usage past the anchor was 25, so the balance computed to
  ///    zero: the dashboard read "no bonus time" the instant it was granted,
  ///    and the ceiling was 39m against 55m of usage, so the group stayed
  ///    blocked. The 3 minutes bought nothing *and* retroactively destroyed
  ///    the earlier grant.
  ///
  /// Settling first makes "+3m" mean three more minutes from where the user is
  /// standing, which is the only reading anyone would give those words.
  ///
  /// Settling preserves the ceiling exactly: anchor + credit is invariant
  /// under settle-then-re-anchor whenever the credit has not already run out,
  /// because (anchor + spent) + (credit - spent) == anchor + credit. It only
  /// moves the ceiling when the credit *was* exhausted — and then it moves it
  /// up, because the exhausted credit was already worth nothing and the new
  /// grant is measured from a usage reading that is finally true.
  ///
  /// [usageMinutes] is a reading that can come back wrong: usage access can
  /// fail, and it can legitimately read lower than the last grant after a
  /// hiccup or a reset-hour change mid-day. The anchor therefore only ever
  /// moves forward. A failed query settles nothing and re-anchors nothing, so
  /// a reward can never be lost to a bad reading — the failure mode of
  /// anchoring to 0 would be a ceiling of 0, confiscating every bonus the
  /// user has paid for.
  Future<void> addBonusSeconds(
    String groupName,
    int seconds, {
    int usageMinutes = 0,
  }) async {
    final key = _bonusKey(groupName);
    final anchorKey = _bonusAnchorKey(groupName);
    final current = _prefs?.getInt(key) ?? 0;
    final existingAnchor = _prefs?.getInt(anchorKey);
    unawaited(_purgeStaleBonuses());

    // Credit that has not already been spent cannot be refunded, so anything
    // beyond the anchor is written off rather than carried into the new grant.
    final spent = existingAnchor != null && usageMinutes > existingAnchor
        ? (usageMinutes - existingAnchor) * 60
        : 0;
    final settled = current - spent;
    final carried = settled > 0 ? settled : 0;

    // Forward-only. A reading below the stored anchor is not trusted to pull
    // the anchor back, which is what would let a bad reading hand out free
    // screen time by looking like unspent credit.
    final anchor = existingAnchor != null && usageMinutes < existingAnchor
        ? existingAnchor
        : usageMinutes;

    await _prefs?.setInt(anchorKey, anchor);
    await _prefs?.setInt(key, carried + seconds);
  }

  /// Credit remaining, in seconds.
  ///
  /// [usageMinutes] is the group's usage reading now. Only usage *beyond* the
  /// anchor draws credit down. Usage can legitimately read lower than the
  /// grant-time value — usage access hiccuping and returning a partial total,
  /// or a reset hour changed mid-day — and crediting that gap back would hand
  /// out time nobody earned, by a margin as large as the gap.
  int remainingBonusSeconds(String groupName, int usageMinutes) {
    final granted = getBonusSeconds(groupName);
    if (granted <= 0) return 0;
    final anchor = getBonusAnchorMinutesOrNull(groupName);
    // No anchor: written before this model existed. Treat as unspent.
    if (anchor == null) return granted;
    final spent = usageMinutes > anchor ? usageMinutes - anchor : 0;
    final remaining = granted - spent * 60;
    return remaining > 0 ? remaining : 0;
  }

  /// Ceiling in minutes: the higher of the limit and the credit budget.
  ///
  /// Credit reaches (usage at grant) + (everything granted) — a fixed budget,
  /// not a balance to subtract from the limit. Subtracting spent credit would
  /// shrink the ceiling as the user spends it, so the instant they started
  /// using the bonus they would drop below it again. Spending has to move
  /// usage up towards a target, not the target down towards usage.
  ///
  /// So a user at 50 minutes against a 40 minute limit who earns 5 minutes
  /// gets a 55 minute ceiling — the five they chose — rather than 45, which is
  /// still under their usage and would look like the bonus did nothing.
  ///
  /// Shared with the native service, which computes the same expression from
  /// the same keys. Both sides must agree or the dashboard and the limiter
  /// will disagree about whether the user is allowed in.
  int effectiveLimitMinutes(
      String groupName, int limitMinutes, int usageMinutes) {
    if (limitMinutes == 0) return 0;
    final granted = getBonusSeconds(groupName);
    if (granted <= 0) return limitMinutes;
    final anchor = getBonusAnchorMinutesOrNull(groupName);
    if (anchor == null) return limitMinutes + granted ~/ 60;
    final creditCeiling = (anchor * 60 + granted) ~/ 60;
    return creditCeiling > limitMinutes ? creditCeiling : limitMinutes;
  }

  Future<void> resetBonusSeconds(String groupName) async {
    await _prefs?.remove(_bonusKey(groupName));
    await _prefs?.remove(_bonusAnchorKey(groupName));
  }

  /// Removes bonus keys that are not scoped to today.
  ///
  /// Pure housekeeping — correctness does not depend on it, because the day
  /// suffix already makes a stale balance invisible to both readers. Without
  /// it these would accumulate one entry per group per day forever.
  ///
  /// The suffix is compared against '_<today>', matching the underscore that
  /// [dayKey] is joined with. It used to test for '-<today>', which no key
  /// can ever end with, so this matched nothing and the sweep silently did
  /// nothing for the life of the app — every day of usage adding two dead
  /// entries per group that nothing ever read or removed.
  Future<void> _purgeStaleBonuses() async {
    final today = dayKey(DateTime.now());
    final suffix = '_$today';
    final keys = _prefs?.getKeys() ?? {};
    for (final k in keys) {
      if ((k.startsWith('bonus_seconds_') || k.startsWith('bonus_anchor_')) &&
          !k.endsWith(suffix)) {
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

