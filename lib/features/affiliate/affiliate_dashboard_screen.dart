import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../../services/affiliate_service.dart';
import '../../state/affiliate_controller.dart';
import 'widgets/affiliate_widgets.dart';

/// Port of affiliate/screens/AffiliateDashboardScreen.tsx.
class AffiliateDashboardScreen extends ConsumerWidget {
  const AffiliateDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(affiliateControllerProvider).value ??
        const AffiliateSummary.empty();

    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: () => ref.read(affiliateControllerProvider.notifier).reload(),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _balanceCard(context, data),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              children: [
                _performanceCard(data),
                const SizedBox(height: 14),
                _periodCard(data),
                const SizedBox(height: 14),
                _shareCard(context, data.code),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _balanceCard(BuildContext context, AffiliateSummary data) => Container(
    width: double.infinity,
    color: AppColors.brand,
    padding: EdgeInsets.fromLTRB(
      20,
      MediaQuery.viewPaddingOf(context).top + 18,
      20,
      24,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _copyCode(context, data.code),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Affiliate ID: ${data.code}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.copy, size: 12, color: Colors.white70),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Available balance',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          formatKes(data.availableBalance),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _whiteStat(
                'Pending',
                formatKes(data.pendingBalance),
              ),
            ),
            Expanded(
              child: _whiteStat(
                'Total earned',
                formatKes(data.totalEarned),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => context.go(Routes.affiliateWithdraw),
          icon: const Icon(Icons.account_balance_wallet_outlined, size: 17),
          label: const Text('Withdraw earnings'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppColors.brand,
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _whiteStat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 11),
      ),
    ],
  );

  Widget _performanceCard(AffiliateSummary data) => AffiliateCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Performance',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppPalette.textStrong,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: AffiliateStat(
                label: 'Referrals',
                value: '${data.referralsCount}',
              ),
            ),
            Expanded(
              child: AffiliateStat(
                label: 'Subscribed',
                value: '${data.activeUsersCount}',
                color: AppPalette.green,
              ),
            ),
            Expanded(
              child: AffiliateStat(
                label: 'Conversion',
                value: '${data.conversionRate}%',
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _periodCard(AffiliateSummary data) => AffiliateCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Earnings',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppPalette.textStrong,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: AffiliateStat(
                label: 'Today',
                value: formatKes(data.earningsToday),
              ),
            ),
            Expanded(
              child: AffiliateStat(
                label: 'This week',
                value: formatKes(data.earningsThisWeek),
              ),
            ),
            Expanded(
              child: AffiliateStat(
                label: 'This month',
                value: formatKes(data.earningsThisMonth),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _shareCard(BuildContext context, String code) => AffiliateCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your referral code',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppPalette.textStrong,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Anyone who registers with this code earns you 30% of every '
          'subscription they pay for.',
          style: TextStyle(
            fontSize: 12,
            color: AppPalette.textMuted,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F7FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppPalette.hairline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  code,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: AppColors.brand,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _copyCode(context, code),
                icon: const Icon(Icons.copy, size: 18),
                color: AppColors.brand,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _copyCode(BuildContext context, String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text('Referral code $code copied.')),
      );
  }
}
