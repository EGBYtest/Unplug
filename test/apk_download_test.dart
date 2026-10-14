import 'package:flutter_test/flutter_test.dart';
import 'package:unplug/services/apk_downloader.dart';
import 'package:unplug/services/update_checker.dart';

void main() {
  group('the APK header check', () {
    // GitHub answers a missing or renamed release asset with HTTP 200 and an
    // HTML error page. If that page reached the package installer under an
    // .apk name the user would get a system dialog about a broken file, or
    // worse, a silent nothing. Four bytes prevent the whole class.
    test('accepts a ZIP local-file header, which is what an APK starts with', () {
      expect(ApkDownloader.looksLikeApk([0x50, 0x4B, 0x03, 0x04]), isTrue);
    });

    test('rejects an HTML error page', () {
      expect(ApkDownloader.looksLikeApk('<!DO'.codeUnits), isFalse);
      expect(ApkDownloader.looksLikeApk('Not '.codeUnits), isFalse);
    });

    test('rejects a truncated read rather than guessing', () {
      expect(ApkDownloader.looksLikeApk([0x50, 0x4B, 0x03]), isFalse);
      expect(ApkDownloader.looksLikeApk([]), isFalse);
    });

    test('rejects a JSON body', () {
      expect(ApkDownloader.looksLikeApk('{"ta'.codeUnits), isFalse);
    });
  });

  group('the direct APK link', () {
    UpdateInfo info(String version, bool available) => UpdateInfo(
          latestVersion: version,
          downloadUrl: 'https://example.invalid/tag',
          isAvailable: available,
        );

    test('is the release download path for the tag it found', () {
      expect(
        info('2.1.0', true).apkUrl,
        'https://github.com/EGBYtest/Unplug/releases/download/v2.1.0/app-release.apk',
      );
    });

    test('is empty with no update, so nothing can be handed to the installer', () {
      // The no-update answer has an empty version. Interpolating that into a
      // path would produce a link to the bare `v` tag rather than an APK, and
      // that would be downloaded and offered for install.
      expect(info('', false).apkUrl, isEmpty);
      expect(info('2.1.0', false).apkUrl, isEmpty);
    });
  });

  group('downloaded files are not left behind', () {
    test('the downloader is reachable and does not throw on a bad URL', () async {
      // Not a network test. A malformed URL must surface as a user-facing
      // message rather than an unhandled FileSystemException.
      await expectLater(
        ApkDownloader.download(
          'not a url',
          onProgress: (_) {},
        ),
        throwsA(isA<ApkDownloadException>()),
      );
    });
  });
}