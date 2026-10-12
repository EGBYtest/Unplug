import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Grants bonus time in exchange for a timed wait.
///
/// This is a local timer dialog, not an advertisement. It contains no ad
/// SDK, contacts no ad network, and makes no network requests at all. The
/// dialog shows a link to the project's own store; tapping it hands off to
/// the browser via url_launcher, which is the only external interaction.
///
/// The wait exists to cost something. How long it costs is the user's setting
/// ([StorageService.waitSeconds], 30s to 5m) — this class never decides it. The
/// timer resets in full whenever the app is backgrounded or the window
/// shrinks, so it cannot be run away in split-screen or a floating window
/// while doing something else.
class RewardGate {
  static final RewardGate _instance = RewardGate._internal();
  factory RewardGate() => _instance;
  RewardGate._internal();

  /// Presents the wait dialog. [onRewardGranted] fires once the wait
  /// completes; [onCancelled] fires if the user backs out.
  ///
  /// [totalSeconds] is how long the wait runs, from [StorageService.waitSeconds]
  /// — the user's setting. Callers must not hardcode it.
  void showWait(
    BuildContext context,
    VoidCallback onRewardGranted,
    VoidCallback onCancelled, {
    required int totalSeconds,
    int accumulatedSeconds = 0,
  }) {
    _presentWaitScreen(
        context, onRewardGranted, onCancelled, accumulatedSeconds, totalSeconds);
  }

  void _presentWaitScreen(
    BuildContext context,
    VoidCallback onRewardGranted,
    VoidCallback onCancelled,
    int accumulatedSeconds,
    int totalSeconds,
  ) {
    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _WaitDialog(
        totalSeconds: totalSeconds,
        accumulatedSeconds: accumulatedSeconds,
        onComplete: onRewardGranted,
        onCancel: onCancelled,
      ),
    );
  }
}

class _WaitDialog extends StatefulWidget {
  final int totalSeconds;
  final int accumulatedSeconds;
  final VoidCallback onComplete;
  final VoidCallback onCancel;

  const _WaitDialog({
    required this.totalSeconds,
    required this.accumulatedSeconds,
    required this.onComplete,
    required this.onCancel,
  });

  @override
  State<_WaitDialog> createState() => _WaitDialogState();
}

class _WaitDialogState extends State<_WaitDialog> with WidgetsBindingObserver {
  late int _remaining;
  late Timer _timer;
  bool _cancelled = false;
  bool _paused = false;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  Size? _fullSize;

  @override
  void initState() {
    super.initState();
    _remaining = widget.totalSeconds;
    WidgetsBinding.instance.addObserver(this);
    // Capture the initial full-screen size so we can detect
    // floating / split-screen / pop-up views where the window shrinks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fullSize = MediaQuery.sizeOf(context);
    });
    _startTicker();
  }

  @override
  void dispose() {
    _timer.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
  }

  void _startTicker() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final size = MediaQuery.sizeOf(context);
      final isFullscreen =
          _fullSize == null ||
          (size.width >= _fullSize!.width - 1 &&
              size.height >= _fullSize!.height - 1);
      final isActive = _lifecycleState == AppLifecycleState.resumed && isFullscreen;

      if (!isActive) {
        if (!_paused) {
          setState(() {
            _paused = true;
            _remaining = widget.totalSeconds;
          });
        }
        return;
      }

      if (_paused) {
        setState(() {
          _paused = false;
          _remaining = widget.totalSeconds;
        });
        return;
      }

      if (_remaining > 0) {
        setState(() => _remaining--);
      } else {
        _timer.cancel();
        if (mounted && !_cancelled) {
          Navigator.of(context).pop();
          widget.onComplete();
        }
      }
    });
  }

  void _cancel() {
    _cancelled = true;
    _timer.cancel();
    Navigator.of(context).pop();
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: CupertinoAlertDialog(
        title: const Text('Sponsor'),
        content: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF0A84FF).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.clock_fill,
                color: Color(0xFF0A84FF),
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Build & buy your own custom watch',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            GestureDetector(
              onTap: () async {
                final uri = Uri.parse('https://yourwatch.no');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Text(
                'at yourwatch.no',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: CupertinoTheme.of(context).primaryColor,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _paused
                  ? 'Paused — timer resets when Unplug is fully open'
                  : 'Wait ${_remaining}s for +time',
              style: const TextStyle(fontSize: 13, color: Colors.white54),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _paused
                      ? 0
                      : (widget.totalSeconds - _remaining) / widget.totalSeconds,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    CupertinoTheme.of(context).primaryColor,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: _cancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
