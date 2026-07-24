import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AdRewardSystem {
  static final AdRewardSystem _instance = AdRewardSystem._internal();
  factory AdRewardSystem() => _instance;
  AdRewardSystem._internal();

  Future<void> initializeAds() async {}

  void showRewardedAd(
    BuildContext context,
    VoidCallback onRewardGranted,
    VoidCallback onAdFailed, {
    int accumulatedSeconds = 0,
  }) {
    _presentWaitScreen(context, onRewardGranted, onAdFailed, accumulatedSeconds);
  }

  void _presentWaitScreen(
    BuildContext context,
    VoidCallback onRewardGranted,
    VoidCallback onAdFailed,
    int accumulatedSeconds,
  ) {
    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PromoWaitDialog(
        accumulatedSeconds: accumulatedSeconds,
        onComplete: onRewardGranted,
        onCancel: onAdFailed,
      ),
    );
  }
}

class _PromoWaitDialog extends StatefulWidget {
  final int accumulatedSeconds;
  final VoidCallback onComplete;
  final VoidCallback onCancel;

  const _PromoWaitDialog({
    required this.accumulatedSeconds,
    required this.onComplete,
    required this.onCancel,
  });

  @override
  State<_PromoWaitDialog> createState() => _PromoWaitDialogState();
}

class _PromoWaitDialogState extends State<_PromoWaitDialog> {
  int _remaining = 30;
  late Timer _timer;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
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

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
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
            const SizedBox(height: 8),
            const Text(
              'Build & buy YOUR own custom WATCH',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () async {
                final uri = Uri.parse('https://yourwatch.no');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Text(
                'yourwatch.no',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: CupertinoTheme.of(context).primaryColor,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Wait ${_remaining}s for +time',
              style: const TextStyle(fontSize: 13, color: Colors.white54),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (30 - _remaining) / 30.0,
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
