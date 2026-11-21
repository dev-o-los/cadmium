import 'package:flutter/material.dart';

/// Dedicated Apple Music-style Explicit Content badge.
/// Features a crisp white background with a bold black 'E' label,
/// positioned in front of the song name with proper spacing all around.
class ExplicitBadge extends StatelessWidget {
  /// Width and height of the badge. Defaults to 14.0.
  final double size;

  /// Outer spacing around the badge. Defaults to 6px on the right.
  final EdgeInsetsGeometry margin;

  const ExplicitBadge({
    super.key,
    this.size = 14.0,
    this.margin = const EdgeInsets.only(right: 6.0),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * 0.22),
        ),
        child: Text(
          'E',
          style: TextStyle(
            color: Colors.black,
            fontSize: size * 0.68,
            fontWeight: FontWeight.w800,
            fontFamily: '.SF Pro Text',
            height: 1.0,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
