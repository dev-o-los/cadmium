import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../providers/auth_provider.dart';
import '../screens/google_signin_screen.dart';
import 'apple_glass_bottom_sheet.dart';
import 'apple_pressable.dart';

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
                // Account Overview Card
                AppleSheetGroup(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.white.withValues(alpha: 0.18),
                          backgroundImage: account.avatarUrl != null
                              ? NetworkImage(account.avatarUrl!)
                              : null,
                          child: account.avatarUrl == null
                              ? Text(
                                  account.initials,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                account.displayName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              if (account.email.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  account.email,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.75),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Account Actions Group
                AppleSheetGroup(
                  children: [
                    AppleSheetActionTile(
                      leading: const Icon(CupertinoIcons.arrow_right_square, color: Color(0xFFFF453A), size: 22),
                      title: 'Log Out',
                      isDestructive: true,
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

          // Not Signed In: Clean Apple-styled Sign-In promotion
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
                'Sign In to Melomaniac',
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
                  'Connect your Google / YouTube Music account to synchronize your favorites, library, playlists, and tailor personalized recommendations.',
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
            ],
          );
        },
      );
    },
  );
}
