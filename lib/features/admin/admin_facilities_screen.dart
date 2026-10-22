import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../models/admin.dart';
import '../../state/admin_controller.dart';
import '../../state/providers.dart';
import 'widgets/admin_widgets.dart';

/// Port of admin/screens/AdminFacilitiesScreen.tsx — CRUD over the doctors
/// and pharmacies catalogues.
class AdminFacilitiesScreen extends ConsumerStatefulWidget {
  const AdminFacilitiesScreen({super.key});

  @override
  ConsumerState<AdminFacilitiesScreen> createState() =>
      _AdminFacilitiesScreenState();
}

class _AdminFacilitiesScreenState extends ConsumerState<AdminFacilitiesScreen> {
  FacilityKind _kind = FacilityKind.doctor;

  String get _addLabel => 'Add ${_kind.singular}';

  /// Hospitals still to check first, then A to Z.
  static int _byPriorityThenName(AdminFacility a, AdminFacility b) {
    final aTodo = a.kind == FacilityKind.hospital && a.verified != true;
    final bTodo = b.kind == FacilityKind.hospital && b.verified != true;
    if (aTodo != bTodo) return aTodo ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final facilities = ref.watch(adminFacilitiesProvider);
    final rows = facilities.value?.where((f) => f.kind == _kind).toList() ?? []
      ..sort(_byPriorityThenName);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          // Ink on a light tint for the selected tab. It took the theme's
          // gold as a solid fill, the loudest thing on the page.
          child: SegmentedButton<FacilityKind>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              minimumSize: const Size(0, 44),
              selectedBackgroundColor: AppColors.ink.withValues(alpha: 0.1),
              selectedForegroundColor: AppColors.ink,
              foregroundColor: AppColors.inkMuted,
              side: const BorderSide(color: AppColors.rule),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            segments: const [
              ButtonSegment(value: FacilityKind.doctor, label: Text('Doctors')),
              ButtonSegment(
                value: FacilityKind.pharmacy,
                label: Text('Pharmacies'),
              ),
              ButtonSegment(
                value: FacilityKind.hospital,
                label: Text('Hospitals'),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
        ),
        if (rows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            // A labelled button, where an unlabelled "+" left it unclear
            // whether it added a doctor or a pharmacy.
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _summary(rows),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _edit(null),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.brand,
                    minimumSize: const Size(0, 44),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 20),
                  label: Text(_addLabel),
                ),
              ],
            ),
          ),
        Expanded(
          child: facilities.when(
            loading: () => const AdminLoading(),
            error: (error, _) => AdminError(
              error: error,
              onRetry: () => ref.invalidate(adminFacilitiesProvider),
            ),
            data: (_) {
              if (rows.isEmpty) return _empty();

              return RefreshIndicator(
                color: AppColors.ruleStrong,
                onRefresh: () async => ref.invalidate(adminFacilitiesProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: rows.length,
                  itemBuilder: (_, i) => _row(rows[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Says what belongs here and offers the next step, where a single small
  /// line sat in the middle of the screen.
  Widget _empty() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            switch (_kind) {
              FacilityKind.doctor => Icons.medical_services_outlined,
              FacilityKind.pharmacy => Icons.local_pharmacy_outlined,
              FacilityKind.hospital => Icons.local_hospital_outlined,
            },
            size: 40,
            color: AppColors.ruleStrong,
          ),
          const SizedBox(height: 12),
          Text(
            'No ${_kind.plural} yet',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Patients find and contact the ${_kind.plural} listed here. Add '
            'only ${_kind.plural} whose details you have confirmed.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.inkMuted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _edit(null),
            style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
            icon: const Icon(Icons.add, size: 20),
            label: Text(_addLabel),
          ),
        ],
      ),
    ),
  );

  /// "18 hospitals · 18 to check" for hospitals, so the work left is
  /// visible; a plain count otherwise.
  String _summary(List<AdminFacility> rows) {
    final n = rows.length;
    final count = '$n ${n == 1 ? _kind.singular : _kind.plural}';
    if (_kind != FacilityKind.hospital) return count;
    final unchecked = rows.where((f) => f.verified != true).length;
    return unchecked == 0 ? count : '$count · $unchecked to check';
  }

  /// Compact rows on the paper, like the users list; tapping a row edits it.
  Widget _row(AdminFacility f) {
    final active = f.available ?? f.open ?? f.verified ?? false;
    final details = switch (f.kind) {
      FacilityKind.doctor => [f.specialization ?? '', f.hospital ?? ''],
      FacilityKind.pharmacy => [f.address ?? ''],
      FacilityKind.hospital => [
        f.address ?? '',
        if (f.latitude == null) 'No map location',
      ],
    };
    final contact = [f.location, f.phone];

    return InkWell(
      onTap: () => _edit(f),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.rule)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  for (final line in [details, contact])
                    if (line.any((s) => s.isNotEmpty))
                      Text(
                        line.where((s) => s.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.inkMuted,
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusPill(
              label: switch (f.kind) {
                FacilityKind.doctor => active ? 'available' : 'unavailable',
                FacilityKind.pharmacy => active ? 'open' : 'closed',
                FacilityKind.hospital => active ? 'verified' : 'to check',
              },
              tone: active
                  ? StatusTone.success
                  : f.kind == FacilityKind.hospital
                  ? StatusTone.warning
                  : StatusTone.neutral,
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              color: AppColors.inkMuted,
              semanticLabel: 'Edit',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(AdminFacility f) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete facility?'),
            content: Text(
              '${f.name} will be removed from the catalogue. This cannot be '
              'undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    try {
      await ref.read(adminServiceProvider).deleteFacility(f.kind, f.id);
      ref.invalidate(adminFacilitiesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Facility deleted.')));
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  /// Add (when [existing] is null) or edit. The field set differs by kind,
  /// matching the doctors and pharmacies table columns.
  Future<void> _edit(AdminFacility? existing) async {
    final kind = existing?.kind ?? _kind;

    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) =>
          _FacilityEditDialog(existing: existing, kind: kind),
    );

    if (data == null) return;
    // Delete is in the form, so a slip on a list row cannot start it. It
    // still goes through the confirmation in _delete.
    if (data['_delete'] == true && existing != null) {
      await _delete(existing);
      return;
    }

    try {
      final service = ref.read(adminServiceProvider);
      if (existing == null) {
        await service.addFacility(kind, data);
      } else {
        await service.updateFacility(kind, existing.id, data);
      }
      ref.invalidate(adminFacilitiesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null ? 'Facility added.' : 'Facility updated.',
          ),
        ),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }
}

class _FacilityEditDialog extends StatefulWidget {
  const _FacilityEditDialog({required this.existing, required this.kind});

  final AdminFacility? existing;
  final FacilityKind kind;

  @override
  State<_FacilityEditDialog> createState() => _FacilityEditDialogState();
}

class _FacilityEditDialogState extends State<_FacilityEditDialog> {
  late final Map<String, TextEditingController> _controllers;
  late bool _active;
  late bool _open24;
  String? _error;

  bool get _isHospital => widget.kind == FacilityKind.hospital;

  /// Kept out of [_controllers], whose keys are inserted as columns: this
  /// one field becomes two, latitude and longitude.
  late final TextEditingController _coords;

  /// Pulls "latitude, longitude" out of what an admin pastes: the pair Google
  /// Maps copies when you right-click a place ("-1.2921, 36.8219"), or a
  /// Google Maps link with "@-1.2921,36.8219" in it. Null unless it lands
  /// inside Kenya, which also catches the two numbers pasted the wrong way
  /// round.
  static ({double lat, double lng})? parseCoords(String text) {
    final at = text.indexOf('@');
    final source = at >= 0 ? text.substring(at + 1) : text;
    final numbers = RegExp(r'-?\d+(?:\.\d+)?')
        .allMatches(source)
        .map((m) => double.parse(m.group(0)!))
        .toList();
    if (numbers.length < 2) return null;
    final (lat, lng) = (numbers[0], numbers[1]);
    final inKenya = lat >= -5 && lat <= 5.5 && lng >= 33.5 && lng <= 42.5;
    return inKenya ? (lat: lat, lng: lng) : null;
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final isDoctor = widget.kind == FacilityKind.doctor;

    _controllers = {
      'name': TextEditingController(text: existing?.name ?? ''),
      'location': TextEditingController(text: existing?.location ?? ''),
      'phone': TextEditingController(text: existing?.phone ?? ''),
      // The hospitals table has no email column.
      if (!_isHospital)
        'email': TextEditingController(text: existing?.email ?? ''),
      if (isDoctor) ...{
        'specialization': TextEditingController(
          text: existing?.specialization ?? '',
        ),
        'hospital': TextEditingController(text: existing?.hospital ?? ''),
        'experience_years': TextEditingController(
          text: '${existing?.experienceYears ?? 0}',
        ),
      } else if (_isHospital) ...{
        'address': TextEditingController(text: existing?.address ?? ''),
      } else ...{
        'address': TextEditingController(text: existing?.address ?? ''),
        'opening_hours': TextEditingController(
          text: existing?.openingHours ?? '',
        ),
      },
    };

    // A new hospital starts unverified: someone has to check it first.
    _active = _isHospital
        ? existing?.verified ?? false
        : existing?.available ?? existing?.open ?? true;
    _open24 = existing?.open24hrs ?? true;
    _coords = TextEditingController(
      text: existing?.latitude == null || existing?.longitude == null
          ? ''
          : '${existing!.latitude}, ${existing.longitude}',
    );
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _coords.dispose();
    super.dispose();
  }

  void _save() {
    final isDoctor = widget.kind == FacilityKind.doctor;
    final name = _controllers['name']?.text.trim() ?? '';
    final location = _controllers['location']?.text.trim() ?? '';
    final phone = _controllers['phone']?.text.trim() ?? '';

    if (name.isEmpty || name == '.' || name.length < 2) {
      _showError('Please enter a valid name.');
      return;
    }

    if (location.isEmpty) {
      _showError('Please enter a location or city.');
      return;
    }

    // Hospitals may go live without a phone; doctors and pharmacies are
    // listed so patients can call them.
    if (phone.isEmpty && !_isHospital) {
      _showError('Please enter a phone number.');
      return;
    }

    if (isDoctor) {
      final specialization = _controllers['specialization']?.text.trim() ?? '';
      final hospital = _controllers['hospital']?.text.trim() ?? '';

      if (specialization.isEmpty) {
        _showError('Please enter a specialization.');
        return;
      }
      if (hospital.isEmpty) {
        _showError('Please enter a hospital or clinic name.');
        return;
      }
    } else if (!_isHospital) {
      final address = _controllers['address']?.text.trim() ?? '';
      if (address.isEmpty) {
        _showError('Please enter a pharmacy address.');
        return;
      }
    }

    // Optional, but without it the place cannot appear on the map.
    final coordsText = _coords.text.trim();
    final coords = coordsText.isEmpty ? null : parseCoords(coordsText);
    if (coordsText.isNotEmpty && coords == null) {
      _showError(
        'That map location is not a place in Kenya. Paste it as latitude, '
        'longitude, for example -1.2921, 36.8219.',
      );
      return;
    }
    if (_isHospital && _active && coords == null) {
      _showError('Add the map location before marking it verified.');
      return;
    }

    final values = {
      for (final entry in _controllers.entries)
        entry.key: entry.value.text.trim(),
    };

    final data = <String, dynamic>{
      ...values,
      'latitude': coords?.lat,
      'longitude': coords?.lng,
      if (isDoctor) ...{
        'experience_years': int.tryParse(values['experience_years'] ?? '') ?? 0,
        'available': _active,
      } else if (_isHospital) ...{
        'verified': _active,
        'open_24hrs': _open24,
      } else
        'open': _active,
    };

    Navigator.pop(context, data);
  }

  void _showError(String message) => setState(() => _error = message);

  Widget _field(
    String key,
    String label, {
    TextInputType? keyboard,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: _controllers[key],
      keyboardType: keyboard,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(labelText: label, hintText: hint),
    ),
  );

  Widget _mapLocation() {
    final coords = parseCoords(_coords.text);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _coords,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.text,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
              labelText: 'Map location',
              hintText: '-1.2921, 36.8219',
              helperText:
                  'Needed to show on the map. In Google Maps, right-click the '
                  'place and click the numbers to copy them, then paste here.',
              helperMaxLines: 3,
            ),
          ),
          // Lets the admin confirm the pin is on the right building before
          // patients are sent there.
          if (coords != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.https('www.google.com', '/maps/search/', {
                    'api': '1',
                    'query': '${coords.lat},${coords.lng}',
                  }),
                  mode: LaunchMode.externalApplication,
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brand,
                  minimumSize: const Size(0, 44),
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Check on Google Maps'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _switch(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    value: value,
    activeThumbColor: AppColors.ink,
    title: Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
    ),
    subtitle: Text(
      subtitle,
      style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
    ),
    onChanged: onChanged,
  );

  // One field per row at full width, where the old dialog paired fields
  // (phone/email, specialization/hospital) into about 100px each on a phone.
  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final isDoctor = widget.kind == FacilityKind.doctor;
    final kind = widget.kind.singular;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existing == null ? 'Add $kind' : 'Edit $kind',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  if (_isHospital && existing != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      existing.verified == true
                          ? 'Verified: shown to patients on the map.'
                          : 'Not checked yet: patients cannot see it.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: existing.verified == true
                            ? AppColors.success
                            : AppColors.accentInk,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _field('name', switch (widget.kind) {
                      FacilityKind.doctor => 'Full name',
                      FacilityKind.pharmacy => 'Pharmacy name',
                      FacilityKind.hospital => 'Hospital name',
                    }),
                    if (isDoctor) ...[
                      _field('specialization', 'Specialization'),
                      _field('hospital', 'Hospital or clinic'),
                    ] else
                      _field(
                        'address',
                        _isHospital
                            ? 'Street address (optional)'
                            : 'Street address',
                      ),
                    _field(
                      'location',
                      'Town or area',
                      hint: 'e.g. Westlands, Nairobi',
                    ),
                    _mapLocation(),
                    _field(
                      'phone',
                      _isHospital ? 'Phone (optional)' : 'Phone',
                      keyboard: TextInputType.phone,
                    ),
                    if (!_isHospital)
                      _field(
                        'email',
                        'Email (optional)',
                        keyboard: TextInputType.emailAddress,
                      ),
                    if (isDoctor)
                      _field(
                        'experience_years',
                        'Years of experience',
                        keyboard: TextInputType.number,
                      )
                    else if (!_isHospital)
                      _field(
                        'opening_hours',
                        'Opening hours',
                        hint: 'e.g. Mon-Sat 8am-8pm',
                      ),
                    if (_isHospital) ...[
                      _switch(
                        'Open 24 hours',
                        'Shown to patients as a 24-hour hospital',
                        _open24,
                        (v) => setState(() => _open24 = v),
                      ),
                      _switch(
                        'Verified',
                        'Only verified hospitals are shown to patients. '
                            'Check the name and map location first.',
                        _active,
                        (v) => setState(() => _active = v),
                      ),
                    ] else
                      _switch(
                        isDoctor ? 'Available' : 'Open',
                        isDoctor
                            ? 'Shown to patients as taking appointments'
                            : 'Shown to patients as open for business',
                        _active,
                        (v) => setState(() => _active = v),
                      ),
                  ],
                ),
              ),
            ),
            // Inside the dialog: a snackbar sat behind its dark overlay.
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Row(
                children: [
                  if (existing != null) ...[
                    IconButton(
                      onPressed: () =>
                          Navigator.pop(context, {'_delete': true}),
                      tooltip: 'Delete $kind',
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        side: const BorderSide(color: AppColors.rule),
                      ),
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AppColors.danger,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, null),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
