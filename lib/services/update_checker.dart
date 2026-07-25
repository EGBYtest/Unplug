import 'dart:convert';
import 'dart:developer';
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
  static const _currentVersion = '1.3.3';

  static Future<UpdateInfo> check() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      client.userAgent = 'Unplug/1.3.3';

      final request = await client.getUrl(Uri.parse(_githubApi));
      final response = await request.close();

      log('UpdateChecker: HTTP ${response.statusCode}', name: 'UpdateChecker');

      if (response.statusCode != 200) {
        client.close();
        return _noUpdate();
      }

      final body = await response.transform(utf8.decoder).join();
      client.close();

      final data = jsonDecode(body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final latestVersion = tagName.replaceFirst('v', '');

      log('UpdateChecker: latest=$latestVersion current=$_currentVersion', name: 'UpdateChecker');

      if (latestVersion.isEmpty || latestVersion == _currentVersion) {
        return _noUpdate();
      }

      final assets = data['assets'] as List<dynamic>? ?? [];
      String downloadUrl = data['html_url'] as String? ?? '';
      if (assets.isNotEmpty) {
        final first = assets.first as Map<String, dynamic>;
        downloadUrl = first['browser_download_url'] as String? ?? downloadUrl;
      }

      if (_compareVersions(latestVersion, _currentVersion) > 0) {
        log('UpdateChecker: update available v$latestVersion', name: 'UpdateChecker');
        return UpdateInfo(
          latestVersion: latestVersion,
          downloadUrl: downloadUrl,
          isAvailable: true,
        );
      }

      return _noUpdate();
    } catch (e, stack) {
      log('UpdateChecker: error $e', name: 'UpdateChecker', error: e, stackTrace: stack);
      return _noUpdate();
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
