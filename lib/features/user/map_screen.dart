import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' hide Position;
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../models/catalogue.dart';

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
    this.phone,
    this.distanceKm,
  });

  final String id;
  final String name;
  final CentreType type;
  final double lat;
  final double lng;
  final bool open;
  final String hours;

  /// For the Call button. Null when unknown, e.g. a Mapbox place.
  final String? phone;
  final double? distanceKm;

  Centre withDistance(double km) => Centre(
    id: id,
    name: name,
    type: type,
    lat: lat,
    lng: lng,
    open: open,
    hours: hours,
    phone: phone,
    distanceKm: km,
  );

  String get typeLabel => switch (type) {
    CentreType.hospital => 'Hospital',
    CentreType.clinic => 'Clinic',
    CentreType.pharmacy => 'Pharmacy',
    CentreType.doctor => 'Doctor',
  };

  /// Marker colour as 0xRRGGBB, shared by the native pins and the web
  /// static map so both read the same.
  int get pinColor => switch (type) {
    CentreType.hospital => 0xE53E3E,
    CentreType.clinic => 0xDD6B20,
    CentreType.pharmacy => 0x38A169,
    CentreType.doctor => 0x3182CE,
  };
}

/// Draws a map pin as PNG bytes for a PointAnnotation.
///
/// The RN app used the `marker-15` sprite, but that Maki icon is not in the
/// Streets v12 style's sprite sheet, so it rendered as a bare black marker.
/// Drawing the pin ourselves removes the dependency on the style's sprites.
/// [pixelRatio] keeps it crisp: Mapbox shows the bitmap at its pixel size
/// divided by the screen density.
Future<Uint8List> _drawPin(int rgb, double pixelRatio) async {
  const width = 28.0;
  const height = 38.0;
  const cx = width / 2;
  const cy = 13.0;
  const r = 11.0;
  const tipY = height - 1.5;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(pixelRatio);

  final pin = Path()
    ..moveTo(cx, tipY)
    ..cubicTo(cx - r * 0.4, tipY - r * 0.9, cx - r, cy + r * 0.6, cx - r, cy)
    ..arcToPoint(const Offset(cx + r, cy), radius: const Radius.circular(r))
    ..cubicTo(cx + r, cy + r * 0.6, cx + r * 0.4, tipY - r * 0.9, cx, tipY)
    ..close();

  canvas
    ..drawShadow(pin, Colors.black, 1.5, false)
    ..drawPath(pin, Paint()..color = Color(0xFF000000 | rgb))
    ..drawPath(
      pin,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    )
    ..drawCircle(const Offset(cx, cy), r * 0.4, Paint()..color = Colors.white);

  final image = await recorder.endRecording().toImage(
    (width * pixelRatio).ceil(),
    (height * pixelRatio).ceil(),
  );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}

/// Nairobi. Used when location permission is refused, so the map still shows
/// something useful rather than an empty grey plane.
const _defaultLocation = (lat: -1.286389, lng: 36.817223);

const _filters = ['All', 'Hospitals & clinics', 'Pharmacies', 'Doctors'];

class _MapScreenState extends ConsumerState<MapScreen> {
  MapboxMap? _mapboxMap;
  PointAnnotationManager? _pointAnnotationManager;

  /// One pin bitmap per colour, drawn on first use.
  final Map<int, Uint8List> _pinImages = {};

  /// Pin annotation id to the place it marks, for pin taps.
  final Map<String, Centre> _pinPlaces = {};
  Cancelable? _pinTaps;

  List<Centre> _centres = const [];
  Centre? _selected;
  ({double lat, double lng}) _location = _defaultLocation;

  bool _loading = true;
  bool _permissionDenied = false;
  bool _listView = false;
  bool _useMapbox = true;
  bool _isSearchingArea = false;
  String _activeFilter = 'All';

  /// Why places (our database, Mapbox) could not be loaded. Null when
  /// everything loaded.
  String? _liveError;

