import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../state/affiliate_controller.dart';
import 'widgets/affiliate_widgets.dart';

/// Port of affiliate/screens/AffiliateEarningsScreen.tsx.
class AffiliateEarningsScreen extends ConsumerWidget {
  const AffiliateEarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(affiliateControllerProvider).requireValue;

    return Column(
      children: [
        AffiliateHeader(
          title: 'Earnings',
          subtitle: '${formatKes(data.totalEarned)} earned in total',
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.brand,
            onRefresh: () =>
                ref.read(affiliateControllerProvider.notifier).reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
              children: [
                AffiliateCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: AffiliateStat(
                          label: 'Available',
                          value: formatKes(data.availableBalance),
                          color: AppPalette.green,
                        ),
                      ),
                      Expanded(
                        child: AffiliateStat(
                          label: 'Pending',
                          value: formatKes(data.pendingBalance),
                          color: AppPalette.orange,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Text(
                    // Explains the pending balance rather than leaving it as
                    // an unexplained number the affiliate cannot withdraw.
                    'Commissions are held for 7 days before they become '
                    'available to withdraw.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppPalette.textMuted,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'History',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textMuted,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 10),
                if (data.earnings.isEmpty)
                  const AffiliateEmpty(
                    icon: '💰',
                    message:
                        'No commissions yet. You earn 30% each time someone '
                        'you referred pays for a subscription.',
                  )
                else
                  for (final e in data.earnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AffiliateCard(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppPalette.textStrong,
                                    ),
                                  ),
                                  Text(
                                    '${e.planLabel} · ${formatMoment(e.createdAt)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppPalette.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '+${formatKes(e.commission)}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppPalette.green,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                Text(
                                  'of ${formatKes(e.amount)}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppPalette.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
