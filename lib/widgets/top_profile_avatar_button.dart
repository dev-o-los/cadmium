import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../providers/auth_provider.dart';
import 'account_modal_sheet.dart';
import 'apple_pressable.dart';
import 'wavify_cached_image.dart';

/// Top Right Profile Avatar Button for the navigation bar across screens.
///
/// Features:
/// 1. Tapping opens the authentic Apple-style account modal sheet.
/// 2. If signed in with YouTube Music, renders the user's authentic high-res
///    profile picture with a smooth fallback to initials and an online green dot.
/// 3. If signed out, renders CupertinoIcons.person_crop_circle_fill.
/// 4. Automatically self-heals in the background if the user is authenticated
///    but missing their high-res avatar photo.
class TopProfileAvatarButton extends ConsumerStatefulWidget {
  final double size;

  const TopProfileAvatarButton({
    super.key,
    this.size = 38,
  });

  @override
  ConsumerState<TopProfileAvatarButton> createState() =>
      _TopProfileAvatarButtonState();
}

class _TopProfileAvatarButtonState
    extends ConsumerState<TopProfileAvatarButton> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndHealAvatar();
    });
  }

  void _checkAndHealAvatar() {
    final account = ref.read(authProvider);
    if (account != null &&
        (account.avatarUrl == null ||
            account.avatarUrl!.isEmpty ||
            account.displayName == 'YouTube Music User')) {
      ref.read(authProvider.notifier).refreshProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(authProvider);
    final size = widget.size;

    return ApplePressable(
      onTap: () => showAccountModalSheet(context, ref),
      borderRadius: BorderRadius.circular(size / 2),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: account != null
                    ? Colors.white.withValues(alpha: 0.85)
                    : Colors.white.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: CircleAvatar(
              radius: (size / 2) - 1.5,
              backgroundColor: account != null
                  ? Colors.white.withValues(alpha: 0.20)
                  : AppColors.appleDarkSurfaceHigh,
              child: ClipOval(
                child: (account?.avatarUrl != null &&
                        account!.avatarUrl!.isNotEmpty)
                    ? WavifyCachedImage(
                        imageUrl: account.avatarUrl!,
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                        errorWidget: Center(
                          child: Text(
                            account.initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      )
                    : (account != null
                        ? Center(
                            child: Text(
                              account.initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : const Center(
                            child: Icon(
                              CupertinoIcons.person_crop_circle_fill,
                              color: Colors.white,
                              size: 24,
                            ),
                          )),
              ),
            ),
          ),
          if (account != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.greenAccent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.black,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
