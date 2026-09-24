import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/admin.dart';
import '../../state/providers.dart';
import 'widgets/admin_widgets.dart';

/// Port of admin/screens/AdminTransactionsScreen.tsx.
class AdminTransactionsScreen extends ConsumerStatefulWidget {
  const AdminTransactionsScreen({super.key});

  @override
  ConsumerState<AdminTransactionsScreen> createState() =>
      _AdminTransactionsScreenState();
}

class _AdminTransactionsScreenState
    extends ConsumerState<AdminTransactionsScreen> {
  final _payments = <AdminPayment>[];
  int? _cursor;
  bool _hasMore = true;
  bool _loading = true;
  Object? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _loading = true;
      if (reset) _error = null;
    });

    try {
      final page = await ref
          .read(adminServiceProvider)
          .payments(cursor: reset ? null : _cursor);

      if (!mounted) return;
      setState(() {
        if (reset) _payments.clear();
        _payments.addAll(page.items);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _error = null;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<AdminPayment> get _filtered => _filter == 'all'
      ? _payments
      : _payments.where((p) => p.status == _filter).toList();

  @override
  Widget build(BuildContext context) {
    if (_error != null && _payments.isEmpty) {
      return AdminError(error: _error!, onRetry: () => _load(reset: true));
    }
    if (_loading && _payments.isEmpty) return const AdminLoading();

    final rows = _filtered;

    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              for (final f in const [
                'all',
                'paid',
                'pending',
                'failed',
                'cancelled',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                    selectedColor: AppColors.ink,
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.rule),
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _filter == f ? AppColors.paper : AppColors.inkMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const AdminEmpty(message: 'No payments match this filter.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: rows.length + (_hasMore ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == rows.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: _loading
                              ? const CircularProgressIndicator(
                                  color: AppColors.ruleStrong,
                                )
                              : OutlinedButton(
                                  onPressed: _load,
                                  child: const Text('Load more'),
                                ),
                        ),
                      );
                    }
                    return _row(rows[i]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _row(AdminPayment p) => Padding(
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
                      p.phone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      '${p.plan} · ${formatWhen(p.createdAt)}',
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(p.amount),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 3),
                  StatusPill(label: p.status, tone: toneForStatus(p.status)),
                ],
              ),
            ],
          ),
          if (p.status == 'pending') ...[
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _reject(p),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Reject'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _reconcile(p),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.ink,
                    foregroundColor: AppColors.paper,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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

  Future<void> _reconcile(AdminPayment p) async {
    final confirmed = await _confirm(
      title: 'Mark as paid?',
      // Spells out the side effect: this is not just a status flip.
      body:
          'This activates ${p.phone}\'s ${p.plan} subscription and credits '
          'their referrer\'s commission, exactly as a real M-Pesa '
          'confirmation would.',
      action: 'Mark paid',
    );
    if (!confirmed) return;

    await _run(
      () => ref.read(adminServiceProvider).reconcilePayment(p.id),
      'Payment reconciled.',
    );
  }

  Future<void> _reject(AdminPayment p) async {
    final confirmed = await _confirm(
      title: 'Reject payment?',
      body: 'This marks the payment failed. No subscription is activated.',
      action: 'Reject',
    );
    if (!confirmed) return;

    await _run(
      () => ref.read(adminServiceProvider).rejectPayment(p.id),
      'Payment rejected.',
    );
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _run(Future<void> Function() action, String success) async {
    try {
      await action();
      await _load(reset: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}
