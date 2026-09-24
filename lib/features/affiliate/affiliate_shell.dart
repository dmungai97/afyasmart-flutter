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

        return PopScope(
          canPop: location == Routes.affiliate,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (location != Routes.affiliate) {
              context.go(Routes.affiliate);
            }
          },
          child: Scaffold(
            backgroundColor: const Color(0xFFF5F7FA),
            body: child,
            bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
                ? null
                : _AffiliateBar(
                    location: location,
                  ),
          ),
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

    // A floating, rounded bar inset from the edges, matching the RN layout's
    // marginHorizontal + borderRadius rather than a flush Material bar.
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottomInset > 0 ? bottomInset : 10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppPalette.hairline),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final item in _items)
              _tab(context, item.route, item.icon, item.label),
          ],
        ),
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
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: focused
                    ? AppColors.brand.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                size: 21,
                color: focused ? AppColors.brand : const Color(0xFF9AA0A6),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: focused ? AppColors.brand : const Color(0xFF9AA0A6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
