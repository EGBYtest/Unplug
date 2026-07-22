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

  final String _adUnitId = 'ca-app-pub-3940256099942544/5224354917';

  Future<void> initializeAds() async {
    await MobileAds.instance.initialize();
    _loadAd();
  }

  void _loadAd() {
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
        },
      ),
    );
  }

  void showRewardedAd(
    BuildContext context,
    VoidCallback onRewardGranted,
    VoidCallback onAdFailed,
  ) {
    if (!_isAdReady || _rewardedAd == null) {
      onAdFailed();
      return;
    }

    _rewardEarned = true;

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        final earned = _rewardEarned;
        ad.dispose();
        _loadAd();

        if (earned) {
          onRewardGranted();
        } else {
          onAdFailed();
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('AdRewardSystem: Failed to show — $error');
        ad.dispose();
        _loadAd();
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
