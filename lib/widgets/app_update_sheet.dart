import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../constants/apple_typography.dart';
import '../providers/update_provider.dart';
import 'apple_glass_bottom_sheet.dart';
import 'apple_pressable.dart';

/// Displays the Apple Music-styled Software Update modal sheet.
void showAppUpdateSheet(BuildContext context) {
  showAppleGlassBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (modalContext) => const AppUpdateSheetContent(),
  );
}

class AppUpdateSheetContent extends ConsumerWidget {
  const AppUpdateSheetContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateState = ref.watch(updateProvider);
    final updateInfo = updateState.updateInfo;
    final isDownloading = updateState.isDownloading;
    final isReadyToInstall = updateState.isReadyToInstall;

    final versionTag = updateInfo?.tagName ?? 'New Version';
    final releaseDate = updateInfo?.formattedDate ?? '';
    final releaseSize = updateInfo?.formattedSize ?? '';
    final notes = updateInfo?.releaseNotes ?? 'Improvements and bug fixes.';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),

          // Header Row with Icon and Title
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 0.8,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    CupertinoIcons.arrow_down_circle_fill,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Update Available',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 0.6,
                            ),
                          ),
                          child: Text(
                            versionTag,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (releaseSize.isNotEmpty) releaseSize,
                        if (releaseDate.isNotEmpty) releaseDate,
                      ].join(' • '),
                      style: const TextStyle(
                        color: AppColors.appleSecondaryText,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // "WHAT'S NEW" Section Header
          const Text(
            "WHAT'S NEW",
            style: AppleTypography.eyebrow,
          ),
          const SizedBox(height: 8),

          // Release Notes Container
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 180),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.appleDarkSurfaceHigh.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 0.8,
              ),
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Text(
                notes.isNotEmpty ? notes : 'General bug fixes, performance improvements, and UI refinements.',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.4,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Downloading Progress Bar & Details
          if (isDownloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: updateState.progress > 0 ? updateState.progress : null,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(updateState.progress * 100).toStringAsFixed(0)}% • ${_formatBytes(updateState.receivedBytes)} of ${_formatBytes(updateState.totalBytes)}',
                  style: const TextStyle(
                    color: AppColors.appleSecondaryText,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                ApplePressable(
                  onTap: () => ref.read(updateProvider.notifier).cancelDownload(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Error banner if any
          if (updateState.hasError && updateState.errorMessage != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.red.withValues(alpha: 0.3),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.exclamationmark_triangle_fill,
                    color: Colors.redAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      updateState.errorMessage!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Action Buttons
          if (isReadyToInstall) ...[
            _buildPrimaryButton(
              title: 'Install Update Now',
              icon: CupertinoIcons.arrow_down_doc_fill,
              onTap: () {
                ref.read(updateProvider.notifier).installDownloadedApk();
              },
            ),
          ] else if (isDownloading) ...[
            Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CupertinoActivityIndicator(color: Colors.white, radius: 9),
                    SizedBox(width: 10),
                    Text(
                      'Downloading APK...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            _buildPrimaryButton(
              title: 'Download & Install',
              icon: CupertinoIcons.arrow_down_to_line,
              onTap: () {
                ref.read(updateProvider.notifier).startDownloadAndInstall();
              },
            ),
          ],

          const SizedBox(height: 10),

          // Secondary Row: View on GitHub & Dismiss
          Row(
            children: [
              Expanded(
                child: ApplePressable(
                  onTap: () => ref.read(updateProvider.notifier).openReleasePage(),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.appleDarkSurfaceHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 0.8,
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.arrow_up_right_square, size: 16, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'View on GitHub',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ApplePressable(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                        width: 0.8,
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        'Later',
                        style: TextStyle(
                          color: AppColors.appleSecondaryText,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ApplePressable(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.black, size: 20),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
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
}
