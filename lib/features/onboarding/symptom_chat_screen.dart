import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../../state/diagnosis_controller.dart';
import '../../state/providers.dart';
import 'widgets/vitals_rule.dart';

/// Port of src/onboarding/screens/SymptomChatScreen.tsx.
class SymptomChatScreen extends ConsumerStatefulWidget {
  const SymptomChatScreen({super.key});

  @override
  ConsumerState<SymptomChatScreen> createState() => _SymptomChatScreenState();
}

class _Message {
  const _Message({required this.fromUser, required this.text, this.typing = false});

  final bool fromUser;
  final String text;
  final bool typing;
}

/// 'clarify' is a real AI-generated follow-up question (content depends on
/// what the user typed) — capped at two rounds server-side. 'duration' is a
/// fixed fallback used only when the AI clarify step is unavailable, so a
/// duration is always collected either way. 'busy' locks the composer and
/// hides the chip row while the next step loads.
enum _Stage { symptom, clarify, duration, gender, busy }

const _durationOptions = ['Today', '1-3 days', '4-7 days', 'Longer than a week'];

const _genderOptions = [
  (label: 'Female', value: 'female'),
  (label: 'Male', value: 'male'),
  (label: 'Prefer not to say', value: 'other'),
];

class _SymptomChatScreenState extends ConsumerState<SymptomChatScreen> {
  final _messages = <_Message>[
    const _Message(
      fromUser: false,
      text:
          "Hi 👋 I'm your AfyaSmart Doctor Assistant.\n\n"
          "I'll help you understand what your symptoms might mean. "
          "What are you experiencing today?",
    ),
  ];

  final _input = TextEditingController();
  final _scroll = ScrollController();

  _Stage _stage = _Stage.symptom;
  String _symptomText = '';
  String? _durationAnswer;
  final _clarifyHistory = <({String question, String answer})>[];
  String? _currentQuestion;
  List<String> _currentOptions = const [];

  /// Counts consecutive too-short submissions so the "tell me a bit more"
  /// nudge only ever shows once. Without this, someone who keeps typing
  /// short answers gets the identical canned message appended again on every
  /// attempt, which reads as the chat being stuck rather than nudging.
  int _shortAttempts = 0;

  /// A one- or two-word description ("sick", "not well") still reaches the AI
  /// analysis step and comes back looking like a confident, specific
  /// diagnosis — the model is not trained to say "I don't have enough to go
  /// on". Catching it here, before it ever reaches the AI, is more reliable
  /// than hoping the model hedges appropriately.
  static const _minSymptomWords = 3;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _append(List<_Message> messages) {
    setState(() => _messages.addAll(messages));
    _scrollToBottom();
  }

  void _showTyping() {
    setState(
      () => _messages.add(const _Message(fromUser: false, text: '', typing: true)),
    );
    _scrollToBottom();
  }

  void _hideTyping() {
    setState(() => _messages.removeWhere((m) => m.typing));
  }

  /// Shows a typing bubble, asks the AI whether one more clarifying question
  /// is worth asking about this specific symptom, and either shows that
  /// question or moves on. If the clarify call is unavailable it fails safe
  /// to the fixed duration chips, so a duration is always collected.
  Future<void> _runClarifyStep(
    String symptom,
    List<({String question, String answer})> history,
  ) async {
    _showTyping();

    final answers = ref.read(diagnosisControllerProvider).healthCheckAnswers;
    final result = await ref
        .read(symptomsServiceProvider)
        .clarify(
          symptom: symptom,
          age: HealthCheckMapping.age(answers),
          severity: HealthCheckMapping.severity(answers),
          history: history,
        );

    if (!mounted) return;
    _hideTyping();

    if (!result.done) {
      final question = result.question ?? 'Can you tell me a bit more?';
      setState(() {
        _currentQuestion = question;
        _currentOptions = result.options ?? const [];
        _stage = _Stage.clarify;
      });
      _append([_Message(fromUser: false, text: question)]);
      return;
    }

    if (result.duration != null) {
      setState(() {
        _durationAnswer = result.duration;
        _stage = _Stage.gender;
      });
      _append([
        const _Message(
          fromUser: false,
          text: 'Got it. And which best describes you?',
        ),
      ]);
    } else {
      setState(() => _stage = _Stage.duration);
      _append([
        const _Message(
          fromUser: false,
          text: 'Got it. How long have you had this?',
        ),
      ]);
    }
  }

  Future<void> _sendSymptom() async {
    final text = _input.text.trim();
    if (text.isEmpty || _stage != _Stage.symptom) return;

    final wordCount = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    if (wordCount < _minSymptomWords && _shortAttempts == 0) {
      // Nudge once. If they submit another short answer right after, don't
      // repeat the identical message — just proceed with it.
      _shortAttempts++;
      _input.clear();
      _append([
        _Message(fromUser: true, text: text),
        const _Message(
          fromUser: false,
          text:
              'Could you tell me a bit more? For example, where it hurts, '
              'what it feels like, or when it started — a few more details '
              'helps me give you a more useful analysis.',
        ),
      ]);
      // Stage stays 'symptom' — the composer remains open for another try.
      return;
    }

    _shortAttempts = 0;
    _input.clear();
    setState(() {
      _symptomText = text;
      _stage = _Stage.busy;
    });
    _append([_Message(fromUser: true, text: text)]);

    await _runClarifyStep(text, const []);
  }

