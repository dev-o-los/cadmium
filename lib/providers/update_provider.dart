import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_update_state.dart';
import '../services/app_update_service.dart';

export '../models/app_update_state.dart';

final updateProvider = StateNotifierProvider<UpdateNotifier, AppUpdateState>((ref) {
  return UpdateNotifier();
});

class UpdateNotifier extends StateNotifier<AppUpdateState> {
  final AppUpdateService _service;
  CancellationToken? _cancelToken;

  UpdateNotifier([AppUpdateService? service])
      : _service = service ?? AppUpdateService.instance,
        super(const AppUpdateState()) {
    _initCurrentVersion();
  }

  Future<void> _initCurrentVersion() async {
    final version = await _service.getCurrentVersion();
    state = state.copyWith(currentVersion: version);
  }

  /// Checks GitHub releases for a newer version.
  Future<void> checkForUpdate({bool userInitiated = false}) async {
    if (state.isChecking || state.isDownloading) return;

    final currentVersion = await _service.getCurrentVersion();
    state = state.copyWith(
      status: UpdateStatus.checking,
      currentVersion: currentVersion,
      errorMessage: null,
      userInitiated: userInitiated,
    );

    try {
      final release = await _service.fetchLatestRelease();
      if (release == null) {
        state = state.copyWith(
          status: UpdateStatus.error,
          errorMessage: 'No release data found on GitHub.',
        );
        return;
      }

      final bool isNewer = release.isNewerThan(currentVersion);

      if (isNewer) {
        state = state.copyWith(
          status: UpdateStatus.updateAvailable,
          updateInfo: release,
          errorMessage: null,
        );
      } else {
        state = state.copyWith(
          status: UpdateStatus.upToDate,
          updateInfo: release,
          errorMessage: null,
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: e.toString().replaceFirst(RegExp(r'^Exception: '), ''),
      );
    }
  }

  /// Starts downloading the APK from GitHub releases.
  Future<void> startDownloadAndInstall({bool autoInstall = true}) async {
    final info = state.updateInfo;
    if (info == null || info.apkDownloadUrl == null) {
      // If no APK asset is attached, open GitHub release in browser
      if (info?.htmlUrl != null) {
        await _service.openUrl(info!.htmlUrl);
      }
      return;
    }

    _cancelToken = CancellationToken();
    state = state.copyWith(
      status: UpdateStatus.downloading,
      progress: 0.0,
      receivedBytes: 0,
      totalBytes: info.apkSizeBytes ?? 0,
      errorMessage: null,
    );

    try {
      final filePath = await _service.downloadApk(
        info,
        cancelToken: _cancelToken,
        onProgress: (progress, received, total) {
          state = state.copyWith(
            progress: progress,
            receivedBytes: received,
            totalBytes: total,
          );
        },
      );

      state = state.copyWith(
        status: UpdateStatus.readyToInstall,
        downloadedApkPath: filePath,
        progress: 1.0,
      );

      if (autoInstall) {
        await installDownloadedApk();
      }
    } catch (e) {
      if (_cancelToken?.isCancelled ?? false) {
        state = state.copyWith(
          status: UpdateStatus.updateAvailable,
          progress: 0.0,
          errorMessage: 'Download cancelled',
        );
      } else {
        state = state.copyWith(
          status: UpdateStatus.error,
          errorMessage: 'Download failed: ${e.toString().replaceFirst(RegExp(r'^Exception: '), '')}',
        );
      }
    } finally {
      _cancelToken = null;
    }
  }

  /// Cancels any active download in progress.
  void cancelDownload() {
    _cancelToken?.cancel();
    _service.cancelActiveDownload();
    state = state.copyWith(
      status: state.updateInfo != null
          ? UpdateStatus.updateAvailable
          : UpdateStatus.idle,
      progress: 0.0,
      receivedBytes: 0,
    );
  }

  /// Triggers OS installation of the downloaded APK.
  Future<bool> installDownloadedApk() async {
    final path = state.downloadedApkPath;
    if (path == null) return false;

    state = state.copyWith(status: UpdateStatus.installing);
    final success = await _service.installApk(
      path,
      fallbackUrl: state.updateInfo?.htmlUrl,
    );

    // Keep readyToInstall state so user can tap install again if prompt dismissed
    state = state.copyWith(status: UpdateStatus.readyToInstall);
    return success;
  }

  /// Opens the release on GitHub in external browser.
  Future<void> openReleasePage() async {
    final url = state.updateInfo?.htmlUrl ??
        'https://github.com/${AppUpdateService.repoOwner}/${AppUpdateService.repoName}/releases';
    await _service.openUrl(url);
  }
}
