import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/services.dart';
import 'services/ad_reward_system.dart';
import 'services/message_verification.dart';
import 'services/storage_service.dart';
import 'utils/no_paste_formatter.dart';

class LockScreenPopup extends StatefulWidget {
  final String appName;
  final String? groupName;
  final String? bannedFeature;

  const LockScreenPopup({
    Key? key,
    required this.appName,
    this.groupName,
    this.bannedFeature,
  }) : super(key: key);

  @override
  State<LockScreenPopup> createState() => _LockScreenPopupState();
}

class _LockScreenPopupState extends State<LockScreenPopup> {
  bool _showOptions = false;
  bool _showTypeChallenge = false;
  bool _adLoading = false;
  int _countdown = 3;
  final TextEditingController _textController = TextEditingController();
  int _wordCount = 0;
  static const int _targetWordCount = 50;
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
    _startCountdown();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      if (_countdown > 1) {
        setState(() => _countdown--);
        _startCountdown();
      } else {
        setState(() {
          _countdown = 0;
          _showOptions = true;
        });
      }
    });
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
      context,
      () async {
        if (mounted) {
          setState(() => _adLoading = false);
          await _grantExtraMinute();
        }
      },
      () {
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
    final bool isFeatureBlock = widget.bannedFeature != null && widget.bannedFeature!.isNotEmpty;
    final String title = isFeatureBlock ? 'In-App Feature Blocked' : 'Time Exhausted';
    final String subtitle = isFeatureBlock
        ? 'Access to "${widget.bannedFeature}" in ${widget.appName} is restricted.'
        : 'Your screen time for "${widget.appName}" is up.';

    return PopScope(
      canPop: false,
      child: CupertinoPageScaffold(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30).withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isFeatureBlock ? CupertinoIcons.shield_slash_fill : CupertinoIcons.lock_fill,
                      size: 38,
                      color: const Color(0xFFFF3B30),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  const SizedBox(height: 24),
                  if (!_showOptions)
                    Column(
                      children: <Widget>[
                        Text(
                          '$_countdown',
                          style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w800, color: Color(0xFF0A84FF)),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Take three seconds before deciding\nif you really want more screen time.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 15, height: 1.4),
                        ),
                      ],
                    )
                  else if (_adLoading)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CupertinoActivityIndicator()),
                    )
                  else if (!_showTypeChallenge)
                    Column(
                      children: <Widget>[
                        Text(
                          '+${_fmtSeconds(_storage.adRewardSeconds)} per action',
                          style: const TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: CupertinoButton(
                            color: const Color(0xFF0A84FF),
                            borderRadius: BorderRadius.circular(12),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            onPressed: _watchAd,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Icon(CupertinoIcons.play_circle_fill, color: Colors.white, size: 18),
                                SizedBox(width: 8),
                                Text('Watch Ad  (+time)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: CupertinoButton(
                            color: const Color(0xFF2C2C2E),
                            borderRadius: BorderRadius.circular(12),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            onPressed: () => setState(() => _showTypeChallenge = true),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Icon(CupertinoIcons.pencil, size: 18),
                                SizedBox(width: 8),
                                Text('Type 50 words  (+time)', style: TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        CupertinoButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('No thanks, go back', style: TextStyle(color: Colors.white38)),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: <Widget>[
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
                          placeholder: 'Type the exact message above...',
                          placeholderStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          padding: const EdgeInsets.all(10),
                          inputFormatters: [NoPasteFormatter()],
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
                          children: <Widget>[
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
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: CupertinoButton(
                            color: _wordCount >= _targetWordCount ? const Color(0xFF0A84FF) : const Color(0xFF2C2C2E),
                            borderRadius: BorderRadius.circular(12),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            onPressed: _wordCount >= _targetWordCount ? _submitMessage : null,
                            child: const Text('Submit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        CupertinoButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Give up, go back', style: TextStyle(color: Colors.white38)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
