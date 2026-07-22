import 'dart:async';
import 'package:flutter/cupertino.dart';

class AdRewardSystem {
  static final AdRewardSystem _instance = AdRewardSystem._internal();
  factory AdRewardSystem() => _instance;
  AdRewardSystem._internal();

  Future<void> initializeAds() async {}

  void showRewardedAd(
    BuildContext context,
    VoidCallback onRewardGranted,
    VoidCallback onAdFailed,
  ) {
    int seconds = 5;

    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        Timer? timer;
        return StatefulBuilder(
          builder: (context, setInner) {
            timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
              seconds--;
              if (seconds <= 0) {
                timer?.cancel();
                Navigator.of(context).pop();
                onRewardGranted();
              } else {
                setInner(() {});
              }
            });
            return _AdDialog(seconds: seconds);
          },
        );
      },
    );
  }
}

class _AdDialog extends StatelessWidget {
  final int seconds;
  const _AdDialog({required this.seconds});

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: const Text('Ad'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          const Text('Please wait...'),
          const SizedBox(height: 16),
          Text(
            '$seconds',
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Bonus time available in ${seconds}s',
            style: TextStyle(
              color: CupertinoColors.systemGrey,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
