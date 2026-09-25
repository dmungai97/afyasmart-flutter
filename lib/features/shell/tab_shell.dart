import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../state/auth_controller.dart';

/// Port of app/(tabs)/_layout.tsx.
///
/// Only five routes appear in the bar; drugs, pharmacy, subscription,
/// symptoms and diagnosis-results are reachable routes with no tab entry
/// (`href: null` in the RN layout), so they live outside this shell and push
/// full-screen.
///
/// Doctors and Map are hidden from the bar entirely for non-subscribers
/// rather than shown-and-blocked. The router's premium redirect is the actual
/// gate; this just avoids dangling a tab that would bounce them to the
/// paywall.
class TabShell extends ConsumerWidget {
  const TabShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final hasFullAccess = user?.isSubscribed ?? false;

    final items = <_TabItem>[
      const _TabItem(
        route: Routes.home,
        label: 'Home',
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
      ),
      if (hasFullAccess) ...[
        const _TabItem(
          route: Routes.doctors,
          label: 'Doctors',
          icon: Icons.people_outline,
          activeIcon: Icons.people,
        ),
        const _TabItem(
          route: Routes.map,
          label: 'Map',
          icon: Icons.location_on_outlined,
          activeIcon: Icons.location_on,
        ),
      ],
      const _TabItem(
        route: Routes.chat,
        label: 'Chat',
        icon: Icons.chat_bubble_outline_rounded,
        activeIcon: Icons.chat_bubble_rounded,
      ),
      const _TabItem(
        route: Routes.profile,
        label: 'Profile',
        icon: Icons.person_outline,
        activeIcon: Icons.person,
      ),
    ];

    final location = GoRouterState.of(context).matchedLocation;

    return PopScope(
      canPop: location == Routes.home,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (location != Routes.home) {
          context.go(Routes.home);
        }
      },
      child: Scaffold(
        body: child,
        // The bar hides itself with the keyboard, matching tabBarHideOnKeyboard.
        bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
            ? null
            : _Bar(items: items, location: location),
      ),
    );
  }
}

class _TabItem {
  const _TabItem({
    required this.route,
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String route;
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// Every tab takes an equal share of the width, so the bar fits whether it
/// shows three tabs (free) or five (subscribed). The selected tab gets a
/// light pill behind its icon rather than a filled block.
class _Bar extends StatelessWidget {
  const _Bar({required this.items, required this.location});

  static const _active = Color(0xFF005454);
  static const _inactive = Color(0xFF718096);
  static const _indicator = Color(0xFFE0F2F1);

  final List<_TabItem> items;
  final String location;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Container(
      padding: EdgeInsets.only(top: 6, bottom: bottomInset > 0 ? bottomInset : 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEDF0F2))),
      ),
      child: Row(
        children: [
          for (final item in items) Expanded(child: _tab(context, item)),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, _TabItem item) {
    final focused = location == item.route;
    final color = focused ? _active : _inactive;

    return InkWell(
      onTap: focused ? null : () => context.go(item.route),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 52,
              height: 30,
              decoration: BoxDecoration(
                color: focused ? _indicator : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                focused ? item.activeIcon : item.icon,
                size: 22,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: focused ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
