import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../constants/apple_typography.dart';
import '../providers/auth_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/player_provider.dart';
import '../utils/playback_utils.dart';
import '../widgets/apple_pressable.dart';
import '../widgets/liquid_glass_bottom_bar.dart';
import '../widgets/player_controls.dart';
import '../widgets/top_status_bar_blur.dart';
import '../widgets/wavify_cached_image.dart';
import 'google_signin_screen.dart';

/// The Apple Music-style Settings screen for Wavify.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _highQualityAudio = true;
  bool _wifiOnly = false;
  bool _gaplessPlayback = true;

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(authProvider);
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    final currentTabIndex = ref.watch(currentTabProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // Apple-style Cupertino navigation bar
              SliverAppBar(
                backgroundColor: Colors.black.withValues(alpha: 0.75),
                pinned: true,
                elevation: 0,
                leading: ApplePressable(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(20),
                  child: const Center(
                    child: Icon(
                      CupertinoIcons.chevron_back,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
                title: const Text(
                  'Settings',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppleSpacing.horizontalPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      const Text('Settings', style: AppleTypography.largeTitle),
                      const SizedBox(height: 24),

                      // Account Header Card
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
                              icon: CupertinoIcons.person_crop_circle_fill,
                              title: 'Sign In with Google Account',
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

                      // Playback & Audio
                      _buildSectionHeader('PLAYBACK & AUDIO'),
                      _buildSettingsGroup(
                        children: [
                          _buildSwitchTile(
                            icon: CupertinoIcons.waveform,
                            title: 'High Quality Streaming',
                            subtitle: 'Stream 256kbps AAC audio',
                            value: _highQualityAudio,
                            onChanged: (val) => setState(() => _highQualityAudio = val),
                          ),
                          _buildDivider(),
                          _buildSwitchTile(
                            icon: CupertinoIcons.wifi,
                            title: 'Stream over Wi-Fi only',
                            subtitle: 'Reduce mobile data usage',
                            value: _wifiOnly,
                            onChanged: (val) => setState(() => _wifiOnly = val),
                          ),
                          _buildDivider(),
                          _buildSwitchTile(
                            icon: CupertinoIcons.infinite,
                            title: 'Gapless Playback',
                            subtitle: 'Seamless transition between tracks',
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
                            trailing: const Text(
                              '1.0.0',
                              style: TextStyle(
                                color: AppColors.appleSecondaryText,
                                fontSize: 15,
                              ),
                            ),
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
          const TopStatusBarBlur(),

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

