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

  /// Shortest gap between real network lookups.
  ///
  /// The dashboard checked on every app resume, and GitHub's unauthenticated
  /// API allows 60 requests per hour per IP. A user glancing at their phone
  /// dozens of times could exhaust that on their own — and mobile carriers
  /// put many users behind one IP, so the ceiling is shared. Once spent, the
  /// API returns 403, the app falls through to the raw VERSION file, and
  /// that file is served from a slower CDN cache — so the banner silently
  /// stops appearing with no error anywhere. Throttling keeps a normal user
  /// at roughly two requests an hour.
  static const Duration minCheckInterval = Duration(minutes: 30);

  static DateTime? _lastCheckAt;
  static UpdateInfo? _lastResult;
  static int _requestCount = 0;

  /// Number of network lookups made this session.
  ///
  /// Exposed because the failure this throttling fixes is invisible otherwise:
  /// when the budget is spent the app still returns a plausible answer and
  /// shows nothing. Being able to count requests is what makes the budget a
  /// testable property rather than a hope.
  @visibleForTesting
  static int get requestCount => _requestCount;

  /// Drops the cached answer so the next [check] goes to the network.
  static void invalidate() {
    _lastCheckAt = null;
    _lastResult = null;
  }

  /// Checks for a newer release.
  ///
  /// [currentVersion] defaults to this build's version. It is a parameter so
  /// the "an older build sees a newer release" path can be exercised against
  /// the real sources — that is the path a user is on when they expect the
  /// banner, and it is the one that has gone quiet before.
  ///
  /// Repeated calls within [minCheckInterval] reuse the last answer rather
  /// than spending another request. Pass [force] to always go out.
  static Future<UpdateInfo> check({
    String currentVersion = _currentVersion,
    bool force = false,
    String? authToken,
  }) async {
    // Only the production path is cached: a result is only meaningful for the
    // version it was computed against. Auth does not affect what the answer
    // means, so it does not affect caching — and the throttle has to hold for
    // the tests too, or they would not be exercising the real behaviour.
    final cacheable = currentVersion == _currentVersion;
    if (cacheable && !force && _cached() != null) {
      log('UpdateChecker: reusing cached result within $minCheckInterval');
      return _cached()!;
    }

    final result = await _checkNow(currentVersion, authToken);
    if (cacheable && result.reached) {
      // Only cache when a source actually answered. Caching a total failure
      // would suppress the banner for the whole window after one bad moment.
      _lastResult = result.info;
      _lastCheckAt = DateTime.now();
    }
    return result.info;
  }

  static UpdateInfo? _cached() {
    final at = _lastCheckAt;
    if (_lastResult == null || at == null) return null;
    if (DateTime.now().difference(at) >= minCheckInterval) return null;
    return _lastResult;
  }

  static Future<({UpdateInfo info, bool reached})> _checkNow(
    String currentVersion,
    String? authToken,
  ) async {
    final api = await _tryFetch(
        _githubApi, _parseReleaseJson, currentVersion, authToken);
    if (api.update != null) return (info: api.update!, reached: true);

    log('UpdateChecker: github API unusable, trying raw fallback...');
    final raw = await _tryFetch(
        _githubFallback, _parseVersionFile, currentVersion, authToken);
    if (raw.update != null) return (info: raw.update!, reached: true);

    // "The source answered and there is nothing newer" is not the same thing
    // as "the source did not answer". Collapsing the two is how a total
    // failure ends up cached as "no update" and the banner stays hidden.
    return (info: _noUpdate(), reached: api.ok || raw.ok);
  }

  /// Fetches one source.
  ///
  /// [ok] reports whether the source actually answered and parsed, which is
  /// independent of whether it found an update.
  static Future<({UpdateInfo? update, bool ok})> _tryFetch(
    String url,
    String? Function(String body) parser,
    String currentVersion,
    String? authToken,
  ) async {
    try {
      _requestCount++;
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      client.userAgent = _userAgent;

      final request = await client.getUrl(Uri.parse(url));
      // raw.githubusercontent.com varies its cache on Accept-Encoding, so the
      // gzip and identity responses are separate objects. Observed directly:
      // just after a release the gzip object still served the previous
      // version for ten-plus minutes while the identity object was current.
      // These payloads are tiny; ask for identity so the fallback reads the
      // object that keeps up.
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (authToken != null && authToken.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
      }
      final response = await request.close();

      final status = response.statusCode;
      log('UpdateChecker: HTTP $status from $url');
      if (status != 200) {
        if (status == 403 || status == 429) {
          log('UpdateChecker: $url rate limited ($status) — falling back to '
              'the raw VERSION file, which may itself be cached briefly '
              'behind a release');
        }
        client.close();
        return (update: null, ok: false);
      }

      final body = await response.transform(utf8.decoder).join();
      client.close();

      final latestVersion = parser(body);
      if (latestVersion == null) return (update: null, ok: false);

      log('UpdateChecker: latest=$latestVersion current=$currentVersion');

      if (latestVersion.isEmpty || latestVersion == currentVersion) {
        return (update: null, ok: true);
      }

      if (compareVersions(latestVersion, currentVersion) > 0) {
        log('UpdateChecker: update available v$latestVersion');
        return (
          update: UpdateInfo(
            latestVersion: latestVersion,
            downloadUrl:
                'https://github.com/EGBYtest/Unplug/releases/tag/v$latestVersion',
            isAvailable: true,
          ),
          ok: true,
        );
      }

      return (update: null, ok: true);
    } catch (e) {
      log('UpdateChecker: $url error $e');
      return (update: null, ok: false);
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
