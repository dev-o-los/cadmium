import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// An Apple-styled interactive pressable wrapper that provides tactile spring feedback
/// (scale-down and gentle opacity dim) without any ugly Material ink ripples or splash effects.
class ApplePressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final double pressedOpacity;
  final BorderRadius? borderRadius;
  final Color? pressedColor;
  final Duration animationDuration;
  final bool enableHaptic;

  const ApplePressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.978,
    this.pressedOpacity = 0.82,
    this.borderRadius,
    this.pressedColor,
    this.animationDuration = const Duration(milliseconds: 140),
    this.enableHaptic = true,
  });

  @override
  State<ApplePressable> createState() => _ApplePressableState();
}

class _ApplePressableState extends State<ApplePressable> {
  bool _isPressed = false;

  void _handleTapDown(TapDownDetails details) {
    if (widget.onTap != null || widget.onLongPress != null) {
      setState(() => _isPressed = true);
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (_isPressed) {
      setState(() => _isPressed = false);
      if (widget.enableHaptic) {
        HapticFeedback.lightImpact();
      }
      widget.onTap?.call();
    }
  }

  void _handleTapCancel() {
    if (_isPressed) {
      setState(() => _isPressed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = widget.borderRadius ?? BorderRadius.circular(10);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onLongPress: widget.onLongPress != null
          ? () {
              if (widget.enableHaptic) {
                HapticFeedback.mediumImpact();
              }
              widget.onLongPress?.call();
            }
          : null,
      child: AnimatedScale(
        scale: _isPressed ? widget.pressedScale : 1.0,
        duration: widget.animationDuration,
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _isPressed ? widget.pressedOpacity : 1.0,
          duration: widget.animationDuration,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: widget.animationDuration,
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: effectiveRadius,
              color: _isPressed
                  ? (widget.pressedColor ?? const Color(0x14FFFFFF))
                  : const Color(0x00000000),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

