import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../state/auth_controller.dart';
import '../../state/providers.dart';

/// Port of src/user/screens/SubscriptionScreen.tsx — plan selection and the
/// M-Pesa STK push flow.
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key, this.initialPlan});

  /// From a ?plan= deep link (the locked-results paywall, the home banner, or
  /// a login carried through registration). Opens straight into checkout.
  final String? initialPlan;

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

typedef _Plan = ({
  String id,
  String name,
  int price,
  String period,
  Color color,
  List<String> features,
});

const _plans = <_Plan>[
  (
    id: 'free',
    name: 'Free Plan',
    price: 0,
    period: 'forever',
    color: Color(0xFF6B7280),
    features: [
      'Explore the app for 1 day',
      'Limited AI chat',
      'Limited symptoms check',
      'View only subscribed services',
    ],
  ),
  (
    id: 'daily',
    name: 'Daily Plan',
    price: 20,
    period: 'day',
    color: AppColors.brand,
    features: [
      'Valid for 24 hours',
      'Full access to all features',
      'Unlimited AI Health Assistant',
      'Full Symptoms Checker',
      'Drugs Database access',
      'Nearby Health Services',
    ],
  ),
  (
    id: 'weekly',
    name: 'Weekly Plan',
    price: 100,
    period: 'week',
    color: AppPalette.purple,
    features: [
      'Valid for 7 days',
      'Everything in Daily',
      'Priority AI responses',
      'Save 30% vs daily',
    ],
  ),
  (
    id: 'monthly',
    name: 'Monthly Plan',
    price: 200,
    period: 'month',
    color: AppPalette.orange,
    features: [
      'Valid for 30 days',
      'Everything in Weekly',
      'Best value per day',
      'Uninterrupted access',
    ],
  ),
];

