import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../providers/auth_provider.dart';
import '../providers/home_data_provider.dart';
import '../screens/google_signin_screen.dart';
import '../utils/playback_utils.dart';
import 'apple_pressable.dart';

/// Shows the Google / YouTube Music account overview sheet, allowing the user
/// to manage personalized recommendations, switch accounts, or sign out.
void showAccountModalSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1C1C1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (modalCtx) {
      return Consumer(
        builder: (context, ref, child) {
          final account = ref.watch(authProvider);

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              MediaQuery.of(context).viewInsets.bottom + 28,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Modal Grabber
                Center(
                  child: Container(
                    width: 36,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                if (account != null) ...[
                  // Signed In Account Overview
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.appleRed,
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
                      const SizedBox(width: 16),
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
                              ),
                            ),
                            if (account.email.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                account.email,
                                style: const TextStyle(
                                  color: AppColors.appleSecondaryText,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.greenAccent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'YouTube Music Connected',
                                  style: TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Personalized Recommendations Switch
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.appleDarkSurfaceHigh,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.sparkles,
                          color: AppColors.appleRed,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Personalized Feed',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Home feed is tailored to your YouTube Music account',
                                style: TextStyle(
                                  color: AppColors.appleSecondaryText,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        CupertinoSwitch(
                          value: account.isPersonalizedEnabled,
                          activeTrackColor: AppColors.appleRed,
                          onChanged: (val) {
                            ref
                                .read(authProvider.notifier)
                                .togglePersonalizedRecommendations(val);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      CupertinoIcons.arrow_2_circlepath,
                      color: Colors.white,
                    ),
                    title: const Text(
                      'Refresh Recommendations',
                      style: TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      Navigator.pop(modalCtx);
                      ref.read(homeDataProvider.notifier).refresh();
                      showWavifySnackBar(context, 'Refreshing your YouTube Music feed...');
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      CupertinoIcons.arrow_right_arrow_left,
                      color: Colors.white,
                    ),
                    title: const Text(
                      'Switch Google Account',
                      style: TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      Navigator.pop(modalCtx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const GoogleSignInScreen(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      CupertinoIcons.square_arrow_right,
                      color: AppColors.appleRed,
                    ),
                    title: const Text(
                      'Sign Out of Google Account',
                      style: TextStyle(
                        color: AppColors.appleRed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(modalCtx);
                      ref.read(authProvider.notifier).signOut();
                      showWavifySnackBar(context, 'Signed out of YouTube Music account');
                    },
                  ),
                ] else ...[
                  // Not Signed In: Connect Promotion
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.appleRed.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        CupertinoIcons.music_note_list,
                        color: AppColors.appleRed,
                        size: 38,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Sign In with Google Account',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Sign in with your Google account that uses YouTube Music to get recommendations according to your specific account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.appleSecondaryText,
                      fontSize: 13,
                      height: 1.35,
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
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.appleRed,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            CupertinoIcons.play_circle_fill,
                            color: Colors.white,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Sign in with Google (YouTube Music)',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      );
    },
  );
}

