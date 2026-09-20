import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../../state/auth_controller.dart';

/// Port of admin/components/Sidebar.tsx + app/admin/_layout.tsx.
///
/// The RN console used a slide-out sidebar on mobile and a persistent rail on
/// wide screens. A Drawer gives the same behaviour, and the rail appears
/// automatically above 900px.
///
/// The admin palette is the restrained "clinical stationery" system, not the
/// warmer patient-app one — the console is meant to read as the same product
/// as onboarding rather than a bolted-on dashboard.
class AdminShell extends ConsumerWidget {
  const AdminShell({required this.child, super.key});

  final Widget child;

  static const _items = [
    (route: Routes.admin, icon: Icons.dashboard_outlined, label: 'Dashboard'),
    (route: Routes.adminUsers, icon: Icons.people_outline, label: 'Users'),
    (
      route: Routes.adminFacilities,
      icon: Icons.local_hospital_outlined,
      label: 'Facilities',
    ),
    (
      route: Routes.adminTransactions,
      icon: Icons.receipt_long_outlined,
      label: 'Transactions',
    ),
    (
      route: Routes.adminPayouts,
      icon: Icons.payments_outlined,
      label: 'Payouts',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final title = _items
        .where((i) => i.route == location)
        .map((i) => i.label)
        .firstOrNull;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: Text(title ?? 'Admin'),
        actions: [
          IconButton(
            tooltip: 'Back to app',
            onPressed: () => context.go(Routes.home),
            icon: const Icon(Icons.exit_to_app),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      drawer: wide ? null : Drawer(child: _nav(context, location)),
      body: wide
          ? Row(
              children: [
                SizedBox(width: 240, child: _nav(context, location)),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            )
          : child,
    );
  }

  Widget _nav(BuildContext context, String location) => Container(
    color: AppColors.surface,
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Text(
              'AfyaSmart Admin',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
          for (final item in _items)
            ListTile(
              selected: location == item.route,
              selectedTileColor: AppColors.tintSuccessBg,
              selectedColor: AppColors.ink,
              leading: Icon(item.icon, size: 20),
              title: Text(
                item.label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                // Close the drawer first on narrow screens, or it lingers
                // over the newly pushed route.
                if (Scaffold.of(context).hasDrawer &&
                    Scaffold.of(context).isDrawerOpen) {
                  Navigator.pop(context);
                }
                context.go(item.route);
              },
            ),
        ],
      ),
    ),
  );
}
