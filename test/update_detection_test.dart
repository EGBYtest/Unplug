/// The scenario that keeps being reported: an older build is installed, a
/// newer release goes out, and the banner does not appear.
///
/// Everything below runs against the real GitHub sources. The only thing
/// faked is which version the app claims to be, because a test cannot install
/// yesterday's APK. That makes it the same path a user on the previous
/// release takes, end to end, with no stubs to hide behind.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:unplug/generated/app_version.dart';
import 'package:unplug/services/update_checker.dart';

/// Adds the caller's GitHub token to every request made inside these tests.
///
/// The app itself is unauthenticated, and GitHub's unauthenticated budget is
/// 60 requests per hour per IP — shared with every other user behind the same
/// carrier NAT. A test suite that spends that budget is spending the user's
/// update checks. Set GITHUB_TOKEN to stay authenticated and out of the way.
String? _token() {
  final t = Platform.environment['GITHUB_TOKEN'];
  return (t == null || t.isEmpty) ? null : t;
}

void main() {
  final token = _token();

  group('an older build sees the latest release', () {
    test('an older build is told about the latest release', () async {
      // 0.0.1 is older than anything this project will ever ship, so this
      // holds whatever the tree's own version happens to be. Deriving it from
      // AppVersion.name instead made the test fail on the commit that bumps
      // the version, before that version is even published.
      final info = await UpdateChecker.check(
        currentVersion: '0.0.1',
        authToken: token,
      );

      debugPrint('pretending to be 0.0.1; '
          'server says ${info.latestVersion}; available=${info.isAvailable}');

      expect(
        info.isAvailable,
        isTrue,
        reason: 'a build reporting itself as 0.0.1 must be told about the '
            'published release, otherwise the banner can never appear',
      );
      expect(info.latestVersion, isNotEmpty);
      expect(info.downloadUrl, contains(info.latestVersion));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('the build in this tree is not offered itself', () async {
      final info = await UpdateChecker.check(currentVersion: AppVersion.name, authToken: token);
      // Only meaningful once this build is published. Before that the server
      // legitimately reports something newer, which is correct behaviour.
      expect(info.latestVersion, isNot(AppVersion.name));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('request budget', () {
    // GitHub allows 60 unauthenticated requests per hour per IP, shared
    // across every user behind a carrier NAT. Checking on every app resume
    // could spend that on one's own glances, after which the API 403s, the
    // app falls back to the raw VERSION file, and that file is served from a
    // slower CDN cache — so the banner vanishes with no error anywhere.
    tearDown(UpdateChecker.invalidate);

    test('a second check inside the window spends no request', () async {
      UpdateChecker.invalidate();

      final first = await UpdateChecker.check(force: true, authToken: token);
      final after = UpdateChecker.requestCount;
      final second = await UpdateChecker.check(authToken: token);

      expect(second.latestVersion, first.latestVersion);
      expect(second.isAvailable, first.isAvailable);
      expect(UpdateChecker.requestCount, after,
          reason: 'a resume inside the window must not spend a request');
    });

    test('the window is long enough to survive ordinary use', () {
      // Comfortably inside the hourly budget even for a heavy user.
      expect(UpdateChecker.minCheckInterval.inMinutes, lessThanOrEqualTo(30));
      expect(
        UpdateChecker.minCheckInterval.inMinutes,
        greaterThanOrEqualTo(15),
        reason: 'longer would make updates feel late; shorter risks the '
            'per-IP rate limit',
      );
    });

    test('force goes back to the network', () async {
      UpdateChecker.invalidate();
      await UpdateChecker.check(force: true, authToken: token);
      final after = UpdateChecker.requestCount;

      await UpdateChecker.check(force: true, authToken: token);
      expect(UpdateChecker.requestCount, greaterThan(after));
    });

    // Ten app resumes in a row must not cost ten requests. Before the
    // throttle every resume issued one, which is how a single user could
    // exhaust the per-IP hourly budget.
    test('repeated resumes cost nothing after the first', () async {
      UpdateChecker.invalidate();
      await UpdateChecker.check(force: true, authToken: token);
      final after = UpdateChecker.requestCount;

      for (var i = 0; i < 10; i++) {
        await UpdateChecker.check(authToken: token);
      }
      expect(UpdateChecker.requestCount, after);
    });

    test('invalidate clears the cache', () async {
      UpdateChecker.invalidate();
      final first = await UpdateChecker.check(force: true, authToken: token);

      UpdateChecker.invalidate();
      final after = await UpdateChecker.check(force: true, authToken: token);

      expect(after.isAvailable, first.isAvailable);
    });
  });
}