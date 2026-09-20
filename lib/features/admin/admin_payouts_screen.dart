import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/admin.dart';
import '../../state/admin_controller.dart';
import '../../state/providers.dart';
import 'widgets/admin_widgets.dart';

/// Port of admin/screens/AdminAffiliatePayoutsScreen.tsx.
///
/// Money movement itself happens outside the app (Safaricom portal or manual
/// disbursement) — this only tracks and resolves the request.
class AdminPayoutsScreen extends ConsumerWidget {
  const AdminPayoutsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payouts = ref.watch(adminPayoutsProvider);

    return payouts.when(
      loading: () => const AdminLoading(),
      error: (error, _) => AdminError(
        error: error,
        onRetry: () => ref.invalidate(adminPayoutsProvider),
      ),
      data: (rows) => RefreshIndicator(
        color: AppColors.ruleStrong,
        onRefresh: () async => ref.invalidate(adminPayoutsProvider),
        child: rows.isEmpty
            ? ListView(
                children: const [
                  AdminEmpty(message: 'No payout requests yet.'),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                itemBuilder: (_, i) => _row(context, ref, rows[i]),
              ),
      ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, AdminPayout p) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatMoney(p.amount),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      '${p.phone} · ${formatWhen(p.createdAt)}',
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
              StatusPill(label: p.status, tone: toneForStatus(p.status)),
            ],
          ),
          // A resolved payout offers no actions: admin_resolve_payout refuses
          // anything that is not still pending, which is what stops a second
          // rejection refunding the balance twice.
          if (p.status == 'pending') ...[
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _resolve(context, ref, p, approve: false),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                  ),
                  child: const Text('Reject'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _resolve(context, ref, p, approve: true),
                  style: FilledButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  child: const Text('Mark paid'),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );

  Future<void> _resolve(
    BuildContext context,
    WidgetRef ref,
    AdminPayout p, {
    required bool approve,
  }) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(approve ? 'Mark as paid?' : 'Reject payout?'),
            content: Text(
              approve
                  ? 'Confirm you have sent ${formatMoney(p.amount)} to '
                        '${p.phone}. This only records the payment; it does '
                        'not move any money.'
                  : 'This returns ${formatMoney(p.amount)} to the '
                        "affiliate's available balance.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(approve ? 'Mark paid' : 'Reject'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    try {
      await ref
          .read(adminServiceProvider)
          .resolvePayout(p.id, approve: approve);
      ref.invalidate(adminPayoutsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(approve ? 'Payout marked paid.' : 'Payout rejected.')),
      );
    } on Exception catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}
