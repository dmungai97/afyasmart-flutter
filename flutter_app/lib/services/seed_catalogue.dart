import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/catalogue.dart';

/// The bundled seed catalogue.
///
/// Deliberately separate from CatalogueService: that one is paywalled, this
/// one is free for everyone. The map's "seeded Kenya services" list is meant
/// to be visible without a subscription, so it must not go through a call
/// that raises PaywallException — mirroring fetchSeededDoctors /
/// fetchSeededPharmacies in the RN services, which read the bundled JSON
/// directly for exactly this reason.
///
/// Do not route a paywalled screen through this.
abstract final class SeedCatalogue {
  static List<Doctor>? _doctors;
  static List<Pharmacy>? _pharmacies;

  static Future<List<Doctor>> doctors() async {
    if (_doctors != null) return _doctors!;

    final raw = await rootBundle.loadString('assets/seed/doctors.json');
    final rows = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();

    // The seed JSON has no id field; the RN version indexed from 1 and the
    // ids are only used as list keys here, so the same rule applies.
    return _doctors = [
      for (var i = 0; i < rows.length; i++)
        Doctor.fromRow({...rows[i], 'id': i + 1}),
    ];
  }

  static Future<List<Pharmacy>> pharmacies() async {
    if (_pharmacies != null) return _pharmacies!;

    final raw = await rootBundle.loadString('assets/seed/pharmacies.json');
    final rows = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();

    return _pharmacies = [
      for (var i = 0; i < rows.length; i++)
        Pharmacy.fromRow({...rows[i], 'id': i + 1}),
    ];
  }
}
