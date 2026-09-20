import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';
import '../models/admin.dart';

/// Port of admin/services/admin.service.ts.
///
/// Everything privileged goes through a security-definer RPC rather than a
/// direct table write: `authenticated` holds an UPDATE grant on only three
/// columns of users, and payment_requests is read-only to clients entirely.
class AdminService {
  const AdminService();

  /// Users and payments grow unboundedly; doctors and pharmacies are curated
  /// by admins and stay small, so only the first two paginate.
  static const pageSize = 50;

  /// Counts rows without transferring any — the equivalent of Firestore's
  /// getCountFromServer(). Selecting a single narrow column keeps the
  /// response small even though only the count header is used.
  Future<int> _countAll(String table) async {
    final res = await supabase.from(table).select('id').count(CountOption.exact);
    return res.count;
  }

  Future<int> _countWhere(String table, String column, Object value) async {
    final res = await supabase
        .from(table)
        .select('id')
        .eq(column, value)
        .count(CountOption.exact);
    return res.count;
  }

  // ── Dashboard ───────────────────────────────────────────────────────────

  Future<AdminDashboard> dashboard() async {
    final counts = await Future.wait([
      _countAll('users'),
      _countWhere('users', 'has_subscribed', true),
      _countAll('doctors'),
      _countAll('pharmacies'),
      _countAll('drugs'),
    ]);

    final subscriberRows = await supabase
        .from('users')
        .select('subscription_plan, is_subscribed, subscription_expires_at')
        .eq('is_subscribed', true);

    var daily = 0;
    var weekly = 0;
    var monthly = 0;
    var activeUsers = 0;

    for (final row in subscriberRows) {
      if (!isActiveSubscription(row)) continue;
      activeUsers++;
      switch (row['subscription_plan']) {
        case 'daily':
          daily++;
        case 'weekly':
          weekly++;
        case 'monthly':
          monthly++;
      }
    }

    // Monday-first week, matching the RN dashboard's bucketing.
    final now = DateTime.now();
    final startOfWeek = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));

    final weeklyRevenue = List<double>.filled(7, 0);
    final weeklySubscribers = List<int>.filled(7, 0);

    final paidRows = await supabase
        .from('payment_requests')
        .select(
          'id, phone, user_id, plan, amount, status, paid_at, created_at, updated_at',
        )
        .eq('paid', true);

    var totalRevenue = 0.0;
    final transactions = <AdminTransaction>[];

    for (final row in paidRows) {
      final amount = paymentAmount(row);
      totalRevenue += amount;

      final at = parseDate(row['paid_at']) ?? parseDate(row['created_at']);
      if (at != null && !at.isBefore(startOfWeek)) {
        final index = at.weekday - 1;
        if (index >= 0 && index < 7) {
          weeklyRevenue[index] += amount;
          weeklySubscribers[index] += 1;
        }
      }

      transactions.add(
        AdminTransaction(
          id: row['id'] as String,
          name: row['phone'] as String? ?? row['user_id'] as String? ?? 'Payment',
          type: row['plan'] == null
              ? 'Subscription'
              : '${row['plan']} subscription',
          amount: amount,
          status: row['status'] as String? ?? 'paid',
          at: at ?? parseDate(row['updated_at']),
        ),
      );
    }

    final pendingRows = await supabase
        .from('payment_requests')
        .select('amount, plan')
        .eq('status', 'pending');

    final pendingValue = pendingRows.fold<double>(
      0,
      (sum, row) => sum + paymentAmount(row),
    );

    final recentRows = await supabase
        .from('users')
        .select(
          'id, name, email, subscription_plan, is_subscribed, subscription_expires_at',
        )
        .order('created_at', ascending: false)
        .limit(5);

    transactions.sort((a, b) {
      final at = a.at, bt = b.at;
      if (at == null || bt == null) return 0;
      return bt.compareTo(at);
    });

    return AdminDashboard(
      metrics: AdminMetrics(
        totalUsers: counts[0],
        subscriptions: counts[1],
        doctors: counts[2],
        pharmacies: counts[3],
        drugs: counts[4],
        activeUsers: activeUsers,
        totalRevenue: totalRevenue,
        pendingPayouts: pendingRows.length,
        pendingPayoutsValue: pendingValue,
        daily: daily,
        weekly: weekly,
        monthly: monthly,
      ),
      recentUsers: [
        for (final row in recentRows)
          AdminRecentUser(
            id: row['id'] as String,
            name: row['name'] as String? ?? 'AfyaSmart User',
            email: row['email'] as String? ?? '',
            plan: row['subscription_plan'] as String? ?? 'free',
            subscribed: isActiveSubscription(row),
          ),
      ],
      recentTransactions: transactions.take(5).toList(),
      weeklyRevenue: weeklyRevenue,
      weeklySubscribers: weeklySubscribers,
    );
  }

  // ── Users ───────────────────────────────────────────────────────────────

  Future<AdminPage<AdminUserRow>> users({int? cursor}) async {
    final from = cursor ?? 0;
    // One extra row tells us whether another page exists.
    final rows = await supabase
        .from('users')
        .select()
        .order('created_at', ascending: false)
        .range(from, from + pageSize);

    final page = rows.take(pageSize).toList();
    return AdminPage(
      items: page.map(AdminUserRow.fromRow).toList(),
      cursor: page.isEmpty ? null : from + page.length,
      hasMore: rows.length > pageSize,
    );
  }

  /// Goes through admin_update_user because role and the subscription fields
  /// are not client-writable, and because "only a super_admin may change a
  /// role" lives inside that function.
  Future<void> updateUser({
    required String userId,
    String? name,
    String? role,
    bool? isSubscribed,
    String? plan,
    DateTime? expiresAt,
  }) async {
    try {
      await supabase.rpc(
        'admin_update_user',
        params: {
          'p_user_id': userId,
          'p_name': name,
          'p_role': role,
          'p_is_subscribed': isSubscribed,
          'p_subscription_plan': plan,
          'p_subscription_expires_at': expiresAt?.toIso8601String(),
        },
      );
    } on PostgrestException catch (e) {
      throw ApiException(e.message);
    }
  }

  // ── Facilities ──────────────────────────────────────────────────────────

  Future<List<AdminFacility>> facilities() async {
    final results = await Future.wait([
      supabase.from('doctors').select(),
      supabase.from('pharmacies').select(),
    ]);

    return [
      ...results[0].map(AdminFacility.doctor),
      ...results[1].map(AdminFacility.pharmacy),
    ];
  }

  String _table(FacilityKind kind) =>
      kind == FacilityKind.doctor ? 'doctors' : 'pharmacies';

  Future<void> addFacility(FacilityKind kind, Map<String, dynamic> data) async {
    try {
      await supabase.from(_table(kind)).insert(data);
    } on PostgrestException catch (e) {
      throw ApiException(e.message);
    }
  }

  Future<void> updateFacility(
    FacilityKind kind,
    int id,
    Map<String, dynamic> data,
  ) async {
    try {
      await supabase.from(_table(kind)).update(data).eq('id', id);
    } on PostgrestException catch (e) {
      throw ApiException(e.message);
    }
  }

  Future<void> deleteFacility(FacilityKind kind, int id) async {
    try {
      await supabase.from(_table(kind)).delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw ApiException(e.message);
    }
  }

  // ── Payments ────────────────────────────────────────────────────────────

  Future<AdminPage<AdminPayment>> payments({int? cursor}) async {
    final from = cursor ?? 0;
    final rows = await supabase
        .from('payment_requests')
        .select()
        .order('created_at', ascending: false)
        .range(from, from + pageSize);

    final page = rows.take(pageSize).toList();
    return AdminPage(
      items: page.map(AdminPayment.fromRow).toList(),
      cursor: page.isEmpty ? null : from + page.length,
      hasMore: rows.length > pageSize,
    );
  }

  /// Reuses the exact activate_subscription() path the automated M-Pesa
  /// callback and poll use, so the referring affiliate's commission is
  /// credited the same way a real payment would be.
  Future<void> reconcilePayment(String paymentId) async {
    try {
      await supabase.rpc(
        'admin_reconcile_payment',
        params: {'p_payment_id': paymentId},
      );
    } on PostgrestException catch (e) {
      throw ApiException(e.message);
    }
  }

  Future<void> rejectPayment(String paymentId) async {
    try {
      await supabase.rpc(
        'admin_reject_payment',
        params: {'p_payment_id': paymentId},
      );
    } on PostgrestException catch (e) {
      throw ApiException(e.message);
    }
  }

  // ── Affiliate payouts ───────────────────────────────────────────────────

  Future<List<AdminPayout>> payouts() async {
    final rows = await supabase
        .from('payout_requests')
        .select()
        .order('created_at', ascending: false);
    return rows.map(AdminPayout.fromRow).toList();
  }

  /// Approval and rejection are one RPC. The refund on rejection used to be a
  /// second, separate write that could be replayed; admin_resolve_payout
  /// refuses a payout that is not still pending, so a double tap cannot
  /// refund twice.
  Future<void> resolvePayout(String payoutId, {required bool approve}) async {
    try {
      await supabase.rpc(
        'admin_resolve_payout',
        params: {'p_payout_id': payoutId, 'p_approve': approve},
      );
    } on PostgrestException catch (e) {
      throw ApiException(e.message);
    }
  }
}
