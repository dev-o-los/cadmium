import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/apple_typography.dart';
import 'apple_pressable.dart';

/// Shows an authentic bottom sheet with a deep black surface,
/// subtle highlight border, and high-contrast white elements blending with the app theme.
Future<T?> showAppleGlassBottomSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext modalContext) builder,
  bool isScrollControlled = true,
  bool enableDrag = true,
  bool isDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    enableDrag: enableDrag,
    isDismissible: isDismissible,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.70),
    builder: (modalContext) {
      return AppleGlassBottomSheetContainer(child: builder(modalContext));
    },
  );
}

/// Bottom sheet container with deep black theme surface, subtle top highlight border,
/// grab handle, and balanced padding blending with the app design theme.
class AppleGlassBottomSheetContainer extends StatelessWidget {
  final Widget child;
  final bool showGrabber;

  const AppleGlassBottomSheetContainer({
    super.key,
    required this.child,
    this.showGrabber = true,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = math.max(MediaQuery.paddingOf(context).bottom, 16.0);
    final viewInsetsBottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsetsBottom),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF16161A),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1F1F24), // Subtle sleek top highlight
              Color(0xFF16161A), // Core black surface blending with app theme
              Color(0xFF121215), // Deep black base
            ],
            stops: [0.0, 0.25, 1.0],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.75),
              blurRadius: 40,
              spreadRadius: 2,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding + 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showGrabber) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        width: 38,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(2.25),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ] else
                    const SizedBox(height: 18),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Layout group for bottom sheet items directly on the sheet's liquid glossy panel.
/// Items are placed directly on the back panel without separate nested containers.
class AppleSheetGroup extends StatelessWidget {
  final List<Widget>? children;
  final Widget? child;
  final EdgeInsetsGeometry? padding;

  const AppleSheetGroup({super.key, this.children, this.child, this.padding})
    : assert(
        children != null || child != null,
        'Either children or child must be provided',
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child:
          child ??
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children!,
          ),
    );
  }
}

/// High-contrast Apple-style action row inside a bottom sheet.
class AppleSheetActionTile extends StatelessWidget {
  final Widget? leading;
  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;
  final Color titleColor;
  final bool isDestructive;

  const AppleSheetActionTile({
    super.key,
    this.leading,
    this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
    this.titleColor = Colors.white,
    this.isDestructive = false,
  }) : assert(
         leading != null || icon != null,
         'Either leading or icon must be provided',
       );

  @override
  Widget build(BuildContext context) {
    // Uniform, pure white text and icons across ALL options without exception
    final leadingWidget = leading ?? Icon(icon, color: Colors.white, size: 22);

    return ApplePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: Center(child: leadingWidget),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppleTypography.sheetAction,
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: AppleSpacing.titleToSubtitle),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppleTypography.sheetSubtitle,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

/// Thin hairline divider for items inside bottom sheets.
class AppleSheetDivider extends StatelessWidget {
  final double indent;
  final double endIndent;

  const AppleSheetDivider({super.key, this.indent = 52, this.endIndent = 8});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1.0,
      thickness: 0.7,
      color: Colors.white.withValues(alpha: 0.12),
      indent: indent,
      endIndent: endIndent,
    );
  }
}
