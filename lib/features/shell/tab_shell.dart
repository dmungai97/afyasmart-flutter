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
        icon: Icons.chat_bubble_outline,
        activeIcon: Icons.chat_bubble,
        badge: true,
      ),
      const _TabItem(
        route: Routes.profile,
        label: 'Profile',
        icon: Icons.person_outline,
        activeIcon: Icons.person,
      ),
    ];

    final location = GoRouterState.of(context).matchedLocation;

    return Scaffold(
      body: child,
      // The bar hides itself with the keyboard, matching tabBarHideOnKeyboard.
      bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
          ? null
          : _Bar(items: items, location: location),
    );
  }
}

class _TabItem {
  const _TabItem({
    required this.route,
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.badge = false,
  });

  final String route;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool badge;
}

/// The selected tab is a filled teal pill rather than a tint change, so the
/// bar is rebuilt by hand instead of using BottomNavigationBar.
class _Bar extends StatelessWidget {
  const _Bar({required this.items, required this.location});

  static const _teal = Color(0xFF005454);
  static const _inactive = Color(0xFF718096);

  final List<_TabItem> items;
  final String location;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Container(
      padding: EdgeInsets.only(top: 8, bottom: bottomInset > 0 ? bottomInset : 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEDF0F2))),
        boxShadow: [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 10,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final item in items) _tab(context, item),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, _TabItem item) {
    final focused = location == item.route;

    return InkWell(
      onTap: focused ? null : () => context.go(item.route),
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minWidth: 76),
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: focused ? _teal : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  focused ? item.activeIcon : item.icon,
                  size: 20,
                  color: focused ? Colors.white : _inactive,
                ),
                // The unread dot only shows when the tab is not selected —
                // once you are on Chat there is nothing to notify about.
                if (item.badge && !focused)
                  Positioned(
                    right: -4,
                    top: -2,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFFBA1A1A),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: focused ? Colors.white : _inactive,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
