import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'lock_screen_popup.dart';
import 'onboarding_screen.dart';
import 'settings_screen.dart';
import 'services/app_closure_handler.dart';
import 'services/usage_tracker.dart';
import 'services/storage_service.dart';
import 'services/update_checker.dart';
import 'services/apk_downloader.dart';
import 'models/app_group.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final UsageTracker _tracker = UsageTracker();
  final StorageService _storage = StorageService();
  Map<String, int> _usageMinutes = {};
  int _totalMinutesToday = 0;
  bool _loading = true;
  Timer? _refreshTimer;
  Timer? _updateCheckTimer;
  late List<AppGroup> _groups;
  UpdateInfo? _updateInfo;
  String? _dismissedVersion;

  // In-app update state. null progress means "not downloading"; the banner
  // otherwise has no way to tell a real download from the old "tap and hope"
  // tap target, and a button that silently does nothing while bytes move is
  // the thing users report as "it's stuck".
  double? _downloadProgress;
  String? _updateError;
  bool _installHandedOff = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _groups = _storage.loadGroups();
    _loadUsage();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _loadUsage());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPermissionsOnStart());
    _checkUpdate();
    // The timer is a nudge, not a demand. UpdateChecker holds a request for
    // at least minCheckInterval, so this costs nothing until the window has
    // passed. It fires often mainly so the banner appears soon after a release
    // for someone already sitting in the app.
    _updateCheckTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _checkUpdate();
    });
  }

  Future<void> _checkUpdate() async {
    // UpdateChecker owns the caching and the request budget, so a resume does
    // not cost a request. The cache here used to be a static written without
    // awaiting in main(), which the first render raced; that is gone.
    final UpdateInfo info = await UpdateChecker.check();
    if (!mounted) return;
    setState(() {
      if (info.isAvailable) {
        _updateInfo = info;
        // A newer release than the one they dismissed is a new thing to
        // acknowledge, so the banner comes back.
        if (_dismissedVersion != null &&
            _dismissedVersion != info.latestVersion) {
          _dismissedVersion = null;
        }
      } else {
        _updateInfo = null;
        _dismissedVersion = null;
      }
    });
  }

  Future<void> _checkPermissionsOnStart() async {
    final hasUsage = await AppClosureHandler().hasUsageAccess();
    final hasAccessibility = await AppClosureHandler().hasAccessibilityEnabled();
    final hasOverlay = await AppClosureHandler().hasOverlayPermission();
    if (!mounted) return;
    if (!hasUsage || !hasAccessibility || !hasOverlay) {
      final missing = [
        if (!hasUsage) 'Usage Access',
        if (!hasAccessibility) 'Accessibility Service',
        if (!hasOverlay) 'Display Over Other Apps',
      ];
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Permissions Required'),
          content: Text(
            'Unplug needs the following permissions to function:\n\n'
            '${missing.map((p) => '• $p').join('\n')}\n\n'
            'Tap "Open Settings" to enable them.',
          ),
          actions: [
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Later'),
            ),
            CupertinoDialogAction(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(
                  CupertinoPageRoute(builder: (_) => const OnboardingScreen()),
                );
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _updateCheckTimer?.cancel();
    super.dispose();
  }

  // Reload usage when app comes back to foreground
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadUsage();
      _checkUpdate();
    }
  }

  Future<void> _loadUsage() async {
    if (!mounted) return;
    setState(() => _loading = true);
    Map<String, int> usage = {};
    int total = 0;
    for (var group in _groups) {
      final groupUsage = await _tracker.getGroupUsage(group.packageNames);
      usage[group.name] = groupUsage;
      total += groupUsage;
    }
    if (!mounted) return;

    final today = _storage.dayKey(DateTime.now());
    await _storage.saveDailyEntry(today, total);

    if (!mounted) return;
    setState(() {
      _usageMinutes = usage;
      _totalMinutesToday = total;
      _loading = false;
    });
  }

  int get _totalLimitMinutes =>
      _groups.fold(0, (sum, g) => sum + g.timeLimitMinutes);

  String _fmt(int minutes) {
    if (minutes <= 0) return '0m';
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Colors.black,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Dashboard', style: TextStyle(color: Colors.white)),
            backgroundColor: const Color(0xFF0F0F0F).withOpacity(0.9),
            border: null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _loadUsage,
                  child: const Icon(CupertinoIcons.arrow_clockwise, color: Colors.white54, size: 20),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () async {
                    await Navigator.of(context).push(
                      CupertinoPageRoute(builder: (_) => const SettingsScreen()),
                    );
                    // Reload groups after returning from settings (user may have changed limits)
                    setState(() { _groups = _storage.loadGroups(); });
                    _loadUsage();
                  },
                  child: const Icon(CupertinoIcons.settings, color: Colors.white),
                ),
              ],
            ),
          ),
          SliverSafeArea(
            top: false,
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 24),
                if (UpdateChecker.shouldShowBanner(_updateInfo, _dismissedVersion))
                  _buildUpdateBanner(),
                _buildRing(),
                const SizedBox(height: 16),
                _buildStatCards(),
                const SizedBox(height: 24),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text('APP LIMITS', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                ),
                const SizedBox(height: 8),
                if (_loading)
                  const Padding(padding: EdgeInsets.all(40), child: Center(child: CupertinoActivityIndicator()))
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Column(
                        children: _groups.asMap().entries.map((entry) {
                          final i = entry.key;
                          final group = entry.value;
                          final used = _usageMinutes[group.name] ?? 0;
                          final bonusSeconds =
                              _storage.remainingBonusSeconds(group.name, used);
                          final bonusMinutes = bonusSeconds ~/ 60;
                          final effectiveLimit = _storage.effectiveLimitMinutes(
                              group.name, group.timeLimitMinutes, used);
                          // 0-minute limit = always blocked; clamp usage for display
                          final remaining = effectiveLimit == 0 ? 0 : (effectiveLimit - used).clamp(0, effectiveLimit);
                          final isExhausted = effectiveLimit == 0 || used >= effectiveLimit;
                          final progress = effectiveLimit == 0 ? 1.0 : (used / effectiveLimit).clamp(0.0, 1.0);
                          final isLast = i == _groups.length - 1;

                          return _AppLimitTile(
                            group: group,
                            usedMinutes: used,
                            remaining: remaining,
                            isExhausted: isExhausted,
                            progress: progress,
                            bonusMinutes: bonusMinutes,
                            formatMinutes: _fmt,
                            isLast: isLast,
                            onTap: bonusSeconds > 0
                                ? () => showCupertinoModalPopup(
                                  context: context,
                                  builder: (ctx) => CupertinoActionSheet(
                                    title: Text(group.name),
                                    message: Text('${_fmt(bonusMinutes * 60)} bonus time remaining', style: const TextStyle(color: Color(0xFF30D158), fontSize: 12)),
                                    actions: [
                                      CupertinoActionSheetAction(
                                        child: const Text('Get More Bonus Time'),
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                          showCupertinoDialog(
                                            context: context,
                                            builder: (_) => LockScreenPopup(
                                              appName: group.name,
                                              groupName: group.name,
                                            ),
                                          ).then((_) => _loadUsage());
                                        },
                                      ),
                                      CupertinoActionSheetAction(
                                        isDestructiveAction: true,
                                        child: const Text('Remove Bonus Time'),
                                        onPressed: () async {
                                          Navigator.pop(ctx);
                                          await _storage.resetBonusSeconds(group.name);
                                          _loadUsage();
                                        },
                                      ),
                                    ],
                                    cancelButton: CupertinoActionSheetAction(
                                      isDestructiveAction: true,
                                      child: const Text('Cancel'),
                                      onPressed: () => Navigator.pop(ctx),
                                    ),
                                  ),
                                )
                                : () => showCupertinoDialog(
                                  context: context,
                                  builder: (_) => LockScreenPopup(
                                    appName: group.name,
                                    groupName: group.name,
                                  ),
                                ).then((_) => _loadUsage()),
                            onRemoveBonus: bonusSeconds > 0
                                ? () async {
                                    final confirm = await showCupertinoDialog<bool>(
                                      context: context,
                                      builder: (ctx) => CupertinoAlertDialog(
                                        title: const Text('Remove Bonus Time'),
                                        content: Text('Remove ${_fmt(bonusMinutes * 60)} bonus time from "${group.name}"?'),
                                        actions: [
                                          CupertinoDialogAction(
                                            child: const Text('Cancel'),
                                            onPressed: () => Navigator.pop(ctx, false),
                                          ),
                                          CupertinoDialogAction(
                                            isDestructiveAction: true,
                                            child: const Text('Remove'),
                                            onPressed: () => Navigator.pop(ctx, true),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await _storage.resetBonusSeconds(group.name);
                                      _loadUsage();
                                    }
                                  }
                                : null,
                          );
                         }).toList(),
                       ),
                     ),
                   ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: const Color(0xFF0A84FF).withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 4))],
                    ),
                    child: CupertinoButton.filled(
                      borderRadius: BorderRadius.circular(14),
                      onPressed: () async {
                        await Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const SettingsScreen()));
                        setState(() { _groups = _storage.loadGroups(); });
                        _loadUsage();
                      },
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(CupertinoIcons.slider_horizontal_3, size: 18),
                          SizedBox(width: 8),
                          Text('Manage App Groups', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 48),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRing() {
    final double fraction = _totalLimitMinutes > 0
        ? (_totalMinutesToday / _totalLimitMinutes).clamp(0.0, 1.0)
        : 0.0;

    final double? weeklyAverage = _storage.getAverageDailyMinutes();
    final bool hasAverage = weeklyAverage != null;
    final bool isOverAverage = hasAverage && _totalMinutesToday > weeklyAverage;
    final int diffMinutes = hasAverage ? (_totalMinutesToday - weeklyAverage).abs().round() : 0;

    final Color ringColor = !hasAverage
        ? const Color(0xFF0A84FF)
        : isOverAverage
            ? const Color(0xFFFF3B30)
            : const Color(0xFF30D158);

    String subtitle;
    if (_loading) {
      subtitle = '';
    } else if (!hasAverage) {
      subtitle = 'No weekly data yet';
    } else if (isOverAverage) {
      subtitle = '${_fmt(diffMinutes)} over weekly avg';
    } else {
      subtitle = '${_fmt(diffMinutes)} under weekly avg';
    }

    return Center(
      child: Container(
        width: 240,
        height: 240,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF121212),
          boxShadow: [BoxShadow(color: ringColor.withOpacity(0.18), blurRadius: 40, spreadRadius: 10)],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 200,
              height: 200,
              child: CircularProgressIndicator(
                value: fraction,
                strokeWidth: 12,
                backgroundColor: const Color(0xFF2C2C2E),
                valueColor: AlwaysStoppedAnimation<Color>(ringColor),
                strokeCap: StrokeCap.round,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _loading ? '--' : _fmt(_totalMinutesToday),
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1),
                ),
                const SizedBox(height: 4),
                const Text("Today's Screentime", style: TextStyle(fontSize: 13, color: Colors.white54, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: ringColor, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the release page in the browser.
  ///
  /// This is the fallback, not the main path: every step of a browser upgrade
  /// is a step where the user can get stuck, which is the problem the in-app
  /// downloader exists to remove. It stays reachable because a download that
  /// fails on a captive portal or a throttled connection should still leave a
  /// way forward.
  Future<void> _openReleasePage() async {
    final url = _updateInfo?.downloadUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _startUpdateDownload() async {
    final info = _updateInfo;
    if (info == null) return;
    setState(() {
      _downloadProgress = 0.0;
      _updateError = null;
      _installHandedOff = false;
    });
    try {
      final file = await ApkDownloader.download(
        info.apkUrl,
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress = p);
        },
      );
      if (!mounted) return;
      setState(() => _downloadProgress = null);
      final handedOff = await ApkDownloader.install(file);
      if (!mounted) return;
      if (handedOff) {
        setState(() => _installHandedOff = true);
      } else {
        // The install permission is not granted yet — MainActivity has already
        // sent the user to the right settings screen. Say what happened rather
        // than closing the dialog on them.
        setState(() => _updateError =
            'Turn on "Install unknown apps" for Unplug, then tap to finish updating.');
      }
    } on ApkDownloadException catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadProgress = null;
        _updateError = e.message;
      });
    }
  }

  Widget _buildUpdateBanner() {
    final double? progress = _downloadProgress;
    final bool downloading = progress != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: GestureDetector(
        onTap: () {
          // A tap while bytes are moving must not start a second download.
          if (downloading) return;
          _startUpdateDownload();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF0A84FF).withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A84FF).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(CupertinoIcons.cloud_download_fill, color: Color(0xFF0A84FF), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Update v${_updateInfo!.latestVersion} available',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _bannerSubtitle(downloading),
                          style: const TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _dismissedVersion = _updateInfo!.latestVersion),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      child: const Icon(CupertinoIcons.clear_circled, color: Colors.white38, size: 18),
                    ),
                  ),
                ],
              ),
              if (downloading) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0A84FF)),
                  ),
                ),
              ],
              if (_updateError != null) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _openReleasePage,
                  child: Text(
                    'Open the release page in your browser instead →',
                    style: TextStyle(
                      color: const Color(0xFF0A84FF).withOpacity(0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _bannerSubtitle(bool downloading) {
    if (downloading) return 'Downloading… ${(_downloadProgress! * 100).round()}%';
    if (_installHandedOff) return 'Confirm the install to finish';
    if (_updateError != null) return 'Tap to try again';
    return 'Tap to download and install';
  }

  Widget _buildStatCards() {
    // Effective limit, not limit + lifetime granted credit. Credit is spent as
    // it is used, so the granted total no longer describes what the user has
    // left — this must agree with the native limiter's own arithmetic or the
    // dashboard will show a group as available that enforcement blocks.
    final exhausted = _groups.where((g) {
      final used = _usageMinutes[g.name] ?? 0;
      final effectiveLimit =
          _storage.effectiveLimitMinutes(g.name, g.timeLimitMinutes, used);
      return effectiveLimit == 0 || used >= effectiveLimit;
    }).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(child: _StatCard(label: 'Groups', value: '${_groups.length}', icon: CupertinoIcons.collections, color: const Color(0xFF0A84FF))),
          const SizedBox(width: 10),
          Expanded(child: _StatCard(label: 'Exhausted', value: '$exhausted', icon: CupertinoIcons.lock_fill, color: const Color(0xFFFF3B30))),
          const SizedBox(width: 10),
          Expanded(child: _StatCard(label: 'Active', value: '${_groups.length - exhausted}', icon: CupertinoIcons.checkmark_circle_fill, color: const Color(0xFF30D158))),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54)),
        ],
      ),
    );
  }
}

