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
    await _requireSubscription();

    // Filtering that used to happen in Dart/JS over every row now runs in the
    // query. Only the distance sort stays client-side.
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

    final rows = await query;
    var doctors = rows.map(Doctor.fromRow).toList();

    if (lat != null && lng != null) {
      doctors = doctors
          .map(
            (d) => d.withDistance(
              double.parse(
                distanceKm(lat, lng, d.latitude, d.longitude).toStringAsFixed(1),
              ),
            ),
          )
          .where((d) => radius == null || (d.distanceKm ?? double.infinity) <= radius)
          .toList()
        ..sort((a, b) => (a.distanceKm ?? 0).compareTo(b.distanceKm ?? 0));
    }

    return doctors;
  }

  Future<Doctor> doctor(int id) async {
    await _requireSubscription();

    final row = await supabase
        .from('doctors')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (row == null) throw const ApiException('Doctor not found.');
    return Doctor.fromRow(row);
  }

  /// Distinct filter values for the doctors screen chips.
  ///
  /// These deliberately do NOT require a subscription: the chips render
  /// behind the paywall, before any directory data is fetched. RLS returns an
  /// empty list to exactly the non-subscribers who need them, so an empty
  /// result is expected here rather than an error.
  Future<List<String>> regions() async {
    final rows = await supabase.from('doctors').select('region');
    final values = <String>{};
    for (final row in rows) {
      final region = row['region'] as String?;
      if (region != null && region.isNotEmpty) {
        values.add(region[0].toUpperCase() + region.substring(1));
      }
    }
    return values.toList()..sort();
  }

  Future<List<String>> specializations() async {
    final rows = await supabase.from('doctors').select('specialization');
    final values = <String>{};
    for (final row in rows) {
      final value = row['specialization'] as String?;
      if (value != null && value.isNotEmpty) values.add(value);
    }
    return values.toList()..sort();
  }

  // ── Pharmacies ────────────────────────────────────────────────────────

  Future<List<Pharmacy>> pharmacies({String? search}) async {
    await _requireSubscription();

    var query = supabase.from('pharmacies').select();

    if (search != null && search.trim().isNotEmpty) {
      final term = '%${search.trim()}%';
      query = query.or(
        'name.ilike.$term,location.ilike.$term,address.ilike.$term',
      );
    }

    final rows = await query;
    return rows.map(Pharmacy.fromRow).toList();
  }

  // ── Drugs ─────────────────────────────────────────────────────────────

  Future<List<Drug>> searchDrugs(String query) async {
    await _requireSubscription();

    // This used to fetch every drug and filter in JS. search_drugs() runs the
    // same match server-side against a GIN index, and is not security
    // definer, so the paywall policy still applies to its results.
    final rows = await supabase.rpc('search_drugs', params: {'q': query});
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(Drug.fromRow)
        .toList();
  }

  Future<Drug> drug(int id) async {
    await _requireSubscription();

    final row = await supabase.from('drugs').select().eq('id', id).maybeSingle();
    if (row == null) throw const ApiException('Drug not found.');
    return Drug.fromRow(row);
  }
}
