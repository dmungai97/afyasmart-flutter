import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../../state/diagnosis_controller.dart';
import 'widgets/vitals_rule.dart';

/// Port of src/onboarding/screens/HealthCheckScreen.tsx.
class HealthCheckScreen extends ConsumerStatefulWidget {
  const HealthCheckScreen({super.key});

  @override
  ConsumerState<HealthCheckScreen> createState() => _HealthCheckScreenState();
}

typedef _Step = ({
  String id,
  String question,
  String emoji,
  List<String> options,
});

const _steps = <_Step>[
  (
    id: 'age',
    question: 'What is your age group?',
    emoji: '🎂',
    options: ['Under 18', '18 – 30', '31 – 45', '46 – 60', 'Over 60'],
  ),
  (
    id: 'feeling',
    question: 'How are you feeling today?',
    emoji: '💭',
    options: ['Very unwell', 'Unwell', 'Okay', 'Good', 'Great'],
  ),
  (
    id: 'concern',
    question: 'What worries you most about your health?',
    emoji: '❤️',
    options: [
      'Recent symptoms',
      'Chronic condition',
      'Mental health',
      'General check-up',
      'Medication advice',
    ],
  ),
];

class _HealthCheckScreenState extends ConsumerState<HealthCheckScreen> {
  int _step = 0;
  final _answers = <String, String>{};

  _Step get _current => _steps[_step];

  Future<void> _select(String option) async {
    _answers[_current.id] = option;

    if (_step < _steps.length - 1) {
      setState(() => _step++);
      return;
    }

    await ref
        .read(diagnosisControllerProvider.notifier)
        .setHealthCheckAnswers(
          HealthCheckAnswers(
            age: _answers['age'],
            feeling: _answers['feeling'],
            concern: _answers['concern'],
          ),
        );

    if (!mounted) return;
    context.push(Routes.symptomChat);
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.welcome);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_step + 1) / _steps.length;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OnboardingHeader(
              title: 'Quick Health Check',
              trailing: '${_step + 1}/${_steps.length}',
              onBack: _back,
            ),
            // Progress rule, not a rounded Material bar — structure here is
            // hairlines.
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 2,
                backgroundColor: AppColors.rule,
                valueColor: const AlwaysStoppedAnimation(AppColors.ruleStrong),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                // Keyed on the step so each question slides in as its own
                // widget, reproducing the RN slide transition.
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.08, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Column(
                    key: ValueKey(_step),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _current.emoji,
                        style: const TextStyle(fontSize: 34),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _current.question,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Select one to continue',
                        style: TextStyle(
                          color: AppColors.inkFaint,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        decoration: const BoxDecoration(
                          border: Border(top: BorderSide(color: AppColors.rule)),
                        ),
                        child: Column(
                          children: [
                            for (final option in _current.options)
                              _optionRow(option),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionRow(String option) {
    final selected = _answers[_current.id] == option;

    return InkWell(
      onTap: () => _select(option),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.rule)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                option,
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            Icon(
              selected ? Icons.check : Icons.chevron_right,
              size: 18,
              color: selected ? AppColors.accent : AppColors.inkFaint,
            ),
          ],
        ),
      ),
    );
  }
}
