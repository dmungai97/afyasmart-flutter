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
    final isDoctor = kind == FacilityKind.doctor;

    final controllers = <String, TextEditingController>{
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

    var active = existing?.available ?? existing?.open ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Text(
            existing == null
                ? (isDoctor ? 'Add doctor' : 'Add pharmacy')
                : 'Edit ${existing.name}',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in controllers.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: entry.value,
                      keyboardType: entry.key == 'experience_years'
                          ? TextInputType.number
                          : null,
                      decoration: InputDecoration(
                        labelText: entry.key
                            .replaceAll('_', ' ')
                            .replaceFirstMapped(
                              RegExp('^.'),
                              (m) => m[0]!.toUpperCase(),
                            ),
                      ),
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  title: Text(isDoctor ? 'Available' : 'Open'),
                  onChanged: (v) => setDialogState(() => active = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    // Read every value before disposing the controllers.
    final values = {
      for (final entry in controllers.entries) entry.key: entry.value.text.trim(),
    };
    for (final c in controllers.values) {
      c.dispose();
    }

    if (saved != true) return;

    final data = <String, dynamic>{
      ...values,
      if (isDoctor) ...{
        'experience_years': int.tryParse(values['experience_years'] ?? '') ?? 0,
        'available': active,
      } else
        'open': active,
    };

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
