import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../../models/app_user.dart';
import '../../state/auth_controller.dart';

/// Port of src/user/screens/HomeScreen.tsx.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final subscribed = user?.isSubscribed ?? false;

    return Container(
      color: AppPalette.canvas,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(context, user, subscribed),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  _hero(context),
                  const SizedBox(height: 20),
                  _featureGrid(context, subscribed),
                  if (!subscribed) ...[
                    const SizedBox(height: 20),
                    _unlockBanner(context, user),
                  ],
                  const SizedBox(height: 20),
                  _emergencyBanner(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, AppUser? user, bool subscribed) {
    final initial = (user?.name.isNotEmpty ?? false)
        ? user!.name[0].toUpperCase()
        : 'U';
    final firstName = user?.name.split(' ').first ?? 'User';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppPalette.teal,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Hi, $firstName 👋',
                  style: const TextStyle(
                    color: AppPalette.textBody,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Row(
                  children: [
                    const Text(
                      'AfyaSmart',
                      style: TextStyle(
                        color: AppPalette.teal,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subscribed) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppPalette.premiumBg,
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: const Text(
                          'PREMIUM',
                          style: TextStyle(
                            color: AppPalette.premiumFg,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppPalette.hairline),
            ),
            child: const Icon(
              Icons.notifications_none,
              size: 22,
              color: AppPalette.teal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero(BuildContext context) => Container(
    height: 190,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: AppPalette.tealHero,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Stack(
      children: [
        // Oversized decorative glyph bleeding off the right edge.
        Positioned(
          right: -40,
          bottom: -30,
          child: Icon(
            Icons.shield,
            size: 180,
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Your health, our priority',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Get trusted health info and find the best care near you.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(Routes.chat),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppPalette.teal,
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  shape: const StadiumBorder(),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Chat Now',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward, size: 14),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _featureGrid(BuildContext context, bool subscribed) {
    // Symptoms is deliberately NOT premium — the free tier is protected by
    // the 3-checks-a-day server quota instead of the paywall.
    final features = [
      (
        icon: Icons.chat_bubble,
        title: 'Health Assistant',
        subtitle: 'AI Chatbot',
        route: Routes.chat,
        color: AppPalette.purple,
        bg: AppPalette.purpleBg,
        premium: false,
      ),
      (
        icon: Icons.monitor_heart,
        title: 'Symptoms',
        subtitle: 'Checker',
        route: Routes.symptoms,
        color: AppPalette.green,
        bg: AppPalette.greenBg,
        premium: false,
      ),
      (
        icon: Icons.medical_services,
        title: 'Drugs',
        subtitle: 'Database',
        route: Routes.drugs,
        color: AppPalette.orange,
        bg: AppPalette.orangeBg,
        premium: true,
      ),
      (
        icon: Icons.location_on,
        title: 'Nearby Health',
        subtitle: 'Services',
        route: Routes.map,
        color: AppPalette.red,
        bg: AppPalette.redBg,
        premium: true,
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: 1.15,
      children: [
        for (final f in features)
          _featureCard(
            context: context,
            icon: f.icon,
            title: f.title,
            subtitle: f.subtitle,
            color: f.color,
            bg: f.bg,
            // A locked card routes to the paywall rather than the feature.
            // The router would redirect anyway; doing it here means the tap
            // lands somewhere useful instead of bouncing.
            onTap: () => context.go(
              f.premium && !subscribed ? Routes.subscription : f.route,
            ),
            locked: f.premium && !subscribed,
          ),
      ],
    );
  }

  Widget _featureCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color bg,
    required VoidCallback onTap,
    required bool locked,
  }) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppPalette.hairline),
        ),
        child: Stack(
          children: [
            if (locked)
              const Positioned(
                right: 0,
                top: 0,
                child: Icon(
                  Icons.lock,
                  size: 12,
                  color: AppPalette.textMuted,
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, size: 28, color: color),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textStrong,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppPalette.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _unlockBanner(BuildContext context, AppUser? user) {
    final remaining = user?.remainingFreeChats ?? 0;
    final eligible = user?.canUseFreeChats ?? false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Unlock Full Access',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textStrong,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  // Distinguishes "never subscribed, has free chats left"
                  // from "subscription lapsed", which need different copy.
                  eligible
                      ? '$remaining free chat${remaining == 1 ? '' : 's'} left. '
                            'Subscribe for full access.'
                      : 'Your subscription has ended. Renew to restore full access.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppPalette.textMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: () => context.go(Routes.subscription),
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.teal,
              foregroundColor: Colors.white,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: const StadiumBorder(),
            ),
            child: const Text(
              'View Plans',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emergencyBanner() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppPalette.redBg,
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning, size: 18, color: AppPalette.alert),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'For emergencies, go to your nearest hospital immediately.',
            style: TextStyle(
              fontSize: 12,
              color: AppPalette.alert,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}
