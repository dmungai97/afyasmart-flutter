import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../../state/auth_controller.dart';
import '../../state/diagnosis_controller.dart';
import 'widgets/profile_widgets.dart';

/// Medical History screen displaying personal health records, vitals summary,
/// and AI symptom evaluation history in a modern, subtle interface.
class MedicalHistoryScreen extends ConsumerWidget {
  const MedicalHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final history = ref.watch(diagnosisHistoryProvider);
    // Results from before history was stored server-side exist only on this
    // device; show that one rather than an empty list.
    final local = ref.watch(diagnosisControllerProvider).pendingDiagnosis;

    void view(PendingDiagnosis diagnosis) {
      ref.read(diagnosisControllerProvider.notifier).setPendingDiagnosis(diagnosis);
      context.push(Routes.diagnosisResults);
    }

    final records = switch (history) {
      AsyncData(:final value) when value.isNotEmpty => value,
      _ when local != null => [local],
      _ => const <PendingDiagnosis>[],
    };

    return ProfileSubpage(
      title: 'Medical History',
      child: RefreshIndicator(
        onRefresh: () => ref.refresh(diagnosisHistoryProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          children: [
            _UserHealthCard(
              name: user?.name ?? 'User',
              email: user?.email ?? '',
            ),
            const SizedBox(height: 20),
            const _SectionHeader('Health Assessments & Records'),
            const SizedBox(height: 8),
            if (history.isLoading && records.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (records.isEmpty)
              const _EmptyHistoryCard()
            else
              for (final diagnosis in records) ...[
                _DiagnosisRecordCard(
                  diagnosis: diagnosis,
                  onView: () => view(diagnosis),
                ),
                const SizedBox(height: 12),
              ],
            if (history.hasError)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Could not load your full history. Pull down to retry.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppPalette.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UserHealthCard extends StatelessWidget {
  const _UserHealthCard({required this.name, required this.email});

  final String name;
  final String email;

  @override
  Widget build(BuildContext context) {
    return ProfileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFFE0F2F1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.folder_shared_outlined,
                  size: 22,
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textStrong,
                      ),
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppPalette.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppPalette.hairline),
          const SizedBox(height: 12),
          const Row(
            children: [
              Expanded(
                child: _HealthMetric(
                  label: 'Blood Group',
                  value: 'Not set',
                ),
              ),
              SizedBox(
                height: 28,
                child: VerticalDivider(color: AppPalette.hairline),
              ),
              Expanded(
                child: _HealthMetric(
                  label: 'Allergies',
                  value: 'None reported',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HealthMetric extends StatelessWidget {
  const _HealthMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppPalette.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppPalette.textStrong,
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppPalette.textMuted,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _DiagnosisRecordCard extends StatelessWidget {
  const _DiagnosisRecordCard({required this.diagnosis, required this.onView});

  final PendingDiagnosis diagnosis;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final urgency = diagnosis.urgency;
    final (fg, bg) = switch (urgency.toLowerCase()) {
      'high' => (AppPalette.red, AppPalette.redBg),
      'moderate' => (AppPalette.orange, AppPalette.orangeBg),
      _ => (AppPalette.green, AppPalette.greenBg),
    };

    final dateStr = _formatDate(diagnosis.preparedAt);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.medical_information_outlined,
                    size: 18,
                    color: AppColors.brand,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dateStr,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.textMuted,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$urgency Urgency',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (diagnosis.symptoms.isNotEmpty) ...[
            Text(
              'Symptoms: ${diagnosis.symptoms}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppPalette.textStrong,
              ),
            ),
            const SizedBox(height: 6),
          ],
          if (diagnosis.summary.isNotEmpty)
            Text(
              diagnosis.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppPalette.textMuted,
              ),
            ),
          if (diagnosis.conditions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: diagnosis.conditions.take(3).map((c) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4F8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${c.name} (${c.probability}%)',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppPalette.textStrong,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onView,
            icon: const Icon(Icons.analytics_outlined, size: 16),
            label: const Text('View Full Analysis'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.brand,
              side: const BorderSide(color: AppPalette.hairline),
              minimumSize: const Size.fromHeight(42),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _formatDate(DateTime utcOrLocal) {
    // Server timestamps arrive in UTC.
    final d = utcOrLocal.toLocal();
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${_months[d.month - 1]} ${d.year}, $hh:$mm';
  }
}

class _EmptyHistoryCard extends StatelessWidget {
  const _EmptyHistoryCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.hairline),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: Color(0xFFF0F4F8),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.description_outlined,
              size: 26,
              color: AppPalette.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'No Health Records Yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppPalette.textStrong,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'When you complete AI symptom assessments or health checks, your medical records will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppPalette.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => context.go(Routes.symptoms),
            icon: const Icon(Icons.add_outlined, size: 18),
            label: const Text('Start Symptom Check'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brand,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
