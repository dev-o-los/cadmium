import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_colors.dart';
import '../constants/apple_typography.dart';
import '../providers/auth_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/player_provider.dart';
import '../providers/update_provider.dart';
import '../services/app_update_service.dart';
import '../utils/playback_utils.dart';
import '../widgets/apple_pressable.dart';
import '../widgets/app_update_sheet.dart';
import '../widgets/liquid_glass_bottom_bar.dart';
import '../widgets/player_controls.dart';
import '../widgets/top_status_bar_blur.dart';
import '../widgets/wavify_cached_image.dart';
import 'google_signin_screen.dart';

const LiquidGlassSettings _kSettingsGlassSettings = LiquidGlassSettings(
  glassColor: Color(0x18FFFFFF),
  thickness: 28,
  blur: 24,
  refractiveIndex: 1.25,
  lightIntensity: 0.75,
  specularSharpness: GlassSpecularSharpness.sharp,
  fresnelStrength: 1.30,
  rimLight: 0.45,
  ambientStrength: 0.12,
  chromaticAberration: 0.015,
);

/// The Apple Music-style Settings screen for Wavify / Cadmium.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const String _autoUpdateKey = 'settings_auto_check_updates';

  bool _highQualityAudio = true;
  bool _wifiOnly = false;
  bool _gaplessPlayback = true;
  bool _autoCheckUpdates = true;
  String _appVersion = '1.0.4';

  @override
  void initState() {
    super.initState();
    _loadSettingsAndVersion();
  }

  Future<void> _loadSettingsAndVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final autoCheck = prefs.getBool(_autoUpdateKey) ?? true;
      final fullVersion = await AppUpdateService.instance.getFullVersionString();

      if (mounted) {
        setState(() {
          _autoCheckUpdates = autoCheck;
          _appVersion = fullVersion;
        });

        if (autoCheck) {
          final state = ref.read(updateProvider);
          if (state.status == UpdateStatus.idle) {
            ref.read(updateProvider.notifier).checkForUpdate(userInitiated: false);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _saveAutoCheckSetting(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoUpdateKey, value);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(authProvider);
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    final currentTabIndex = ref.watch(currentTabProvider);
    final updateState = ref.watch(updateProvider);
    final topPadding = MediaQuery.of(context).padding.top;

    // Open sheet when a manual check finds a new release
    ref.listen<AppUpdateState>(updateProvider, (previous, next) {
      if (next.userInitiated &&
          next.hasUpdate &&
          previous?.status != UpdateStatus.updateAvailable) {
        showAppUpdateSheet(context);
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // Top padding clearing the floating back button
              SliverToBoxAdapter(
                child: SizedBox(height: topPadding + 60),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppleSpacing.horizontalPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Settings', style: AppleTypography.largeTitle),
                      const SizedBox(height: 24),

                      // Account Section
                      _buildSectionHeader('ACCOUNT'),
                      _buildSettingsGroup(
                        children: [
                          if (account != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 26,
                                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                                    child: ClipOval(
                                      child: (account.avatarUrl != null && account.avatarUrl!.isNotEmpty)
                                          ? WavifyCachedImage(
                                              imageUrl: account.avatarUrl!,
                                              width: 52,
                                              height: 52,
                                              fit: BoxFit.cover,
                                              errorWidget: Center(
                                                child: Text(
                                                  account.initials,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            )
                                          : Center(
                                              child: Text(
                                                account.initials,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          account.displayName,
                                          style: AppleTypography.songTitle,
                                        ),
                                        const SizedBox(height: AppleSpacing.titleToSubtitle),
                                        Text(
                                          account.email,
                                          style: AppleTypography.songArtist,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            _buildSettingsTile(
                              icon: CupertinoIcons.person_crop_circle,
                              title: 'Sign In',
                              subtitle: 'Connect your YouTube Music account',
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const GoogleSignInScreen(),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: AppleSpacing.sectionSpacing),

                      // Software Update Section
                      _buildSectionHeader('SOFTWARE UPDATE'),
                      _buildSettingsGroup(
                        children: [
                          _buildUpdateTile(updateState),
                          _buildDivider(),
                          _buildSwitchTile(
                            icon: CupertinoIcons.arrow_2_circlepath,
                            title: 'Automatic Checks',
                            value: _autoCheckUpdates,
                            onChanged: (val) {
                              setState(() => _autoCheckUpdates = val);
                              _saveAutoCheckSetting(val);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: AppleSpacing.sectionSpacing),

                      // Playback & Audio
                      _buildSectionHeader('PLAYBACK & AUDIO'),
                      _buildSettingsGroup(
                        children: [
                          _buildSwitchTile(
                            icon: CupertinoIcons.waveform,
                            title: 'High Quality Audio',
                            subtitle: '256kbps AAC streaming',
                            value: _highQualityAudio,
                            onChanged: (val) => setState(() => _highQualityAudio = val),
                          ),
                          _buildDivider(),
                          _buildSwitchTile(
                            icon: CupertinoIcons.wifi,
                            title: 'Stream over Wi-Fi only',
                            value: _wifiOnly,
                            onChanged: (val) => setState(() => _wifiOnly = val),
                          ),
                          _buildDivider(),
                          _buildSwitchTile(
                            icon: CupertinoIcons.infinite,
                            title: 'Gapless Playback',
                            value: _gaplessPlayback,
                            onChanged: (val) => setState(() => _gaplessPlayback = val),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppleSpacing.sectionSpacing),

                      // About & Build
                      _buildSectionHeader('ABOUT'),
                      _buildSettingsGroup(
                        children: [
                          _buildSettingsTile(
                            icon: CupertinoIcons.info_circle,
                            title: 'Version',
                            trailing: Text(
                              _appVersion,
                              style: const TextStyle(
                                color: AppColors.appleSecondaryText,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          _buildDivider(),
                          _buildSettingsTile(
                            icon: CupertinoIcons.compass,
                            title: 'GitHub Releases',
                            subtitle: 'dev-o-los/cadmium',
                            onTap: () {
                              ref.read(updateProvider.notifier).openReleasePage();
                            },
                          ),
                          if (account != null) ...[
                            _buildDivider(),
                            _buildSettingsTile(
                              icon: CupertinoIcons.arrow_right_square,
                              iconColor: CupertinoColors.destructiveRed,
                              title: 'Log Out',
                              titleColor: CupertinoColors.destructiveRed,
                              onTap: () {
                                ref.read(authProvider.notifier).signOut();
                                Navigator.pop(context);
                              },
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 140),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Top Status Bar Blur
          const TopStatusBarBlur(),

          // Floating Top Bar with Liquid Glass Circular Back Button (Matches AlbumScreen)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: GlassIconButton(
                    icon: const Icon(
                      CupertinoIcons.chevron_back,
                      color: Colors.white,
                      size: 22,
                    ),
                    onPressed: () => Navigator.maybePop(context),
                    size: 44,
                    iconSize: 22,
                    shape: GlassIconButtonShape.circle,
                    useOwnLayer: true,
                    settings: _kSettingsGlassSettings,
                  ),
                ),
              ),
            ),
          ),

          // Floating Liquid Glass Bottom Navigation Dock / Mini Player
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: LiquidGlassBottomBar(
                currentIndex: currentTabIndex,
                isCrawled: false,
                onTabSelected: (index) {
                  ref.read(currentTabProvider.notifier).state = index;
                  Navigator.popUntil(context, (route) => route.isFirst);
                },
                onExpand: () {},
                bottomAccessory: currentSong != null
                    ? PlayerControls(
                        onTap: () => openPlayerScreen(context),
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateTile(AppUpdateState updateState) {
    IconData icon;
    String subtitle;
    Widget? trailing;

    if (updateState.isChecking) {
      icon = CupertinoIcons.arrow_2_circlepath;
      subtitle = 'Checking for updates…';
      trailing = const CupertinoActivityIndicator(radius: 8);
    } else if (updateState.isDownloading) {
      icon = CupertinoIcons.arrow_down_to_line;
      subtitle = 'Downloading… ${(updateState.progress * 100).toInt()}%';
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              value: updateState.progress > 0 ? updateState.progress : null,
              strokeWidth: 2,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              backgroundColor: Colors.white24,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(updateState.progress * 100).toInt()}%',
            style: const TextStyle(
              color: AppColors.appleSecondaryText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    } else if (updateState.isReadyToInstall) {
      icon = CupertinoIcons.arrow_down_doc_fill;
      subtitle = 'Ready to install';
      trailing = _buildActionPill('INSTALL');
    } else if (updateState.hasUpdate) {
      icon = CupertinoIcons.arrow_down_circle_fill;
      final tag = updateState.updateInfo?.tagName ?? 'New';
      subtitle = '$tag available';
      trailing = _buildActionPill('UPDATE');
    } else if (updateState.isUpToDate) {
      icon = CupertinoIcons.checkmark_seal_fill;
      subtitle = 'Up to date';
      trailing = const Icon(
        CupertinoIcons.checkmark_alt,
        color: AppColors.appleSecondaryText,
        size: 18,
      );
    } else if (updateState.hasError) {
      icon = CupertinoIcons.exclamationmark_triangle_fill;
      subtitle = 'Unable to check for updates';
      trailing = const Icon(
        CupertinoIcons.chevron_forward,
        color: Colors.white38,
        size: 16,
      );
    } else {
      icon = CupertinoIcons.arrow_2_circlepath;
      subtitle = 'Check for updates';
      trailing = const Icon(
        CupertinoIcons.chevron_forward,
        color: Colors.white38,
        size: 16,
      );
    }

    return ApplePressable(
      onTap: () {
        if (updateState.hasUpdate ||
            updateState.isDownloading ||
            updateState.isReadyToInstall ||
            (updateState.updateInfo != null && updateState.isUpToDate)) {
          showAppUpdateSheet(context);
        } else {
          ref.read(updateProvider.notifier).checkForUpdate(userInitiated: true);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Software Update',
                    style: AppleTypography.sheetAction,
                  ),
                  const SizedBox(height: AppleSpacing.titleToSubtitle),
                  Text(
                    subtitle,
                    style: AppleTypography.sheetSubtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildActionPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: AppleSpacing.sectionHeaderToContent),
      child: Text(
        title,
        style: AppleTypography.eyebrow,
      ),
    );
  }

  Widget _buildSettingsGroup({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.appleDarkSurfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 0.6,
      color: Colors.white.withValues(alpha: 0.12),
      indent: 52,
      endIndent: 0,
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    Color iconColor = Colors.white,
    required String title,
    Color titleColor = Colors.white,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ApplePressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppleTypography.sheetAction.copyWith(color: titleColor),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: AppleSpacing.titleToSubtitle),
                    Text(
                      subtitle,
                      style: AppleTypography.sheetSubtitle,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing
            else if (onTap != null)
              const Icon(
                CupertinoIcons.chevron_forward,
                color: Colors.white38,
                size: 16,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppleTypography.sheetAction,
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: AppleSpacing.titleToSubtitle),
                  Text(
                    subtitle,
                    style: AppleTypography.sheetSubtitle,
                  ),
                ],
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            activeTrackColor: AppColors.appleBlue,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
