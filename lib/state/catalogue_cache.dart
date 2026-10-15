import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/catalogue.dart';
import 'auth_controller.dart';

/// Results the catalogue screens have already fetched this session, so going
/// back to a tab shows its last list at once instead of a spinner. The
/// screens still refresh in the background; this only fills the wait.
///
/// Only successful results go in — never a paywall or error state, which
/// must always be re-checked.
class CatalogueCache {
  ({List<String> regions, List<String> specializations})? doctorFilters;
  final doctors = <String, List<Doctor>>{};
  final pharmacies = <String, List<Pharmacy>>{};

  /// Drug searches, keyed on the lower-cased query. Not refreshed on a hit:
  /// a drug label does not change within a session.
  final drugs = <String, ({List<Drug> results, bool fromFda})>{};
}

/// Rebuilt — and so emptied — whenever the signed-in user changes, so one
/// account never sees another's cached results.
final catalogueCacheProvider = Provider<CatalogueCache>((ref) {
  ref.watch(authControllerProvider.select((s) => s.user?.id));
  return CatalogueCache();
});