class _AppLimitTile extends StatelessWidget {
  final AppGroup group;
  final int usedMinutes;
  final int remaining;
  final bool isExhausted;
  final double progress;
  final int bonusMinutes;
  final String Function(int) formatMinutes;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback? onRemoveBonus;

  const _AppLimitTile({
    required this.group, required this.usedMinutes, required this.remaining,
    required this.isExhausted, required this.progress, required this.bonusMinutes,
    required this.formatMinutes, required this.isLast, required this.onTap,
    this.onRemoveBonus,
  });

  @override
  Widget build(BuildContext context) {
    final Color accentColor = isExhausted
        ? const Color(0xFFFF3B30)
        : progress > 0.75
            ? const Color(0xFFFFD60A)
            : const Color(0xFF0A84FF);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFF2C2C2E), width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: accentColor.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                  child: Icon(isExhausted ? CupertinoIcons.lock_fill : CupertinoIcons.timer, color: accentColor, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group.name, style: TextStyle(color: isExhausted ? Colors.white38 : Colors.white, fontWeight: FontWeight.w600, fontSize: 15, decoration: isExhausted ? TextDecoration.lineThrough : null)),
                      Text(
                        '${group.packageNames.length} apps  •  ${formatMinutes(group.timeLimitMinutes)} limit${bonusMinutes > 0 ? "  +${formatMinutes(bonusMinutes)} bonus" : ""}',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      isExhausted ? 'DONE' : formatMinutes(remaining),
                      style: TextStyle(color: accentColor, fontWeight: FontWeight.w700, fontSize: 15, shadows: [Shadow(color: accentColor.withOpacity(0.4), blurRadius: 8)]),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (bonusMinutes > 0 && onRemoveBonus != null)
                          GestureDetector(
                            onTap: onRemoveBonus,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF3B30).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('−bonus', style: TextStyle(color: Color(0xFFFF3B30), fontSize: 9, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        Text(isExhausted ? 'Tap for +time' : 'left', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: progress, backgroundColor: const Color(0xFF2C2C2E), valueColor: AlwaysStoppedAnimation<Color>(accentColor), minHeight: 4),
            ),
          ],
        ),
      ),
    );
  }
}
