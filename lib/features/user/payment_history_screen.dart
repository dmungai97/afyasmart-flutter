import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../state/providers.dart';
import 'widgets/profile_widgets.dart';

final _paymentHistoryProvider = FutureProvider.autoDispose<List<PaymentRecord>>(
  (ref) => ref.read(authServiceProvider).paymentHistory(),
);

/// The user's M-Pesa payment attempts, including failed and cancelled ones,
/// so "I paid but nothing happened" can be checked against what we recorded.
class PaymentHistoryScreen extends ConsumerWidget {
  const PaymentHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(_paymentHistoryProvider);

    return ProfileSubpage(
      title: 'Payment History',
      child: RefreshIndicator(
        onRefresh: () => ref.refresh(_paymentHistoryProvider.future),
        child: payments.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const _Message(
            icon: Icons.cloud_off_outlined,
            text: 'Could not load your payments. Pull down to try again.',
          ),
          data: (rows) => rows.isEmpty
              ? const _Message(
                  icon: Icons.receipt_long_outlined,
                  text: 'No payments yet.',
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                  children: [
                    _Summary(rows),
                    const SizedBox(height: 20),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                      child: Text(
                        'Transactions',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.textMuted,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    _PaymentList(rows),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary(this.rows);

  final List<PaymentRecord> rows;

  @override
  Widget build(BuildContext context) {
    final paid = rows.where((p) => p.status == 'paid');
    final total = paid.fold<double>(0, (sum, p) => sum + p.amount);

    return ProfileCard(
      child: Row(
        children: [
          Expanded(
            child: _SummaryStat(
              value: 'Ksh ${total.toStringAsFixed(0)}',
              label: 'Total paid',
            ),
          ),
          const SizedBox(
            height: 32,
            child: VerticalDivider(color: AppPalette.hairline),
          ),
          Expanded(
            child: _SummaryStat(
              value: '${paid.length} of ${rows.length}',
              label: 'Successful',
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.brand,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: AppPalette.textMuted),
      ),
    ],
  );
}

class _PaymentList extends StatelessWidget {
  const _PaymentList(this.rows);

  final List<PaymentRecord> rows;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppPalette.hairline),
    ),
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            const Divider(height: 1, indent: 68, color: AppPalette.hairline),
          _PaymentRow(rows[i]),
        ],
      ],
    ),
  );
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow(this.payment);

  final PaymentRecord payment;

  @override
  Widget build(BuildContext context) {
    final (label, icon, fg, bg) = switch (payment.status) {
      'paid' => ('Paid', Icons.check_rounded, AppPalette.green, AppPalette.greenBg),
      'failed' => ('Failed', Icons.close_rounded, AppPalette.red, AppPalette.redBg),
      'cancelled' => (
        'Cancelled',
        Icons.block_rounded,
        AppPalette.textMuted,
        AppPalette.hairline,
      ),
      _ => ('Pending', Icons.schedule_rounded, AppPalette.orange, AppPalette.orangeBg),
    };

    final plan = payment.plan.isEmpty
        ? 'Subscription'
        : '${payment.plan[0].toUpperCase()}${payment.plan.substring(1)} plan';

    final reason = payment.status == 'failed'
        ? _shortReason(payment.failureReason)
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: fg),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.textStrong,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (payment.createdAt != null) _formatDate(payment.createdAt!),
                    ?reason,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppPalette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Ksh ${payment.amount.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textStrong,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Daraja's ResultDesc strings are full sentences; the list needs a few
  /// words. Unknown reasons fall back to a generic label rather than a
  /// truncated sentence.
  static String _shortReason(String? reason) {
    final r = (reason ?? '').toLowerCase();
    if (r.contains('insufficient')) return 'Insufficient balance';
    if (r.contains('cancel')) return 'Cancelled on phone';
    if (r.contains('timeout') ||
        r.contains('timed out') ||
        r.contains('expired') ||
        r.contains('no response')) {
      return 'No response';
    }
    if (r.contains('pin') || r.contains('initiator')) return 'Wrong PIN';
    if (r.contains('unreachable') || r.contains('not reachable')) {
      return 'Phone unreachable';
    }
    return 'Not completed';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _formatDate(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    final year = d.year == DateTime.now().year ? '' : ' ${d.year}';
    return '${d.day} ${_months[d.month - 1]}$year, $hh:$mm';
  }
}

/// Empty and error states. Wrapped in a ListView so pull-to-refresh still
/// works when there is nothing to scroll.
class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: 120),
      Icon(icon, size: 48, color: AppPalette.textMuted),
      const SizedBox(height: 12),
      Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppPalette.textMuted),
      ),
    ],
  );
}