  Future<void> _pickClarify(String option) async {
    final question = _currentQuestion;
    if (question == null) return;

    _clarifyHistory.add((question: question, answer: option));
    setState(() => _stage = _Stage.busy);
    _append([_Message(fromUser: true, text: option)]);

    await _runClarifyStep(_symptomText, List.of(_clarifyHistory));
  }

  Future<void> _pickDuration(String option) async {
    setState(() {
      _durationAnswer = option;
      _stage = _Stage.busy;
    });
    _append([_Message(fromUser: true, text: option)]);

    _showTyping();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _hideTyping();

    setState(() => _stage = _Stage.gender);
    _append([
      const _Message(fromUser: false, text: 'And which best describes you?'),
    ]);
  }

  Future<void> _pickGender(String label, String value) async {
    setState(() => _stage = _Stage.busy);
    _append([_Message(fromUser: true, text: label)]);

    final answers = ref.read(diagnosisControllerProvider).healthCheckAnswers;

    final request = PendingAnalysisRequest(
      symptoms: [_symptomText],
      age: HealthCheckMapping.age(answers),
      gender: value,
      duration: _durationAnswer ?? '1-3 days',
      severity: HealthCheckMapping.severity(answers),
      answers: {
        if (answers?.concern != null) 'concern': answers!.concern!,
        for (var i = 0; i < _clarifyHistory.length; i++)
          'followup_${i + 1}_${_clarifyHistory[i].question}':
              _clarifyHistory[i].answer,
      },
    );

    await ref
        .read(diagnosisControllerProvider.notifier)
        .setPendingAnalysisRequest(request);

    // Brief typing beat before handing off — the actual analysis runs on the
    // next screen, so this message cannot claim findings it does not have.
    if (!mounted) return;
    _showTyping();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _hideTyping();

    _append([
      const _Message(
        fromUser: false,
        text: 'Got it — let me analyze that for you now.',
      ),
    ]);

    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    context.push(Routes.analysisLoading);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      // resizeToAvoidBottomInset keeps the composer above the IME. The RN
      // version needed react-native-keyboard-controller for this; Flutter
      // handles it natively.
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            OnboardingHeader(
              title: 'AfyaSmart Doctor Assistant',
              onBack: () => context.canPop()
                  ? context.pop()
                  : context.go(Routes.healthCheck),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                itemCount: _messages.length,
                itemBuilder: (_, i) => _bubble(_messages[i]),
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _bubble(_Message message) {
    if (message.typing) return const _TypingBubble();

    final isUser = message.fromUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser ? AppColors.ink : AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: isUser ? AppColors.ink : AppColors.rule),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isUser ? AppColors.paper : AppColors.ink,
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ),
    );
  }

  /// The footer is one of: the free-text composer, a chip row, or nothing
  /// while a step is in flight.
  Widget _footer() => switch (_stage) {
    _Stage.symptom => _composer(),
    _Stage.clarify => _chips(_currentOptions, _pickClarify),
    _Stage.duration => _chips(_durationOptions, _pickDuration),
    _Stage.gender => _chips(
      _genderOptions.map((g) => g.label).toList(),
      (label) => _pickGender(
        label,
        _genderOptions.firstWhere((g) => g.label == label).value,
      ),
    ),
    _Stage.busy => const SizedBox(height: 16),
  };

  Widget _chips(List<String> options, Future<void> Function(String) onPick) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.rule)),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              OutlinedButton(
                onPressed: () => onPick(option),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  side: const BorderSide(color: AppColors.ruleStrong),
                  shape: const StadiumBorder(),
                  foregroundColor: AppColors.ink,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                child: Text(option),
              ),
          ],
        ),
      );

  Widget _composer() => Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.rule)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _input,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _sendSymptom(),
            decoration: const InputDecoration(
              hintText: 'Describe how you feel…',
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filled(
          onPressed: _sendSymptom,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.ink,
            foregroundColor: AppColors.paper,
            minimumSize: const Size(46, 46),
          ),
          icon: const Icon(Icons.arrow_upward, size: 20),
        ),
      ],
    ),
  );
}

/// Three dots bouncing out of phase, matching the RN staggered dot animation.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: AppColors.rule),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              AnimatedBuilder(
                animation: _c,
                builder: (_, _) {
                  // 150ms offset per dot, as a fraction of the 900ms cycle.
                  final t = (_c.value - i * (150 / 900)) % 1.0;
                  final lift = t < 0.5 ? -6 * (t * 2) : -6 * (2 - t * 2);
                  return Transform.translate(
                    offset: Offset(0, lift),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.inkFaint,
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
