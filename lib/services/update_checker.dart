import 'dart:convert';
import 'dart:io';

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
  static const _currentVersion = '1.6.0';

  static UpdateInfo? cachedUpdate;

  static Future<void> initCheck() async {
    cachedUpdate = await check();
  }

  static Future<UpdateInfo> check() async {
    final result = await _tryFetch(_githubApi, _parseReleaseJson);
    if (result != null) return result;

    print('UpdateChecker: primary failed, trying fallback...');
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
      client.userAgent = 'Unplug/1.6.0';

      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      print('UpdateChecker: HTTP ${response.statusCode} from $url');

      if (response.statusCode != 200) {
        client.close();
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      client.close();

      final latestVersion = parser(body);
      if (latestVersion == null) return null;

      print('UpdateChecker: latest=$latestVersion current=$_currentVersion');

      if (latestVersion.isEmpty || latestVersion == _currentVersion) {
        return null;
      }

      if (_compareVersions(latestVersion, _currentVersion) > 0) {
        print('UpdateChecker: update available v$latestVersion');
        return UpdateInfo(
          latestVersion: latestVersion,
          downloadUrl: 'https://github.com/EGBYtest/Unplug/releases/tag/v$latestVersion',
          isAvailable: true,
        );
      }

      return null;
    } catch (e, _) {
      print('UpdateChecker: $url error $e');
      return null;
    }
  }

  static String? _parseReleaseJson(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final tagName = data['tag_name'] as String? ?? '';
    return tagName.replaceFirst('v', '');
  }

  static String? _parseVersionFile(String body) {
    return body.trim().isEmpty ? null : body.trim();
  }

  static UpdateInfo _noUpdate() => const UpdateInfo(
    latestVersion: '',
    downloadUrl: '',
    isAvailable: false,
  );

  static int _compareVersions(String a, String b) {
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
