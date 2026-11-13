import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_update_info.dart';

class AppUpdateService {
  static final AppUpdateService instance = AppUpdateService._internal();
  AppUpdateService._internal();

  static const String repoOwner = 'dev-o-los';
  static const String repoName = 'cadmium';
  static const String releaseApiUrl =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

  PackageInfo? _cachedPackageInfo;
  HttpClient? _downloadClient;

  /// Retrieves the current version from the platform package metadata.
  Future<String> getCurrentVersion() async {
    try {
      _cachedPackageInfo ??= await PackageInfo.fromPlatform();
      return _cachedPackageInfo!.version;
    } catch (_) {
      return '1.0.5';
    }
  }

  /// Retrieves full version string with build number (e.g. "1.0.5+6").
  Future<String> getFullVersionString() async {
    try {
      _cachedPackageInfo ??= await PackageInfo.fromPlatform();
      final version = _cachedPackageInfo!.version;
      final buildNumber = _cachedPackageInfo!.buildNumber;
      if (buildNumber.isNotEmpty) {
        return '$version ($buildNumber)';
      }
      return version;
    } catch (_) {
      return '1.0.5';
    }
  }

  /// Fetches the latest release from the GitHub repository.
  Future<AppUpdateInfo?> fetchLatestRelease() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);

    try {
      final uri = Uri.parse(releaseApiUrl);
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'Cadmium-App');
      request.headers.set('Accept', 'application/vnd.github.v3+json');

      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('GitHub returned status code ${response.statusCode}');
      }

      final body = await response.transform(utf8.decoder).join();
      final dynamic decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return AppUpdateInfo.fromJson(decoded);
      }
      return null;
    } finally {
      client.close();
    }
  }

  /// Downloads the APK to a local temporary directory with streaming progress.
  Future<String> downloadApk(
    AppUpdateInfo updateInfo, {
    required void Function(double progress, int received, int total) onProgress,
    CancellationToken? cancelToken,
  }) async {
    final apkUrl = updateInfo.apkDownloadUrl;
    if (apkUrl == null || apkUrl.isEmpty) {
      throw Exception('No APK file found in this release.');
    }

    final tempDir = await getTemporaryDirectory();
    final updatesDir = Directory('${tempDir.path}/updates');
    if (!await updatesDir.exists()) {
      await updatesDir.create(recursive: true);
    }

    final fileName = updateInfo.apkFileName ?? 'cadmium-${updateInfo.version}.apk';
    final targetFile = File('${updatesDir.path}/$fileName');

    // If file already exists and is fully downloaded, verify size
    if (await targetFile.exists()) {
      final length = await targetFile.length();
      if (updateInfo.apkSizeBytes != null && length == updateInfo.apkSizeBytes) {
        onProgress(1.0, length, length);
        return targetFile.path;
      } else {
        await targetFile.delete();
      }
    }

    _downloadClient?.close(force: true);
    _downloadClient = HttpClient();
    _downloadClient!.connectionTimeout = const Duration(seconds: 30);

    final client = _downloadClient!;
    final uri = Uri.parse(apkUrl);
    final request = await client.getUrl(uri);
    request.followRedirects = true;
    request.maxRedirects = 8;
    request.headers.set('User-Agent', 'Mozilla/5.0 (Android; Mobile)');

    cancelToken?.onCancel = () {
      client.close(force: true);
      if (targetFile.existsSync()) {
        try {
          targetFile.deleteSync();
        } catch (_) {}
      }
    };

    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Download failed with status: ${response.statusCode}');
    }

    final contentLength = response.contentLength > 0
        ? response.contentLength
        : (updateInfo.apkSizeBytes ?? -1);

    int receivedBytes = 0;
    final sink = targetFile.openWrite();

    try {
      await for (final chunk in response) {
        if (cancelToken?.isCancelled ?? false) {
          throw Exception('Download cancelled by user.');
        }
        sink.add(chunk);
        receivedBytes += chunk.length;

        final double progress = contentLength > 0
            ? (receivedBytes / contentLength).clamp(0.0, 1.0)
            : 0.0;

        onProgress(progress, receivedBytes, contentLength);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    return targetFile.path;
  }

  /// Cancels any active APK download.
  void cancelActiveDownload() {
    _downloadClient?.close(force: true);
    _downloadClient = null;
  }

  /// Prompts installation of the downloaded APK.
  /// On Android, checks REQUEST_INSTALL_PACKAGES and invokes the native installer.
  /// On iOS/other platforms, opens the release page in the browser.
  Future<bool> installApk(String filePath, {String? fallbackUrl}) async {
    if (Platform.isAndroid) {
      try {
        final installPermStatus = await Permission.requestInstallPackages.status;
        if (!installPermStatus.isGranted) {
          final requested = await Permission.requestInstallPackages.request();
          if (!requested.isGranted) {
            // Still proceed to open file as Android OS can show the "Allow from this source" prompt
          }
        }

        final result = await OpenFilex.open(
          filePath,
          type: 'application/vnd.android.package-archive',
        );

        if (result.type == ResultType.done) {
          return true;
        }

        // If open_filex failed, fallback to opening release in browser
        if (fallbackUrl != null) {
          await openUrl(fallbackUrl);
        }
        return false;
      } catch (e) {
        if (fallbackUrl != null) {
          await openUrl(fallbackUrl);
        }
        return false;
      }
    } else {
      // Non-Android platforms open release page directly
      if (fallbackUrl != null) {
        await openUrl(fallbackUrl);
        return true;
      }
      return false;
    }
  }

  /// Opens an external URL in the browser.
  Future<bool> openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}

class CancellationToken {
  bool _isCancelled = false;
  void Function()? onCancel;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
    onCancel?.call();
  }
}

