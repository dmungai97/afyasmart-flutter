import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../../models/admin.dart';
import '../../state/admin_controller.dart';
import 'widgets/admin_widgets.dart';

/// Port of admin/screens/AdminDashboardScreen.tsx and its StatCard /
/// IncomeOverview / FacilitiesOverview / QuickActions / RecentTables
/// components.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(adminDashboardProvider);

    return dashboard.when(
      loading: () => const AdminLoading(),
      error: (error, _) => AdminError(
        error: error,
        onRetry: () => ref.read(adminDashboardProvider.notifier).refresh(),
      ),
      data: (data) => RefreshIndicator(
        color: AppColors.ruleStrong,
        onRefresh: () => ref.read(adminDashboardProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _metricGrid(context, data.metrics),
            const SizedBox(height: 16),
            _weekChart(data),
            const SizedBox(height: 16),
            _quickActions(context),
            const SizedBox(height: 16),
            _recentUsers(data),
            const SizedBox(height: 16),
            _recentTransactions(data),
          ],
        ),
      ),
    );
  }

  Widget _metricGrid(BuildContext context, AdminMetrics m) {
    final cards = [
      StatCard(
        label: 'Total revenue',
        value: formatMoney(m.totalRevenue),
        sub: '${m.subscriptions} lifetime subscribers',
        icon: Icons.payments_outlined,
      ),
      StatCard(
        label: 'Active subscribers',
        value: formatNumber(m.activeUsers),
        sub: 'Daily ${m.daily} · Weekly ${m.weekly} · Monthly ${m.monthly}',
        icon: Icons.verified_user_outlined,
      ),
      StatCard(
        label: 'Conversion',
        value: '${m.conversionRate}%',
        sub: '${formatNumber(m.totalUsers)} registered users',
        icon: Icons.trending_up,
      ),
      StatCard(
        label: 'Pending payments',
        value: formatMoney(m.pendingPayoutsValue),
        sub: '${m.pendingPayouts} awaiting confirmation',
        icon: Icons.hourglass_empty,
      ),
      StatCard(
        label: 'Facilities',
        value: formatNumber(m.totalFacilities),
        sub: '${m.doctors} doctors · ${m.pharmacies} pharmacies',
        icon: Icons.local_hospital_outlined,
      ),
      StatCard(
        label: 'Drug catalogue',
        value: formatNumber(m.drugs),
        sub: 'entries available to subscribers',
        icon: Icons.medication_outlined,
      ),
    ];

    final columns = MediaQuery.sizeOf(context).width >= 700 ? 3 : 2;

    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: cards,
    );
  }

  /// A plain bar chart of the current week. The RN version used a charting
  /// library; seven bars do not need one.
  Widget _weekChart(AdminDashboard data) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final peak = data.weeklyRevenue.fold<double>(0, (a, b) => a > b ? a : b);

    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This week',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${formatMoney(data.weeklyRevenue.fold<double>(0, (a, b) => a + b))} '
            'from ${data.weeklySubscribers.fold<int>(0, (a, b) => a + b)} payments',
            style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            data.weeklyRevenue[i] == 0
                                ? ''
                                : formatMoney(data.weeklyRevenue[i]),
                            style: const TextStyle(
                              fontSize: 9,
                              color: AppColors.inkFaint,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: peak == 0
                                ? 2
                                : (data.weeklyRevenue[i] / peak * 78).clamp(
                                    2.0,
                                    78.0,
                                  ),
                            decoration: BoxDecoration(
                              color: AppColors.ruleStrong,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            days[i],
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActions(BuildContext context) => AdminCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick actions',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _action(context, 'Manage users', Icons.people_outline, Routes.adminUsers),
            _action(
              context,
              'Facilities',
              Icons.local_hospital_outlined,
              Routes.adminFacilities,
            ),
            _action(
              context,
              'Transactions',
              Icons.receipt_long_outlined,
              Routes.adminTransactions,
            ),
            _action(
              context,
              'Payouts',
              Icons.payments_outlined,
              Routes.adminPayouts,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _action(
    BuildContext context,
    String label,
    IconData icon,
    String route,
  ) => OutlinedButton.icon(
    onPressed: () => context.go(route),
    icon: Icon(icon, size: 16),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      minimumSize: Size.zero,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );

  Widget _recentUsers(AdminDashboard data) => AdminCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Newest users',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 10),
        if (data.recentUsers.isEmpty)
          const Text(
            'No users yet.',
            style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
          )
        else
          for (final u in data.recentUsers)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          u.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          u.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusPill(
                    label: u.subscribed ? u.plan : 'free',
                    tone: u.subscribed
                        ? StatusTone.success
                        : StatusTone.neutral,
                  ),
                ],
              ),
            ),
      ],
    ),
  );

  Widget _recentTransactions(AdminDashboard data) => AdminCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent payments',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 10),
        if (data.recentTransactions.isEmpty)
          const Text(
            'No payments yet.',
            style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
          )
        else
          for (final t in data.recentTransactions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          '${t.type} · ${formatWhen(t.at)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatMoney(t.amount),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
      ],
    ),
  );
}
