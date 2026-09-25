import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../../services/symptoms_service.dart';
import '../../state/auth_controller.dart';
import '../../state/diagnosis_controller.dart';
import '../../state/providers.dart';

/// Port of src/user/screens/SymptomsScreen.tsx — the in-app symptom checker.
///
/// Distinct from the onboarding funnel: that one runs once before an account
/// exists, this is the repeatable tool. Both call the same analyze endpoint
/// and both write the result to the diagnosis store.
class SymptomsScreen extends ConsumerStatefulWidget {
  const SymptomsScreen({super.key});

  @override
  ConsumerState<SymptomsScreen> createState() => _SymptomsScreenState();
}

enum _Step { entry, symptoms, details, questions, processing, results }

const _popularSymptoms = [
  'Fever',
  'Headache',
  'Cough',
  'Stomach pain',
  'Body pain',
  'Sore throat',
  'Nausea',
  'Diarrhea',
  'Fatigue',
  'Chest pain',
];

typedef _Question = ({
  String id,
  String question,
  String sub,
  List<String>? options,
});

const _smartQuestions = <_Question>[
  (
    id: 'fever',
    question: 'Do you have a fever?',
    sub: 'Temperature above 37.5°C',
    options: null,
  ),
  (
    id: 'duration',
    question: 'How long have symptoms lasted?',
    sub: 'Please choose one option',
    options: ['< 1 day', '1–3 days', '4–7 days', '1 week+'],
  ),
  (
    id: 'travel',
    question: 'Have you travelled recently?',
    sub: 'In the last 2 weeks',
    options: null,
  ),
  (
    id: 'contact',
    question: 'Contacted someone sick?',
    sub: 'Close contact with ill person',
    options: null,
  ),
  (
    id: 'meds',
    question: 'Are you on any medication?',
    sub: 'Prescription or OTC drugs',
    options: null,
  ),
];

const _durationOptions = ['Today', '1–3 days', '4–7 days', '1 week+'];
const _severityLabels = ['Mild', 'Moderate', 'Severe'];

const _processingLabels = [
  'Reading your symptoms…',
  'Matching against common patterns…',
  'Preparing your results…',
];

class _SymptomsScreenState extends ConsumerState<SymptomsScreen> {
  final _customSymptom = TextEditingController();

  _Step _step = _Step.entry;
  final _selected = <String>[];
  int _age = 25;
  String? _gender;
  String? _duration;
  int _severity = 1;
  int _questionIdx = 0;
  final _answers = <String, String>{};

  SymptomsAnalysis? _analysis;
  String? _error;
  int _processingStep = 0;
  Timer? _tick1;
  Timer? _tick2;

  @override
  void dispose() {
    _tick1?.cancel();
    _tick2?.cancel();
    _customSymptom.dispose();
    super.dispose();
  }

  bool get _subscribed =>
      ref.read(currentUserProvider)?.isSubscribed ?? false;

