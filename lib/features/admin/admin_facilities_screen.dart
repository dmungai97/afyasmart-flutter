import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class _AdminFacilitiesScreenState
    extends ConsumerState<AdminFacilitiesScreen> {
  FacilityKind _kind = FacilityKind.doctor;

  @override
  Widget build(BuildContext context) {
    final facilities = ref.watch(adminFacilitiesProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<FacilityKind>(
                  segments: const [
                    ButtonSegment(
                      value: FacilityKind.doctor,
                      label: Text('Doctors'),
                    ),
                    ButtonSegment(
                      value: FacilityKind.pharmacy,
                      label: Text('Pharmacies'),
                    ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) => setState(() => _kind = s.first),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: () => _edit(null),
                icon: const Icon(Icons.add),
                tooltip: 'Add',
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
            data: (all) {
              final rows = all.where((f) => f.kind == _kind).toList();
              if (rows.isEmpty) {
                return AdminEmpty(
                  message: _kind == FacilityKind.doctor
                      ? 'No doctors in the catalogue yet.'
                      : 'No pharmacies in the catalogue yet.',
                );
              }

              return RefreshIndicator(
                color: AppColors.ruleStrong,
                onRefresh: () async =>
                    ref.invalidate(adminFacilitiesProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
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

  Widget _row(AdminFacility f) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AdminCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  f.kind == FacilityKind.doctor
                      ? '${f.specialization} · ${f.hospital}'
                      : f.address ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.inkMuted,
                  ),
                ),
                Text(
                  [
                    f.location,
                    if (f.phone.isNotEmpty) f.phone,
                  ].where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusPill(
                label: (f.available ?? f.open ?? false) ? 'active' : 'inactive',
                tone: (f.available ?? f.open ?? false)
                    ? StatusTone.success
                    : StatusTone.neutral,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => _edit(f),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed: () => _delete(f),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: AppColors.danger,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
  );

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Facility deleted.')));
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// Add (when [existing] is null) or edit. The field set differs by kind,
  /// matching the doctors and pharmacies table columns.
  Future<void> _edit(AdminFacility? existing) async {
    final kind = existing?.kind ?? _kind;

    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => _FacilityEditDialog(
        existing: existing,
        kind: kind,
      ),
    );

    if (data == null) return;

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
          content: Text(existing == null ? 'Facility added.' : 'Facility updated.'),
        ),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final isDoctor = widget.kind == FacilityKind.doctor;

    _controllers = {
      'name': TextEditingController(text: existing?.name ?? ''),
      'location': TextEditingController(text: existing?.location ?? ''),
      'phone': TextEditingController(text: existing?.phone ?? ''),
      'email': TextEditingController(text: existing?.email ?? ''),
      if (isDoctor) ...{
        'specialization': TextEditingController(
          text: existing?.specialization ?? '',
        ),
        'hospital': TextEditingController(text: existing?.hospital ?? ''),
        'experience_years': TextEditingController(
          text: '${existing?.experienceYears ?? 0}',
        ),
      } else ...{
        'address': TextEditingController(text: existing?.address ?? ''),
        'opening_hours': TextEditingController(
          text: existing?.openingHours ?? '',
        ),
      },
    };

    _active = existing?.available ?? existing?.open ?? true;
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
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

    if (phone.isEmpty) {
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
    } else {
      final address = _controllers['address']?.text.trim() ?? '';
      if (address.isEmpty) {
        _showError('Please enter a pharmacy address.');
        return;
      }
    }

    final values = {
      for (final entry in _controllers.entries)
        entry.key: entry.value.text.trim(),
    };

    final data = <String, dynamic>{
      ...values,
      if (isDoctor) ...{
        'experience_years':
            int.tryParse(values['experience_years'] ?? '') ?? 0,
        'available': _active,
      } else
        'open': _active,
    };

    Navigator.pop(context, data);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final isDoctor = widget.kind == FacilityKind.doctor;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      title: Text(
        existing == null
            ? (isDoctor ? 'Add doctor' : 'Add pharmacy')
            : 'Edit ${existing.name}',
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _controllers['name'],
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.person_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controllers['location'],
                decoration: const InputDecoration(
                  labelText: 'Location / City',
                  prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controllers['phone'],
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        prefixIcon: Icon(Icons.phone_android, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _controllers['email'],
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (isDoctor) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controllers['specialization'],
                        decoration: const InputDecoration(
                          labelText: 'Specialization',
                          prefixIcon: Icon(
                            Icons.medical_services_outlined,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _controllers['hospital'],
                        decoration: const InputDecoration(
                          labelText: 'Hospital',
                          prefixIcon: Icon(
                            Icons.local_hospital_outlined,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controllers['experience_years'],
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Experience (years)',
                          prefixIcon: Icon(
                            Icons.workspace_premium_outlined,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.rule),
                        ),
                        child: SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                          ),
                          value: _active,
                          dense: true,
                          activeThumbColor: AppColors.ink,
                          title: const Text(
                            'Available',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                          onChanged: (v) => setState(() => _active = v),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                TextField(
                  controller: _controllers['address'],
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    prefixIcon: Icon(Icons.home_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controllers['opening_hours'],
                        decoration: const InputDecoration(
                          labelText: 'Opening hours',
                          prefixIcon: Icon(Icons.access_time, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.rule),
                        ),
                        child: SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                          ),
                          value: _active,
                          dense: true,
                          activeThumbColor: AppColors.ink,
                          title: const Text(
                            'Open',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                          onChanged: (v) => setState(() => _active = v),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.ink,
            foregroundColor: AppColors.paper,
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 12,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
