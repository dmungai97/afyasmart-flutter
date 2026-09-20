import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../models/catalogue.dart';
import '../../state/providers.dart';
import 'widgets/catalogue_widgets.dart';

/// Port of src/user/screens/DoctorsScreen.tsx.
class DoctorsScreen extends ConsumerStatefulWidget {
  const DoctorsScreen({super.key});

  @override
  ConsumerState<DoctorsScreen> createState() => _DoctorsScreenState();
}

/// "Dr. Sarah Mwangi" -> "SM". The Dr. prefix is stripped so every initial
/// pair is not just "DS".
String _initials(String name) {
  final cleaned = name.replaceFirst(RegExp(r'^Dr\.\s*', caseSensitive: false), '');
  return cleaned
      .split(' ')
      .where((p) => p.isNotEmpty)
      .take(2)
      .map((p) => p[0])
      .join()
      .toUpperCase();
}

String _stars(double rating) {
  final full = rating.floor().clamp(0, 5);
  return '★' * full + '☆' * (5 - full);
}

class _DoctorsScreenState extends ConsumerState<DoctorsScreen> {
  final _search = TextEditingController();

  List<Doctor> _doctors = const [];
  List<String> _regions = const [];
  List<String> _specializations = const [];

  bool _loading = true;
  bool _filtersLoading = true;
  bool _locked = false;

  String? _activeRegion;
  String? _activeSpec;
  bool _nearMeOnly = false;
  ({double lat, double lng})? _coords;

  static const _nearMeRadiusKm = 50.0;

  bool get _hasActiveFilters =>
      _activeRegion != null ||
      _activeSpec != null ||
      _nearMeOnly ||
      _search.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadFilters();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadFilters() async {
    try {
      final service = ref.read(catalogueServiceProvider);
      final results = await Future.wait([
        service.regions(),
        service.specializations(),
      ]);
      if (!mounted) return;
      setState(() {
        _regions = results[0];
        _specializations = results[1];
      });
    } on Exception {
      // The chips are a convenience; a failure here must not block the list.
    } finally {
      if (mounted) setState(() => _filtersLoading = false);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await ref
          .read(catalogueServiceProvider)
          .nearbyDoctors(
            search: _search.text.trim().isEmpty ? null : _search.text.trim(),
            region: _activeRegion,
            specialization: _activeSpec,
            lat: _nearMeOnly ? _coords?.lat : null,
            lng: _nearMeOnly ? _coords?.lng : null,
            radius: _nearMeOnly ? _nearMeRadiusKm : null,
          );
      if (!mounted) return;
      setState(() {
        _doctors = results;
        _locked = false;
      });
    } on PaywallException {
      if (!mounted) return;
      setState(() {
        _doctors = const [];
        _locked = true;
      });
    } on Exception {
      if (!mounted) return;
      setState(() => _doctors = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Near Me needs a fix before it can filter, so permission is requested on
  /// toggle rather than at screen open — asking for location before the user
  /// has shown interest in it reads as intrusive.
  Future<void> _toggleNearMe() async {
    if (_nearMeOnly) {
      setState(() => _nearMeOnly = false);
      await _load();
      return;
    }

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission is needed to sort by distance.'),
          ),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _coords = (lat: position.latitude, lng: position.longitude);
        _nearMeOnly = true;
      });
      await _load();
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not determine your location.')),
      );
    }
  }

  Future<void> _clearFilters() async {
    setState(() {
      _activeRegion = null;
      _activeSpec = null;
      _nearMeOnly = false;
      _search.clear();
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F7FA),
      child: Column(
        children: [
          const CatalogueHeader(
            title: 'Find a Doctor',
            subtitle: 'Browse specialists and book a consultation',
          ),
          CatalogueSearchRow(
            controller: _search,
            hint: 'Search name, hospital or specialty...',
            onSearch: _load,
          ),
          _nearMeToggle(),
          FilterChipRow(
            label: 'REGION',
            values: _regions,
            active: _activeRegion,
            loading: _filtersLoading,
            onPick: (value) {
              setState(
                () => _activeRegion = _activeRegion == value ? null : value,
              );
              _load();
            },
          ),
          FilterChipRow(
            label: 'SPECIALIZATION',
            values: _specializations,
            active: _activeSpec,
            loading: _filtersLoading,
            onPick: (value) {
              setState(() => _activeSpec = _activeSpec == value ? null : value);
              _load();
            },
          ),
          if (_hasActiveFilters) _filterSummary(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.brand),
                  )
                : _doctors.isEmpty
                ? SingleChildScrollView(
                    child: CatalogueEmpty(
                      locked: _locked,
                      lockedMessage: 'Subscribe to view doctors near you',
                      emptyMessage: 'No doctors found',
                      emptyIcon: '🩺',
                      onClearFilters: _hasActiveFilters ? _clearFilters : null,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: _doctors.length,
                    itemBuilder: (_, i) => _card(_doctors[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _nearMeToggle() => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: FilterChip(
        label: const Text('Near Me (50km)'),
        avatar: Icon(
          Icons.my_location,
          size: 15,
          color: _nearMeOnly ? Colors.white : AppColors.brand,
        ),
        selected: _nearMeOnly,
        onSelected: (_) => _toggleNearMe(),
        selectedColor: AppColors.brand,
        backgroundColor: Colors.white,
        side: const BorderSide(color: AppPalette.hairline),
        showCheckmark: false,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _nearMeOnly ? Colors.white : AppPalette.textBody,
        ),
      ),
    ),
  );

  Widget _filterSummary() => Container(
    margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.brand.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            [
              _activeRegion,
              _activeSpec,
              if (_nearMeOnly) 'Near Me (50km)',
              if (_search.text.trim().isNotEmpty) _search.text.trim(),
            ].whereType<String>().join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.brand),
          ),
        ),
        GestureDetector(
          onTap: _clearFilters,
          child: const Text(
            'Clear all',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.brand,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _card(Doctor d) => CatalogueCard(
    onTap: () => _showDetail(d),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: AppColors.brand,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            _initials(d.name),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      d.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textStrong,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: d.available
                          ? AppPalette.greenBg
                          : AppPalette.redBg,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Text(
                      d.available ? 'Available' : 'Unavailable',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: d.available
                            ? AppPalette.green
                            : AppPalette.red,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                d.specialization,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brand,
                ),
              ),
              Text(
                d.hospital,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppPalette.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    _stars(d.rating),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFD4A017),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${d.rating} · ${d.experienceYears} yrs exp',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppPalette.textMuted,
                      ),
                    ),
                  ),
                  if (d.distanceKm != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppPalette.hairline,
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                      child: Text(
                        '📍 ${d.distanceKm} km',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppPalette.textBody,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  void _showDetail(Doctor d) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                d.name,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textStrong,
                ),
              ),
              Text(
                '${d.specialization} · ${d.hospital}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.brand,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              _detailRow(Icons.location_on_outlined, d.location),
              if (d.availability.isNotEmpty)
                _detailRow(Icons.schedule, d.availability),
              _detailRow(
                Icons.workspace_premium_outlined,
                '${d.experienceYears} years experience · ${d.rating}★',
              ),
              if (d.phone.isNotEmpty) _detailRow(Icons.phone_outlined, d.phone),
              if (d.email.isNotEmpty) _detailRow(Icons.mail_outline, d.email),
              const SizedBox(height: 18),
              if (d.phone.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => _dial(d.phone),
                  icon: const Icon(Icons.phone, size: 18),
                  label: const Text('Call doctor'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.brand),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: AppPalette.textBody,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _dial(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the dialler.')),
      );
    }
  }
}
