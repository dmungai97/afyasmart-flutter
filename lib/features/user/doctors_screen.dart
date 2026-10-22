import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../models/catalogue.dart';
import '../../state/catalogue_cache.dart';
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
  String? _error;

  /// Bumped by every [_load]. A response whose number is no longer current
  /// was overtaken by a newer filter or search and is dropped, so a slow
  /// earlier request can never overwrite the list the user asked for last.
  int _loadSeq = 0;

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
    final cache = ref.read(catalogueCacheProvider);
    if (cache.doctorFilters case final cached?) {
      // The chip values barely change; one fetch per session is enough.
      setState(() {
        _regions = cached.regions;
        _specializations = cached.specializations;
        _filtersLoading = false;
      });
      return;
    }

    try {
      final filters = await ref.read(catalogueServiceProvider).doctorFilters();
      if (filters.regions.isNotEmpty || filters.specializations.isNotEmpty) {
        cache.doctorFilters = filters;
      }
      if (!mounted) return;
      setState(() {
        _regions = filters.regions;
        _specializations = filters.specializations;
      });
    } on Exception {
      // The chips are a convenience; a failure here must not block the list.
    } finally {
      if (mounted) setState(() => _filtersLoading = false);
    }
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    final search = _search.text.trim().isEmpty ? null : _search.text.trim();
    final coords = _nearMeOnly ? _coords : null;
    final key = [
      search,
      _activeRegion,
      _activeSpec,
      if (coords != null) '${coords.lat},${coords.lng}',
    ].join('|');

    // A list already fetched for these filters shows at once; the request
    // below then refreshes it without a spinner.
    final cache = ref.read(catalogueCacheProvider);
    final cached = cache.doctors[key];
    setState(() {
      _error = null;
      if (cached != null) {
        _doctors = cached;
        _locked = false;
      }
      _loading = cached == null;
    });

    try {
      final results = await ref
          .read(catalogueServiceProvider)
          .nearbyDoctors(
            search: search,
            region: _activeRegion,
            specialization: _activeSpec,
            lat: coords?.lat,
            lng: coords?.lng,
            radius: coords == null ? null : _nearMeRadiusKm,
          );
      cache.doctors[key] = results;
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _doctors = results;
        _locked = false;
      });
    } on PaywallException {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _doctors = const [];
        _locked = true;
      });
    } on Exception catch (e) {
      if (!mounted || seq != _loadSeq) return;
      // A failed refresh keeps the list already on screen; offline, the
      // banner says why.
      if (cached != null) {
        if (!isNetworkError(e)) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(errorMessage(e))));
        }
        return;
      }
      setState(() {
        _doctors = const [];
        _error = errorMessage(e);
      });
    } finally {
      if (mounted && seq == _loadSeq) setState(() => _loading = false);
    }
  }

  /// Retries the list, and the filter chips too if those failed as well.
  void _retry() {
    if (_regions.isEmpty && _specializations.isEmpty) {
      setState(() => _filtersLoading = true);
      _loadFilters();
    }
    _load();
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

    ({double lat, double lng})? coords;
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      final isGranted = permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;

      if (isGranted) {
        final position = await Geolocator.getCurrentPosition().timeout(
          const Duration(seconds: 8),
        );
        coords = (lat: position.latitude, lng: position.longitude);
      }
    } on Object {
      // Denied, services off, or no fix in time — handled below.
    }

    if (!mounted) return;
    if (coords == null) {
      // Sorting by distance from somewhere that is not the user would be
      // worse than not sorting at all, so Near Me stays off.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not get your location. Check that location is on and '
            'allowed for AfyaSmart.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _coords = coords;
      _nearMeOnly = true;
    });
    await _load();
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
                : _error != null
                ? SingleChildScrollView(
                    child: CatalogueError(message: _error!, onRetry: _retry),
                  )
                : _doctors.isEmpty
                ? SingleChildScrollView(
                    child: CatalogueEmpty(
                      locked: _locked,
                      lockedMessage: 'Subscribe to view doctors near you',
                      emptyMessage: _nearMeOnly
                          ? 'No doctors within ${_nearMeRadiusKm.toInt()} km'
                          : 'No doctors found',
                      emptyIcon: '🩺',
                      onClearFilters: _hasActiveFilters ? _clearFilters : null,
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 768;

                      return Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1100),
                          child: isWide
                              ? GridView.builder(
                                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisExtent: 135,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                  ),
                                  itemCount: _doctors.length,
                                  itemBuilder: (_, i) => _card(_doctors[i]),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  itemCount: _doctors.length,
                                  itemBuilder: (_, i) => _card(_doctors[i]),
                                ),
                        ),
                      );
                    },
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
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(
            _initials(d.name),
            style: const TextStyle(
              color: AppColors.brand,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 14),
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
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: d.available
                                ? const Color(0xFF059669)
                                : const Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          d.available ? 'Available' : 'Unavailable',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: d.available
                                ? const Color(0xFF059669)
                                : const Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
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
              const SizedBox(height: 8),
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
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 12,
                            color: AppColors.brand,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${d.distanceKm} km',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.textStrong,
                            ),
                          ),
                        ],
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
