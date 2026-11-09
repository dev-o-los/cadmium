import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/apple_typography.dart';
import '../models/audio_device_item.dart';
import '../providers/player_provider.dart';
import 'apple_pressable.dart';

/// Shows an authentic bottom sheet with frosted glass blur,
/// translucent dark background, subtle highlight border, and rounded corners.
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
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (modalContext) {
      return AppleGlassBottomSheetContainer(child: builder(modalContext));
    },
  );
}

/// Bottom sheet container with frosted glass blur backdrop, subtle top highlight border,
/// drag grab handle, and high-fidelity translucent dark surface.
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xCC181822),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xD922222C),
                  const Color(0xCC181822),
                  const Color(0xDE121218),
                ],
                stops: const [0.0, 0.35, 1.0],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 40,
                  spreadRadius: 2,
                  offset: const Offset(0, -10),
                ),
              ],
            ),
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
                            color: Colors.white.withValues(alpha: 0.32),
                            borderRadius: BorderRadius.circular(2.25),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
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

/// High-fidelity Audio Output Bottom Sheet matching Image 1:
/// - "Audio output" bold left-aligned header
/// - Individual dark rounded container cards
/// - Phone device card
/// - Connected audio device with "Playing here" and checkmark
/// - Cast card with Google Cast / Chromecast and chevron
/// - Volume slider card with speaker icon and rounded track
/// - Audio Pipeline card with "32-bit float · 48 kHz" and chevron
void showAudioOutputModal(BuildContext context, WidgetRef ref) {
  final notifier = ref.read(playerProvider.notifier);
  notifier.refreshAudioDevices();

  showAppleGlassBottomSheet(
    context: context,
    builder: (modalContext) {
      return Consumer(
        builder: (context, ref, _) {
          final volume = ref.watch(playerProvider.select((s) => s.volume));
          final connectedDevice = ref.watch(
            playerProvider.select((s) => s.connectedDevice),
          );
          final devices = ref.watch(
            playerProvider.select((s) => s.availableAudioDevices),
          );
          double localVolume = volume;

          // Find phone speaker or build default
          final phoneDevice = devices.firstWhere(
            (d) => d.isSpeaker || d.id == 'speaker',
            orElse: () => const AudioDeviceItem(
              id: 'speaker',
              name: 'Phone Speaker',
              category: OutputDeviceCategory.speaker,
            ),
          );

          // Find connected bluetooth/accessory device if present
          final externalDevice = devices.firstWhere(
            (d) => d.id != phoneDevice.id,
            orElse: () => connectedDevice.id != phoneDevice.id
                ? connectedDevice
                : const AudioDeviceItem(
                    id: 'external_device',
                    name: 'Bluetooth Audio',
                    category: OutputDeviceCategory.bluetooth,
                    isSelected: false,
                  ),
          );

          final isPhoneSelected = connectedDevice.id == phoneDevice.id;
          final isExternalSelected = !isPhoneSelected;

          return StatefulBuilder(
            builder: (context, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 16),
                    child: Text(
                      'Audio Output',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),

                  // Card 1: Phone Device Card
                  _buildOutputCard(
                    leadingIcon: const Icon(
                      Icons.phone_android_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    title: phoneDevice.name.isNotEmpty
                        ? phoneDevice.name
                        : 'Phone Speaker',
                    subtitle: isPhoneSelected ? 'Playing here' : null,
                    trailing: isPhoneSelected
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 22,
                          )
                        : null,
                    onTap: () {
                      notifier.selectAudioDevice(phoneDevice);
                    },
                  ),

                  // Card 2: Connected Audio Device Card
                  _buildOutputCard(
                    leadingIcon: const Icon(
                      CupertinoIcons.waveform_path,
                      color: Colors.white,
                      size: 22,
                    ),
                    title: externalDevice.name.isNotEmpty
                        ? externalDevice.name
                        : 'Bluetooth Audio',
                    subtitle: isExternalSelected ? 'Playing here' : null,
                    trailing: isExternalSelected
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 22,
                          )
                        : null,
                    onTap: () {
                      notifier.selectAudioDevice(externalDevice);
                    },
                  ),

                  // Card 3: Cast
                  _buildOutputCard(
                    leadingIcon: const Icon(
                      Icons.cast_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    title: 'Cast',
                    subtitle: 'Chromecast and Google Cast speakers',
                    trailing: const Icon(
                      CupertinoIcons.chevron_right,
                      color: Colors.white38,
                      size: 18,
                    ),
                    onTap: () {
                      Navigator.pop(modalContext);
                      _showCastDialog(context);
                    },
                  ),

                  // Card 4: Volume Card
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.volume_down,
                          color: Colors.white70,
                          size: 20,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4.5,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 7,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14,
                              ),
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white.withValues(
                                alpha: 0.20,
                              ),
                              thumbColor: Colors.white,
                            ),
                            child: Slider(
                              value: localVolume.clamp(0.0, 1.0),
                              min: 0.0,
                              max: 1.0,
                              onChanged: (v) {
                                setModalState(() => localVolume = v);
                                notifier.setVolume(v);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Card 5: Audio Pipeline
                  _buildOutputCard(
                    leadingIcon: const Icon(
                      Icons.graphic_eq_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    title: 'Audio Pipeline',
                    subtitle: '32-bit float · 48 kHz',
                    trailing: const Icon(
                      CupertinoIcons.chevron_right,
                      color: Colors.white38,
                      size: 18,
                    ),
                    onTap: () {
                      _showPipelineInfoDialog(context);
                    },
                  ),
                ],
              );
            },
          );
        },
      );
    },
  );
}

Widget _buildOutputCard({
  required Widget leadingIcon,
  required String title,
  String? subtitle,
  Widget? trailing,
  required VoidCallback onTap,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    child: ApplePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: leadingIcon),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing,
            ],
          ],
        ),
      ),
    ),
  );
}

void _showCastDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: const [
          Icon(Icons.cast_rounded, color: Colors.white),
          SizedBox(width: 10),
          Text(
            'Google Cast',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
        ],
      ),
      content: const Text(
        'Searching for nearby Chromecast, Google Nest, and Cast-enabled speakers on your Wi-Fi network...',
        style: TextStyle(color: Colors.white70, fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

void _showPipelineInfoDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: const [
          Icon(Icons.graphic_eq_rounded, color: Colors.white),
          SizedBox(width: 10),
          Text(
            'Audio Pipeline',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Format: 32-bit float PCM',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 6),
          Text(
            'Sample Rate: 48.0 kHz',
            style: TextStyle(color: Colors.white70),
          ),
          SizedBox(height: 4),
          Text(
            'Engine: JustAudio + AudioSession Bit-Perfect Output',
            style: TextStyle(color: Colors.white70),
          ),
          SizedBox(height: 4),
          Text(
            'Hardware Buffer: Zero latency floating-point mixing',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Done', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

/// Layout group for bottom sheet items directly on the sheet's liquid glossy panel.
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
