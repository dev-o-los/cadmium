import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Refined Apple-styled smooth player loader widget.
/// Features a subtle glowing luminous aura behind a fluid Cupertino activity indicator,
/// creating a seamless loading state inside play/pause buttons without harsh flicker.
class SmoothPlayerLoader extends StatelessWidget {
  final double radius;
  final Color color;

  const SmoothPlayerLoader({
    super.key,
    this.radius = 12,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: radius * 2.4,
        height: radius * 2.4,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Soft luminous pulsing backing
            Container(
              width: radius * 2.1,
              height: radius * 2.1,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.18),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            // High-fidelity iOS activity spinner
            CupertinoActivityIndicator(
              radius: radius,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}

