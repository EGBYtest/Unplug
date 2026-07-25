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
  static const _counterApi = 'https://api.counterapi.dev/v1/unplug/version_build/';
  static const _currentVersion = '1.7.1';
  static const _currentBuild = 14;

  static UpdateInfo? cachedUpdate;

  static Future<void> initCheck() async {
    cachedUpdate = await check();
  }

  static Future<UpdateInfo> check() async {
    final result = await _tryFetch(_githubApi, _parseReleaseJson);
    if (result != null) return result;

    print('UpdateChecker: github API failed, trying raw fallback...');
    final fallback = await _tryFetch(_githubFallback, _parseVersionFile);
    if (fallback != null) return fallback;

    print('UpdateChecker: raw fallback failed, trying counter fallback...');
    final counter = await _tryFetchCounter();
    if (counter != null) return counter;

    print('UpdateChecker: all DNS failed, trying direct IP...');
    final direct = await _tryFetchDirectIp();
    if (direct != null) return direct;

    return _noUpdate();
  }

  static Future<UpdateInfo?> _tryFetch(
    String url,
    String? Function(String body) parser,
  ) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      client.userAgent = 'Unplug/1.7.1';

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

  static Future<UpdateInfo?> _tryFetchCounter() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      client.userAgent = 'Unplug/1.7.1';

      final request = await client.getUrl(Uri.parse(_counterApi));
      final response = await request.close();

      print('UpdateChecker: HTTP ${response.statusCode} from $_counterApi');

      if (response.statusCode != 200) {
        client.close();
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      client.close();

      final data = jsonDecode(body) as Map<String, dynamic>;
      final latestBuild = data['count'] as int? ?? 0;

      print('UpdateChecker: counter latestBuild=$latestBuild current=$_currentBuild');

      if (latestBuild > _currentBuild) {
        print('UpdateChecker: update available (build $latestBuild)');
        return UpdateInfo(
          latestVersion: '${latestBuild}',
          downloadUrl: 'https://github.com/EGBYtest/Unplug/releases/latest',
          isAvailable: true,
        );
      }

      return null;
    } catch (e, _) {
      print('UpdateChecker: $_counterApi error $e');
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

  static Future<UpdateInfo?> _tryFetchDirectIp() async {
    try {
      final client = HttpClient()
        ..badCertificateCallback = (_, __, ___) => true;
      client.connectionTimeout = const Duration(seconds: 5);

      final request = await client.getUrl(
        Uri.parse('https://140.82.121.5/repos/EGBYtest/Unplug/releases/latest'),
      );
      request.headers.set('Host', 'api.github.com');
      request.headers.set('User-Agent', 'Unplug/1.7.0');
      final response = await request.close();

      print('UpdateChecker: IP direct HTTP ${response.statusCode}');

      if (response.statusCode != 200) {
        client.close();
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      client.close();

      final data = jsonDecode(body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final latestVersion = tagName.replaceFirst('v', '');

      print('UpdateChecker: IP direct latest=$latestVersion current=$_currentVersion');

      if (latestVersion.isEmpty || latestVersion == _currentVersion) {
        return null;
      }

      if (_compareVersions(latestVersion, _currentVersion) > 0) {
        print('UpdateChecker: IP direct update available v$latestVersion');
        return UpdateInfo(
          latestVersion: latestVersion,
          downloadUrl: 'https://github.com/EGBYtest/Unplug/releases/tag/v$latestVersion',
          isAvailable: true,
        );
      }

      return null;
    } catch (e, _) {
      print('UpdateChecker: IP direct error $e');
      return null;
    }
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
