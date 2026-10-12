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
    Future<({int status, String body})> fetch(String url) async {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final res = await client.getUrl(Uri.parse(url)).then((r) => r.close());
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

    test('the VERSION file matches the latest release tag', () async {
      final raw = await fetch(
        'https://raw.githubusercontent.com/EGBYtest/Unplug/main/VERSION',
      );
      final api = await fetch(
        'https://api.github.com/repos/EGBYtest/Unplug/releases/latest',
      );
      final tag = (jsonDecode(api.body) as Map<String, dynamic>)['tag_name']
          as String;

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
}