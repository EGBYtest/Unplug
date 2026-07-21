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

  // ─── Settings Lock ──────────────────────────────────────────────────────────

  bool get settingsLockEnabled => _prefs?.getBool('settings_lock_enabled') ?? false;

  Future<void> setSettingsLockEnabled(bool value) async {
    await _prefs?.setBool('settings_lock_enabled', value);
  }

  bool get settingsLockAutoEnabled => _prefs?.getBool('settings_lock_auto_enabled') ?? false;

  Future<void> setSettingsLockAutoEnabled() async {
    await _prefs?.setBool('settings_lock_auto_enabled', true);
  }

  // ─── App Groups ────────────────────────────────────────────────────────────

  List<AppGroup> loadGroups() {
    final json = _prefs?.getString('app_groups');
    if (json == null || json.isEmpty) return _defaultGroups();
    try {
      final List<dynamic> decoded = jsonDecode(json) as List<dynamic>;
      return decoded
          .map((e) => AppGroup.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return _defaultGroups();
    }
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

  // ─── Defaults ──────────────────────────────────────────────────────────────

  List<AppGroup> _defaultGroups() => [
        AppGroup(
          name: 'Social Media',
          packageNames: [
            'com.instagram.android',
            'com.facebook.katana',
            'com.twitter.android',
            'com.zhiliaoapp.musically',
          ],
          timeLimitMinutes: 30,
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
        ),
        AppGroup(
          name: 'News & Reading',
          packageNames: [
            'com.google.android.apps.magazines',
            'flipboard.app',
          ],
          timeLimitMinutes: 45,
        ),
      ];
}
