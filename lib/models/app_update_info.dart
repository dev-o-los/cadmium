/// Model representing release metadata fetched from GitHub Releases.
class AppUpdateInfo {
  final String tagName;
  final String version;
  final String releaseName;
  final String releaseNotes;
  final String? apkDownloadUrl;
  final String? apkFileName;
  final int? apkSizeBytes;
  final String htmlUrl;
  final DateTime? publishedAt;

  const AppUpdateInfo({
    required this.tagName,
    required this.version,
    required this.releaseName,
    required this.releaseNotes,
    this.apkDownloadUrl,
    this.apkFileName,
    this.apkSizeBytes,
    required this.htmlUrl,
    this.publishedAt,
  });

  /// Factory to parse from GitHub API release JSON
  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    final tagName = (json['tag_name'] as String? ?? '').trim();
    // Normalize version by removing leading 'v' or 'V'
    final cleanVersion = tagName.replaceFirst(RegExp(r'^[vV]'), '');

    final releaseName = (json['name'] as String? ?? tagName).trim();
    final releaseNotes = (json['body'] as String? ?? '').trim();
    final htmlUrl = (json['html_url'] as String? ?? 'https://github.com/dev-o-los/cadmium/releases').trim();

    DateTime? publishedAt;
    if (json['published_at'] != null) {
      try {
        publishedAt = DateTime.parse(json['published_at'] as String);
      } catch (_) {}
    }

    String? apkUrl;
    String? apkName;
    int? apkSize;

    final assets = json['assets'] as List<dynamic>? ?? [];
    for (final asset in assets) {
      if (asset is Map<String, dynamic>) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk')) {
          apkUrl = asset['browser_download_url'] as String?;
          apkName = asset['name'] as String?;
          apkSize = asset['size'] as int?;
          break;
        }
      }
    }

    return AppUpdateInfo(
      tagName: tagName,
      version: cleanVersion,
      releaseName: releaseName.isNotEmpty ? releaseName : tagName,
      releaseNotes: releaseNotes,
      apkDownloadUrl: apkUrl,
      apkFileName: apkName,
      apkSizeBytes: apkSize,
      htmlUrl: htmlUrl,
      publishedAt: publishedAt,
    );
  }

  /// Formatted download size (e.g., "60.8 MB" or "12.4 KB")
  String get formattedSize {
    final bytes = apkSizeBytes;
    if (bytes == null || bytes <= 0) return 'Unknown size';
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  /// Formatted published date (e.g. "Nov 11, 2026")
  String get formattedDate {
    if (publishedAt == null) return '';
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final month = months[publishedAt!.month - 1];
    return '$month ${publishedAt!.day}, ${publishedAt!.year}';
  }

  /// Compares this release version against current version.
  /// Returns true if this release is strictly newer than [currentVersion].
  bool isNewerThan(String currentVersion) {
    return compareSemver(version, currentVersion) > 0;
  }

  /// Semantic version comparator.
  /// Returns > 0 if v1 > v2, < 0 if v1 < v2, and 0 if equal.
  static int compareSemver(String v1, String v2) {
    // Strip leading 'v' or 'V' and any metadata after '+'
    final clean1 = v1.replaceFirst(RegExp(r'^[vV]'), '').split('+').first.trim();
    final clean2 = v2.replaceFirst(RegExp(r'^[vV]'), '').split('+').first.trim();

    // Split on pre-release tag like -beta, -rc
    final parts1 = clean1.split('-');
    final parts2 = clean2.split('-');

    final nums1 = parts1[0].split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final nums2 = parts2[0].split('.').map((s) => int.tryParse(s) ?? 0).toList();

    final maxLen = nums1.length > nums2.length ? nums1.length : nums2.length;
    for (int i = 0; i < maxLen; i++) {
      final n1 = i < nums1.length ? nums1[i] : 0;
      final n2 = i < nums2.length ? nums2[i] : 0;
      if (n1 > n2) return 1;
      if (n1 < n2) return -1;
    }

    // If main numbers are identical, handle pre-release presence:
    // 1.0.0 is newer than 1.0.0-beta
    if (parts1.length == 1 && parts2.length > 1) return 1;
    if (parts1.length > 1 && parts2.length == 1) return -1;

    return 0;
  }
}