  /// See _loadSeq on the doctors screen: the startup load, the background
  /// GPS fix and a manual refresh can overlap, and only the newest may land.
  int _fetchSeq = 0;

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
    _pinTaps?.cancel();
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

      isGranted =
          permission == LocationPermission.whileInUse ||
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

  List<Centre> _withDistances(
    List<Centre> centres,
    ({double lat, double lng}) coords,
  ) =>
      centres
          .map(
            (c) => c.withDistance(
              double.parse(
                distanceKm(
                  coords.lat,
                  coords.lng,
                  c.lat,
                  c.lng,
                ).toStringAsFixed(1),
              ),
            ),
          )
          .toList()
        ..sort((a, b) => (a.distanceKm ?? 0).compareTo(b.distanceKm ?? 0));

  Future<void> _fetchAndMergeFacilities(
    ({double lat, double lng}) coords,
  ) async {
    final seq = ++_fetchSeq;

    final results = await Future.wait([
      _supabaseCentres(),
      if (!_permissionDenied) _mapboxCentres(coords),
    ]);
    final dbCentres = results[0].centres;
    final live = results.length > 1 ? results[1].centres : const <Centre>[];
    final error = results.map((r) => r.error).nonNulls.firstOrNull;

    final merged = _withDistances(_merge(live, dbCentres), coords);

    if (!mounted || seq != _fetchSeq) return;
    setState(() {
      _location = coords;
      _centres = merged;
      _loading = false;
      _isSearchingArea = false;
      _liveError = error == null
          ? null
          : isNetworkError(error)
          ? 'You are offline, so nearby places could not be loaded. Tap to retry.'
          : 'Some nearby places could not be loaded. Tap to retry.';
    });

    _updateMapAnnotations();
  }

