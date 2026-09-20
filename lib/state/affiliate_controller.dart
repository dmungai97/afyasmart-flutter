import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/affiliate_service.dart';
import 'providers.dart';

/// Port of the zustand store inside affiliate/services/affiliate.service.ts.
///
/// The RN version mixed the store and the data access in one file; here the
/// service does the querying and this only holds state, so the service can be
/// swapped for a fake in tests.
class AffiliateController extends AsyncNotifier<AffiliateSummary> {
  @override
  Future<AffiliateSummary> build() =>
      ref.watch(affiliateServiceProvider).load();

  Future<void> reload() async {
    // Deliberately does NOT set AsyncValue.loading() first.
    //
    // AffiliateShell gates the whole tab UI on this value, so flipping to
    // loading would unmount the tabs and replace them with a full-screen
    // spinner on every pull-to-refresh, every enrollment and every payout —
    // the content would visibly disappear and come back. Keeping the previous
    // value means the screens stay on screen while the reload runs.
    state = await AsyncValue.guard(
      () => ref.read(affiliateServiceProvider).load(),
    );
  }

  /// Claims a referral code and reloads. Returns an error message, or null on
  /// success — the screens show it in an alert rather than an error state,
  /// since the rest of the page is still valid.
  Future<String?> enroll() async {
    try {
      await ref.read(affiliateServiceProvider).enroll();
      await reload();
      return null;
    } on Exception catch (e) {
      return e.toString();
    }
  }

  Future<String?> requestPayout({
    required double amount,
    required String phone,
  }) async {
    final current = state.value;
    if (current == null) return 'Your affiliate account is still loading.';

    try {
      await ref
          .read(affiliateServiceProvider)
          .requestPayout(
            amount: amount,
            phone: phone,
            availableBalance: current.availableBalance,
          );
      await reload();
      return null;
    } on Exception catch (e) {
      return e.toString();
    }
  }
}

final affiliateControllerProvider =
    AsyncNotifierProvider<AffiliateController, AffiliateSummary>(
      AffiliateController.new,
    );
