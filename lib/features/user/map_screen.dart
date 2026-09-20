import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../models/catalogue.dart';
import '../../services/seed_catalogue.dart';

/// Port of src/user/screens/MapScreen.tsx.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

enum CentreType { hospital, clinic, pharmacy, doctor }

class Centre {
  const Centre({
    required this.id,
    required this.name,
    required this.type,
    required this.lat,
    required this.lng,
    required this.open,
    required this.hours,
    this.distanceKm,
  });

  final String id;
  final String name;
  final CentreType type;
  final double lat;
  final double lng;
  final bool open;
  final String hours;
  final double? distanceKm;

  Centre withDistance(double km) => Centre(
    id: id,
    name: name,
    type: type,
    lat: lat,
    lng: lng,
    open: open,
    hours: hours,
    distanceKm: km,
  );

  String get typeLabel => switch (type) {
    CentreType.hospital => 'Hospital',
    CentreType.clinic => 'Clinic',
    CentreType.pharmacy => 'Pharmacy',
    CentreType.doctor => 'Doctor',
  };
}

/// Nairobi. Used when location permission is refused, so the map still shows
/// something useful rather than an empty grey plane.
const _defaultLocation = (lat: -1.286389, lng: 36.817223);

const _filters = ['Care', 'Pharmacies', 'Doctors', 'Hospitals', 'Clinics', 'All'];

class _MapScreenState extends ConsumerState<MapScreen> {
  GoogleMapController? _controller;

  List<Centre> _centres = const [];
  Centre? _selected;
  ({double lat, double lng}) _location = _defaultLocation;

