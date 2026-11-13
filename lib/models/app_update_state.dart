import 'app_update_info.dart';
export 'app_update_info.dart';

enum UpdateStatus {
  idle,
  checking,
  upToDate,
  updateAvailable,
  downloading,
  readyToInstall,
  installing,
  error,
}

class AppUpdateState {
  final UpdateStatus status;
  final AppUpdateInfo? updateInfo;
  final String currentVersion;
  final double progress; // 0.0 to 1.0
  final int receivedBytes;
  final int totalBytes;
  final String? downloadedApkPath;
  final String? errorMessage;
  final bool userInitiated;

  const AppUpdateState({
    this.status = UpdateStatus.idle,
    this.updateInfo,
    this.currentVersion = '1.0.4',
    this.progress = 0.0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.downloadedApkPath,
    this.errorMessage,
    this.userInitiated = false,
  });

  bool get isChecking => status == UpdateStatus.checking;
  bool get hasUpdate => status == UpdateStatus.updateAvailable;
  bool get isDownloading => status == UpdateStatus.downloading;
  bool get isReadyToInstall => status == UpdateStatus.readyToInstall;
  bool get isUpToDate => status == UpdateStatus.upToDate;
  bool get hasError => status == UpdateStatus.error;

  AppUpdateState copyWith({
    UpdateStatus? status,
    AppUpdateInfo? updateInfo,
    String? currentVersion,
    double? progress,
    int? receivedBytes,
    int? totalBytes,
    String? downloadedApkPath,
    String? errorMessage,
    bool? userInitiated,
  }) {
    return AppUpdateState(
      status: status ?? this.status,
      updateInfo: updateInfo ?? this.updateInfo,
      currentVersion: currentVersion ?? this.currentVersion,
      progress: progress ?? this.progress,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedApkPath: downloadedApkPath ?? this.downloadedApkPath,
      errorMessage: errorMessage ?? this.errorMessage,
      userInitiated: userInitiated ?? this.userInitiated,
    );
  }
}