  /// Doctors and pharmacies from our database. A non-subscriber gets no rows
  /// under RLS, which is expected rather than a failure; Mapbox places still
  /// show. There used to be a bundled list as well, but its doctors were
  /// invented (placeholder phone numbers, emails on real hospitals' domains),
  /// so the map now shows only places that exist.
  Future<({List<Centre> centres, Object? error})> _supabaseCentres() async {
    try {
      final centres = <Centre>[];
      // Hospitals are open to every signed-in user (only verified rows come
      // back); doctors and pharmacies return nothing to a non-subscriber.
      final rows = await Future.wait([
        supabase.from('pharmacies').select(),
        supabase.from('doctors').select(),
        supabase.from('hospitals').select().eq('verified', true),
      ]);
      final ph = rows[0];
      final docs = rows[1];

      for (final h in rows[2]) {
        final lat = (h['latitude'] as num?)?.toDouble() ?? 0.0;
        final lng = (h['longitude'] as num?)?.toDouble() ?? 0.0;
        if (lat != 0.0 && lng != 0.0) {
          centres.add(
            Centre(
              id: 'db-hospital-${h['id']}',
              name: h['name'] as String? ?? 'Hospital',
              type: CentreType.hospital,
              lat: lat,
              lng: lng,
              open: true,
              hours: h['open_24hrs'] as bool? ?? true
                  ? 'Open 24 hours'
                  : 'Hours vary',
              phone: h['phone'] as String?,
            ),
          );
        }
      }

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
              phone: p['phone'] as String?,
            ),
          );
        }
      }

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
              phone: d['phone'] as String?,
            ),
          );
        }
      }
      return (centres: centres, error: null);
    } on Exception catch (e) {
      debugPrint('Supabase fetch failed: $e');
      return (centres: const <Centre>[], error: e);
    }
  }

  /// Nearby places from Mapbox search. Only a rejected token turns Mapbox
  /// off for the session; a network failure is reported and retried next
  /// time, rather than hiding live places until the app restarts.
  Future<({List<Centre> centres, Object? error})> _mapboxCentres(
    ({double lat, double lng}) coords,
  ) async {
    if (!_useMapbox || _mapboxAccessToken.isEmpty) {
      return (centres: const <Centre>[], error: null);
    }

    Future<List<Centre>> search(String q) async {
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

      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 401 || response.statusCode == 403) {
        _useMapbox = false;
        return const [];
      }
      if (response.statusCode != 200) {
        throw ApiException('Mapbox search failed (${response.statusCode}).');
      }

      final results = <Centre>[];
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
      return results;
    }

    // The three searches are independent, so they run together, and one
    // failing still keeps the others' results.
    final results = <Centre>[];
    Object? error;
    await Future.wait([
      for (final q in const ['clinic', 'hospital', 'pharmacy'])
        search(q).then(results.addAll).catchError((Object e) {
          debugPrint('Mapbox $q search failed: $e');
          error ??= e;
        }),
    ]);
    return (centres: results, error: error);
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

  List<Centre> _filteredBy(String filter) => switch (filter) {
    'Hospitals & clinics' =>
      _centres
          .where(
            (c) => c.type == CentreType.hospital || c.type == CentreType.clinic,
          )
          .toList(),
    'Pharmacies' =>
      _centres.where((c) => c.type == CentreType.pharmacy).toList(),
    'Doctors' => _centres.where((c) => c.type == CentreType.doctor).toList(),
    _ => _centres,
  };

  List<Centre> get _filtered => _filteredBy(_activeFilter);

  Future<void> _updateMapAnnotations() async {
    if (kIsWeb) return;
    final manager = _pointAnnotationManager;
    if (manager == null) return;

    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final items = _filtered;
    final options = <PointAnnotationOptions>[];

    for (final c in items) {
      final image = _pinImages[c.pinColor] ??= await _drawPin(
        c.pinColor,
        pixelRatio,
      );
      options.add(
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(c.lng, c.lat)),
          image: image,
          iconAnchor: IconAnchor.BOTTOM,
          textField: c.name,
          textSize: 12.0,
          textOffset: [0.0, 0.4],
          textAnchor: TextAnchor.TOP,
          textHaloColor: Colors.white.toARGB32(),
          textHaloWidth: 1.2,
        ),
      );
    }

    await manager.deleteAll();
    final created = await manager.createMulti(options);
    // Remember which pin is which place, so a tap on a pin can open it.
    _pinPlaces
      ..clear()
      ..addAll({
        for (var i = 0; i < created.length; i++)
          if (created[i] != null) created[i]!.id: items[i],
      });
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
      if (!mounted) return;
      setState(() => _isSearchingArea = false);
      // It used to fail silently, which looked like a broken button.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not find your location. Check that location is on.',
          ),
        ),
      );
    }
  }

  /// Opens [c]: its card at the bottom, the map moved onto it. From the list
  /// this also switches to the map, which used to stay on the list.
  void _focus(Centre c) {
    final wasMap = !_listView;
    setState(() {
      _selected = c;
      _listView = false;
    });
    if (wasMap) {
      _mapboxMap?.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(c.lng, c.lat)),
          zoom: 14.5,
        ),
        MapAnimationOptions(duration: 600),
      );
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
                'Finding places near you…',
                style: TextStyle(fontSize: 14, color: AppPalette.textMuted),
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
              if (_liveError != null) _liveErrorNotice(),
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
      isWide ? 24 : 8,
      10,
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nearby Health Services',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${_filtered.length} '
                '${_filtered.length == 1 ? 'place' : 'places'}'
                '${_permissionDenied ? ' around Nairobi' : ' near you'}',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
        // A labelled switch: the bare list icon was easy to miss, and it was
        // the only way to browse places on a phone.
        if (!isWide)
          TextButton.icon(
            onPressed: () => setState(() => _listView = !_listView),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            icon: Icon(
              _listView ? Icons.map_outlined : Icons.view_list_outlined,
              size: 20,
            ),
            label: Text(_listView ? 'Map' : 'List'),
          ),
      ],
    ),
  );

  /// All, plus the categories that have something in them. Six overlapping
  /// chips ("Care", "Hospitals", "Clinics", "All"...) and empty "(0)" ones
  /// became four, with empty ones hidden.
  Widget _filterRow() {
    final visible = [
      for (final f in _filters)
        if (f == 'All' || f == _activeFilter || _filteredBy(f).isNotEmpty) f,
    ];

    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          for (final f in visible)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('$f (${_filteredBy(f).length})'),
                selected: _activeFilter == f,
                onSelected: (_) {
                  setState(() {
                    _activeFilter = f;
                    if (_selected != null && !_filtered.contains(_selected)) {
                      _selected = null;
                    }
                  });
                  _updateMapAnnotations();
                },
                selectedColor: AppColors.brand,
                backgroundColor: Colors.white,
                side: const BorderSide(color: AppPalette.hairline),
                showCheckmark: false,
                labelStyle: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _activeFilter == f
                      ? Colors.white
                      : AppPalette.textBody,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _notice({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Material(
      color: AppPalette.orangeBg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppPalette.textStrong),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppPalette.textStrong,
                    height: 1.35,
                  ),
                ),
              ),
              const Icon(
                Icons.refresh_outlined,
                size: 18,
                color: AppPalette.textStrong,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _permissionNotice() => _notice(
    icon: Icons.location_off_outlined,
    text:
        'Location is off, so distances are from central Nairobi. '
        'Tap to use your location.',
    onTap: () {
      setState(() {
        _loading = true;
        _permissionDenied = false;
      });
      _bootstrap();
    },
  );

  Widget _liveErrorNotice() => _notice(
    icon: Icons.cloud_off_outlined,
    text: _liveError!,
    onTap: () {
      setState(() => _liveError = null);
      _fetchAndMergeFacilities(_location);
    },
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
        Expanded(child: _map(isWide: true)),
      ],
    );
  }

  String _mapboxStaticMapUrl() {
    final centerLng = _selected?.lng ?? _location.lng;
    final centerLat = _selected?.lat ?? _location.lat;
    final zoom = _selected != null ? 14.0 : 12.5;

    final pins = <String>['pin-s+007bff(${_location.lng},${_location.lat})'];
    for (final c in _filtered.take(15)) {
      final color = c.pinColor.toRadixString(16).padLeft(6, '0');
      final pinType = (_selected?.id == c.id) ? 'pin-l' : 'pin-s';
      pins.add('$pinType+$color(${c.lng},${c.lat})');
    }

    return 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/'
        '${pins.join(',')}/$centerLng,$centerLat,$zoom/800x800@2x'
        '?access_token=$_mapboxAccessToken';
  }

  Widget _webMapFallback() => Container(
    color: const Color(0xFFE2E8F0),
    alignment: Alignment.center,
    child: const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.map_outlined, size: 36, color: AppColors.brand),
        SizedBox(height: 8),
        Text(
          'The map could not load. Pick a place below.',
          style: TextStyle(fontSize: 14, color: AppPalette.textMuted),
        ),
      ],
    ),
  );

  /// The map itself: Mapbox on a phone, a static image on the web, where
  /// the native SDK does not run.
  Widget _mapSurface() {
    if (kIsWeb) {
      return _useMapbox
          ? Image.network(
              _mapboxStaticMapUrl(),
              key: ValueKey(_mapboxStaticMapUrl()),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _webMapFallback(),
            )
          : _webMapFallback();
    }

    final focus = _selected;
    return MapWidget(
      key: const ValueKey('mapboxMap'),
      cameraOptions: CameraOptions(
        center: Point(
          coordinates: Position(
            focus?.lng ?? _location.lng,
            focus?.lat ?? _location.lat,
          ),
        ),
        zoom: focus == null ? 12.0 : 14.5,
      ),
      styleUri: MapboxStyles.MAPBOX_STREETS,
      onMapCreated: (mapboxMap) async {
        _mapboxMap = mapboxMap;
        _pinTaps?.cancel();
        final manager = await mapboxMap.annotations
            .createPointAnnotationManager();
        _pointAnnotationManager = manager;
        // Pins used to do nothing when tapped.
        _pinTaps = manager.tapEvents(
          onTap: (annotation) {
            final place = _pinPlaces[annotation.id];
            if (place != null) _focus(place);
          },
        );
        _updateMapAnnotations();
      },
    );
  }

  Widget _map({required bool isWide}) {
    final items = _filtered;
    final selected = _selected;

    return Stack(
      children: [
        Positioned.fill(child: _mapSurface()),
        // Corner controls only: the full-width "18 health services found"
        // bar used to sit over the top of the map and hide pins.
        Positioned(
          top: 12,
          right: 12,
          child: Column(
            children: [
              _mapButton(
                icon: Icons.my_location,
                tooltip: 'Use my location',
                onPressed: _refreshCurrentGpsLocation,
                busy: _isSearchingArea,
              ),
              const SizedBox(height: 8),
              _mapButton(
                icon: Icons.refresh,
                tooltip: 'Refresh places',
                onPressed: () => _fetchAndMergeFacilities(_location),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 12,
          child: selected != null
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: _selectedCard(selected),
                    ),
                  ),
                )
              : (items.isEmpty || isWide)
              ? const SizedBox.shrink()
              : _carousel(items),
        ),
      ],
    );
  }

  Widget _mapButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool busy = false,
  }) => Material(
    color: Colors.white,
    shape: const CircleBorder(),
    elevation: 3,
    child: IconButton(
      onPressed: busy ? null : onPressed,
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.brand,
              ),
            )
          : Icon(icon, size: 22, color: AppColors.brand),
    ),
  );

  /// Nearest first, swipe for more, tap to open. It was web-only, so on a
  /// phone the only way to browse was finding the list icon.
  Widget _carousel(List<Centre> items) => SizedBox(
    height: 88,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (_, i) {
        final c = items[i];
        return SizedBox(
          width: 260,
          child: Material(
            color: Colors.white,
            elevation: 2,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: () => _focus(c),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    _typeIcon(c),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.textStrong,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _summary(c),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppPalette.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  static String _summary(Centre c) =>
      [c.typeLabel, if (c.distanceKm != null) '${c.distanceKm} km'].join(' · ');

  Widget _typeIcon(Centre c) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: Color(0x1F000000 | c.pinColor),
      shape: BoxShape.circle,
    ),
    child: Icon(
      switch (c.type) {
        CentreType.pharmacy => Icons.local_pharmacy_outlined,
        CentreType.doctor => Icons.person_outline,
        CentreType.clinic => Icons.medical_services_outlined,
        CentreType.hospital => Icons.local_hospital_outlined,
      },
      size: 22,
      color: Color(0xFF000000 | c.pinColor),
    ),
  );

  Widget _selectedCard(Centre c) {
    final phone = c.phone?.trim() ?? '';

    return Material(
      color: Colors.white,
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _typeIcon(c),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.textStrong,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [_summary(c), c.hours].join(' · '),
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppPalette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _selected = null),
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _openDirections(c),
                      icon: const Icon(Icons.directions, size: 20),
                      label: const Text('Directions'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brand,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                  if (phone.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _call(phone),
                        icon: const Icon(Icons.call_outlined, size: 20),
                        label: const Text('Call'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.brand,
                          minimumSize: const Size.fromHeight(48),
                          side: const BorderSide(color: AppColors.brand),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    final items = _filtered;
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Nothing nearby in this category yet.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppPalette.textMuted),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final c = items[i];
        final isSelected = _selected?.id == c.id;

        return Material(
          color: isSelected
              ? AppColors.brand.withValues(alpha: 0.06)
              : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isSelected ? AppColors.brand : AppPalette.hairline,
            ),
          ),
          child: InkWell(
            onTap: () => _focus(c),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _typeIcon(c),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.textStrong,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${c.typeLabel} · ${c.hours}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppPalette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (c.distanceKm != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${c.distanceKm} km',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brand,
                      ),
                    ),
                  ],
                  const Icon(Icons.chevron_right, color: AppPalette.textMuted),
                ],
              ),
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

  Future<void> _call(String phone) async {
    final number = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (!await launchUrl(Uri(scheme: 'tel', path: number))) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Call $phone from your phone.')));
    }
  }
}
