import '../core/supabase_client.dart';
import '../models/catalogue.dart';
import 'auth_service.dart';

/// Ports of doctor.service.ts, pharmacy.service.ts and drug.service.ts.
///
/// The RN versions carried a bundled seed-data fallback for when a Firestore
/// read came back empty. That fallback is gone here, and deliberately so —
/// see the note on [_requireSubscription]. Screens that want generic data for
/// everyone (the map) get it from a dedicated unauthenticated source rather
/// than from a fallback inside a paywalled query.
class CatalogueService {
  const CatalogueService(this._auth);

  final AuthService _auth;

  /// The paywall gate.
  ///
  /// Firestore rules REJECTED an unauthorised read, so the RN services could
  /// detect permission-denied and let it propagate past their seed-data
  /// fallback. Postgres RLS does not reject — it filters, so a
  /// non-subscriber's query succeeds and returns zero rows, which is
  /// indistinguishable from an empty table.
  ///
  /// So the check is explicit and happens first. The RLS policies
  /// (doctors_select and friends) still enforce it server-side; this only
  /// makes the client fail in a way the screens can show.
  ///
  /// Any new paywalled read needs this too — an empty result will not tell
  /// you anything is wrong.
  Future<void> _requireSubscription() async {
    final user = await _auth.currentProfile();
    if (user == null || !user.isSubscribed) throw const PaywallException();
  }

  /// Runs [query] alongside the [_requireSubscription] check rather than
  /// after it, so a paywalled read costs one round trip instead of two. The
  /// check still decides the outcome: a non-subscriber's query succeeds with
  /// zero rows under RLS, and the PaywallException wins over that result.
  Future<T> _paywalled<T>(Future<T> query) async {
    final results = await Future.wait<Object?>([
      _requireSubscription(),
      query,
    ]);
    return results[1] as T;
  }

  // ── Doctors ───────────────────────────────────────────────────────────

  Future<List<Doctor>> nearbyDoctors({
    String? specialization,
    String? search,
    bool? available,
    String? region,
    double? lat,
    double? lng,
    double? radius,
  }) async {
    var query = supabase.from('doctors').select();

    if (available != null) query = query.eq('available', available);
    if (region != null && region.trim().isNotEmpty) {
      query = query.ilike('region', region.trim());
    }
    if (specialization != null && specialization.trim().isNotEmpty) {
      query = query.ilike('specialization', specialization.trim());
    }
    if (search != null && search.trim().isNotEmpty) {
      final term = '%${search.trim()}%';
      query = query.or(
        'name.ilike.$term,specialization.ilike.$term,'
        'hospital.ilike.$term,location.ilike.$term,region.ilike.$term',
      );
    }

    final rows = await _paywalled(query.order('name'));
    var doctors = rows.map(Doctor.fromRow).toList();

    if (lat != null && lng != null) {
      final withDist = doctors
          .map(
            (d) => d.withDistance(
              double.parse(
                distanceKm(lat, lng, d.latitude, d.longitude).toStringAsFixed(1),
              ),
            ),
          )
          .toList()
        ..sort((a, b) => (a.distanceKm ?? 0).compareTo(b.distanceKm ?? 0));

      doctors = radius == null
          ? withDist
          : withDist
                .where((d) => (d.distanceKm ?? double.infinity) <= radius)
                .toList();
    }

    return doctors;
  }

  /// Distinct filter values for the doctors screen chips.
  ///
  /// These deliberately do NOT require a subscription: the chips render
  /// behind the paywall, before any directory data is fetched. RLS returns an
  /// empty list to exactly the non-subscribers who need them, so an empty
  /// result is expected here rather than an error.
  ///
  /// One request for both chip rows: they come from the same rows.
  Future<({List<String> regions, List<String> specializations})>
  doctorFilters() async {
    final rows = await supabase.from('doctors').select('region, specialization');
    final regions = <String>{};
    final specializations = <String>{};
    for (final row in rows) {
      final region = row['region'] as String?;
      if (region != null && region.isNotEmpty) {
        regions.add(region[0].toUpperCase() + region.substring(1));
      }
      final spec = row['specialization'] as String?;
      if (spec != null && spec.isNotEmpty) specializations.add(spec);
    }
    return (
      regions: regions.toList()..sort(),
      specializations: specializations.toList()..sort(),
    );
  }

  // ── Pharmacies ────────────────────────────────────────────────────────

  Future<List<Pharmacy>> pharmacies({String? search}) async {
    var query = supabase.from('pharmacies').select();

    if (search != null && search.trim().isNotEmpty) {
      final term = '%${search.trim()}%';
      query = query.or(
        'name.ilike.$term,location.ilike.$term,address.ilike.$term',
      );
    }

    final rows = await _paywalled(query.order('name'));
    return rows.map(Pharmacy.fromRow).toList();
  }

  // ── Drugs ─────────────────────────────────────────────────────────────

  Future<List<Drug>> searchDrugs(String query) async {

    // This used to fetch every drug and filter in JS. search_drugs() runs the
    // same match server-side against a GIN index, and is not security
    // definer, so the paywall policy still applies to its results.
    final rows = await _paywalled(
      supabase.rpc<List<dynamic>>('search_drugs', params: {'q': query}),
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(Drug.fromRow)
        .toList();
  }
}
