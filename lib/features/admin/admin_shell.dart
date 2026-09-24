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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (location != Routes.admin) {
          context.go(Routes.admin);
        } else {
          context.go(Routes.home);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.paper,
        appBar: AppBar(
          title: Text(
            title ?? 'Admin',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
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
        drawer: wide
            ? null
            : Drawer(
                child: _nav(context, location, isDrawer: true),
              ),
        body: wide
            ? Row(
                children: [
                  SizedBox(
                    width: 240,
                    child: _nav(context, location, isDrawer: false),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: child),
                ],
              )
            : child,
      ),
    );
  }

  Widget _nav(
    BuildContext context,
    String location, {
    required bool isDrawer,
  }) => Container(
    color: AppColors.surface,
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 18,
                    color: AppColors.paper,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: 'Afya'),
                        TextSpan(
                          text: 'Smart',
                          style: TextStyle(color: AppColors.accent),
                        ),
                        TextSpan(
                          text: ' Admin',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.inkMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.rule),
          const SizedBox(height: 8),
          for (final item in _items) ...[
            Builder(
              builder: (_) {
                final focused = location == item.route;
                return Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: focused
                        ? AppColors.ink.withValues(alpha: 0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: Icon(
                      item.icon,
                      size: 20,
                      color: focused ? AppColors.ink : AppColors.inkMuted,
                    ),
                    title: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            focused ? FontWeight.w700 : FontWeight.w500,
                        color: focused ? AppColors.ink : AppColors.inkMuted,
                      ),
                    ),
                    onTap: () {
                      if (isDrawer) {
                        Navigator.of(context).pop();
                      }
                      context.go(item.route);
                    },
                  ),
                );
              },
            ),
          ],
        ],
      ),
    ),
  );
}
