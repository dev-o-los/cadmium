import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'apple_pressable.dart';

/// Shows an authentic Apple-style Liquid Glass bottom sheet with translucent
/// Gaussian frosted glass, specular highlights, and high-contrast white elements.
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
    barrierColor: Colors.black.withValues(alpha: 0.65),
    builder: (modalContext) {
      return AppleGlassBottomSheetContainer(
        child: builder(modalContext),
      );
    },
  );
}

/// Liquid Glass container wrapper with Gaussian blur, ultra-fine white specular outline,
/// top grab handle, and balanced, reduced side padding for Apple-style sheets.
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
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xEE161619),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 28,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(14, 0, 14, bottomPadding + 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showGrabber) ...[
                      const SizedBox(height: 10),
                      Center(
                        child: Container(
                          width: 36,
                          height: 4.5,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(2.25),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ] else
                      const SizedBox(height: 16),
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Apple-style grouped section card for actions inside bottom sheets.
class AppleSheetGroup extends StatelessWidget {
  final List<Widget>? children;
  final Widget? child;
  final EdgeInsetsGeometry? padding;

  const AppleSheetGroup({
    super.key,
    this.children,
    this.child,
    this.padding,
  }) : assert(children != null || child != null, 'Either children or child must be provided');

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 0.65,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: child ??
              Column(
                mainAxisSize: MainAxisSize.min,
                children: children!,
              ),
        ),
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
  }) : assert(leading != null || icon != null, 'Either leading or icon must be provided');

  @override
  Widget build(BuildContext context) {
    final effectiveTitleColor = isDestructive ? const Color(0xFFFF453A) : titleColor;
    final leadingWidget = leading ??
        Icon(
          icon,
          color: isDestructive ? const Color(0xFFFF453A) : Colors.white,
          size: 22,
        );

    return ApplePressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
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
                    style: TextStyle(
                      color: effectiveTitleColor,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// Thin hairline divider for items inside an [AppleSheetGroup].
class AppleSheetDivider extends StatelessWidget {
  final double indent;

  const AppleSheetDivider({super.key, this.indent = 56});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 0.7,
      thickness: 0.7,
      color: Colors.white.withValues(alpha: 0.10),
      indent: indent,
      endIndent: 0,
    );
  }
}
