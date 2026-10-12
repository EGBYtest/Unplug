import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/reward_gate.dart';
import 'services/message_verification.dart';
import 'services/storage_service.dart';
import 'services/usage_tracker.dart';
import 'models/app_group.dart';
import 'utils/no_paste_formatter.dart';
import 'screens/app_picker_screen.dart';
import 'generated/app_version.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _saving = false;
  final StorageService _storage = StorageService();
  late List<AppGroup> _groups;
  late List<BannedFeature> _globalTabBlockers;
  late int _bonusRewardSeconds;
  late int _waitSeconds;
  late int _resetHour;
  late bool _settingsLock;

  /// Per-group usage reading, used to work out how much bonus credit is
  /// actually left. Credit is anchored to the usage at grant time, so a
  /// granted total no longer describes what remains — showing it would
  /// disagree with what the limiter will actually allow.
  final Map<String, int> _usageMinutes = {};

  @override
  void initState() {
    super.initState();
    _groups = List.from(_storage.loadGroups());
    _globalTabBlockers = List.from(_storage.loadGlobalTabBlockers());
    _bonusRewardSeconds = _storage.bonusRewardSeconds;
    _waitSeconds = _storage.waitSeconds;
    _resetHour = _storage.resetHour;
    _settingsLock = _storage.settingsLockEnabled;
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    for (final g in List<AppGroup>.from(_storage.loadGroups())) {
      int used = 0;
      try {
        used = await UsageTracker().getGroupUsage(g.packageNames);
      } catch (_) {
        // Usage access revoked, or the query failed. Treat as zero: shows the
        // full granted credit rather than throwing the screen away.
      }
      if (mounted) setState(() => _usageMinutes[g.name] = used);
    }
  }

  // ─── Per-Change Challenge ─────────────────────────────────

  void _confirmChange(VoidCallback action) {
    // Settings Lock off → apply changes instantly, no challenge.
    if (!_settingsLock) {
      action();
      return;
    }
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Confirm Change'),
        message: const Text('Complete a challenge to change this setting.'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              RewardGate().showWait(
                context,
                action,
                () {},
                totalSeconds: _storage.waitSeconds,
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.clock_fill, color: Color(0xFF0A84FF), size: 18),
                SizedBox(width: 8),
                Text(
                  'Wait ${_formatSeconds(_storage.waitSeconds)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _typeToUnlock(action);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.pencil, color: Color(0xFF0A84FF), size: 18),
                SizedBox(width: 8),
                Text('Type 50 words', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
      ),
    );
  }

  void _typeToUnlock(VoidCallback action) {
    final ctrl = TextEditingController();
    final target = MessageVerification().generateMessage();

    showCupertinoDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setInner) {
          int wordCount = ctrl.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
          return CupertinoAlertDialog(
            title: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.pencil_outline, size: 18),
                SizedBox(width: 6),
                Text('Type to Confirm'),
              ],
            ),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF2C2C2E), borderRadius: BorderRadius.circular(8)),
                  child: Text(target, style: const TextStyle(fontSize: 11, color: Colors.white60, height: 1.5)),
                ),
                const SizedBox(height: 10),
                CupertinoTextField(
                  controller: ctrl,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white),
                  placeholder: 'Type exact message (no copy-paste)...',
                  inputFormatters: [NoPasteFormatter()],
                  contextMenuBuilder: (_, __) => const SizedBox.shrink(),
                  onChanged: (_) => setInner(() {}),
                ),
                const SizedBox(height: 6),
                Text(
                  '${ctrl.text.trim().split(RegExp(r"\s+")).where((w) => w.isNotEmpty).length} / 50 words',
                  style: TextStyle(
                    color: wordCount >= 50 ? const Color(0xFF30D158) : Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            actions: [
              CupertinoDialogAction(child: const Text('Cancel'), onPressed: () => Navigator.pop(ctx)),
              CupertinoDialogAction(
                isDefaultAction: true,
                child: const Text('Verify'),
                onPressed: () {
                  if (MessageVerification().verifyMessage(ctrl.text)) {
                    Navigator.pop(ctx);
                    action();
                  } else {
                    showCupertinoDialog(
                      context: ctx,
                      builder: (_) => CupertinoAlertDialog(
                        title: const Text('Mismatch'),
                        content: const Text('Text must match exactly (case-sensitive).'),
                        actions: [CupertinoDialogAction(child: const Text('OK'), onPressed: () => Navigator.pop(ctx))],
                      ),
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── Edit Group Limit ─────────────────────────────────────────────────────

  void _editLimit(int index) {
    final group = _groups[index];
    int tempMinutes = group.timeLimitMinutes % 60;
    int tempHours = group.timeLimitMinutes ~/ 60;

    showCupertinoModalPopup(
      context: context,
      builder: (_) => Container(
        height: 340,
        decoration: const BoxDecoration(
          color: Color(0xFF1C1C1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(group.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Text('Save', style: TextStyle(color: Color(0xFF0A84FF), fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      final totalMinutes = tempHours * 60 + tempMinutes;
                      setState(() => _groups[index] = AppGroup(
                        name: group.name,
                        packageNames: group.packageNames,
                        timeLimitMinutes: totalMinutes,
                      ));
                      await _storage.saveGroups(_groups);
                      if (mounted) Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 4),
            const Text('Daily Time Limit', style: TextStyle(color: Colors.white54, fontSize: 13)),
            Expanded(
              child: CupertinoTimerPicker(
                mode: CupertinoTimerPickerMode.hm,
                initialTimerDuration: Duration(minutes: group.timeLimitMinutes),
                onTimerDurationChanged: (d) {
                  tempHours = d.inHours;
                  tempMinutes = d.inMinutes % 60;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Edit Reward ───────────────────────────────────────────────────────────

  void _editAdRatio() {
    final options = StorageService.bonusRewardOptions();
    var selectedIndex = options.indexOf(_bonusRewardSeconds);
    if (selectedIndex < 0) {
      selectedIndex = options.indexOf(StorageService.defaultBonusRewardSeconds);
      if (selectedIndex < 0) selectedIndex = 0;
    }

    showCupertinoModalPopup(
      context: context,
      builder: (_) => Container(
        height: 340,
        decoration: const BoxDecoration(
          color: Color(0xFF1C1C1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text('Reward per Wait', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Text('Save', style: TextStyle(color: Color(0xFF0A84FF), fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      final value = options[selectedIndex];
                      setState(() => _bonusRewardSeconds = value);
                      await _storage.saveBonusRewardSeconds(value);
                      if (mounted) Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            const Text('Time granted per wait', style: TextStyle(color: Colors.white54, fontSize: 13)),
            // The last entry is the ceiling, not a scroll target: bonus time
            // is never drawn back down, so this value permanently raises the
            // day's limit by that much for everyone who completes a wait.
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                'Maximum 20m',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
            Expanded(
              // Bounded list from StorageService.bonusRewardOptions(), so it
              // cannot be scrolled past the cap.
              child: CupertinoPicker(
                itemExtent: 40,
                scrollController:
                    FixedExtentScrollController(initialItem: selectedIndex),
                onSelectedItemChanged: (i) => selectedIndex = i,
                children: options
                    .map((s) => Center(
                          child: Text(
                            _formatSeconds(s),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 20),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Edit Wait Duration ─────────────────────────────────────────────────────

  void _editWaitDuration() {
    var totalSeconds = _waitSeconds;

    showCupertinoModalPopup(
      context: context,
      builder: (popupContext) => _WaitDurationSheet(
        initialSeconds: totalSeconds,
        onCancel: () => Navigator.pop(popupContext),
        onSave: (value) async {
          setState(() => _waitSeconds = value);
          await _storage.saveWaitSeconds(value);
          if (mounted) Navigator.pop(popupContext);
        },
      ),
    );
  }

  // ─── Edit Apps in Group ───────────────────────────────────────────────────

  void _editGroupApps(int index) async {
    final group = _groups[index];
    final selected = await Navigator.of(context).push<List<String>>(
      CupertinoPageRoute(builder: (_) => AppPickerScreen(initialSelection: group.packageNames, groupName: group.name)),
    );
    if (selected != null) {
      setState(() => _groups[index] = AppGroup(name: group.name, packageNames: selected, timeLimitMinutes: group.timeLimitMinutes));
      await _storage.saveGroups(_groups);
    }
  }

  void _toggleBannedFeature(BannedFeature feature, bool isEnabled) async {
    setState(() {
      feature.isEnabled = isEnabled;
    });
    await _storage.saveGlobalTabBlockers(_globalTabBlockers);
  }

  // ─── Save ──────────────────────────────────────────────────────────
  Future<void> _save() async {
    setState(() => _saving = true);
    await _storage.saveGroups(_groups);
    await _storage.saveGlobalTabBlockers(_globalTabBlockers);
    await _storage.saveBonusRewardSeconds(_bonusRewardSeconds);
    await _storage.saveResetHour(_resetHour);

    if (mounted) {
      setState(() => _saving = false);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Colors.black,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Settings', style: TextStyle(color: Colors.white)),
        previousPageTitle: 'Dashboard',
        backgroundColor: const Color(0xFF0F0F0F).withOpacity(0.9),
        border: null,
        trailing: _saving
            ? const CupertinoActivityIndicator()
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _save,
                child: const Text('Save', style: TextStyle(color: Color(0xFF30D158), fontWeight: FontWeight.bold)),
              ),
      ),
      child: SafeArea(
            child: ListView(
              children: [
                // ── App Group Limits ──
                CupertinoListSection.insetGrouped(
                  backgroundColor: Colors.black,
                  decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(12)),
                  header: const Text('APP GROUP LIMITS', style: TextStyle(color: Colors.white54)),
                  children: _groups.asMap().entries.map((e) {
                    final i = e.key;
                    final group = e.value;
final bonusSeconds = _storage.remainingBonusSeconds(
                        group.name, _usageMinutes[group.name] ?? 0);
                    return CupertinoListTile(
                      backgroundColor: const Color(0xFF1C1C1E),
                      leading: const Icon(CupertinoIcons.timer, color: Color(0xFF0A84FF), size: 22),
                      title: Text(group.name, style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                        '${group.packageNames.length} apps${bonusSeconds > 0 ? "  •  +${_formatSeconds(bonusSeconds)} bonus" : ""}',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      additionalInfo: Text(_formatMinutes(group.timeLimitMinutes + bonusSeconds ~/ 60), style: const TextStyle(color: Colors.white70)),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => _showGroupOptions(i),
                    );
                  }).toList(),
                ),

                // Add Group button
                CupertinoListTile(
                  backgroundColor: const Color(0xFF1C1C1E),
                  leading: const Icon(CupertinoIcons.add_circled, color: Color(0xFF0A84FF), size: 22),
                  title: const Text('Add Group', style: TextStyle(color: Colors.white)),
                  onTap: () => _confirmChange(_addGroup),
                ),

                // ── In-App Tab Blockers ──
                CupertinoListSection.insetGrouped(
                  backgroundColor: Colors.black,
                  decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(12)),
                  header: const Text('IN-APP TAB BLOCKERS', style: TextStyle(color: Colors.white54)),
                  footer: const Text('Blocks short-form content tabs (YouTube Shorts, Instagram Reels, Snapchat Spotlight, etc.) while keeping the rest of the application accessible. Turning a blocker on is instant — turning it off requires a challenge.', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  children: _globalTabBlockers.isEmpty
                      ? [
                          CupertinoListTile(
                            backgroundColor: const Color(0xFF1C1C1E),
                            leading: const Icon(CupertinoIcons.arrow_counterclockwise, color: Color(0xFF0A84FF), size: 22),
                            title: const Text('Load Default Tab Blockers', style: TextStyle(color: Colors.white)),
                            subtitle: const Text('Tap to load YouTube Shorts, Instagram Reels & Snapchat Spotlight blockers', style: TextStyle(color: Colors.white38, fontSize: 12)),
                            onTap: () => _confirmChange(() async {
                              final defaults = _storage.loadGlobalTabBlockers();
                              setState(() { _globalTabBlockers = defaults; });
                            }),
                          ),
                        ]
                      : _globalTabBlockers.map((feature) {
                          final IconData iconData = feature.name.contains('YouTube')
                              ? CupertinoIcons.play_rectangle_fill
                              : feature.name.contains('Instagram')
                                  ? CupertinoIcons.camera_fill
                                  : feature.name.contains('Snapchat')
                                      ? CupertinoIcons.chat_bubble_2_fill
                                      : feature.name.contains('Facebook')
                                          ? CupertinoIcons.film_fill
                                          : CupertinoIcons.shield_fill;
                          return CupertinoListTile(
                            backgroundColor: const Color(0xFF1C1C1E),
                            leading: Icon(iconData, color: const Color(0xFFFF3B30), size: 22),
                            title: Text(feature.name, style: const TextStyle(color: Colors.white)),
                            subtitle: Text(
                              feature.isEnabled ? 'Active • Auto-back on tab open' : 'Disabled',
                              style: TextStyle(
                                color: feature.isEnabled ? const Color(0xFF30D158) : Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                            trailing: CupertinoSwitch(
                              value: feature.isEnabled,
                              onChanged: (val) {
                                if (val) {
                                  _toggleBannedFeature(feature, val);
                                } else {
                                  _confirmChange(() => _toggleBannedFeature(feature, val));
                                }
                              },
                            ),
                          );
                        }).toList(),
                ),

                // ── Ad Ratio ──
                CupertinoListSection.insetGrouped(
                  backgroundColor: Colors.black,
                  decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(12)),
                  header: const Text('REWARD-TO-TIME RATIO', style: TextStyle(color: Colors.white54)),
                  children: [
                    CupertinoListTile(
                      backgroundColor: const Color(0xFF1C1C1E),
                      leading: const Icon(CupertinoIcons.play_rectangle_fill, color: Color(0xFFFF9F0A), size: 22),
                      title: const Text('Reward per Wait', style: TextStyle(color: Colors.white)),
                      additionalInfo: Text(_formatSeconds(_bonusRewardSeconds), style: const TextStyle(color: Colors.white70)),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => _confirmChange(_editAdRatio),
                    ),
                    CupertinoListTile(
                      backgroundColor: const Color(0xFF1C1C1E),
                      leading: const Icon(CupertinoIcons.clock_fill, color: Color(0xFF0A84FF), size: 22),
                      title: const Text('Wait Duration', style: TextStyle(color: Colors.white)),
                      subtitle: const Text('30s to 3m 59s', style: TextStyle(color: Colors.white38, fontSize: 12)),
                      additionalInfo: Text(_formatSeconds(_waitSeconds), style: const TextStyle(color: Colors.white70)),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => _confirmChange(_editWaitDuration),
                    ),
                  ],
                ),

                // ── Daily Reset ──
                CupertinoListSection.insetGrouped(
                  backgroundColor: Colors.black,
                  decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(12)),
                  header: const Text('DAILY RESET', style: TextStyle(color: Colors.white54)),
                      footer: Text('Resets at ${_resetHour.toString().padLeft(2, '0')}:00 each day. Even hours only — aligns with Android usage data buckets.', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  children: [
                    CupertinoListTile(
                      backgroundColor: const Color(0xFF1C1C1E),
                      leading: const Icon(CupertinoIcons.moon_fill, color: Color(0xFF0A84FF), size: 22),
                      title: const Text('Reset Time', style: TextStyle(color: Colors.white)),
                      additionalInfo: Text('${_resetHour.toString().padLeft(2, '0')}:00', style: const TextStyle(color: Colors.white70)),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => _confirmChange(_editResetHour),
                    ),
                  ],
                ),

                // ── Security ──
                CupertinoListSection.insetGrouped(
                  backgroundColor: Colors.black,
                  decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(12)),
                  header: const Text('SECURITY', style: TextStyle(color: Colors.white54)),
                  footer: const Text('When on, changing settings requires the 30-second wait or typing challenge — including turning this off. Turn on to lock it back up.', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  children: [
                    CupertinoListTile(
                      backgroundColor: const Color(0xFF1C1C1E),
                      leading: const Icon(CupertinoIcons.lock_fill, color: Color(0xFF30D158), size: 22),
                      title: const Text('Settings Lock', style: TextStyle(color: Colors.white)),
                      subtitle: Text(
                        _settingsLock
                            ? 'Asks a question before changing settings. Stored on-device only — not secure against a rooted phone.'
                            : 'Changes apply instantly',
                        style: TextStyle(
                          color: _settingsLock ? const Color(0xFF30D158) : Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                      trailing: CupertinoSwitch(
                        value: _settingsLock,
                        onChanged: (val) {
                          // Turning the lock ON is always free — locking
                          // yourself in is not a way around it. Turning it OFF
                          // removes the challenge from every other setting
                          // here, so it costs the same as any of them.
                          if (val) {
                            setState(() => _settingsLock = true);
                            _storage.setSettingsLockEnabled(true);
                          } else {
                            _confirmChange(() {
                              setState(() => _settingsLock = false);
                              _storage.setSettingsLockEnabled(false);
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),

                // ── About ──
                CupertinoListSection.insetGrouped(
                  backgroundColor: Colors.black,
                  decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(12)),
                  header: const Text('ABOUT', style: TextStyle(color: Colors.white54)),
                  children: [
                    const CupertinoListTile(
                      backgroundColor: Color(0xFF1C1C1E),
                      leading: Icon(CupertinoIcons.lock_fill, color: Color(0xFF30D158), size: 22),
                      title: Text('Privacy', style: TextStyle(color: Colors.white)),
                      additionalInfo: Text('All local', style: TextStyle(color: Color(0xFF30D158))),
                    ),
                    CupertinoListTile(
                      backgroundColor: const Color(0xFF1C1C1E),
                      leading: const Icon(CupertinoIcons.chevron_left_slash_chevron_right, color: Color(0xFF0A84FF), size: 22),
                      title: const Text('Open Source', style: TextStyle(color: Colors.white)),
                      additionalInfo: const Text('GitHub', style: TextStyle(color: Color(0xFF0A84FF))),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () async {
                        final uri = Uri.parse('https://github.com/EGBYtest/Unplug');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        }
                      },
                    ),
                    CupertinoListTile(
                      backgroundColor: const Color(0xFF1C1C1E),
                      leading: const Icon(CupertinoIcons.mail_solid, color: Color(0xFFFF9F0A), size: 22),
                      title: const Text('Contact & Feedback', style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Report bugs or suggest features', style: TextStyle(color: Colors.white38, fontSize: 12)),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () async {
                        final uri = Uri.parse('https://github.com/EGBYtest/Unplug/issues');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        }
                      },
                    ),
                    const CupertinoListTile(
                      backgroundColor: Color(0xFF1C1C1E),
                      leading: Icon(CupertinoIcons.info_circle_fill, color: Colors.white38, size: 22),
                      title: Text('Version', style: TextStyle(color: Colors.white)),
                      additionalInfo: Text(
                        AppVersion.name,
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
  }

  void _showGroupOptions(int index) {
    final group = _groups[index];
    final bonusSeconds = _storage.remainingBonusSeconds(
        group.name, _usageMinutes[group.name] ?? 0);
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: Text(group.name),
        message: bonusSeconds > 0
            ? Text('${_formatSeconds(bonusSeconds)} bonus time remaining', style: const TextStyle(color: Color(0xFF30D158), fontSize: 12))
            : null,
        actions: [
          CupertinoActionSheetAction(child: const Text('Edit Time Limit'), onPressed: () { Navigator.pop(context); _confirmChange(() => _editLimit(index)); }),
          CupertinoActionSheetAction(child: const Text('Edit Apps in Group'), onPressed: () { Navigator.pop(context); _confirmChange(() => _editGroupApps(index)); }),
          if (bonusSeconds > 0)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              child: const Text('Remove Bonus Time'),
              onPressed: () {
                Navigator.pop(context);
                _confirmChange(() {
                  showCupertinoDialog(
                    context: context,
                    builder: (ctx) => CupertinoAlertDialog(
                      title: const Text('Remove Bonus Time'),
                      content: Text('Remove ${_formatSeconds(bonusSeconds)} bonus time from "${group.name}"?'),
                      actions: [
                        CupertinoDialogAction(child: const Text('Cancel'), onPressed: () => Navigator.pop(ctx)),
                        CupertinoDialogAction(
                          isDestructiveAction: true,
                          child: const Text('Remove'),
                          onPressed: () async {
                            await _storage.resetBonusSeconds(group.name);
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                        ),
                      ],
                    ),
                  );
                });
              },
            ),
          CupertinoActionSheetAction(isDestructiveAction: true, child: const Text('Delete Group'), onPressed: () { Navigator.pop(context); _confirmChange(() => _deleteGroup(index)); }),
        ],
        cancelButton: CupertinoActionSheetAction(isDestructiveAction: true, child: const Text('Cancel'), onPressed: () => Navigator.pop(context)),
      ),
    );
  }

  void _addGroup() {
    final controller = TextEditingController();
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('New Group'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            placeholder: 'Group name',
            autofocus: true,
            style: const TextStyle(color: CupertinoColors.white),
            placeholderStyle: const TextStyle(color: CupertinoColors.systemGrey),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            child: const Text('Create'),
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              // Prevent duplicate names
              if (_groups.any((g) => g.name.toLowerCase() == name.toLowerCase())) {
                return;
              }
              setState(() {
                _groups.add(AppGroup(
                  name: name,
                  packageNames: [],
                  timeLimitMinutes: 30,
                ));
              });
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _deleteGroup(int index) {
    final groupName = _groups[index].name;
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Delete Group'),
        content: Text('Are you sure you want to delete "$groupName"?'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Delete'),
            onPressed: () {
              setState(() {
                _groups.removeAt(index);
              });
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _editResetHour() {
    int tempHour = _resetHour;
    showCupertinoModalPopup(
      context: context,
      builder: (_) => Container(
        height: 300,
        decoration: const BoxDecoration(
          color: Color(0xFF1C1C1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text('Daily Reset Hour', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Text('Save', style: TextStyle(color: Color(0xFF0A84FF), fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      setState(() => _resetHour = tempHour);
                      await _storage.saveResetHour(tempHour);
                      if (mounted) Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 4),
            const Text('Hour (0, 2, 4... 22)', style: TextStyle(color: Colors.white54, fontSize: 13)),
            Expanded(
              child: CupertinoPicker(
                itemExtent: 40,
                onSelectedItemChanged: (i) => tempHour = i * 2,
                scrollController: FixedExtentScrollController(initialItem: tempHour ~/ 2),
                children: List.generate(12, (i) => Center(
                  child: Text(
                    '${(i * 2).toString().padLeft(2, '0')}:00',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500),
                  ),
                )),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  String _formatMinutes(int totalMinutes) {
    if (totalMinutes < 60) return '${totalMinutes}m';
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  String _formatSeconds(int totalSeconds) {
    if (totalSeconds < 60) return '${totalSeconds}s';
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }
}

/// Minute/second wheels for the bonus wait.
///
/// Two plain CupertinoPickers rather than CupertinoTimerPicker. TimerPicker
/// sizes its minute wheel from the initial duration it is given, so it cannot
/// express a fixed 0–3:59 range — passing 30s yields a one-minute wheel, and
/// the range moves as you scroll. Explicit wheels keep the range fixed.
///
/// The floor is enforced by snapping back rather than by withholding options.
/// Letting a user spin to 0:05, silently saving 5s, and only then finding out
/// is worse than a wheel that refuses to settle there: the setting is meant to
/// be the user's expression of how much friction they want, so a value the app
/// will not honour should not be selectable at all.
class _WaitDurationSheet extends StatefulWidget {
  final int initialSeconds;
  final VoidCallback onCancel;
  final ValueChanged<int> onSave;

  const _WaitDurationSheet({
    required this.initialSeconds,
    required this.onCancel,
    required this.onSave,
  });

  @override
  State<_WaitDurationSheet> createState() => _WaitDurationSheetState();
}

class _WaitDurationSheetState extends State<_WaitDurationSheet> {
  static const int _floor = StorageService.minWaitSeconds;
  static const int _ceiling = StorageService.maxWaitSeconds;

  late int _minutes;
  late int _seconds;

  String? _warning;

  /// Rebuilt whenever the selection is corrected, so the wheels jump back
  /// rather than sitting on a value that was rejected.
  late FixedExtentScrollController _minuteCtl;
  late FixedExtentScrollController _secondCtl;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSeconds.clamp(_floor, _ceiling);
    _minutes = initial ~/ 60;
    _seconds = initial % 60;
    _minuteCtl = FixedExtentScrollController(initialItem: _minutes);
    _secondCtl = FixedExtentScrollController(initialItem: _seconds);
  }

  @override
  void dispose() {
    _minuteCtl.dispose();
    _secondCtl.dispose();
    super.dispose();
  }

  int get _total => _minutes * 60 + _seconds;

  void _onWheelChanged() {
    final total = _total;
    if (total < _floor) {
      // Snap the offending wheel to the floor and say why. 0m30s is reachable
      // from either wheel, so both are recomputed from the floored total.
      final floored = _floor;
      setState(() {
        _minutes = floored ~/ 60;
        _seconds = floored % 60;
        _warning = 'Minimum wait is 30 seconds';
        _minuteCtl = FixedExtentScrollController(initialItem: _minutes);
        _secondCtl = FixedExtentScrollController(initialItem: _seconds);
      });
      return;
    }
    if (total > _ceiling) {
      final capped = _ceiling;
      setState(() {
        _minutes = capped ~/ 60;
        _seconds = capped % 60;
        _warning = 'Maximum wait is 3 minutes 59 seconds';
        _minuteCtl = FixedExtentScrollController(initialItem: _minutes);
        _secondCtl = FixedExtentScrollController(initialItem: _seconds);
      });
      return;
    }
    if (_warning != null) setState(() => _warning = null);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 360,
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.white54)),
                  onPressed: widget.onCancel,
                ),
                const Text('Wait Duration',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: const Text('Save',
                      style: TextStyle(
                          color: Color(0xFF0A84FF),
                          fontWeight: FontWeight.bold)),
                  onPressed: () => widget.onSave(_total.clamp(_floor, _ceiling)),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          const Text('How long you wait for bonus time',
              style: TextStyle(color: Colors.white54, fontSize: 13)),
          // Reserved height so the wheels do not jump when the warning
          // appears and disappears.
          SizedBox(
            height: 20,
            child: Center(
              child: _warning == null
                  ? null
                  : Text(_warning!,
                      style: const TextStyle(
                          color: Color(0xFFFF9F0A), fontSize: 12)),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _wheel('min', _ceiling ~/ 60, _minutes, _minuteCtl)),
                Expanded(child: _wheel('sec', 59, _seconds, _secondCtl)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _wheel(
    String label,
    int max,
    int value,
    FixedExtentScrollController controller,
  ) {
    return CupertinoPicker(
      itemExtent: 40,
      scrollController: controller,
      onSelectedItemChanged: (i) {
        if (label == 'min') {
          _minutes = i;
        } else {
          _seconds = i;
        }
        _onWheelChanged();
      },
      children: [
        for (int i = 0; i <= max; i++)
          Center(
            child: Text(
              i < 10 ? '0$i' : '$i',
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
          ),
      ],
    );
  }
}
