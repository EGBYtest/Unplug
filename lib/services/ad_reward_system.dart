import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdRewardSystem {
  static final AdRewardSystem _instance = AdRewardSystem._internal();
  factory AdRewardSystem() => _instance;
  AdRewardSystem._internal();

  RewardedAd? _rewardedAd;
  bool _isAdReady = false;
  bool _rewardEarned = false;
  DateTime? _watchStartTime;
  int _accumulatedWatchSeconds = 0;
  static const _minWatchSeconds = 30;

  final String _adUnitId = 'ca-app-pub-3940256099942544/5224354917';

  Future<void> initializeAds() async {
    await MobileAds.instance.initialize();
    _loadAd();
  }

  void _loadAd({int retryCount = 0}) {
    _isAdReady = false;
    _rewardEarned = false;
    RewardedAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isAdReady = true;
          debugPrint('AdRewardSystem: Ad loaded.');
        },
        onAdFailedToLoad: (error) {
          debugPrint('AdRewardSystem: Ad failed to load — $error');
          _isAdReady = false;
          _rewardedAd = null;
          if (retryCount < 5) {
            Future.delayed(Duration(seconds: 2 * (retryCount + 1)), () {
              _loadAd(retryCount: retryCount + 1);
            });
          }
        },
      ),
    );
  }

  /// Attempt to show ad with retry if not ready yet.
  void showRewardedAd(
    BuildContext context,
    VoidCallback onRewardGranted,
    VoidCallback onAdFailed, {
    int accumulatedSeconds = 0,
  }) {
    _accumulatedWatchSeconds = accumulatedSeconds;
    if (_isAdReady && _rewardedAd != null) {
      _presentAd(context, onRewardGranted, onAdFailed);
      return;
    }

    // Ad not ready — start loading and wait up to 8s
    _loadAd();
    int attempts = 0;
    const maxAttempts = 16; // 16 × 500ms = 8s
    void checkReady() {
      attempts++;
      if (_isAdReady && _rewardedAd != null) {
        _presentAd(context, onRewardGranted, onAdFailed);
      } else if (attempts < maxAttempts) {
        Future.delayed(const Duration(milliseconds: 500), checkReady);
      } else {
        onAdFailed();
      }
    }
    Future.delayed(const Duration(milliseconds: 500), checkReady);
  }

  void _presentAd(
    BuildContext context,
    VoidCallback onRewardGranted,
    VoidCallback onAdFailed,
  ) {
    _rewardEarned = false;
    _watchStartTime = DateTime.now();

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        final earned = _rewardEarned;
        final sessionElapsed = DateTime.now().difference(_watchStartTime!).inSeconds;
        final totalElapsed = _accumulatedWatchSeconds + sessionElapsed;
        ad.dispose();

        if (earned && totalElapsed >= _minWatchSeconds) {
          _loadAd();
          _accumulatedWatchSeconds = 0;
          onRewardGranted();
        } else if (earned && totalElapsed < _minWatchSeconds) {
          // Demo ad too short — accumulate time and prompt replay
          final newAccumulated = totalElapsed;
          _loadAd();
          showCupertinoDialog(
            context: context,
            builder: (_) => CupertinoAlertDialog(
              title: const Text('Keep Watching'),
              content: Text('Please watch for at least $_minWatchSeconds seconds.\n\nWatched: ${newAccumulated}s / ${_minWatchSeconds}s'),
              actions: [
                CupertinoDialogAction(
                  child: const Text('Watch Again'),
                  onPressed: () {
                    Navigator.pop(context);
                    showRewardedAd(context, onRewardGranted, onAdFailed, accumulatedSeconds: newAccumulated);
                  },
                ),
                CupertinoDialogAction(
                  isDestructiveAction: true,
                  child: const Text('Cancel'),
                  onPressed: () {
                    _accumulatedWatchSeconds = 0;
                    _loadAd();
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          );
        } else {
          _loadAd();
          _accumulatedWatchSeconds = 0;
          onAdFailed();
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('AdRewardSystem: Failed to show — $error');
        ad.dispose();
        _loadAd();
        _accumulatedWatchSeconds = 0;
        onAdFailed();
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        _rewardEarned = true;
        debugPrint('AdRewardSystem: User earned reward.');
      },
    );
  }
}
