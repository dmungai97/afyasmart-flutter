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

  // ── Dashboard ───────────────────────────────────────────────────────────

  /// Totals come from admin_dashboard_stats(), computed in the database over
  /// customer accounts only. This used to download every paid payment and
  /// sum it here, which PostgREST's 1000-row cap would have silently
  /// truncated, and it counted admin accounts as users and subscribers.
  /// The two short lists are capped queries.
  Future<AdminDashboard> dashboard() async {
    final results = await Future.wait<dynamic>([
      supabase.rpc('admin_dashboard_stats'),
      supabase
          .from('users')
          .select(
            'id, name, email, subscription_plan, is_subscribed, subscription_expires_at',
          )
          .order('created_at', ascending: false)
          .limit(5),
      supabase
          .from('payment_requests')
          .select('id, phone, user_id, plan, amount, status, paid_at')
          .eq('status', 'paid')
          .order('paid_at', ascending: false)
          .limit(5),
    ]);

    final stats = results[0] as Map<String, dynamic>;
    final recentRows = results[1] as List<dynamic>;
    final paidRows = results[2] as List<dynamic>;

    int count(String key) => (stats[key] as num?)?.toInt() ?? 0;
    double money(String key) => (stats[key] as num?)?.toDouble() ?? 0;

    final weeklyRevenue = List<double>.filled(7, 0);
    final weeklySubscribers = List<int>.filled(7, 0);
    for (final day in (stats['week'] as List?) ?? const []) {
      final index = (day['day'] as num).toInt();
      if (index < 0 || index > 6) continue;
      weeklyRevenue[index] = (day['revenue'] as num).toDouble();
      weeklySubscribers[index] = (day['payments'] as num).toInt();
    }

    return AdminDashboard(
      metrics: AdminMetrics(
        totalUsers: count('total_users'),
        activeUsers: count('active_subscribers'),
        doctors: count('doctors'),
        pharmacies: count('pharmacies'),
        hospitals: count('hospitals'),
        hospitalsUnverified: count('hospitals_unverified'),
        drugs: count('drugs'),
        totalRevenue: money('revenue'),
        paidPayments: count('paid_payments'),
        pendingPayments: count('pending_payments'),
        pendingPaymentsValue: money('pending_value'),
        payoutsToApprove: count('payouts_to_approve'),
        payoutsToApproveValue: money('payouts_to_approve_value'),
        daily: count('daily'),
        weekly: count('weekly'),
        monthly: count('monthly'),
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
      recentTransactions: [
        for (final row in paidRows)
          AdminTransaction(
            id: row['id'] as String,
            name:
                row['phone'] as String? ??
                row['user_id'] as String? ??
                'Payment',
            type: row['plan'] == null
                ? 'Subscription'
                : '${row['plan']} subscription',
            amount: paymentAmount(row),
            status: row['status'] as String? ?? 'paid',
            at: parseDate(row['paid_at']),
          ),
      ],
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
          // toUtc: a local DateTime serialises without an offset, which the
          // database reads as UTC, ending a Nairobi grant three hours early.
          'p_subscription_expires_at': expiresAt?.toUtc().toIso8601String(),
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
      supabase.from('hospitals').select(),
    ]);

    return [
      ...results[0].map(AdminFacility.doctor),
      ...results[1].map(AdminFacility.pharmacy),
      ...results[2].map(AdminFacility.hospital),
    ];
  }

  String _table(FacilityKind kind) => kind.table;

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
