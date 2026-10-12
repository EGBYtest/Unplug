import 'dart:convert';
import 'dart:developer' show log;
import 'dart:io';

import 'package:meta/meta.dart';

import '../generated/app_version.dart';

class UpdateInfo {
  final String latestVersion;
  final String downloadUrl;
  final bool isAvailable;

  const UpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    required this.isAvailable,
  });
}

class UpdateChecker {
  static const _githubApi = 'https://api.github.com/repos/EGBYtest/Unplug/releases/latest';
  static const _githubFallback = 'https://raw.githubusercontent.com/EGBYtest/Unplug/main/VERSION';

  /// Version of the running build. Generated from pubspec.yaml — see
  /// tool/gen_version.sh. Do not hardcode a version string here.
  static const _currentVersion = AppVersion.name;

  static const String _userAgent = 'Unplug/${AppVersion.full}';

  static Future<UpdateInfo> check() async {
    final result = await _tryFetch(_githubApi, _parseReleaseJson);
    if (result != null) return result;

    log('UpdateChecker: github API failed, trying raw fallback...');
    final fallback = await _tryFetch(_githubFallback, _parseVersionFile);
    if (fallback != null) return fallback;

    return _noUpdate();
  }

  static Future<UpdateInfo?> _tryFetch(
    String url,
    String? Function(String body) parser,
  ) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      client.userAgent = _userAgent;

      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      log('UpdateChecker: HTTP ${response.statusCode} from $url');

      if (response.statusCode != 200) {
        client.close();
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      client.close();

      final latestVersion = parser(body);
      if (latestVersion == null) return null;

      log('UpdateChecker: latest=$latestVersion current=$_currentVersion');

      if (latestVersion.isEmpty || latestVersion == _currentVersion) {
        return null;
      }

      if (compareVersions(latestVersion, _currentVersion) > 0) {
        log('UpdateChecker: update available v$latestVersion');
        return UpdateInfo(
          latestVersion: latestVersion,
          downloadUrl: 'https://github.com/EGBYtest/Unplug/releases/tag/v$latestVersion',
          isAvailable: true,
        );
      }

      return null;
    } catch (e) {
      log('UpdateChecker: $url error $e');
      return null;
    }
  }

  static String? _parseReleaseJson(String body) {
    // Tolerates anything that is not the expected shape. A truncated body or
    // an unexpected schema must degrade to "no update from this source" so
    // the fallback still gets its turn, not throw past the caller.
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final tagName = decoded['tag_name'];
      if (tagName is! String || tagName.isEmpty) return null;
      return tagName.replaceFirst(RegExp('^v'), '');
    } catch (_) {
      return null;
    }
  }

  static String? _parseVersionFile(String body) {
    return body.trim().isEmpty ? null : body.trim();
  }

  static UpdateInfo _noUpdate() => const UpdateInfo(
    latestVersion: '',
    downloadUrl: '',
    isAvailable: false,
  );

  /// Whether the update banner should be visible.
  ///
  /// Dismissal is remembered per version rather than as a bare flag. A user
  /// who dismisses "v1.1.3 is available" has acknowledged that release; they
  /// have not acknowledged a later one. With a single boolean the banner stayed
  /// hidden for the rest of the session even when a newer release appeared,
  /// which is the same "never clears" bug the banner had before.
  static bool shouldShowBanner(UpdateInfo? info, String? dismissedVersion) {
    if (info == null || !info.isAvailable) return false;
    return info.latestVersion != dismissedVersion;
  }

  /// Parses the GitHub Releases payload. Separate from [_tryFetch] so the
  /// decision about whether a release counts as newer can be tested against
  /// real payloads without a network round trip.
  @visibleForTesting
  static UpdateInfo? fromReleasePayload(String body, String currentVersion) {
    final latestVersion = _parseReleaseJson(body);
    if (latestVersion == null || latestVersion.isEmpty) return null;
    return latestVersion == currentVersion || compareVersions(latestVersion, currentVersion) <= 0
        ? null
        : UpdateInfo(
            latestVersion: latestVersion,
            downloadUrl: 'https://github.com/EGBYtest/Unplug/releases/tag/v$latestVersion',
            isAvailable: true,
          );
  }

  /// Compares two dotted version strings numerically, returning a negative
  /// value if [a] is older, zero if equal, positive if [a] is newer.
  /// Missing components count as 0, so '1.0' == '1.0.0'. Non-numeric
  /// components ('1.0.x', '1.0.1-beta') count as 0 rather than throwing.
  ///
  /// Public so it can be unit tested directly — the update gate depends on
  /// it being correct and it used to be reachable only over the network.
  static int compareVersions(String a, String b) {
    final partsA = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final partsB = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i = 0; i < partsA.length || i < partsB.length; i++) {
      final va = i < partsA.length ? partsA[i] : 0;
      final vb = i < partsB.length ? partsB[i] : 0;
      if (va != vb) return va - vb;
    }
    return 0;
  }
}
