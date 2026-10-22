import 'package:flutter/material.dart';

import 'theme.dart';

/// The AfyaSmart wordmark, "Smart" in the darkened accent. Shared by splash,
/// welcome and the sign-in screens so the three cannot drift apart.
class Wordmark extends StatelessWidget {
  const Wordmark({this.fontSize = 18, super.key});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      const TextSpan(
        children: [
          TextSpan(text: 'Afya'),
          TextSpan(
            text: 'Smart',
            style: TextStyle(color: AppColors.accentInk),
          ),
        ],
      ),
      style: TextStyle(
        color: AppColors.ink,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }
}
