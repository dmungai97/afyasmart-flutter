import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';

/// Port of affiliate/services/affiliate.service.ts.

class Referral {
  const Referral({
    required this.id,
    required this.name,
    required this.active,
    required this.joinedAt,
  });

  final String id;
  final String name;
  final bool active;
  final DateTime? joinedAt;
}

class Earning {
  const Earning({
    required this.id,
    required this.name,
    required this.plan,
    required this.amount,
    required this.commission,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String plan;
  final double amount;
  final double commission;
  final DateTime? createdAt;

  String get planLabel => plan.isEmpty
      ? 'Subscription'
      : '${plan[0].toUpperCase()}${plan.substring(1)} Plan';
}

enum WithdrawalStatus { completed, processing, failed }

class Withdrawal {
  const Withdrawal({
    required this.id,
    required this.amount,
    required this.status,
    required this.phone,
    required this.createdAt,
  });

  final String id;
  final double amount;
  final WithdrawalStatus status;
  final String phone;
  final DateTime? createdAt;
}

class AffiliateSummary {
  const AffiliateSummary({
    required this.enrolled,
    required this.code,
    required this.since,
    required this.availableBalance,
    required this.pendingBalance,
    required this.totalEarned,
    required this.referrals,
    required this.earnings,
    required this.withdrawals,
    required this.earningsToday,
    required this.earningsThisWeek,
    required this.earningsThisMonth,
  });

  const AffiliateSummary.empty()
    : enrolled = false,
      code = '',
      since = null,
      availableBalance = 0,
      pendingBalance = 0,
      totalEarned = 0,
      referrals = const [],
      earnings = const [],
      withdrawals = const [],
      earningsToday = 0,
      earningsThisWeek = 0,
      earningsThisMonth = 0;

  final bool enrolled;
  final String code;
  final DateTime? since;
  final double availableBalance;
  final double pendingBalance;
  final double totalEarned;
  final List<Referral> referrals;
  final List<Earning> earnings;
  final List<Withdrawal> withdrawals;
  final double earningsToday;
  final double earningsThisWeek;
  final double earningsThisMonth;

  int get referralsCount => referrals.length;
  int get activeUsersCount => referrals.where((r) => r.active).length;
  int get conversionRate => referrals.isEmpty
      ? 0
      : ((activeUsersCount / referrals.length) * 100).round();
}

class AffiliateService {
  const AffiliateService();

  static const minWithdrawal = 100.0;

  Future<AffiliateSummary> load() async {
    final uid = currentUserId;
    if (uid == null) return const AffiliateSummary.empty();

    final affiliate = await supabase
        .from('affiliates')
        .select()
        .eq('id', uid)
        .maybeSingle();

    if (affiliate == null) return const AffiliateSummary.empty();

    // RLS scopes each of these to this affiliate (users_select allows reading
    // the users you referred; commissions_select and payout_requests_select
    // match on affiliate_id), so the filters are for clarity, not security.
    final results = await Future.wait([
      supabase
          .from('users')
          .select('id, name, is_subscribed, created_at')
          .eq('referred_by_uid', uid),
      supabase
          .from('commissions')
          .select('id, referred_id, plan, amount, commission_amount, created_at')
          .eq('affiliate_id', uid)
          .order('created_at', ascending: false),
      supabase
          .from('payout_requests')
          .select('id, amount, phone, status, created_at')
          .eq('affiliate_id', uid)
          .order('created_at', ascending: false),
    ]);

    final nameByUid = <String, String>{};
    final referrals = results[0].map((row) {
      final name = row['name'] as String? ?? 'AfyaSmart User';
      nameByUid[row['id'] as String] = name;
      return Referral(
        id: row['id'] as String,
        name: name,
        active: row['is_subscribed'] as bool? ?? false,
        joinedAt: _parse(row['created_at']),
      );
    }).toList();

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfWeek = startOfToday.subtract(
      Duration(days: now.weekday == DateTime.sunday ? 6 : now.weekday - 1),
    );
    final startOfMonth = DateTime(now.year, now.month);

    var today = 0.0;
    var week = 0.0;
    var month = 0.0;

    final earnings = results[1].map((row) {
      final commission = _toDouble(row['commission_amount']);
      final createdAt = _parse(row['created_at']);

      if (createdAt != null) {
        if (!createdAt.isBefore(startOfToday)) today += commission;
        if (!createdAt.isBefore(startOfWeek)) week += commission;
        if (!createdAt.isBefore(startOfMonth)) month += commission;
      }

      return Earning(
        id: row['id'] as String,
        name: nameByUid[row['referred_id']] ?? 'Referred user',
        plan: row['plan'] as String? ?? '',
        amount: _toDouble(row['amount']),
        commission: commission,
        createdAt: createdAt,
      );
    }).toList();

    final withdrawals = results[2]
        .map(
          (row) => Withdrawal(
            id: row['id'] as String,
            amount: _toDouble(row['amount']),
            status: switch (row['status']) {
              'paid' => WithdrawalStatus.completed,
              'rejected' => WithdrawalStatus.failed,
              _ => WithdrawalStatus.processing,
            },
            phone: row['phone'] as String? ?? '',
            createdAt: _parse(row['created_at']),
          ),
        )
        .toList();

    return AffiliateSummary(
      enrolled: true,
      code: affiliate['code'] as String? ?? '',
      since: _parse(affiliate['created_at']),
      availableBalance: _toDouble(affiliate['available_balance']),
      pendingBalance: _toDouble(affiliate['pending_balance']),
      totalEarned: _toDouble(affiliate['total_earned']),
      referrals: referrals,
      earnings: earnings,
      withdrawals: withdrawals,
      earningsToday: today,
      earningsThisWeek: week,
      earningsThisMonth: month,
    );
  }

  /// Claims a referral code. The RPC settles collisions against the unique
  /// index and returns the existing code if already enrolled.
  Future<String> enroll() async {
    try {
      final code = await supabase.rpc('enroll_affiliate');
      return code as String? ?? '';
    } on PostgrestException catch (e) {
      throw ApiException(
        e.message.isEmpty
            ? 'Could not enroll as an affiliate. Please try again.'
            : e.message,
      );
    }
  }

  /// Requests a payout.
  ///
  /// The guards here are for a fast, friendly message. request_payout
  /// re-checks both authoritatively and deducts the balance under a row lock,
  /// so two concurrent withdrawals cannot both succeed.
  Future<void> requestPayout({
    required double amount,
    required String phone,
    required double availableBalance,
  }) async {
    if (amount <= 0 || amount < minWithdrawal) {
      throw const ApiException(
        'Minimum withdrawal amount is Ksh 100.',
      );
    }
    if (amount > availableBalance) {
      throw const ApiException('You do not have enough available balance.');
    }

    try {
      await supabase.rpc(
        'request_payout',
        params: {'p_amount': amount, 'p_phone': phone},
      );
    } on PostgrestException catch (e) {
      throw ApiException(
        e.message.isEmpty ? 'Unable to process withdrawal request.' : e.message,
      );
    }
  }

  static DateTime? _parse(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;

  static double _toDouble(Object? value) => switch (value) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s) ?? 0,
    _ => 0,
  };
}
