import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/services.dart';
import 'services/ad_reward_system.dart';
import 'services/message_verification.dart';
import 'services/storage_service.dart';
import 'utils/no_paste_formatter.dart';

class LockScreenPopup extends StatefulWidget {
  final String appName;
  final String? groupName; // Optional — if known, used to grant bonus minutes

  const LockScreenPopup({Key? key, required this.appName, this.groupName}) : super(key: key);

  @override
  State<LockScreenPopup> createState() => _LockScreenPopupState();
}

class _LockScreenPopupState extends State<LockScreenPopup> {
  bool _showTypeChallenge = false;
  bool _adLoading = false;
  final TextEditingController _textController = TextEditingController();
  int _wordCount = 0;
  static const int _targetWordCount = 100;
  final MessageVerification _verifier = MessageVerification();
  final AdRewardSystem _ads = AdRewardSystem();
  final StorageService _storage = StorageService();
  late final String _targetMessage;

  void _onTextChanged() {
    final words = _textController.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    setState(() => _wordCount = words.length);
  }

  @override
  void initState() {
    super.initState();
    _targetMessage = _verifier.generateMessage();
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  String get _effectiveGroupName => widget.groupName ?? widget.appName;

  Future<void> _grantExtraMinute() async {
    await _storage.addBonusSeconds(_effectiveGroupName, _storage.adRewardSeconds);
    if (mounted) Navigator.of(context).pop();
  }

  String _fmtSeconds(int totalSeconds) {
    if (totalSeconds < 60) return '${totalSeconds}s';
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }

  void _watchAd() {
    setState(() => _adLoading = true);
    _ads.showRewardedAd(
      () async {
        // Ad dismissed after reward was earned
        if (mounted) {
          setState(() => _adLoading = false);
          await _grantExtraMinute();
        }
      },
      () {
        // Ad unavailable — fall back to typing
        if (mounted) setState(() { _adLoading = false; _showTypeChallenge = true; });
      },
    );
  }

  void _submitMessage() {
    if (_verifier.verifyMessage(_textController.text)) {
      _grantExtraMinute();
    } else {
      showCupertinoDialog(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('Not quite right'),
          content: const Text('The message doesn\'t match exactly. Check capitalization and spacing — it is case-sensitive.'),
          actions: [CupertinoDialogAction(child: const Text('Try Again'), onPressed: () => Navigator.pop(context))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // PopScope prevents Android back button from dismissing the lock screen
    return PopScope(
      canPop: false,
      child: CupertinoAlertDialog(
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B30).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(CupertinoIcons.lock_fill, size: 38, color: Color(0xFFFF3B30)),
            ),
            const SizedBox(height: 10),
            const Text('Time Exhausted', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ],
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Your screen time for "${widget.appName}" is up.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 4),
              Text(
                '+${_fmtSeconds(_storage.adRewardSeconds)} per action',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 20),
              if (_adLoading)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CupertinoActivityIndicator()),
                )
              else if (!_showTypeChallenge) ...[
                CupertinoButton(
                  color: const Color(0xFF0A84FF),
                  borderRadius: BorderRadius.circular(10),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  onPressed: _watchAd,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(CupertinoIcons.play_circle_fill, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('Watch Ad  (+time)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                CupertinoButton(
                  color: const Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.circular(10),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  onPressed: () => setState(() => _showTypeChallenge = true),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(CupertinoIcons.pencil, color: Color(0xFF0A84FF), size: 18),
                      SizedBox(width: 8),
                      Text('Type 100 words  (+time)', style: TextStyle(color: Color(0xFF0A84FF), fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ] else ...[
                // ── Typing Challenge ──
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C2C2E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_targetMessage, style: const TextStyle(fontSize: 11, color: Colors.white60, height: 1.5)),
                ),
                const SizedBox(height: 10),
                CupertinoTextField(
                  controller: _textController,
                  maxLines: 4,
                  placeholder: 'Type the exact message above (no copy-paste)...',
                  placeholderStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  padding: const EdgeInsets.all(10),
                  // No paste formatter blocks clipboard paste
                  inputFormatters: [NoPasteFormatter()],
                  // Remove context menu entirely to prevent paste
                  contextMenuBuilder: (_, __) => const SizedBox.shrink(),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    border: Border.all(color: const Color(0xFF3A3A3C)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$_wordCount / $_targetWordCount words',
                      style: TextStyle(
                        color: _wordCount >= _targetWordCount ? const Color(0xFF30D158) : const Color(0xFFFF3B30),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => setState(() => _showTypeChallenge = false),
                      child: const Text('← Back', style: TextStyle(color: Colors.white38, fontSize: 13)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          // "Close App" just goes home — it does NOT dismiss the popup in a normal sense;
          // the app they were using was already blocked by the AccessibilityService.
          // Dismiss button removed to enforce lock persistence
          if (_showTypeChallenge && !_adLoading)
            CupertinoDialogAction(
              isDefaultAction: _wordCount >= _targetWordCount,
              onPressed: _wordCount >= _targetWordCount ? _submitMessage : null,
              child: Text(
                'Submit',
                style: TextStyle(color: _wordCount >= _targetWordCount ? const Color(0xFF0A84FF) : Colors.white24),
              ),
            ),
        ],
      ),
    );
  }
}
