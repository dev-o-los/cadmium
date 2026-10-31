import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Apple-styled animatable Cupertino Icon that smoothly morphs, cross-fades,
/// and springs whenever its icon or color state changes, or when pressed.
class AnimatedCupertinoIcon extends StatefulWidget {
  final IconData icon;
  final double size;
  final Color color;
  final Duration duration;
  final VoidCallback? onTap;

  const AnimatedCupertinoIcon({
    super.key,
    required this.icon,
    this.size = 24.0,
    required this.color,
    this.duration = const Duration(milliseconds: 240),
    this.onTap,
  });

  @override
  State<AnimatedCupertinoIcon> createState() => _AnimatedCupertinoIconState();
}

class _AnimatedCupertinoIconState extends State<AnimatedCupertinoIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _springController;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.86).chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.86, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 65,
      ),
    ]).animate(_springController);
  }

  @override
  void didUpdateWidget(covariant AnimatedCupertinoIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.icon != widget.icon || oldWidget.color != widget.color) {
      _springController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget iconWidget = ScaleTransition(
      scale: _scaleAnimation,
      child: AnimatedSwitcher(
        duration: widget.duration,
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.82, end: 1.0).animate(animation),
              child: child,
            ),
          );
        },
        child: Icon(
          widget.icon,
          key: ValueKey('${widget.icon.codePoint}_${widget.color.toARGB32()}'),
          size: widget.size,
          color: widget.color,
        ),
      ),
    );

    if (widget.onTap != null) {
      return GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap!();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _isPressed ? 0.88 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: iconWidget,
        ),
      );
    }

    return iconWidget;
  }
}
