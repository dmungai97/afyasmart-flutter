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
            _InteractiveWeekChart(data: data),
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
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 600;

    final cards = [
      StatCard(
        label: 'Total revenue',
        value: formatMoney(m.totalRevenue),
        sub: '${m.subscriptions} subscribers',
        icon: Icons.payments_outlined,
      ),
      StatCard(
        label: 'Subscribers',
        value: formatNumber(m.activeUsers),
        sub: 'D: ${m.daily} · W: ${m.weekly} · M: ${m.monthly}',
        icon: Icons.verified_user_outlined,
      ),
      StatCard(
        label: 'Conversion',
        value: '${m.conversionRate}%',
        sub: '${formatNumber(m.totalUsers)} users',
        icon: Icons.trending_up,
      ),
      StatCard(
        label: 'Pending',
        value: formatMoney(m.pendingPayoutsValue),
        sub: '${m.pendingPayouts} awaiting',
        icon: Icons.hourglass_empty,
      ),
      StatCard(
        label: 'Facilities',
        value: formatNumber(m.totalFacilities),
        sub: '${m.doctors} doc · ${m.pharmacies} pharm',
        icon: Icons.local_hospital_outlined,
      ),
      StatCard(
        label: 'Drugs',
        value: formatNumber(m.drugs),
        sub: 'Available entries',
        icon: Icons.medication_outlined,
      ),
    ];

    final columns = isMobile ? 2 : (width >= 900 ? 3 : 2);
    final aspectRatio = isMobile ? 1.8 : 2.2;

    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: aspectRatio,
      children: cards,
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
        Row(
          children: [
            Expanded(
              child: _action(
                context,
                'Users',
                Icons.people_outline,
                Routes.adminUsers,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _action(
                context,
                'Facilities',
                Icons.local_hospital_outlined,
                Routes.adminFacilities,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _action(
                context,
                'Transactions',
                Icons.receipt_long_outlined,
                Routes.adminTransactions,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _action(
                context,
                'Payouts',
                Icons.payments_outlined,
                Routes.adminPayouts,
              ),
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

class _InteractiveWeekChart extends StatefulWidget {
  const _InteractiveWeekChart({required this.data});

  final AdminDashboard data;

  @override
  State<_InteractiveWeekChart> createState() => _InteractiveWeekChartState();
}

class _InteractiveWeekChartState extends State<_InteractiveWeekChart> {
  int? _selectedDayIndex;

  @override
  Widget build(BuildContext context) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const fullDays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    final peak = widget.data.weeklyRevenue.fold<double>(
      0,
      (a, b) => a > b ? a : b,
    );
    final totalRevenue = widget.data.weeklyRevenue.fold<double>(
      0,
      (a, b) => a + b,
    );
    final totalPayments = widget.data.weeklySubscribers.fold<int>(
      0,
      (a, b) => a + b,
    );

    final selected = _selectedDayIndex;
    final selectedDayName = selected != null ? fullDays[selected] : null;
    final selectedRev = selected != null ? widget.data.weeklyRevenue[selected] : null;
    final selectedSubs = selected != null ? widget.data.weeklySubscribers[selected] : null;

    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
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
                    '${formatMoney(totalRevenue)} from $totalPayments payments',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
              if (selected != null)
                GestureDetector(
                  onTap: () => setState(() => _selectedDayIndex = null),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.ink.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$selectedDayName: ${formatMoney(selectedRev!)} ($selectedSubs)',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.close, size: 12, color: AppColors.inkMuted),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 125,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++) ...[
                  Builder(
                    builder: (_) {
                      final isSelected = selected == i;
                      final rev = widget.data.weeklyRevenue[i];
                      final barHeight = peak == 0
                          ? 4.0
                          : (rev / peak * 70).clamp(4.0, 70.0);

                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            setState(() {
                              _selectedDayIndex = isSelected ? null : i;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  rev == 0 ? '' : formatMoney(rev),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? AppColors.ink
                                        : AppColors.inkFaint,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  height: barHeight,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.ink
                                        : (rev > 0
                                            ? AppColors.ruleStrong
                                            : AppColors.rule),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.ink
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    days[i],
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? AppColors.paper
                                          : AppColors.inkMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