  Future<void> _startProcessing() async {
    setState(() {
      _step = _Step.processing;
      _processingStep = 0;
      _error = null;
    });

    // Purely cosmetic staging — the request has no progress to report.
    _tick1 = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _processingStep = 1);
    });
    _tick2 = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _processingStep = 2);
    });

    try {
      final analysis = await ref
          .read(symptomsServiceProvider)
          .analyze(
            symptoms: _selected,
            age: _age,
            gender: _gender ?? 'other',
            duration: _duration ?? '1–3 days',
            severity: _severityLabels[_severity],
            answers: _answers,
          );

      _tick1?.cancel();
      _tick2?.cancel();
      if (!mounted) return;

      // Stored so the result survives if they subscribe and come back — the
      // diagnosis-results screen reads the same store.
      await ref
          .read(diagnosisControllerProvider.notifier)
          .setPendingDiagnosis(
            PendingDiagnosis(
              symptoms: _selected.join(', '),
              summary: analysis.urgencyDesc,
              urgency: analysis.urgency,
              conditions: analysis.conditions
                  .map(
                    (c) => DiagnosisCondition(
                      name: c.name,
                      probability: c.percent,
                      level: c.likelihood,
                      color: c.color,
                    ),
                  )
                  .toList(),
              medications: analysis.medications
                  .map((m) => DiagnosisMedication(name: m.name, note: m.desc))
                  .toList(),
              preparedAt: DateTime.now(),
            ),
          );

      if (!mounted) return;
      setState(() {
        _analysis = analysis;
        _step = _Step.results;
      });
    } on Exception catch (e) {
      _tick1?.cancel();
      _tick2?.cancel();
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _step = _Step.results;
      });
    }
  }

  void _reset() => setState(() {
    _step = _Step.entry;
    _selected.clear();
    _answers.clear();
    _gender = null;
    _duration = null;
    _severity = 1;
    _age = 25;
    _questionIdx = 0;
    _analysis = null;
    _error = null;
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F7FA),
    body: SafeArea(
      bottom: false,
      child: switch (_step) {
        _Step.entry => _entry(),
        _Step.symptoms => _symptoms(),
        _Step.details => _details(),
        _Step.questions => _questions(),
        _Step.processing => _processing(),
        _Step.results => _results(),
      },
    ),
  );

  // ── Shared chrome ────────────────────────────────────────────────────────

  Widget _stepHeader({required String label, required VoidCallback onBack}) =>
      Container(
        color: AppColors.brand,
        padding: const EdgeInsets.fromLTRB(8, 8, 20, 12),
        child: Row(
          children: [
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            ),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 36),
          ],
        ),
      );

  Widget _progress(double value) => LinearProgressIndicator(
    value: value,
    minHeight: 3,
    backgroundColor: AppPalette.hairline,
    valueColor: const AlwaysStoppedAnimation(AppColors.brand),
  );

  Widget _primaryButton(String label, VoidCallback? onPressed) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.brand,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppPalette.hairline,
      minimumSize: const Size.fromHeight(50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label),
        const SizedBox(width: 8),
        const Icon(Icons.arrow_forward, size: 18),
      ],
    ),
  );

  // ── Step: entry ──────────────────────────────────────────────────────────

  Widget _entry() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
    children: [
      const Text(
        'Symptom Checker',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppPalette.textStrong,
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        'Answer a few questions and get an idea of what might be going on.',
        style: TextStyle(
          fontSize: 14,
          color: AppPalette.textMuted,
          height: 1.5,
        ),
      ),
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.brand,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.monitor_heart, size: 32, color: Colors.white),
            const SizedBox(height: 12),
            const Text(
              'Start a new check',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Takes about a minute.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => setState(() => _step = _Step.symptoms),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.brand,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Begin'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'This is health guidance, not a diagnosis. For emergencies, go to '
        'the nearest hospital immediately.',
        style: TextStyle(
          fontSize: 11,
          color: AppPalette.textMuted,
          height: 1.5,
        ),
      ),
    ],
  );

  // ── Step: symptoms ───────────────────────────────────────────────────────

  Widget _symptoms() => Column(
    children: [
      _stepHeader(
        label: 'Step 1 of 3',
        onBack: () => setState(() => _step = _Step.entry),
      ),
      _progress(1 / 3),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          children: [
            const Text(
              'What are you experiencing?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppPalette.textStrong,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Pick from the list or add your own.',
              style: TextStyle(fontSize: 13, color: AppPalette.textMuted),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customSymptom,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addCustom(),
                    decoration: const InputDecoration(
                      hintText: 'Add a symptom…',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _addCustom,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.add, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in {..._popularSymptoms, ..._selected})
                  FilterChip(
                    label: Text(s),
                    selected: _selected.contains(s),
                    onSelected: (_) => setState(
                      () => _selected.contains(s)
                          ? _selected.remove(s)
                          : _selected.add(s),
                    ),
                    selectedColor: AppColors.brand,
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: AppPalette.hairline),
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _selected.contains(s)
                          ? Colors.white
                          : AppPalette.textBody,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: _primaryButton(
          'Continue',
          _selected.isEmpty
              ? null
              : () => setState(() => _step = _Step.details),
        ),
      ),
    ],
  );

  void _addCustom() {
    final text = _customSymptom.text.trim();
    if (text.isEmpty || _selected.contains(text)) {
      _customSymptom.clear();
      return;
    }
    setState(() => _selected.add(text));
    _customSymptom.clear();
  }

  // ── Step: details ────────────────────────────────────────────────────────

  Widget _details() => Column(
    children: [
      _stepHeader(
        label: 'Step 2 of 3',
        onBack: () => setState(() => _step = _Step.symptoms),
      ),
      _progress(2 / 3),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          children: [
            const Text(
              'A bit about you',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppPalette.textStrong,
              ),
            ),
            const SizedBox(height: 20),
            _fieldLabel('Age'),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _age.toDouble(),
                    min: 1,
                    max: 100,
                    divisions: 99,
                    activeColor: AppColors.brand,
                    label: '$_age',
                    onChanged: (v) => setState(() => _age = v.round()),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '$_age',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textStrong,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _fieldLabel('Gender'),
            Wrap(
              spacing: 8,
              children: [
                for (final g in const [
                  (label: 'Female', value: 'female'),
                  (label: 'Male', value: 'male'),
                  (label: 'Prefer not to say', value: 'other'),
                ])
                  ChoiceChip(
                    label: Text(g.label),
                    selected: _gender == g.value,
                    onSelected: (_) => setState(() => _gender = g.value),
                    selectedColor: AppColors.brand,
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: AppPalette.hairline),
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      fontSize: 13,
                      color: _gender == g.value
                          ? Colors.white
                          : AppPalette.textBody,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _fieldLabel('How long have you felt this way?'),
            Wrap(
              spacing: 8,
              children: [
                for (final d in _durationOptions)
                  ChoiceChip(
                    label: Text(d),
                    selected: _duration == d,
                    onSelected: (_) => setState(() => _duration = d),
                    selectedColor: AppColors.brand,
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: AppPalette.hairline),
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      fontSize: 13,
                      color: _duration == d
                          ? Colors.white
                          : AppPalette.textBody,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _fieldLabel('How severe is it?'),
            SegmentedButton<int>(
              segments: [
                for (var i = 0; i < _severityLabels.length; i++)
                  ButtonSegment(value: i, label: Text(_severityLabels[i])),
              ],
              selected: {_severity},
              onSelectionChanged: (s) => setState(() => _severity = s.first),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: _primaryButton(
          'Continue',
          _gender == null || _duration == null
              ? null
              : () => setState(() {
                  _questionIdx = 0;
                  _step = _Step.questions;
                }),
        ),
      ),
    ],
  );

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppPalette.textBody,
      ),
    ),
  );

  // ── Step: questions ──────────────────────────────────────────────────────

  Widget _questions() {
    final q = _smartQuestions[_questionIdx];
    final total = _smartQuestions.length;
    final isLast = _questionIdx == total - 1;
    final current = _answers[q.id];
    final options = q.options ?? const ['Yes', 'No'];

    return Column(
      children: [
        _stepHeader(
          label: 'Step ${_questionIdx + 1} of $total',
          onBack: () => setState(() {
            if (_questionIdx == 0) {
              _step = _Step.details;
            } else {
              _questionIdx--;
            }
          }),
        ),
        _progress((_questionIdx + 1) / total),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
            children: [
              const Center(child: Text('❓', style: TextStyle(fontSize: 34))),
              const SizedBox(height: 16),
              Text(
                q.question,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textStrong,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                q.sub,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppPalette.textMuted,
                ),
              ),
              const SizedBox(height: 24),
              for (final opt in options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: () => setState(() => _answers[q.id] = opt),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 15,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: current == opt
                                ? AppColors.brand
                                : AppPalette.hairline,
                            width: current == opt ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                opt,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: current == opt
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: AppPalette.textStrong,
                                ),
                              ),
                            ),
                            Icon(
                              current == opt
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              size: 22,
                              color: current == opt
                                  ? AppColors.brand
                                  : AppPalette.hairline,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: _primaryButton(
            isLast ? 'Analyze' : 'Next',
            current == null
                ? null
                : () {
                    if (isLast) {
                      _startProcessing();
                    } else {
                      setState(() => _questionIdx++);
                    }
                  },
          ),
        ),
      ],
    );
  }

  // ── Step: processing ─────────────────────────────────────────────────────

  Widget _processing() => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.brand),
          const SizedBox(height: 28),
          Text(
            _processingLabels[_processingStep.clamp(
              0,
              _processingLabels.length - 1,
            )],
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppPalette.textStrong,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This usually takes a few seconds.',
            style: TextStyle(fontSize: 12, color: AppPalette.textMuted),
          ),
        ],
      ),
    ),
  );

  // ── Step: results ────────────────────────────────────────────────────────

  Widget _results() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: AppPalette.red,
              ),
              const SizedBox(height: 16),
              const Text(
                "We couldn't finish your check",
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textStrong,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppPalette.textMuted,
                ),
              ),
              const SizedBox(height: 20),
              _primaryButton('Start over', _reset),
            ],
          ),
        ),
      );
    }

    final analysis = _analysis!;
    final subscribed = _subscribed;
    final urgencyColor = switch (analysis.urgency) {
      'High' => AppPalette.red,
      'Medium' => AppPalette.orange,
      _ => AppPalette.green,
    };

    // A free user sees the top condition and everything else locked — enough
    // to know the check worked, not enough to skip the paywall.
    final visible = subscribed
        ? analysis.conditions
        : analysis.conditions.take(1).toList();
    final hiddenCount = analysis.conditions.length - visible.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Your results',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textStrong,
                ),
              ),
            ),
            TextButton(onPressed: _reset, child: const Text('New check')),
          ],
        ),
        const SizedBox(height: 12),
        _resultCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 22, color: urgencyColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Urgency: ${analysis.urgency}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: urgencyColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      analysis.urgencyDesc,
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
        ),
        const SizedBox(height: 14),
        _resultCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Possible conditions',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textStrong,
                ),
              ),
              const SizedBox(height: 12),
              for (final c in visible) _conditionRow(c),
              if (hiddenCount > 0) ...[
                for (var i = 0; i < hiddenCount; i++) _lockedRow(),
                const SizedBox(height: 10),
                _unlockButton('Unlock Full Results'),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _resultCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Suggested medication',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textStrong,
                ),
              ),
              const SizedBox(height: 12),
              if (subscribed)
                for (final m in analysis.medications)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.icon, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppPalette.textStrong,
                                ),
                              ),
                              Text(
                                m.desc,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppPalette.textMuted,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
              else ...[
                const Icon(
                  Icons.lock_outline,
                  size: 24,
                  color: AppColors.brand,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Subscribe to view recommended treatments and dosages.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppPalette.textMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                _unlockButton('Unlock with Premium'),
              ],
            ],
          ),
        ),
        if (subscribed && analysis.selfCare.isNotEmpty) ...[
          const SizedBox(height: 14),
          _resultCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Self care',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textStrong,
                  ),
                ),
                const SizedBox(height: 10),
                for (final tip in analysis.selfCare)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check,
                          size: 15,
                          color: AppPalette.green,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tip,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppPalette.textBody,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        const Text(
          'AfyaSmart provides health guidance, not a final diagnosis. For '
          'emergencies, visit the nearest hospital immediately.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: AppPalette.textMuted,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _resultCard({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppPalette.hairline),
    ),
    child: child,
  );

  Widget _conditionRow(ConditionResult c) {
    final cleaned = c.color.replaceFirst('#', '');
    final parsed = int.tryParse(cleaned, radix: 16);
    final color = parsed == null
        ? AppColors.brand
        : Color(0xFF000000 | parsed);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.textStrong,
                  ),
                ),
                Text(
                  '${c.likelihood} match',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppPalette.textMuted,
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: LinearProgressIndicator(
                    value: c.percent / 100,
                    minHeight: 5,
                    backgroundColor: AppPalette.hairline,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${c.percent}%',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lockedRow() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppPalette.hairline,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 8, color: AppPalette.hairline),
              const SizedBox(height: 5),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: 0.5,
                child: Container(height: 8, color: AppPalette.hairline),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        const Icon(Icons.lock, size: 16, color: AppPalette.hairline),
      ],
    ),
  );

  Widget _unlockButton(String label) => FilledButton.icon(
    onPressed: () => context.go(Routes.subscription),
    icon: const Icon(Icons.lock_open, size: 16),
    label: Text(label),
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.brand,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
