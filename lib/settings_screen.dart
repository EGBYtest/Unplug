import 'dart:ui';
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
  bool _isUnlocked = false;
  bool _saving = false;
  final StorageService _storage = StorageService();
  final UsageTracker _tracker = UsageTracker();
  late List<AppGroup> _groups;
  late int _adRewardSeconds;

  @override
  void initState() {
    super.initState();
    _groups = List.from(_storage.loadGroups());
    _adRewardSeconds = _storage.adRewardSeconds;
    if (!_storage.settingsLockEnabled) _isUnlocked = true;
  }

  // ─── Unlock Logic ────────────────────────────────────────────────────────

  void _unlockSettings() => setState(() => _isUnlocked = true);

  void _watchAdToUnlock() {
    AdRewardSystem().showRewardedAd(context, _unlockSettings, () {});
  }

  void _showTypeChallenge() {
    final ctrl = TextEditingController();
    final target = MessageVerification().generateMessage();

    showCupertinoDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setInner) {
          int wordCount = ctrl.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
          return CupertinoAlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(CupertinoIcons.pencil_outline, size: 18),
                SizedBox(width: 6),
                Text('Type to Unlock'),
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
                  '${ctrl.text.trim().split(RegExp(r"\s+")).where((w) => w.isNotEmpty).length} / 100 words',
                  style: TextStyle(
                    color: wordCount >= 100 ? const Color(0xFF30D158) : Colors.white54,
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
                    _unlockSettings();
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
                      if (context.mounted) Navigator.pop(context);
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
                      if (context.mounted) Navigator.pop(context);
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

  // ─── Save & Lock ──────────────────────────────────────────────────────────
  Future<void> _saveAndLock() async {
    setState(() => _saving = true);
    await _storage.saveGroups(_groups);
    await _storage.saveAdRewardSeconds(_adRewardSeconds);
    _tracker.appGroups = List.from(_groups);

    // Auto-enable settings lock only once after first save
    if (!_storage.settingsLockAutoEnabled) {
      await _storage.setSettingsLockEnabled(true);
      await _storage.setSettingsLockAutoEnabled();
    }

    if (mounted) {
      setState(() { _saving = false; _isUnlocked = _storage.settingsLockEnabled ? false : true; });
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
        trailing: _isUnlocked
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _saving ? null : _saveAndLock,
                child: _saving
                    ? const CupertinoActivityIndicator()
                    : const Text('Save', style: TextStyle(color: Color(0xFF30D158), fontWeight: FontWeight.bold)),
              )
            : null,
      ),
      child: Stack(
        children: [
          SafeArea(
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
                    return CupertinoListTile(
                      backgroundColor: const Color(0xFF1C1C1E),
                      leading: Icon(CupertinoIcons.timer, color: const Color(0xFF0A84FF), size: 22),
                      title: Text(group.name, style: const TextStyle(color: Colors.white)),
                      subtitle: Text('${group.packageNames.length} apps', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      additionalInfo: Text(_formatMinutes(group.timeLimitMinutes), style: const TextStyle(color: Colors.white70)),
                      trailing: _isUnlocked ? const CupertinoListTileChevron() : null,
                      onTap: _isUnlocked ? () => _showGroupOptions(i) : null,
                    );
                  }).toList(),
                ),

                // Add Group button
                if (_isUnlocked)
                  CupertinoListTile(
                    backgroundColor: const Color(0xFF1C1C1E),
                    leading: const Icon(CupertinoIcons.add_circled, color: Color(0xFF0A84FF), size: 22),
                    title: const Text('Add Group', style: TextStyle(color: Colors.white)),
                    onTap: _addGroup,
                  ),
                // ── Settings Lock Toggle ──
                CupertinoListSection.insetGrouped(
                  backgroundColor: Colors.black,
                  decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(12)),
                  header: const Text('SECURITY', style: TextStyle(color: Colors.white54)),
                  children: [
                    CupertinoListTile(
                      backgroundColor: const Color(0xFF1C1C1E),
                      leading: const Icon(CupertinoIcons.lock_fill, color: Color(0xFFFF9F0A), size: 22),
                      title: const Text('Lock Settings', style: TextStyle(color: Colors.white)),
                      subtitle: Text(
                        _storage.settingsLockEnabled
                            ? 'Challenge required to edit'
                            : 'No lock on settings',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      trailing: CupertinoSwitch(
                        value: _storage.settingsLockEnabled,
                        onChanged: (val) async {
                          await _storage.setSettingsLockEnabled(val);
                          setState(() {
                            if (!val) _isUnlocked = true;
                          });
                        },
                      ),
                    ),
                  ],
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
                      trailing: _isUnlocked ? const CupertinoListTileChevron() : null,
                      onTap: _isUnlocked ? () => _editAdRatio() : null,
                    ),
                  ],
                ),

                // ── About ──
                CupertinoListSection.insetGrouped(
                  backgroundColor: Colors.black,
                  decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(12)),
                  header: const Text('ABOUT', style: TextStyle(color: Colors.white54)),
                  children: [
                    CupertinoListTile(
                      backgroundColor: const Color(0xFF1C1C1E),
                      leading: const Icon(CupertinoIcons.lock_fill, color: Color(0xFF30D158), size: 22),
                      title: const Text('Privacy', style: TextStyle(color: Colors.white)),
                      additionalInfo: const Text('All local', style: TextStyle(color: Color(0xFF30D158))),
                    ),
                    CupertinoListTile(
                      backgroundColor: const Color(0xFF1C1C1E),
                      leading: const Icon(CupertinoIcons.chevron_left_slash_chevron_right, color: Color(0xFF0A84FF), size: 22),
                      title: const Text('Open Source', style: TextStyle(color: Colors.white)),
                      additionalInfo: const Text('GitHub', style: TextStyle(color: Color(0xFF0A84FF))),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () async {
                        final uri = Uri.parse('https://github.com/EGBYtest/APp-idea');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        }
                      },
                    ),
                    CupertinoListTile(
                      backgroundColor: const Color(0xFF1C1C1E),
                      leading: const Icon(CupertinoIcons.info_circle_fill, color: Colors.white38, size: 22),
                      title: const Text('Version', style: TextStyle(color: Colors.white)),
                      additionalInfo: const Text('1.1 (Beta)', style: TextStyle(color: Colors.white54)),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Lock Overlay ──
          if (!_isUnlocked)
            Positioned.fill(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    color: Colors.black.withOpacity(0.65),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2C2C2E).withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(CupertinoIcons.lock_shield_fill, size: 72, color: Colors.white),
                        ),
                        const SizedBox(height: 24),
                        const Text('Settings Locked', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5)),
                        const SizedBox(height: 10),
                        const Text('Complete a challenge to edit settings.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 15)),
                        const SizedBox(height: 44),
                        SizedBox(
                          width: double.infinity,
                          child: Container(
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: const Color(0xFF0A84FF).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 4))]),
                            child: CupertinoButton(
                              color: const Color(0xFF0A84FF),
                              borderRadius: BorderRadius.circular(14),
                              onPressed: _watchAdToUnlock,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(CupertinoIcons.play_circle_fill, color: Colors.white, size: 20),
                                  SizedBox(width: 10),
                                  Text('Watch an Ad to Unlock', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: CupertinoButton(
                            color: const Color(0xFF1C1C1E),
                            borderRadius: BorderRadius.circular(14),
                            onPressed: _showTypeChallenge,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(CupertinoIcons.pencil, color: Color(0xFF0A84FF), size: 20),
                                SizedBox(width: 10),
                                Text('Type 100 words to Unlock', style: TextStyle(color: Color(0xFF0A84FF), fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showGroupOptions(int index) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: Text(_groups[index].name),
        actions: [
          CupertinoActionSheetAction(child: const Text('Edit Time Limit'), onPressed: () { Navigator.pop(context); _editLimit(index); }),
          CupertinoActionSheetAction(child: const Text('Edit Apps in Group'), onPressed: () { Navigator.pop(context); _editGroupApps(index); }),
          CupertinoActionSheetAction(isDestructiveAction: true, child: const Text('Delete Group'), onPressed: () { Navigator.pop(context); _deleteGroup(index); }),
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