enum _PayStep { form, waiting, confirmed, failed }

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  final _phone = TextEditingController();

  _Plan? _selected;
  _PayStep _step = _PayStep.form;
  String? _checkoutId;
  int _pollCount = 0;

  Timer? _poll;
  Timer? _timeout;
  RealtimeChannel? _channel;

  /// 30 polls at 3s, and a hard 90s stop. The poll is the backstop; realtime
  /// normally resolves this within a second of the callback landing.
  static const _maxPolls = 30;
  static const _pollInterval = Duration(seconds: 3);
  static const _giveUpAfter = Duration(seconds: 90);

  @override
  void initState() {
    super.initState();
    _phone.text = ref.read(currentUserProvider)?.phone ?? '';

    final wanted = widget.initialPlan;
    if (wanted != null && wanted != 'free') {
      final match = _plans.where((p) => p.id == wanted).firstOrNull;
      if (match != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openCheckout(match);
        });
      }
    }
  }

  @override
  void dispose() {
    _stopWatchers();
    _phone.dispose();
    super.dispose();
  }

  void _stopWatchers() {
    _poll?.cancel();
    _poll = null;
    _timeout?.cancel();
    _timeout = null;
    if (_channel != null) {
      supabase.removeChannel(_channel!);
      _channel = null;
    }
  }

  void _openCheckout(_Plan plan) {
    setState(() {
      _selected = plan;
      _step = _PayStep.form;
      _checkoutId = null;
      _pollCount = 0;
      _phone.text = ref.read(currentUserProvider)?.phone ?? '';
    });
    _showPaymentSheet();
  }

  Future<void> _initiate(void Function(void Function()) setSheetState) async {
    final plan = _selected;
    if (plan == null || _phone.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your M-Pesa phone number.')),
      );
      return;
    }

    setSheetState(() => _step = _PayStep.waiting);

    try {
      final checkoutId = await ref
          .read(mpesaServiceProvider)
          .initiate(phone: _phone.text.trim(), plan: plan.id);

      _checkoutId = checkoutId;
      _startWatching(checkoutId, setSheetState);
    } on Exception catch (e) {
      setSheetState(() => _step = _PayStep.failed);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('STK Push failed: $e')),
      );
    }
  }

  /// Confirms by asking the backend, then re-reading the profile.
  ///
  /// Returns true only once the user row actually shows an active
  /// subscription — a paid payment whose activation had not landed yet would
  /// otherwise show success on a screen that still has no access.
  Future<bool> _confirmAccess(String checkoutId) async {
    final status = await ref.read(mpesaServiceProvider).poll(checkoutId);
    if (!status.paid) return false;

    await ref.read(authControllerProvider.notifier).refresh();
    return ref.read(currentUserProvider)?.isSubscribed ?? false;
  }

  void _startWatching(
    String checkoutId,
    void Function(void Function()) setSheetState,
  ) {
    _stopWatchers();
    _pollCount = 0;

    Future<void> check() async {
      try {
        if (await _confirmAccess(checkoutId)) {
          _stopWatchers();
          if (mounted) setSheetState(() => _step = _PayStep.confirmed);
        }
      } on Exception {
        // A failed poll is expected while the user is still entering their
        // PIN; the next tick retries.
      }
    }

    // Realtime: the M-Pesa callback updates payment_requests, and this is
    // filtered to the single row for this checkout. RLS keeps it to the
    // caller's own payment.
    _channel = supabase
        .channel('payment:$checkoutId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'payment_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'checkout_request_id',
            value: checkoutId,
          ),
          callback: (payload) async {
            final row = payload.newRecord;
            final status = row['status'] as String?;

            if (row['paid'] == true || status == 'paid') {
              await check();
            } else if (status == 'cancelled' || status == 'failed') {
              _stopWatchers();
              if (mounted) setSheetState(() => _step = _PayStep.failed);
            }
          },
        )
        .subscribe();

    _poll = Timer.periodic(_pollInterval, (timer) async {
      _pollCount++;
      if (mounted) setSheetState(() {});
      if (_pollCount >= _maxPolls) timer.cancel();
      await check();
    });

    _timeout = Timer(_giveUpAfter, () {
      _stopWatchers();
      if (mounted) setSheetState(() => _step = _PayStep.failed);
    });
  }

  void _showPaymentSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              child: switch (_step) {
                _PayStep.form => _formBody(sheetContext, setSheetState),
                _PayStep.waiting => _waitingBody(sheetContext),
                _PayStep.confirmed => _confirmedBody(sheetContext),
                _PayStep.failed => _failedBody(sheetContext, setSheetState),
              },
            ),
          ),
        ),
      ),
    ).whenComplete(_stopWatchers);
  }

  Widget _sheetHandle() => Center(
    child: Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: AppPalette.hairline,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  Widget _formBody(
    BuildContext sheetContext,
    void Function(void Function()) setSheetState,
  ) {
    final plan = _selected!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sheetHandle(),
        Text(
          plan.name,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: AppPalette.textStrong,
          ),
        ),
        Text(
          'Ksh ${plan.price} per ${plan.period}',
          style: const TextStyle(fontSize: 13, color: AppPalette.textMuted),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'M-Pesa phone number',
            hintText: '0712 345 678',
            prefixIcon: Icon(Icons.phone_android),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "You'll receive an STK push on this number. Enter your M-Pesa PIN "
          'to confirm.',
          style: TextStyle(
            fontSize: 11,
            color: AppPalette.textMuted,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () => _initiate(setSheetState),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brand,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text('Pay Ksh ${plan.price}'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _waitingBody(BuildContext sheetContext) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _sheetHandle(),
      const SizedBox(height: 8),
      const CircularProgressIndicator(color: AppColors.brand),
      const SizedBox(height: 20),
      const Text(
        'Check your phone',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppPalette.textStrong,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Enter your M-Pesa PIN on the prompt sent to ${_phone.text.trim()}.',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13,
          color: AppPalette.textMuted,
          height: 1.5,
        ),
      ),
      const SizedBox(height: 14),
      Text(
        'Waiting for confirmation… ${_pollCount * 3}s',
        style: const TextStyle(fontSize: 11, color: AppPalette.textMuted),
      ),
      const SizedBox(height: 20),
    ],
  );

  Widget _confirmedBody(BuildContext sheetContext) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _sheetHandle(),
      const Icon(Icons.check_circle, size: 56, color: AppPalette.green),
      const SizedBox(height: 16),
      const Text(
        'Subscription active',
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: AppPalette.textStrong,
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        'Everything is unlocked. Enjoy full access to AfyaSmart.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          color: AppPalette.textMuted,
          height: 1.5,
        ),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () => Navigator.pop(sheetContext),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text('Continue'),
      ),
    ],
  );

  Widget _failedBody(
    BuildContext sheetContext,
    void Function(void Function()) setSheetState,
  ) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _sheetHandle(),
      const Icon(Icons.error_outline, size: 56, color: AppPalette.red),
      const SizedBox(height: 16),
      const Text(
        'Payment not confirmed',
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: AppPalette.textStrong,
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        "We didn't receive confirmation. If you were charged, tap Check "
        'again — your subscription will activate automatically.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          color: AppPalette.textMuted,
          height: 1.5,
        ),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () async {
          final id = _checkoutId;
          if (id == null) {
            setSheetState(() => _step = _PayStep.form);
            return;
          }
          setSheetState(() => _step = _PayStep.waiting);
          if (await _confirmAccess(id)) {
            if (mounted) setSheetState(() => _step = _PayStep.confirmed);
          } else {
            if (mounted) setSheetState(() => _step = _PayStep.failed);
          }
        },
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text('Check again'),
      ),
      TextButton(
        onPressed: () {
          setSheetState(() => _step = _PayStep.form);
        },
        child: const Text('Try a different number'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(sheetContext),
        child: const Text('Close'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final activePlan = user?.isSubscribed == true ? user!.effectivePlan : 'free';

    return Container(
      color: const Color(0xFFF5F7FA),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            width: double.infinity,
            color: AppColors.brand,
            padding: EdgeInsets.fromLTRB(
              24,
              MediaQuery.viewPaddingOf(context).top + 20,
              24,
              24,
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose your plan',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Pay with M-Pesa. Cancel any time.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              children: [
                for (final plan in _plans)
                  _planCard(plan, isCurrent: plan.id == activePlan),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCard(_Plan plan, {required bool isCurrent}) {
    final isFree = plan.id == 'free';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCurrent ? plan.color : AppPalette.hairline,
          width: isCurrent ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: plan.color,
                  ),
                ),
              ),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: plan.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Text(
                    'Current',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: plan.color,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: isFree ? 'Free' : 'Ksh ${plan.price}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textStrong,
                  ),
                ),
                TextSpan(
                  text: ' / ${plan.period}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppPalette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (final feature in plan.features)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check, size: 15, color: plan.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      feature,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppPalette.textBody,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!isFree) ...[
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => _openCheckout(plan),
              style: FilledButton.styleFrom(
                backgroundColor: plan.color,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(isCurrent ? 'Renew' : 'Choose ${plan.name}'),
            ),
          ],
        ],
      ),
    );
  }
}
