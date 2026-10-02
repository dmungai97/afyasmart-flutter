import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../../state/affiliate_controller.dart';
import 'affiliate_enroll_screen.dart';

/// Port of app/affiliate/_layout.tsx.
///
/// The gate matters: an unenrolled user gets the enrollment screen instead of
/// the tabs, because every tab below reads balances that do not exist until
/// they have a referral code.
class AffiliateShell extends ConsumerWidget {
  const AffiliateShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(affiliateControllerProvider);

    return summary.when(
      loading: () => const ColoredBox(
        color: Color(0xFFF5F7FA),
        child: Center(child: CircularProgressIndicator(color: AppColors.brand)),
      ),
      error: (error, _) => ColoredBox(
        color: const Color(0xFFF5F7FA),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 44,
                  color: AppPalette.red,
                ),
                const SizedBox(height: 14),
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppPalette.textMuted,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () =>
                      ref.read(affiliateControllerProvider.notifier).reload(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (data) {
        if (!data.enrolled) return const AffiliateEnrollScreen();
        final location = GoRouterState.of(context).matchedLocation;

        final scaffold = Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          body: child,
          bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
              ? null
              : _AffiliateBar(
                  location: location,
                ),
        );

        if (kIsWeb) return scaffold;

        return PopScope(
          canPop: location == Routes.affiliate,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (location != Routes.affiliate) {
              context.go(Routes.affiliate);
            }
          },
          child: scaffold,
        );
      },
    );
  }
}

class _AffiliateBar extends StatelessWidget {
  const _AffiliateBar({required this.location});

  final String location;

  static const _items = [
    (route: Routes.affiliate, icon: Icons.dashboard_outlined, label: 'Home'),
    (
      route: Routes.affiliateReferrals,
      icon: Icons.people_outline,
      label: 'Referrals',
    ),
    (
      route: Routes.affiliateEarnings,
      icon: Icons.trending_up,
      label: 'Earnings',
    ),
    (
      route: Routes.affiliateWithdraw,
      icon: Icons.account_balance_wallet_outlined,
      label: 'Withdraw',
    ),
    (
      route: Routes.affiliateProfile,
      icon: Icons.person_outline,
      label: 'Profile',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Container(
      padding: EdgeInsets.only(top: 8, bottom: bottomInset > 0 ? bottomInset : 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppPalette.hairline)),
        boxShadow: [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 10,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final item in _items)
            Expanded(child: _tab(context, item.route, item.icon, item.label)),
        ],
      ),
    );
  }

  Widget _tab(
    BuildContext context,
    String route,
    IconData icon,
    String label,
  ) {
    final focused = location == route;

    return InkWell(
      onTap: focused ? null : () => context.go(route),
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: focused ? AppColors.brand : const Color(0xFF9AA0A6),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: focused ? FontWeight.w700 : FontWeight.w500,
                    color: focused ? AppColors.brand : const Color(0xFF9AA0A6),
                  ),
                ),
                const SizedBox(height: 8), // Room for the indicator
              ],
            ),
          ),
          if (focused)
            Positioned(
              bottom: 0,
              child: Container(
                width: 32,
                height: 3,
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
