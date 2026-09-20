import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../../state/auth_controller.dart';
import '../../state/diagnosis_controller.dart';

/// Port of src/onboarding/screens/LockedResultsScreen.tsx — the paywall at
/// the end of the onboarding funnel. The analysis is complete and stored;
/// this shows its shape without its content until the user subscribes.
class LockedResultsScreen extends ConsumerStatefulWidget {
  const LockedResultsScreen({super.key});

  @override
  ConsumerState<LockedResultsScreen> createState() =>
      _LockedResultsScreenState();
}

const _unlockFeatures = [
  (
    icon: Icons.format_list_bulleted,
    text: 'Possible conditions with probabilities',
  ),
  (icon: Icons.medical_services_outlined, text: 'Recommended medication & dosage'),
  (icon: Icons.error_outline, text: 'Urgency level (Low / Medium / High)'),
  (icon: Icons.location_on_outlined, text: 'Nearby hospitals, doctors & pharmacies'),
  (icon: Icons.chat_bubble_outline, text: 'Unlimited AI follow-up chat'),
];

const _plans = [
  (id: 'daily', label: 'Daily', price: 'Ksh 20', badge: 'Most Popular'),
  (id: 'weekly', label: 'Weekly', price: 'Ksh 100', badge: 'Save 30%'),
  (id: 'monthly', label: 'Monthly', price: 'Ksh 200', badge: 'Best Value'),
];

/// Severity drives both the icon and the colour of each locked row, so the
/// user can see the shape of their result without its content.
IconData _severityIcon(String level) => switch (level) {
  'High' => Icons.thermostat,
  'Medium' => Icons.monitor_heart_outlined,
  _ => Icons.healing_outlined,
};

Color _severityColor(String level) => switch (level) {
  'High' => AppColors.danger,
  'Medium' => AppColors.warning,
  _ => AppColors.success,
};

class _LockedResultsScreenState extends ConsumerState<LockedResultsScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..forward();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();

    // This is the true end of the onboarding funnel (welcome -> health-check
    // -> symptom-chat -> analysis-loading -> here) regardless of whether the
    // user subscribes next, so this is where onboarding is marked complete.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(authControllerProvider.notifier).completeOnboarding();
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _subscribe(String planId) {
    final signedIn = ref.read(authControllerProvider).isSignedIn;

    // A signed-in user goes straight to checkout; a guest has to create an
    // account first, and the chosen plan rides along so they land back on its
    // checkout rather than the home tab.
    context.push(
      signedIn
          ? '${Routes.subscription}?plan=$planId'
          : '${Routes.register}?plan=$planId',
    );
  }

  @override
  Widget build(BuildContext context) {
    final diagnosis = ref.watch(
      diagnosisControllerProvider.select((s) => s.pendingDiagnosis),
    );
    final conditions = diagnosis?.conditions ?? const [];
    final fade = CurvedAnimation(parent: _intro, curve: Curves.easeOut);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: FadeTransition(
          opacity: fade,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            children: [
              _banner(conditions.length),
              const SizedBox(height: 32),
              _sectionTitle('Your Results'),
              const SizedBox(height: 12),
              // Falls back to three generic rows when the store is empty (a
              // cold start that lost the diagnosis) so the paywall still
              // reads as a real result rather than a blank panel.
              if (conditions.isEmpty)
                for (final level in ['Medium', 'High', 'Low']) _lockedRow(level)
              else
                for (final c in conditions) _lockedRow(c.level),
              const SizedBox(height: 32),
              _sectionTitle('Unlock to see'),
              const SizedBox(height: 12),
              for (final f in _unlockFeatures) _featureRow(f.icon, f.text),
              const SizedBox(height: 32),
              _sectionTitle('Choose a plan'),
              const SizedBox(height: 12),
              for (final plan in _plans) _planRow(plan),
              const SizedBox(height: 20),
              const Text(
                'Cancel any time. Payment is by M-Pesa.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.inkFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _banner(int conditionCount) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ScaleTransition(
        scale: Tween<double>(begin: 1, end: 1.1).animate(_pulse),
        alignment: Alignment.centerLeft,
        child: Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: AppColors.ink,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.lock_outline,
            size: 28,
            color: AppColors.paper,
          ),
        ),
      ),
      const SizedBox(height: 18),
      const Text(
        'Analysis Complete',
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      const SizedBox(height: 8),
      Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'We found '),
            TextSpan(
              text: '${conditionCount == 0 ? 3 : conditionCount} '
                  'possible conditions',
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            const TextSpan(text: ' related to your symptoms'),
          ],
        ),
        style: const TextStyle(
          fontSize: 15,
          color: AppColors.inkMuted,
          height: 1.5,
        ),
      ),
    ],
  );

  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.inkFaint,
      letterSpacing: 0.8,
    ),
  );

  /// A result row with its text replaced by blur bars — the shape of the
  /// finding is visible, the finding itself is not.
  Widget _lockedRow(String level) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.rule)),
    ),
    child: IntrinsicHeight(
      child: Row(
        children: [
          Container(width: 2, color: _severityColor(level)),
          const SizedBox(width: 12),
          Icon(_severityIcon(level), size: 18, color: _severityColor(level)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _blurBar(widthFactor: 1),
                const SizedBox(height: 6),
                _blurBar(widthFactor: 0.6),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Row(
            children: [
              const Icon(
                Icons.lock_outline,
                size: 11,
                color: AppColors.inkFaint,
              ),
              const SizedBox(width: 4),
              Text(
                'Locked',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.inkFaint,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _blurBar({required double widthFactor}) => FractionallySizedBox(
    alignment: Alignment.centerLeft,
    widthFactor: widthFactor,
    child: Container(
      height: 8,
      decoration: BoxDecoration(
        color: AppColors.rule,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
    ),
  );

  Widget _featureRow(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Icon(icon, size: 17, color: AppColors.ruleStrong),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
          ),
        ),
      ],
    ),
  );

  Widget _planRow(({String id, String label, String price, String badge}) plan) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: OutlinedButton(
          onPressed: () => _subscribe(plan.id),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            side: const BorderSide(color: AppColors.rule),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            alignment: Alignment.centerLeft,
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    plan.badge,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.inkFaint,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                plan.price,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward,
                size: 16,
                color: AppColors.inkFaint,
              ),
            ],
          ),
        ),
      );
}
