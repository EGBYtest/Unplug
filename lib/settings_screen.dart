import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/ad_reward_system.dart';
import 'services/message_verification.dart';
import 'services/storage_service.dart';
import 'services/usage_tracker.dart';
import 'models/app_group.dart';
import 'utils/no_paste_formatter.dart';
import 'screens/app_picker_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _saving = false;
  final StorageService _storage = StorageService();
  final UsageTracker _tracker = UsageTracker();
  late List<AppGroup> _groups;
  late List<BannedFeature> _globalTabBlockers;
  late int _adRewardSeconds;
  late int _resetHour;
  late bool _settingsLock;

  @override
  void initState() {
    super.initState();
    _groups = List.from(_storage.loadGroups());
    _globalTabBlockers = List.from(_storage.loadGlobalTabBlockers());
    _adRewardSeconds = _storage.adRewardSeconds;
    _resetHour = _storage.resetHour;
    _settingsLock = _storage.settingsLockEnabled;
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
              AdRewardSystem().showRewardedAd(context, action, () {});
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.play_circle_fill, color: Color(0xFF0A84FF), size: 18),
                SizedBox(width: 8),
                Text('Wait 30s', style: TextStyle(fontWeight: FontWeight.bold)),
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
                      _tracker.appGroups = List.from(_groups);
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

  // ─── Edit Ad Ratio ─────────────────────────────────────────────────────────

  void _editAdRatio() {
    int tempSeconds = _adRewardSeconds % 60;
    int tempMinutes = _adRewardSeconds ~/ 60;

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
                  const Text('Reward per Ad', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Text('Save', style: TextStyle(color: Color(0xFF0A84FF), fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      setState(() => _adRewardSeconds = tempMinutes * 60 + tempSeconds);
                      await _storage.saveAdRewardSeconds(_adRewardSeconds);
                      if (mounted) Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 4),
            const Text('Time Granted', style: TextStyle(color: Colors.white54, fontSize: 13)),
            Expanded(
              child: CupertinoTimerPicker(
                mode: CupertinoTimerPickerMode.ms,
                initialTimerDuration: Duration(seconds: _adRewardSeconds),
                onTimerDurationChanged: (d) {
                  tempMinutes = d.inMinutes;
                  tempSeconds = d.inSeconds % 60;
                },
              ),
            ),
          ],
        ),
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
      _tracker.appGroups = List.from(_groups);
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
    await _storage.saveAdRewardSeconds(_adRewardSeconds);
    await _storage.saveResetHour(_resetHour);
    _tracker.appGroups = List.from(_groups);

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
                    final bonusSeconds = _storage.getBonusSeconds(group.name);
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
                  header: const Text('AD-TO-TIME RATIO', style: TextStyle(color: Colors.white54)),
                  children: [
                    CupertinoListTile(
                      backgroundColor: const Color(0xFF1C1C1E),
                      leading: const Icon(CupertinoIcons.play_rectangle_fill, color: Color(0xFFFF9F0A), size: 22),
                      title: const Text('Reward per Ad', style: TextStyle(color: Colors.white)),
                      additionalInfo: Text(_formatSeconds(_adRewardSeconds), style: const TextStyle(color: Colors.white70)),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => _confirmChange(_editAdRatio),
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
                  footer: const Text('When on, changing settings requires the 30-second wait or typing challenge. Turn off to apply changes instantly.', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  children: [
                    CupertinoListTile(
                      backgroundColor: const Color(0xFF1C1C1E),
                      leading: const Icon(CupertinoIcons.lock_fill, color: Color(0xFF30D158), size: 22),
                      title: const Text('Settings Lock', style: TextStyle(color: Colors.white)),
                      subtitle: Text(
                        _settingsLock ? 'Challenge required to change settings' : 'Changes apply instantly',
                        style: TextStyle(
                          color: _settingsLock ? const Color(0xFF30D158) : Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                      trailing: CupertinoSwitch(
                        value: _settingsLock,
                        onChanged: (val) {
                          setState(() => _settingsLock = val);
                          _storage.setSettingsLockEnabled(val);
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
                      additionalInfo: Text('1.8.5 (Beta)', style: TextStyle(color: Colors.white54)),
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
    final bonusSeconds = _storage.getBonusSeconds(group.name);
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
