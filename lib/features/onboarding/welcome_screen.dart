import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand.dart';
import '../../core/router.dart';
import '../../core/theme.dart';
import '../../state/diagnosis_controller.dart';
import 'widgets/vitals_rule.dart';

/// Port of src/onboarding/screens/WelcomeScreen.tsx.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

const _features = [
  (
    icon: Icons.monitor_heart_outlined,
    title: 'Symptom checker',
    desc: 'Answer a few questions about how you feel',
  ),
  (
    icon: Icons.chat_bubble_outline,
    title: 'Health chat',
    desc: 'Talk through a concern any time of day',
  ),
  (
    icon: Icons.medical_services_outlined,
    title: 'Drug information',
    desc: 'Check dosages, side effects and details',
  ),
  (
    icon: Icons.location_on_outlined,
    title: 'Local services',
    desc: 'Find clinics, pharmacies and doctors near you',
  ),
];

class _WelcomeScreenState extends ConsumerState<WelcomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  late final AnimationController _list = AnimationController(
    vsync: this,
    // 4 staggered items at 60ms apart, each 300ms long.
    duration: const Duration(milliseconds: 480),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_intro.isAnimating || _intro.isCompleted) return;
    // With system animations off, show everything in place at once.
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
      _list.value = 1;
      return;
    }
    _intro.forward().then((_) {
      if (mounted) _list.forward();
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _intro, curve: Curves.easeOut);
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(fade);

    // Content reads top-down; the actions sit at the bottom, in thumb reach,
    // and only scroll with the rest on short screens or large text.
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.lg,
                  Insets.xl,
                  Insets.lg,
                  Insets.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FadeTransition(
                      opacity: fade,
                      child: SlideTransition(position: slide, child: _hero()),
                    ),
                    const SizedBox(height: Insets.xl),
                    _featureList(),
                    const SizedBox(height: Insets.lg),
                    FadeTransition(opacity: fade, child: _trust()),
                    const Spacer(),
                    const SizedBox(height: Insets.lg),
                    FadeTransition(opacity: fade, child: _cta(context)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The promise is the headline; the wordmark is a label above it.
  Widget _hero() => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wordmark(),
      SizedBox(height: Insets.md),
      VitalsRule(),
      SizedBox(height: Insets.md),
      Text(
        'Find out what your symptoms mean in 60 seconds',
        style: TextStyle(
          color: AppColors.ink,
          fontSize: 28,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
      ),
      SizedBox(height: Insets.sm),
      Text(
        'Free health check-in, then guidance on what to do next.',
        style: TextStyle(color: AppColors.inkMuted, fontSize: 16, height: 1.5),
      ),
    ],
  );

  Widget _featureList() => Container(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.rule)),
    ),
    child: Column(
      children: [
        for (var i = 0; i < _features.length; i++)
          _staggered(i, _featureRow(_features[i])),
      ],
    ),
  );

  /// Reproduces Animated.stagger: each row fades and rises 60ms after the
  /// one before it.
  Widget _staggered(int index, Widget child) {
    final start = (index * 60) / 480;
    final anim = CurvedAnimation(
      parent: _list,
      curve: Interval(start, (start + 300 / 480).clamp(0.0, 1.0)),
    );

    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(anim),
        child: child,
      ),
    );
  }

  Widget _featureRow(({IconData icon, String title, String desc}) f) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.rule)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(f.icon, size: 22, color: AppColors.brand),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    f.title,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    f.desc,
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  /// No directory counts or hospital names here: small numbers undercut
  /// trust, and naming real institutions implies a partnership we don't have.
  Widget _trust() => const Row(
    children: [
      Icon(Icons.verified_user_outlined, size: 16, color: AppColors.inkMuted),
      SizedBox(width: 6),
      Text(
        'Private and secure',
        style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
      ),
    ],
  );

  // Sizes and shape come from the theme's button styles, so this matches
  // every other primary action in the app.
  Widget _cta(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        onPressed: () async {
          await ref.read(diagnosisControllerProvider.notifier).clearAll();
          if (!context.mounted) return;
          context.go(Routes.healthCheck);
        },
        iconAlignment: IconAlignment.end,
        icon: const Icon(Icons.arrow_forward, size: 20),
        label: const Text('Start your check-in'),
      ),
      const SizedBox(height: Insets.sm),
      TextButton(
        onPressed: () => context.go(Routes.login),
        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: const Text.rich(
          TextSpan(
            text: 'Already have an account? ',
            style: TextStyle(color: AppColors.inkMuted),
            children: [
              TextSpan(
                text: 'Sign in',
                style: TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          style: TextStyle(fontSize: 15),
        ),
      ),
      const SizedBox(height: Insets.xs),
      const Text(
        'Not a replacement for professional medical advice.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
      ),
    ],
  );
}