  bool _loading = true;
  bool _permissionDenied = false;
  bool _listView = false;
  String _activeFilter = 'Care';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    var coords = _defaultLocation;

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _permissionDenied = true;
      } else {
        final position = await Geolocator.getCurrentPosition();
        coords = (lat: position.latitude, lng: position.longitude);
      }
    } on Exception {
      _permissionDenied = true;
    }

    // The seeded list is always loaded — it is free for everyone and is what
    // makes this screen useful without a subscription. OSM results are a
    // bonus layered on top when the network cooperates.
    final seeded = await _seededCentres();
    final live = _permissionDenied ? <Centre>[] : await _nominatimCentres(coords);

    final merged = _merge(live, seeded)
        .map(
          (c) => c.withDistance(
            double.parse(
              distanceKm(coords.lat, coords.lng, c.lat, c.lng).toStringAsFixed(1),
            ),
          ),
        )
        .toList()
      ..sort((a, b) => (a.distanceKm ?? 0).compareTo(b.distanceKm ?? 0));

    if (!mounted) return;
    setState(() {
      _location = coords;
      _centres = merged;
      _loading = false;
    });
  }

  Future<List<Centre>> _seededCentres() async {
    final doctors = await SeedCatalogue.doctors();
    final pharmacies = await SeedCatalogue.pharmacies();

    return [
      for (final d in doctors)
        if (d.latitude != 0 && d.longitude != 0)
          Centre(
            id: 'doctor-${d.id}',
            name: d.name,
            type: CentreType.doctor,
            lat: d.latitude,
            lng: d.longitude,
            open: d.available,
            hours: d.availability.isEmpty
                ? 'Availability varies'
                : d.availability,
          ),
      for (final p in pharmacies)
        if (p.latitude != 0 && p.longitude != 0)
          Centre(
            id: 'pharmacy-${p.id}',
            name: p.name,
            type: CentreType.pharmacy,
            lat: p.latitude,
            lng: p.longitude,
            open: p.open,
            hours: p.openingHours.isEmpty ? 'Hours vary' : p.openingHours,
          ),
    ];
  }

  /// Nominatim (OpenStreetMap) lookup for nearby facilities. Best-effort: any
  /// failure just means the seeded list stands alone.
  Future<List<Centre>> _nominatimCentres(({double lat, double lng}) coords) async {
    try {
      const delta = 0.12;
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'json',
        'q': 'hospital clinic pharmacy',
        'limit': '40',
        'bounded': '1',
        'viewbox': [
          coords.lng - delta,
          coords.lat + delta,
          coords.lng + delta,
          coords.lat - delta,
        ].join(','),
      });

      final response = await http
          .get(uri, headers: {'User-Agent': 'AfyaSmart/1.0'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return const [];

      final rows = jsonDecode(response.body) as List;
      return [
        for (final row in rows)
          if (row case final Map<String, dynamic> r)
            if (double.tryParse('${r['lat']}') case final lat?)
              if (double.tryParse('${r['lon']}') case final lng?)
                Centre(
                  id: 'osm-${r['place_id']}',
                  name: (r['display_name'] as String?)?.split(',').first ?? 'Health centre',
                  type: _typeFromName('${r['display_name']}'),
                  lat: lat,
                  lng: lng,
                  open: true,
                  hours: 'Hours unknown',
                ),
      ];
    } on Exception {
      return const [];
    }
  }

  CentreType _typeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('pharmac') || lower.contains('chemist')) {
      return CentreType.pharmacy;
    }
    if (lower.contains('clinic')) return CentreType.clinic;
    return CentreType.hospital;
  }

  /// Drops duplicates between the live and seeded lists by name + rounded
  /// position, keeping the live entry.
  List<Centre> _merge(List<Centre> primary, List<Centre> fallback) {
    final seen = <String>{};
    return [
      for (final c in [...primary, ...fallback])
        if (seen.add(
          '${c.name.toLowerCase()}-'
          '${c.lat.toStringAsFixed(4)}-${c.lng.toStringAsFixed(4)}',
        ))
          c,
    ];
  }

  List<Centre> get _filtered => switch (_activeFilter) {
    'All' => _centres,
    'Care' => _centres
        .where(
          (c) => c.type == CentreType.hospital || c.type == CentreType.clinic,
        )
        .toList(),
    'Pharmacies' =>
      _centres.where((c) => c.type == CentreType.pharmacy).toList(),
    'Doctors' => _centres.where((c) => c.type == CentreType.doctor).toList(),
    'Hospitals' =>
      _centres.where((c) => c.type == CentreType.hospital).toList(),
    'Clinics' => _centres.where((c) => c.type == CentreType.clinic).toList(),
    _ => _centres,
  };

  int _countFor(String filter) {
    final saved = _activeFilter;
    _activeFilter = filter;
    final count = _filtered.length;
    _activeFilter = saved;
    return count;
  }

  double _hueFor(CentreType type) => switch (type) {
    CentreType.hospital => BitmapDescriptor.hueRed,
    CentreType.clinic => BitmapDescriptor.hueOrange,
    CentreType.pharmacy => BitmapDescriptor.hueGreen,
    CentreType.doctor => BitmapDescriptor.hueAzure,
  };

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        color: const Color(0xFFF5F7FA),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.brand),
              SizedBox(height: 16),
              Text(
                'Finding centres near you…',
                style: TextStyle(fontSize: 13, color: AppPalette.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFFF5F7FA),
      child: Column(
        children: [
          _header(),
          _filterRow(),
          if (_permissionDenied) _permissionNotice(),
          Expanded(child: _listView ? _list() : _map()),
        ],
      ),
    );
  }

  Widget _header() => Container(
    color: AppColors.brand,
    padding: EdgeInsets.fromLTRB(
      20,
      MediaQuery.viewPaddingOf(context).top + 14,
      12,
      12,
    ),
    child: Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nearby Health Services',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Hospitals, clinics, pharmacies and doctors',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => setState(() => _listView = !_listView),
          icon: Icon(
            _listView ? Icons.map_outlined : Icons.list,
            color: Colors.white,
          ),
          tooltip: _listView ? 'Map view' : 'List view',
        ),
      ],
    ),
  );

  Widget _filterRow() => SizedBox(
    height: 48,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        for (final f in _filters)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text('$f (${_countFor(f)})'),
              selected: _activeFilter == f,
              onSelected: (_) => setState(() => _activeFilter = f),
              selectedColor: AppColors.brand,
              backgroundColor: Colors.white,
              side: const BorderSide(color: AppPalette.hairline),
              showCheckmark: false,
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _activeFilter == f ? Colors.white : AppPalette.textBody,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _permissionNotice() => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: AppPalette.orangeBg,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Row(
      children: [
        Icon(Icons.info_outline, size: 15, color: AppPalette.orange),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Location is off, so distances are measured from Nairobi.',
            style: TextStyle(fontSize: 11, color: AppPalette.orange),
          ),
        ),
      ],
    ),
  );

  Widget _map() => Stack(
    children: [
      GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(_location.lat, _location.lng),
          zoom: 12,
        ),
        onMapCreated: (c) => _controller = c,
        myLocationEnabled: !_permissionDenied,
        myLocationButtonEnabled: !_permissionDenied,
        markers: {
          for (final c in _filtered)
            Marker(
              markerId: MarkerId(c.id),
              position: LatLng(c.lat, c.lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(_hueFor(c.type)),
              onTap: () => setState(() => _selected = c),
            ),
        },
      ),
      if (_selected != null)
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: _selectedCard(_selected!),
        ),
    ],
  );

  Widget _selectedCard(Centre c) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppPalette.hairline),
      boxShadow: const [
        BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4)),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                c.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textStrong,
                ),
              ),
            ),
            IconButton(
              onPressed: () => setState(() => _selected = null),
              icon: const Icon(Icons.close, size: 18),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        Text(
          '${c.typeLabel} · ${c.hours}',
          style: const TextStyle(fontSize: 12, color: AppPalette.textMuted),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _openDirections(c),
          icon: const Icon(Icons.directions, size: 17),
          label: Text(
            c.distanceKm == null
                ? 'Directions'
                : 'Directions · ${c.distanceKm} km',
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brand,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _list() {
    final items = _filtered;
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'No centres match this filter.',
          style: TextStyle(fontSize: 13, color: AppPalette.textMuted),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final c = items[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppPalette.hairline),
              ),
              leading: CircleAvatar(
                backgroundColor: AppColors.brand.withValues(alpha: 0.1),
                child: Icon(
                  switch (c.type) {
                    CentreType.pharmacy => Icons.local_pharmacy_outlined,
                    CentreType.doctor => Icons.person_outline,
                    CentreType.clinic => Icons.medical_services_outlined,
                    CentreType.hospital => Icons.local_hospital_outlined,
                  },
                  size: 20,
                  color: AppColors.brand,
                ),
              ),
              title: Text(
                c.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.textStrong,
                ),
              ),
              subtitle: Text(
                '${c.typeLabel} · ${c.hours}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppPalette.textMuted,
                ),
              ),
              trailing: Text(
                c.distanceKm == null ? '' : '${c.distanceKm} km',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brand,
                ),
              ),
              onTap: () => _openDirections(c),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openDirections(Centre c) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${c.lat},${c.lng}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open directions.')),
      );
    }
  }
}
