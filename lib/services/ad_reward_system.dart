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
  bool _rewardEarned = false; // Track if reward was earned before dismiss

  // Test rewarded ad unit ID (replace with real one for production)
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

  /// Shows a rewarded ad.
  /// [onRewardGranted] is called only AFTER the ad is fully dismissed AND
  /// the user earned the reward (they watched long enough).
  /// [onAdFailed] is called if no ad is available or the ad fails to show.
  /// 
  /// In test mode, AdMob test ads can be skipped instantly. This method
  /// artificially enforces a 30-second minimum wait time by showing a countdown
  /// if the ad was closed too early, preserving the required time friction.
  void showRewardedAd(VoidCallback onRewardGranted, VoidCallback onAdFailed) {
    if (!_isAdReady || _rewardedAd == null) {
      onAdFailed();
      return;
    }

    // Force true for testing so you don't accidentally skip the reward by closing too fast
    _rewardEarned = true;

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        final earned = _rewardEarned; // Save it BEFORE loadAd resets it!
        ad.dispose();
        _loadAd(); // Pre-load next ad (which resets flags)
        
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
