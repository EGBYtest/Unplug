import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Downloads a release APK into the app's cache and hands it to Android's
/// package installer.
///
/// The alternative was leaving the app for a browser and finding the APK
/// among a release page's assets by hand, then handing that file to a file
/// manager. Every step of that is a place for the user to get stuck, and
/// none of it is Unplug's fault, which is exactly why it should not be the
/// upgrade path.
///
/// The download itself is deliberately not streamed to the Downloads folder.
/// There is no way to write there without a permission prompt on modern
/// Android, and the installer only needs to read the file once, through a
/// content:// grant that [install] hands it. The cache directory is the
/// right home: it is private, it needs no permission, and the OS reclaims it
/// on its own.
class ApkDownloader {
  static const MethodChannel _channel = MethodChannel('unplug/apk');

  /// Downloads [url] to the cache directory, reporting progress in the range
  /// 0.0–1.0.
  ///
  /// Throws [ApkDownloadException] with a message meant for the user if
  /// anything goes wrong. Callers are expected to show it and offer the
  /// browser fallback rather than leaving a dead button on screen.
  static Future<File> download(
    String url, {
    required void Function(double progress) onProgress,
  }) async {
    final http.Client client = http.Client();
    File? partial;
    var complete = false;
    try {
      onProgress(0.0);

      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request).timeout(
        const Duration(seconds: 60),
      );

      if (response.statusCode != 200) {
        throw ApkDownloadException(
          'The download failed (HTTP ${response.statusCode}).',
        );
      }

      final total = response.contentLength;
      final dir = await getTemporaryDirectory();
      partial = File('${dir.path}/unplug-update.apk');
      // A leftover from an interrupted attempt would otherwise be appended
      // to or mistaken for the new file.
      if (await partial.exists()) await partial.delete();

      final sink = partial.openWrite();
      var received = 0;
      var head = <int>[];
      try {
        await for (final chunk in response.stream) {
          if (head.length < 4) {
            head.addAll(chunk.take(4 - head.length));
          }
          received += chunk.length;
          sink.add(chunk);
          if (total != null && total > 0) {
            onProgress((received / total).clamp(0.0, 1.0));
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (!looksLikeApk(head)) {
        throw ApkDownloadException(
          "That wasn't an APK file. The release may have been taken down.",
        );
      }

      onProgress(1.0);
      complete = true;
      return partial;
    } on TimeoutException {
      throw ApkDownloadException('The download timed out.');
    } on SocketException {
      throw ApkDownloadException("Couldn't reach the server. Check your connection.");
    } on ApkDownloadException {
      rethrow;
    } on FormatException {
      throw ApkDownloadException("That link doesn't look right.");
    } catch (e) {
      throw ApkDownloadException('The download failed. ($e)');
    } finally {
      client.close();
      // A failed or rejected download leaves nothing for the installer to
      // pick up later, and a half-written APK would fail the install with a
      // far more confusing message.
      if (!complete && partial != null) {
        try {
          if (await partial.exists()) await partial.delete();
        } catch (_) {}
      }
    }
  }

  /// Asks Android to install [file].
  ///
  /// Returns false when the user has not yet allowed this app to install
  /// packages, in which case [openInstallPermissionSettings] has been called
  /// to send them there — the system prompt cannot be raised from here.
  static Future<bool> install(File file) async {
    try {
      final granted = await _channel.invokeMethod<bool>('installApk', {
        'path': file.path,
      });
      return granted ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens the per-app "allow from this source" screen.
  static Future<void> openInstallPermissionSettings() async {
    try {
      await _channel.invokeMethod<bool>('openInstallPermissionSettings');
    } catch (_) {}
  }

  /// Whether the bytes at the head of a file are a ZIP local-file header,
  /// which every APK starts with.
  ///
  /// This check is the reason the browser fallback can be trusted. GitHub
  /// answers a missing or renamed asset with a 200 and an HTML error page,
  /// and an HTML page named `.apk` handed straight to the package installer
  /// produces either a silent failure or a confusing system dialog. Four
  /// bytes rule that out before anything else happens.
  @visibleForTesting
  static bool looksLikeApk(List<int> bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
  }

  static Future<bool> looksLikeApkFile(File file) async {
    try {
      final handle = await file.open();
      try {
        final head = await handle.read(4);
        return looksLikeApk(head);
      } finally {
        await handle.close();
      }
    } catch (_) {
      return false;
    }
  }
}

class ApkDownloadException implements Exception {
  final String message;
  const ApkDownloadException(this.message);
  @override
  String toString() => message;
}