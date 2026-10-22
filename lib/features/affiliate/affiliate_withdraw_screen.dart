import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../services/affiliate_service.dart';
import '../../state/affiliate_controller.dart';
import '../../state/auth_controller.dart';
import 'widgets/affiliate_widgets.dart';

/// Port of affiliate/screens/AffiliateWithdrawScreen.tsx.
class AffiliateWithdrawScreen extends ConsumerStatefulWidget {
  const AffiliateWithdrawScreen({super.key});

  @override
  ConsumerState<AffiliateWithdrawScreen> createState() =>
      _AffiliateWithdrawScreenState();
}

class _AffiliateWithdrawScreenState
    extends ConsumerState<AffiliateWithdrawScreen> {
  final _amount = TextEditingController();
  final _phone = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _phone.text = ref.read(currentUserProvider)?.phone ?? '';
  }

  @override
  void dispose() {
    _amount.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit(double available) async {
    final amountText = _amount.text.trim();
    if (amountText.isEmpty) {
      _toast('Enter a withdrawal amount.');
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      _toast('Enter a valid withdrawal amount.');
      return;
    }

    if (amount < AffiliateService.minWithdrawal) {
      _toast('Minimum withdrawal amount is Ksh 100.');
      return;
    }

    if (amount > available) {
      _toast('Amount exceeds your available balance.');
      return;
    }

    final phone = _phone.text.trim();
    if (phone.isEmpty) {
      _toast('Enter your M-Pesa phone number.');
      return;
    }

    setState(() => _submitting = true);
    final error = await ref
        .read(affiliateControllerProvider.notifier)
        .requestPayout(amount: amount, phone: phone);

    if (!mounted) return;
    setState(() => _submitting = false);

    if (error != null) {
      _toast(error.replaceAll('ApiException: ', ''));
      return;
    }

    _amount.clear();
    _toast('Withdrawal request submitted for review.');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(affiliateControllerProvider).value ??
        const AffiliateSummary.empty();

    return Column(
      children: [
        AffiliateHeader(
          title: 'Withdraw',
          subtitle: '${formatKes(data.availableBalance)} available',
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              AffiliateCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Request a payout',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textStrong,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Minimum ${formatKes(AffiliateService.minWithdrawal)}. '
                      'Paid to your M-Pesa number after review.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppPalette.textMuted,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount (Ksh)',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'M-Pesa number',
                        hintText: '0712 345 678',
                        prefixIcon: Icon(Icons.phone_android),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: data.availableBalance <= 0
                            ? null
                            : () => _amount.text = data.availableBalance
                                  .toStringAsFixed(0),
                        child: const Text('Withdraw everything'),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FilledButton(
                      onPressed: _submitting
                          ? null
                          : () => _submit(data.availableBalance),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brand,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Request withdrawal'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Past withdrawals',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textMuted,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 10),
              if (data.withdrawals.isEmpty)
                const AffiliateEmpty(
                  icon: '🏦',
                  message: 'No withdrawals yet.',
                )
              else
                for (final w in data.withdrawals)
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
                                  formatKes(w.amount),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppPalette.textStrong,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${w.phone} · ${formatMoment(w.createdAt)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppPalette.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _statusBadge(w.status),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusBadge(WithdrawalStatus status) {
    final (label, bg, fg) = switch (status) {
      WithdrawalStatus.completed => (
        'Paid',
        AppPalette.greenBg,
        AppPalette.green,
      ),
      WithdrawalStatus.failed => ('Rejected', AppPalette.redBg, AppPalette.red),
      WithdrawalStatus.processing => (
        'Processing',
        AppPalette.orangeBg,
        AppPalette.orange,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
