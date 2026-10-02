import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' hide Position;
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:url_launcher/url_launcher.dart';

import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../models/catalogue.dart';
import '../../services/seed_catalogue.dart';

/// Mapbox public token, from --dart-define=ACCESS_TOKEN=pk.... Not defaulted
/// in source: GitHub push protection rejects Mapbox tokens in the repo.
const String _mapboxAccessToken = String.fromEnvironment('ACCESS_TOKEN');

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
  MapboxMap? _mapboxMap;
  PointAnnotationManager? _pointAnnotationManager;

  List<Centre> _centres = const [];
  Centre? _selected;
  ({double lat, double lng}) _location = _defaultLocation;

  bool _loading = true;
  bool _permissionDenied = false;
  bool _listView = false;
  bool _useMapbox = true;
  bool _isSearchingArea = false;
  String _activeFilter = 'Care';

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      MapboxOptions.setAccessToken(_mapboxAccessToken);
    }
    _bootstrap();
  }

  @override
  void dispose() {
    _mapboxMap = null;
    super.dispose();
  }

  Future<void> _bootstrap() async {
    var coords = _defaultLocation;
    bool isGranted = false;

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      isGranted = permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
      _permissionDenied = !isGranted;
    } catch (e) {
      debugPrint('Location permission check notice: $e');
      _permissionDenied = true;
    }

    // Step 1: Render facilities immediately (Instant startup < 100ms)
    await _fetchAndMergeFacilities(coords);

    // Step 2: Acquire high-accuracy live GPS in background without blocking screen render
    if (isGranted) {
      _acquireLiveGpsInBackground();
    }
  }

  Future<void> _acquireLiveGpsInBackground() async {
    try {
      final position = await Geolocator.getCurrentPosition().timeout(
        const Duration(seconds: 4),
      );
      final liveCoords = (lat: position.latitude, lng: position.longitude);
      if (mounted &&
          (liveCoords.lat != _location.lat ||
              liveCoords.lng != _location.lng)) {
        await _fetchAndMergeFacilities(liveCoords);
      }
    } catch (e) {
      debugPrint('Background GPS acquire notice: $e');
    }
  }

  Future<void> _fetchAndMergeFacilities(({double lat, double lng}) coords) async {
    final seeded = await _seededCentres();
    final dbCentres = await _supabaseCentres();
    final live = _permissionDenied ? <Centre>[] : await _mapboxCentres(coords);

    final merged = _merge(live, [...dbCentres, ...seeded])
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
      _isSearchingArea = false;
    });

    _updateMapAnnotations();
  }

  Future<List<Centre>> _supabaseCentres() async {
    try {
      final centres = <Centre>[];

      // Query Supabase pharmacies
      final ph = await supabase.from('pharmacies').select();
      for (final p in ph) {
        final lat = (p['latitude'] as num?)?.toDouble() ?? 0.0;
        final lng = (p['longitude'] as num?)?.toDouble() ?? 0.0;
        if (lat != 0.0 && lng != 0.0) {
          centres.add(
            Centre(
              id: 'db-pharmacy-${p['id']}',
              name: p['name'] as String? ?? 'Pharmacy',
              type: CentreType.pharmacy,
              lat: lat,
              lng: lng,
              open: p['open'] as bool? ?? true,
              hours: p['opening_hours'] as String? ?? 'Hours vary',
            ),
          );
        }
      }

      // Query Supabase doctors
      final docs = await supabase.from('doctors').select();
      for (final d in docs) {
        final lat = (d['latitude'] as num?)?.toDouble() ?? 0.0;
        final lng = (d['longitude'] as num?)?.toDouble() ?? 0.0;
        if (lat != 0.0 && lng != 0.0) {
          centres.add(
            Centre(
              id: 'db-doctor-${d['id']}',
              name: d['name'] as String? ?? 'Doctor',
              type: CentreType.doctor,
              lat: lat,
              lng: lng,
              open: d['available'] as bool? ?? true,
              hours: d['availability'] as String? ?? 'Availability varies',
            ),
          );
        }
      }
      return centres;
    } catch (e) {
      debugPrint('Supabase fetch notice: $e');
      return const [];
    }
  }

  Future<List<Centre>> _seededCentres() async {
    final doctors = await SeedCatalogue.doctors();
    final pharmacies = await SeedCatalogue.pharmacies();

    final centres = <Centre>[];
    final seenHospitals = <String>{};

    for (final d in doctors) {
      if (d.latitude != 0 && d.longitude != 0) {
        centres.add(
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
        );

        if (d.hospital.isNotEmpty) {
          final hospKey = d.hospital.toLowerCase().trim();
          if (seenHospitals.add(hospKey)) {
            final isHospital = hospKey.contains('hospital');
            final isClinic = !isHospital ||
                hospKey.contains('clinic') ||
                hospKey.contains('dispensary') ||
                hospKey.contains('medical centre') ||
                hospKey.contains('medical center');
            centres.add(
              Centre(
                id: 'hospital-${d.id}',
                name: d.hospital,
                type: isClinic ? CentreType.clinic : CentreType.hospital,
                lat: d.latitude,
                lng: d.longitude,
                open: true,
                hours: '24/7 Care',
              ),
            );
          }
        }
      }
    }

    for (final p in pharmacies) {
      if (p.latitude != 0 && p.longitude != 0) {
        centres.add(
          Centre(
            id: 'pharmacy-${p.id}',
            name: p.name,
            type: CentreType.pharmacy,
            lat: p.latitude,
            lng: p.longitude,
            open: p.open,
            hours: p.openingHours.isEmpty ? 'Hours vary' : p.openingHours,
          ),
        );
      }
    }

    return centres;
  }

  Future<List<Centre>> _mapboxCentres(({double lat, double lng}) coords) async {
    if (!_useMapbox || _mapboxAccessToken.isEmpty) return const [];

    try {
      final queries = ['clinic', 'hospital', 'pharmacy'];
      final results = <Centre>[];

      for (final q in queries) {
        final uri = Uri.https(
          'api.mapbox.com',
          '/geocoding/v5/mapbox.places/$q.json',
          {
            'access_token': _mapboxAccessToken,
            'proximity': '${coords.lng},${coords.lat}',
            'country': 'KE',
            'types': 'poi',
            'limit': '15',
          },
        );

        final response = await http.get(uri).timeout(const Duration(seconds: 5));
        if (response.statusCode == 401 || response.statusCode == 403) {
          _useMapbox = false;
          break;
        }
        if (response.statusCode != 200) continue;

        final data = jsonDecode(response.body);
        if (data case {'features': final List features}) {
          for (final item in features) {
            if (item case {
              'id': final String id,
              'text': final String name,
              'center': [final num lngNum, final num latNum],
            }) {
              final placeName = '${item['place_name'] ?? ''}';
              results.add(
                Centre(
                  id: 'mapbox-$id',
                  name: name,
                  type: _typeFromName(
                    '$name $placeName',
                    fallback: _typeFromQuery(q),
                  ),
                  lat: latNum.toDouble(),
                  lng: lngNum.toDouble(),
                  open: true,
                  hours: 'Hours unknown',
                ),
              );
            }
          }
        }
      }

      return results;
    } catch (_) {
      _useMapbox = false;
      return const [];
    }
  }

  CentreType _typeFromQuery(String query) {
    if (query == 'pharmacy') return CentreType.pharmacy;
    if (query == 'clinic') return CentreType.clinic;
    return CentreType.hospital;
  }

  CentreType _typeFromName(
    String name, {
    CentreType fallback = CentreType.hospital,
  }) {
    final lower = name.toLowerCase();
    if (lower.contains('pharmac') || lower.contains('chemist')) {
      return CentreType.pharmacy;
    }
    if (lower.contains('clinic')) return CentreType.clinic;
    if (lower.contains('hospital') ||
        lower.contains('dispensary') ||
        lower.contains('health centre') ||
        lower.contains('health center')) {
      return CentreType.hospital;
    }
    return fallback;
  }

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

  Future<void> _updateMapAnnotations() async {
    if (kIsWeb) return;
    final manager = _pointAnnotationManager;
    if (manager == null) return;

    await manager.deleteAll();
    final items = _filtered;

    for (final c in items) {
      final options = PointAnnotationOptions(
        geometry: Point(coordinates: Position(c.lng, c.lat)),
        iconImage: 'marker-15',
        iconSize: 1.5,
        textField: c.name,
        textSize: 11.0,
        textOffset: [0.0, 1.2],
      );
      await manager.create(options);
    }
  }

  Future<void> _refreshCurrentGpsLocation() async {
    setState(() => _isSearchingArea = true);
    try {
      final position = await Geolocator.getCurrentPosition().timeout(
        const Duration(seconds: 6),
      );
      final coords = (lat: position.latitude, lng: position.longitude);
      await _fetchAndMergeFacilities(coords);
    } catch (_) {
      setState(() => _isSearchingArea = false);
    }
  }

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 768;

        return Container(
          color: const Color(0xFFF5F7FA),
          child: Column(
            children: [
              _header(isWide: isWide),
              if (!isWide) _filterRow(),
              if (_permissionDenied) _permissionNotice(),
              Expanded(
                child: isWide
                    ? _wideLayout()
                    : (_listView ? _list() : _map(isWide: false)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _header({required bool isWide}) => Container(
    color: AppColors.brand,
    padding: EdgeInsets.fromLTRB(
      isWide ? 24 : 20,
      MediaQuery.viewPaddingOf(context).top + 14,
      isWide ? 24 : 12,
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
        if (!isWide)
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
              onSelected: (_) {
                setState(() => _activeFilter = f);
                _updateMapAnnotations();
              },
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

  Widget _permissionNotice() => InkWell(
    onTap: () {
      setState(() {
        _loading = true;
        _permissionDenied = false;
      });
      _bootstrap();
    },
    borderRadius: BorderRadius.circular(10),
    child: Container(
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
              'Location is off, so distances are measured from Nairobi. Tap to update.',
              style: TextStyle(fontSize: 11, color: AppPalette.orange),
            ),
          ),
          Icon(Icons.refresh_outlined, size: 14, color: AppPalette.orange),
        ],
      ),
    ),
  );

  Widget _wideLayout() {
    return Row(
      children: [
        SizedBox(
          width: 360,
          child: Column(
            children: [
              _filterRow(),
              Expanded(child: _list()),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: AppPalette.hairline),
        Expanded(
          child: _map(isWide: true),
        ),
      ],
    );
  }

  String _mapboxStaticMapUrl() {
    final centerLng = _selected?.lng ?? _location.lng;
    final centerLat = _selected?.lat ?? _location.lat;
    final zoom = _selected != null ? 14.0 : 12.5;

    final pins = <String>[];

    pins.add('pin-s+007bff(${_location.lng},${_location.lat})');

    for (final c in _filtered.take(15)) {
      final color = switch (c.type) {
        CentreType.hospital => 'e53e3e',
        CentreType.clinic => 'dd6b20',
        CentreType.pharmacy => '38a169',
        CentreType.doctor => '3182ce',
      };
      final pinType = (_selected?.id == c.id) ? 'pin-l' : 'pin-s';
      pins.add('$pinType+$color(${c.lng},${c.lat})');
    }

    final overlay = pins.join(',');
    return 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/$overlay/$centerLng,$centerLat,$zoom/800x500@2x?access_token=$_mapboxAccessToken';
  }

  Widget _webMapFallback(List<Centre> items) {
    final bottomOffset = (items.isNotEmpty && _selected == null) ? 120.0 : 0.0;
    return Container(
      color: const Color(0xFFE2E8F0),
      padding: EdgeInsets.only(bottom: bottomOffset),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.brand.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_on_outlined,
                size: 36,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${items.length} Health Services Found',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppPalette.textStrong,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Select a facility below or switch to List View',
              style: TextStyle(
                fontSize: 12,
                color: AppPalette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _webMap({required bool isWide}) {
    final items = _filtered;
    return Stack(
      children: [
        Positioned.fill(
          child: _useMapbox
              ? Image.network(
                  _mapboxStaticMapUrl(),
                  fit: BoxFit.cover,
                  frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                    if (wasSynchronouslyLoaded || frame != null) {
                      return child;
                    }
                    return AnimatedOpacity(
                      opacity: frame == null ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      child: child,
                    );
                  },
                  errorBuilder: (_, _, _) => _webMapFallback(items),
                )
              : _webMapFallback(items),
        ),
        // Search & Location Action Bar
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(color: Color(0x1A000000), blurRadius: 8),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.map_outlined, size: 18, color: AppColors.brand),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${items.length} health services found near you',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.textStrong,
                          ),
                        ),
                      ),
                      if (_isSearchingArea)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.brand,
                          ),
                        )
                      else
                        InkWell(
                          onTap: () => _fetchAndMergeFacilities(_location),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              children: [
                                Icon(Icons.refresh, size: 15, color: AppColors.brand),
                                SizedBox(width: 4),
                                Text(
                                  'Refresh',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.brand,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FloatingActionButton.small(
                heroTag: 'myLocationWeb',
                elevation: 3,
                backgroundColor: Colors.white,
                foregroundColor: AppColors.brand,
                onPressed: _refreshCurrentGpsLocation,
                child: const Icon(Icons.my_location, size: 18),
              ),
            ],
          ),
        ),
        if (_selected != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _selectedCard(_selected!),
                ),
              ),
            ),
          )
        else if (items.isNotEmpty && !isWide)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SizedBox(
              height: 110,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final c = items[i];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () => setState(() => _selected = c),
                      child: Container(
                        width: 220,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppPalette.hairline),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppPalette.textStrong,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${c.typeLabel} · ${c.distanceKm ?? 0} km away',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppPalette.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _map({required bool isWide}) {
    if (kIsWeb) {
      return _webMap(isWide: isWide);
    }

    final cameraOptions = CameraOptions(
      center: Point(coordinates: Position(_location.lng, _location.lat)),
      zoom: 12.0,
    );

    return Stack(
      children: [
        MapWidget(
          key: const ValueKey('mapboxMap'),
          cameraOptions: cameraOptions,
          styleUri: MapboxStyles.MAPBOX_STREETS,
          onMapCreated: (mapboxMap) async {
            _mapboxMap = mapboxMap;
            _pointAnnotationManager =
                await mapboxMap.annotations.createPointAnnotationManager();
            _updateMapAnnotations();
          },
        ),
        Positioned(
          top: 12,
          right: 12,
          child: FloatingActionButton.small(
            heroTag: 'myLocationNative',
            elevation: 3,
            backgroundColor: Colors.white,
            foregroundColor: AppColors.brand,
            onPressed: _refreshCurrentGpsLocation,
            child: const Icon(Icons.my_location, size: 18),
          ),
        ),
        if (_selected != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _selectedCard(_selected!),
                ),
              ),
            ),
          ),
      ],
    );
  }

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
      mainAxisSize: MainAxisSize.min,
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
        final isSelected = _selected?.id == c.id;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: isSelected
                ? AppColors.brand.withValues(alpha: 0.05)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isSelected ? AppColors.brand : AppPalette.hairline,
                  width: isSelected ? 1.5 : 1.0,
                ),
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
              onTap: () {
                setState(() => _selected = c);
                if (_mapboxMap != null) {
                  _mapboxMap?.setCamera(
                    CameraOptions(
                      center: Point(
                        coordinates: Position(c.lng, c.lat),
                      ),
                      zoom: 14.0,
                    ),
                  );
                }
              },
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
