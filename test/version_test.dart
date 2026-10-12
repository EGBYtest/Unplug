import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unplug/generated/app_version.dart';
import 'package:unplug/services/update_checker.dart';

void main() {
  group('AppVersion', () {
    test('is sourced from pubspec.yaml, not hardcoded', () {
      expect(AppVersion.name, matches(RegExp(r'^\d+\.\d+\.\d+$')));
      expect(AppVersion.buildNumber, greaterThan(0));
      expect(AppVersion.full, '${AppVersion.name}+${AppVersion.buildNumber}');
    });
  });

  group('update sources', () {
    // These are the only two update sources left. If either breaks the app
    // silently stops offering updates, so pin them here. Separate client per
    // request because closing one HttpClient invalidates in-flight ones.
    //
    // Unauthenticated, GitHub allows 60 requests per hour per IP — the same
    // budget the app spends on a user's behalf, and shared across everyone
    // behind one carrier NAT. Running these unauthenticated could exhaust the
    // app's own budget and suppress update checks on the user's device. Set
    // GITHUB_TOKEN to run them authenticated (5000/hour) instead.
    Future<({int status, String body})> fetch(String url) async {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final req = await client.getUrl(Uri.parse(url));
      final token = Platform.environment['GITHUB_TOKEN'];
      if (token != null && token.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close();
      return (status: res.statusCode, body: body);
    }

    test('both sources are reachable and report a parseable version', () async {
      final api = await fetch(
        'https://api.github.com/repos/EGBYtest/Unplug/releases/latest',
      );
      expect(api.status, 200, reason: 'GitHub Releases API unreachable');
      final tag =
          (jsonDecode(api.body) as Map<String, dynamic>)['tag_name'];
      expect(tag, matches(RegExp(r'^v?\d+\.\d+\.\d+')),
          reason: 'tag_name is not a version string');

      final raw = await fetch(
        'https://raw.githubusercontent.com/EGBYtest/Unplug/main/VERSION',
      );
      expect(raw.status, 200, reason: 'raw VERSION file unreachable');
      expect(raw.body.trim(), matches(RegExp(r'^\d+\.\d+\.\d+$')),
          reason: 'VERSION file is not a bare version string');
    });

    // Checks the VERSION file at the release TAG, not at main.
    //
    // raw.githubusercontent.com serves `vary: Authorization, Accept-Encoding`,
    // so the identity and gzip responses are separate Fastly cache objects.
    // HttpClient — which both this test and UpdateChecker use — requests
    // gzip, and for a few minutes after a release that gzip object keeps
    // serving the previous version while the identity object is already
    // fresh. Asserting equality against `main` therefore raced the CDN and
    // failed on release days; a tag is immutable, so this checks the real
    // invariant — the tagged source matches the release — with no race.
    //
    // The consequence for the app is recorded in the test above: the raw
    // fallback can briefly disagree with the API, so the API stays primary.
    test('the VERSION file at the release tag matches the release tag',
        () async {
      final api = await fetch(
        'https://api.github.com/repos/EGBYtest/Unplug/releases/latest',
      );
      final tag = (jsonDecode(api.body) as Map<String, dynamic>)['tag_name']
          as String;

      final raw = await fetch(
        'https://raw.githubusercontent.com/EGBYtest/Unplug/$tag/VERSION',
      );
      expect(raw.status, 200, reason: 'tagged VERSION file unreachable');

      expect(raw.body.trim(), tag.replaceFirst('v', ''),
          reason: 'VERSION and the release tag disagree; the raw fallback '
              'would report a version the API does not');
    });
  });

  group('UpdateChecker.compareVersions', () {
    const compare = UpdateChecker.compareVersions;

    test('equal versions compare equal', () {
      expect(compare('1.0.0', '1.0.0'), 0);
      expect(compare('1.2.3', '1.2.3'), 0);
    });

    test('compares each component numerically, not lexically', () {
      // Lexical comparison would say '9' > '10', which is wrong.
      expect(compare('1.0.10', '1.0.9'), greaterThan(0));
      expect(compare('1.0.9', '1.0.10'), lessThan(0));
      expect(compare('1.10.0', '1.9.0'), greaterThan(0));
      expect(compare('2.0.0', '1.99.99'), greaterThan(0));
    });

    test('handles differing lengths by treating missing parts as zero', () {
      expect(compare('1.0.1', '1.0'), greaterThan(0));
      expect(compare('1.0', '1.0.0'), 0);
      expect(compare('1.0.0.1', '1.0.0'), greaterThan(0));
    });

    test('treats unparseable parts as zero rather than throwing', () {
      expect(compare('1.0.x', '1.0.0'), 0);
      expect(compare('', '1.0.0'), lessThan(0));
    });

    // Known gap, not a pass: a prerelease tag of the CURRENT version is
    // seen as equal, so beta builds are never offered to users already on
    // that version. GitHub tags here are 'v1.8.7-beta' style.
    test('prerelease of the current version reads as equal', () {
      expect(compare('1.0.0-beta', '1.0.0'), 0);
      // It only registers when the numeric parts differ.
      expect(compare('1.0.1-beta', '1.0.0'), 0);
      expect(compare('1.1.0-beta', '1.0.0'), greaterThan(0));
    });

    // The 1.8.x line was abandoned for 1.0.0. Because the update gate is a
    // numeric comparison, a 1.8.x install never sees a 1.0.x release as newer.
    // This test documents that consequence rather than asserting it is fine.
    test('1.8.x install does not see 1.0.x as an update', () {
      expect(compare('1.0.1', '1.8.7'), lessThan(0));
      expect(compare('1.0.0', '1.8.7'), lessThan(0));
    });
  });

  group('update banner visibility', () {
    // The banner is the only download affordance since v1.1.1, so a check
    // that fails to surface an available release leaves the user with no way
    // to see there is an update at all.
    const show = UpdateChecker.shouldShowBanner;

    UpdateInfo avail(String v) => UpdateInfo(
          latestVersion: v,
          downloadUrl: 'https://github.com/EGBYtest/Unplug/releases/tag/v$v',
          isAvailable: true,
        );
    const none = UpdateInfo(
      latestVersion: '',
      downloadUrl: '',
      isAvailable: false,
    );

    test('shows when an update exists and nothing was dismissed', () {
      expect(show(avail('1.1.3'), null), isTrue);
    });

    test('hidden when there is no update', () {
      expect(show(none, null), isFalse);
      expect(show(null, null), isFalse);
    });

    test('stays hidden for the version that was dismissed', () {
      expect(show(avail('1.1.3'), '1.1.3'), isFalse);
    });

    // Dismissing "1.1.3" acknowledges that release, not every future one.
    // A single boolean used to hide the banner for the rest of the session,
    // so a genuinely newer release was never announced.
    test('returns when a newer version appears than the one dismissed', () {
      expect(show(avail('1.1.4'), '1.1.3'), isTrue);
    });

    test('a dismissed version does not suppress a later re-check of itself', () {
      expect(show(avail('1.1.3'), '1.1.3'), isFalse);
      expect(show(avail('1.1.3'), '1.1.3'), isFalse);
    });
  });

  group('release payload parsing', () {
    // Every check is independent and returns its own answer. This used to
    // write into a static cache that main() populated without awaiting, so
    // one failed check at startup cached "no update" and the banner stayed
    // hidden for the whole session. Returning null here is the only thing a
    // non-newer release may do — there is nowhere for it to persist.
    String payload(String tag) => jsonEncode({'tag_name': tag});
    const parse = UpdateChecker.fromReleasePayload;

    test('a newer release yields an available update', () {
      final info = parse(payload('v1.2.0'), '1.1.3');
      expect(info, isNotNull);
      expect(info!.isAvailable, isTrue);
      expect(info.latestVersion, '1.2.0');
      expect(info.downloadUrl, contains('v1.2.0'));
    });

    test('the current release is not an update', () {
      expect(parse(payload('v1.1.3'), '1.1.3'), isNull);
    });

    test('an older release is not an update', () {
      expect(parse(payload('v1.0.0'), '1.1.3'), isNull);
    });

    test('a malformed payload is not an update', () {
      expect(parse('{}', '1.1.3'), isNull);
      expect(parse('not json', '1.1.3'), isNull);
    });

    // The abandoned 1.8.x line: numerically newer, so it would be offered.
    // Documented rather than asserted as correct.
    test('the 1.8.x line still outranks 1.1.x numerically', () {
      expect(UpdateChecker.compareVersions('1.8.7', '1.1.3'), greaterThan(0));
    });
  });
}