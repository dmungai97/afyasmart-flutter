import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../../state/diagnosis_controller.dart';
import '../../state/providers.dart';

/// Port of src/onboarding/screens/AnalysisLoadingScreen.tsx.
class AnalysisLoadingScreen extends ConsumerStatefulWidget {
  const AnalysisLoadingScreen({super.key});

  @override
  ConsumerState<AnalysisLoadingScreen> createState() =>
      _AnalysisLoadingScreenState();
}

class _AnalysisLoadingScreenState extends ConsumerState<AnalysisLoadingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  /// Progress has no way to know a real completion percentage, so it creeps
  /// toward — but never reaches — "done" until the request actually resolves.
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4000),
  );

  bool _started = false;
  String? _error;

  @override
  void dispose() {
    _pulse.dispose();
    _spin.dispose();
    _progress.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final controller = ref.read(diagnosisControllerProvider.notifier);
    final request = ref.read(diagnosisControllerProvider).pendingAnalysisRequest;

    if (request == null) {
      context.go(Routes.symptomChat);
      return;
    }

    setState(() => _error = null);
    _pulse.repeat(reverse: true);
    _spin.repeat();
    // Crawls to ~86% and holds; the real completion drives it to 1.
    _progress.animateTo(0.86, curve: Curves.easeOut);

    try {
      final analysis = await request.run(ref.read(symptomsServiceProvider));
      if (!mounted) return;

      await controller.setPendingDiagnosis(
        PendingDiagnosis(
          symptoms: request.symptoms.join(', '),
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
      await controller.clearPendingAnalysisRequest();

      if (!mounted) return;
      _pulse.stop();
      _spin.stop();
      await _progress.animateTo(
        1,
        duration: const Duration(milliseconds: 350),
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));

      if (!mounted) return;
      context.go(Routes.lockedResults);
    } on Exception catch (e) {
      if (!mounted) return;
      _pulse.stop();
      _spin.stop();
      _progress.stop();
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Wait for the persisted diagnosis state to finish loading first —
    // otherwise a build that races ahead of that read would see
    // pendingAnalysisRequest as null and bounce the user back to
    // symptom-chat even though their request is about to load a moment later.
    final hydrated = ref.watch(
      diagnosisControllerProvider.select((s) => s.hydrated),
    );

    if (hydrated && !_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _run();
      });
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: _error == null ? _loadingBody() : _errorBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Container(
    padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.rule)),
    ),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: AppColors.ink,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.auto_awesome_outlined,
            size: 16,
            color: AppColors.paper,
          ),
        ),
        const SizedBox(width: 10),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AfyaSmart AI',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            Text(
              'Online',
              style: TextStyle(fontSize: 11, color: AppColors.success),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _loadingBody() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      AnimatedBuilder(
        animation: Listenable.merge([_pulse, _spin]),
        builder: (_, child) => Transform.rotate(
          angle: _spin.value * 6.28318,
          child: Transform.scale(
            scale: 0.9 + (_pulse.value * 0.15),
            child: child,
          ),
        ),
        child: _orb(),
      ),
      const SizedBox(height: 32),
      const Text(
        "I'm analyzing your symptoms...",
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        'This may take a few seconds',
        style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
      ),
      const SizedBox(height: 28),
      AnimatedBuilder(
        animation: _progress,
        builder: (_, _) => LinearProgressIndicator(
          value: _progress.value,
          minHeight: 2,
          backgroundColor: AppColors.rule,
          valueColor: const AlwaysStoppedAnimation(AppColors.ruleStrong),
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        'Analyzing...',
        style: TextStyle(fontSize: 11, color: AppColors.inkFaint),
      ),
    ],
  );

  Widget _orb({bool error = false}) => Container(
    width: 108,
    height: 108,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: error ? AppColors.danger : AppColors.ruleStrong,
        width: 2,
      ),
    ),
    child: Center(
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: error ? AppColors.danger : AppColors.ink,
          shape: BoxShape.circle,
        ),
        child: Icon(
          error ? Icons.priority_high : Icons.medical_services_outlined,
          size: 34,
          color: AppColors.paper,
        ),
      ),
    ),
  );

  Widget _errorBody() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _orb(error: true),
      const SizedBox(height: 32),
      const Text(
        "We couldn't finish your analysis",
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        _error ?? '',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
      ),
      const SizedBox(height: 28),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _run,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.ink,
            foregroundColor: AppColors.paper,
            shape: const StadiumBorder(),
          ),
          child: const Text('Try Again'),
        ),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => context.canPop()
            ? context.pop()
            : context.go(Routes.symptomChat),
        child: const Text(
          'Go back',
          style: TextStyle(color: AppColors.inkFaint, fontSize: 13),
        ),
      ),
    ],
  );
}
