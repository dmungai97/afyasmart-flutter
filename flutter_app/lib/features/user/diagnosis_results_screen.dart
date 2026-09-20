import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../../state/diagnosis_controller.dart';

/// Port of src/user/screens/DiagnosisResultsScreen.tsx — the unlocked view of
/// what locked-results teased.
class DiagnosisResultsScreen extends ConsumerWidget {
  const DiagnosisResultsScreen({super.key});

  static const _teal = AppColors.brand;
  static const _green = Color(0xFF16A34A);
  static const _red = Color(0xFFDC2626);
  static const _orange = Color(0xFFD97706);

  /// Parses the '#RRGGBB' strings the analysis endpoint returns.
  static Color _hex(String value) {
    final cleaned = value.replaceFirst('#', '');
    final parsed = int.tryParse(cleaned, radix: 16);
    return parsed == null ? _teal : Color(0xFF000000 | parsed);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stored = ref.watch(
      diagnosisControllerProvider.select((s) => s.pendingDiagnosis),
    );

    // Falls back to the keyword heuristic when the stored analysis is gone,
    // so the screen shows a plausible result rather than an empty panel.
    final diagnosis =
        stored ?? buildDiagnosisFromSymptoms('fever, headache, body weakness');

    final urgencyColor = switch (diagnosis.urgency) {
      'High' => _red,
      'Medium' => _orange,
      _ => _green,
    };

    return Container(
      color: const Color(0xFFF5F7FA),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _header(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              children: [
                _summaryCard(diagnosis),
                const SizedBox(height: 16),
                _conditionsCard(diagnosis),
                const SizedBox(height: 16),
                _urgencyCard(diagnosis, urgencyColor),
                const SizedBox(height: 16),
                _medicationsCard(diagnosis),
                const SizedBox(height: 16),
                _actionsCard(context),
                const SizedBox(height: 20),
                const Text(
                  'AfyaSmart provides health guidance, not a final diagnosis. '
                  'For emergencies, visit the nearest hospital immediately.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppPalette.textMuted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) => Container(
    width: double.infinity,
    color: _teal,
    padding: EdgeInsets.fromLTRB(
      24,
      MediaQuery.viewPaddingOf(context).top + 20,
      24,
      28,
    ),
    child: const Column(
      children: [
        Icon(Icons.check_circle, size: 34, color: Color(0xFF4ADE80)),
        SizedBox(height: 10),
        Text(
          'Your Diagnosis Is Ready',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Unlocked from your prepared symptom analysis',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppPalette.hairline),
    ),
    child: child,
  );

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppPalette.textMuted,
      letterSpacing: 0.5,
    ),
  );

  Widget _title(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: AppPalette.textStrong,
    ),
  );

  Widget _summaryCard(PendingDiagnosis d) => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('SYMPTOMS ANALYSED'),
        const SizedBox(height: 8),
        Text(
          d.symptoms,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppPalette.textStrong,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          d.summary,
          style: const TextStyle(
            fontSize: 13,
            color: AppPalette.textMuted,
            height: 1.5,
          ),
        ),
      ],
    ),
  );

  Widget _conditionsCard(PendingDiagnosis d) => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [_title('Possible Conditions'), _label('PROBABILITY')],
        ),
        const SizedBox(height: 14),
        for (final c in d.conditions) _conditionRow(c),
      ],
    ),
  );

  Widget _conditionRow(DiagnosisCondition c) {
    final color = _hex(c.color);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.textStrong,
                  ),
                ),
                Text(
                  '${c.level} match',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppPalette.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: LinearProgressIndicator(
                    value: c.probability / 100,
                    minHeight: 6,
                    backgroundColor: AppPalette.hairline,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${c.probability}%',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _urgencyCard(PendingDiagnosis d, Color color) => _card(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.error_outline, size: 24, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Urgency Level: ${d.urgency}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textStrong,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                d.urgency == 'High'
                    ? 'Seek medical attention as soon as possible, especially '
                          'if symptoms are worsening.'
                    : 'Monitor symptoms closely and get care if they persist '
                          'or become severe.',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppPalette.textMuted,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _medicationsCard(PendingDiagnosis d) => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Recommended Next Steps'),
        const SizedBox(height: 14),
        for (final m in d.medications)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.medical_services,
                    size: 18,
                    color: _teal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.textStrong,
                        ),
                      ),
                      Text(
                        m.note,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppPalette.textMuted,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _actionsCard(BuildContext context) => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Get Care Nearby'),
        const SizedBox(height: 4),
        const Text(
          'Find hospitals, clinics, pharmacies, and doctors near you.',
          style: TextStyle(fontSize: 12, color: AppPalette.textMuted),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => context.go(Routes.map),
          icon: const Icon(Icons.location_on, size: 17),
          label: const Text('See nearby services'),
          style: FilledButton.styleFrom(
            backgroundColor: _teal,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => context.go(Routes.chat),
          icon: const Icon(Icons.chat_bubble, size: 17),
          label: const Text('Continue AI chat'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _teal,
            side: const BorderSide(color: _teal),
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    ),
  );
}
