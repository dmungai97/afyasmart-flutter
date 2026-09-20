/// Catalogue models: doctors, drugs, pharmacies.
///
/// Ids are plain ints. The RN services carried a numericId() helper to coerce
/// opaque Firestore document ids into numbers; Postgres identity columns are
/// already numeric, so that is gone.
library;

import 'dart:math' as math;

double _toDouble(Object? value) => switch (value) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s) ?? 0,
  _ => 0,
};

int _toInt(Object? value) => switch (value) {
  final num n => n.toInt(),
  final String s => int.tryParse(s) ?? 0,
  _ => 0,
};

class Doctor {
  const Doctor({
    required this.id,
    required this.name,
    required this.specialization,
    required this.hospital,
    required this.location,
    required this.phone,
    required this.email,
    required this.latitude,
    required this.longitude,
    required this.experienceYears,
    required this.rating,
    required this.availability,
    required this.available,
    this.region,
    this.distanceKm,
  });

  final int id;
  final String name;
  final String specialization;
  final String hospital;
  final String location;
  final String? region;
  final String phone;
  final String email;
  final double latitude;
  final double longitude;
  final int experienceYears;
  final double rating;
  final String availability;
  final bool available;
  final double? distanceKm;

  factory Doctor.fromRow(Map<String, dynamic> row) => Doctor(
    id: _toInt(row['id']),
    name: row['name'] as String? ?? '',
    specialization: row['specialization'] as String? ?? '',
    hospital: row['hospital'] as String? ?? '',
    location: row['location'] as String? ?? '',
    region: row['region'] as String?,
    phone: row['phone'] as String? ?? '',
    email: row['email'] as String? ?? '',
    latitude: _toDouble(row['latitude']),
    longitude: _toDouble(row['longitude']),
    experienceYears: _toInt(row['experience_years']),
    rating: _toDouble(row['rating']),
    availability: row['availability'] as String? ?? '',
    available: row['available'] as bool? ?? false,
  );

  Doctor withDistance(double km) => Doctor(
    id: id,
    name: name,
    specialization: specialization,
    hospital: hospital,
    location: location,
    region: region,
    phone: phone,
    email: email,
    latitude: latitude,
    longitude: longitude,
    experienceYears: experienceYears,
    rating: rating,
    availability: availability,
    available: available,
    distanceKm: km,
  );
}

class Drug {
  const Drug({
    required this.id,
    required this.name,
    required this.genericName,
    required this.category,
    required this.uses,
    required this.dosage,
    required this.sideEffects,
    required this.pregnancySafe,
    required this.alcoholSafe,
    required this.lactationSafe,
    required this.prescriptionRequired,
  });

  final int id;
  final String name;
  final String genericName;
  final String category;
  final String uses;
  final String dosage;
  final String sideEffects;
  final bool pregnancySafe;
  final bool alcoholSafe;
  final bool lactationSafe;
  final String prescriptionRequired;

  factory Drug.fromRow(Map<String, dynamic> row) => Drug(
    id: _toInt(row['id']),
    name: row['name'] as String? ?? '',
    genericName: row['generic_name'] as String? ?? '',
    category: row['category'] as String? ?? 'Other',
    uses: row['uses'] as String? ?? '',
    dosage: row['dosage'] as String? ?? '',
    sideEffects: row['side_effects'] as String? ?? '',
    pregnancySafe: row['pregnancy_safe'] as bool? ?? false,
    alcoholSafe: row['alcohol_safe'] as bool? ?? false,
    lactationSafe: row['lactation_safe'] as bool? ?? false,
    prescriptionRequired: row['prescription_required'] as String? ?? 'Yes',
  );
}

class Pharmacy {
  const Pharmacy({
    required this.id,
    required this.name,
    required this.location,
    required this.address,
    required this.phone,
    required this.latitude,
    required this.longitude,
    required this.openingHours,
    required this.open24hrs,
    required this.open,
    this.email,
  });

  final int id;
  final String name;
  final String location;
  final String address;
  final String phone;
  final String? email;
  final double latitude;
  final double longitude;
  final String openingHours;
  final bool open24hrs;
  final bool open;

  factory Pharmacy.fromRow(Map<String, dynamic> row) => Pharmacy(
    id: _toInt(row['id']),
    name: row['name'] as String? ?? '',
    location: row['location'] as String? ?? '',
    address: row['address'] as String? ?? '',
    phone: row['phone'] as String? ?? '',
    email: row['email'] as String?,
    latitude: _toDouble(row['latitude']),
    longitude: _toDouble(row['longitude']),
    openingHours: row['opening_hours'] as String? ?? '',
    open24hrs: row['open_24hrs'] as bool? ?? false,
    open: row['open'] as bool? ?? false,
  );
}

/// Haversine distance in km, ported from distanceKm() in doctor.service.ts.
double distanceKm(double lat1, double lon1, double lat2, double lon2) {
  double toRad(double value) => value * math.pi / 180;
  const radius = 6371.0;
  final dLat = toRad(lat2 - lat1);
  final dLon = toRad(lon2 - lon1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(toRad(lat1)) *
          math.cos(toRad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}
