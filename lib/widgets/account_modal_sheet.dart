import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/apple_typography.dart';
import '../providers/auth_provider.dart';
import '../screens/google_signin_screen.dart';
import '../screens/settings_screen.dart';
import 'apple_glass_bottom_sheet.dart';
import 'apple_pressable.dart';
import 'wavify_cached_image.dart';

/// Shows the Google / YouTube Music account overview sheet with authentic
/// Apple-style Liquid Glass blur, grouped cards, and pure white typography.
void showAccountModalSheet(BuildContext context, WidgetRef ref) {
  showAppleGlassBottomSheet(
    context: context,
    builder: (modalCtx) {
      return Consumer(
        builder: (context, ref, child) {
          final account = ref.watch(authProvider);

          if (account != null) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Profile Header Card: Avatar, Full Name, and Username
                AppleSheetGroup(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  children: [
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.6),
                              width: 1.5,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 28,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.18,
                            ),
                            child: ClipOval(
                              child:
                                  account.avatarUrl != null &&
                                          account.avatarUrl!.isNotEmpty
                                      ? WavifyCachedImage(
                                          imageUrl: account.avatarUrl!,
                                          width: 56,
                                          height: 56,
                                          fit: BoxFit.cover,
                                          errorWidget: Center(
                                            child: Text(
                                              account.initials,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 20,
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
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                            ),
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppleTypography.songTitle.copyWith(
                                  fontSize: 18,
                                ),
                              ),
                              if (account.email.isNotEmpty) ...[
                                const SizedBox(
                                  height: AppleSpacing.titleToSubtitle,
                                ),
                                Text(
                                  account.email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppleTypography.songArtist,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const AppleSheetDivider(indent: 0, endIndent: 0),
                const SizedBox(height: 4),

                // Actions Group: Settings & Log Out
                AppleSheetGroup(
                  children: [
                    AppleSheetActionTile(
                      icon: CupertinoIcons.gear_alt,
                      title: 'Settings',
                      trailing: const Icon(
                        CupertinoIcons.chevron_forward,
                        color: Colors.white38,
                        size: 16,
                      ),
                      onTap: () {
                        Navigator.pop(modalCtx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SettingsScreen(),
                          ),
                        );
                      },
                    ),
                    const AppleSheetDivider(),
                    AppleSheetActionTile(
                      icon: CupertinoIcons.arrow_right_square,
                      title: 'Log Out',
                      onTap: () {
                        Navigator.pop(modalCtx);
                        ref.read(authProvider.notifier).signOut();
                      },
                    ),
                  ],
                ),
              ],
            );
          }

          // Not Signed In: Clean Apple-styled Sign-In promotion + Settings
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 4),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    CupertinoIcons.music_note_list,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Sign In to Wavify',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Connect your YouTube Music account to synchronize your Liked Music, playlists, saved albums, and personalize your Home recommendations.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ApplePressable(
                onTap: () {
                  Navigator.pop(modalCtx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const GoogleSignInScreen(),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(
                        CupertinoIcons.play_circle_fill,
                        color: Colors.black,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Sign In with Google Account',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const AppleSheetDivider(indent: 0, endIndent: 0),
              AppleSheetActionTile(
                icon: CupertinoIcons.gear_alt,
                title: 'Settings',
                trailing: const Icon(
                  CupertinoIcons.chevron_forward,
                  color: Colors.white38,
                  size: 16,
                ),
                onTap: () {
                  Navigator.pop(modalCtx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                },
              ),
            ],
          );
        },
      );
    },
  );
}
