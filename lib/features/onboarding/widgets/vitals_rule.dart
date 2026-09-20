import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// A tick-mark rule — the one recurring motif across onboarding, used as a
/// divider here and as the analysis-loading trace elsewhere. Static, not an
/// animated pulse.
class VitalsRule extends StatelessWidget {
  const VitalsRule({super.key});

  static const _heights = <double>[4, 4, 14, 4, 20, 8, 4, 4, 16, 4, 4];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final h in _heights) ...[
            Container(
              width: 2,
              height: h,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(width: 3),
          ],
        ],
      ),
    );
  }
}

/// The shared onboarding header: a back arrow, a title and a step counter,
/// over a hairline rule. Used by health-check and symptom-chat.
class OnboardingHeader extends StatelessWidget {
  const OnboardingHeader({
    required this.title,
    this.trailing,
    this.onBack,
    super.key,
  });

  final String title;
  final String? trailing;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 20, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.rule)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 22, color: AppColors.ink),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.inkFaint,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}
