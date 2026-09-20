import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';
import '../models/admin.dart';
import 'providers.dart';

/// Port of admin/hooks/useAdminDashboard.ts.
///
/// The RN hook carried its own full copy of the aggregation logic,
/// duplicating fetchAdminDashboardData() line for line so the two drifted as
/// either was edited. This calls the service and simply re-runs it when the
/// underlying tables change.
///
/// Firestore's onSnapshot pushed whole result sets, which is why the old hook
/// recomputed from the snapshot; Postgres pushes row-level change events, so
/// the natural shape is "something changed, re-read the aggregate".
class AdminDashboardController extends AsyncNotifier<AdminDashboard> {
  Timer? _debounce;
  RealtimeChannel? _channel;

  @override
  Future<AdminDashboard> build() async {
    _listen();
    ref.onDispose(() {
      _debounce?.cancel();
      final channel = _channel;
      if (channel != null) supabase.removeChannel(channel);
    });

    return ref.read(adminServiceProvider).dashboard();
  }

  void _listen() {
    // Both tables are in the supabase_realtime publication. RLS applies to
    // these streams, so a non-admin subscribing receives nothing.
    _channel = supabase
        .channel('admin-dashboard')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'payment_requests',
          callback: (_) => _scheduleRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'users',
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe();
  }

  /// Coalesces bursts: a single settled M-Pesa payment touches users and
  /// payment_requests within milliseconds.
  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), refresh);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(adminServiceProvider).dashboard(),
    );
  }
}

final adminDashboardProvider =
    AsyncNotifierProvider<AdminDashboardController, AdminDashboard>(
      AdminDashboardController.new,
    );

/// Payout requests, reloaded on demand from the payouts screen.
final adminPayoutsProvider = FutureProvider<List<AdminPayout>>(
  (ref) => ref.watch(adminServiceProvider).payouts(),
);

/// Facilities, reloaded after any add/edit/delete.
final adminFacilitiesProvider = FutureProvider<List<AdminFacility>>(
  (ref) => ref.watch(adminServiceProvider).facilities(),
);
