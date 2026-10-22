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
  const _Message({
    required this.fromUser,
    required this.text,
    this.typing = false,
  });

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

const _durationOptions = [
  'Today',
  '1-3 days',
  '4-7 days',
  'Longer than a week',
];

/// Says what is being asked and why; "which best describes you?" did neither.
const _genderQuestion =
    'Last question: are you female or male? Some conditions are more '
    'common in one or the other.';

const _genderOptions = [
  (label: 'Female', value: 'female'),
  (label: 'Male', value: 'male'),
  (label: 'Prefer not to say', value: 'other'),
];

class _SymptomChatScreenState extends ConsumerState<SymptomChatScreen> {
  final _messages = <_Message>[
    const _Message(
      fromUser: false,
      // Not "Doctor Assistant": no doctor is involved, and a health app
      // should not let anyone think one is.
      text:
          "Hi, I'm the AfyaSmart health assistant.\n\n"
          "I'm not a doctor, but I can help you understand what your "
          "symptoms might mean and what to do next. "
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

  /// Counts consecutive vague submissions so the "tell me a bit more" nudge
  /// only ever shows once. Without this, someone who keeps typing vague
  /// answers gets the identical canned message appended again on every
  /// attempt, which reads as the chat being stuck rather than nudging.
  int _vagueAttempts = 0;

  /// A description with nothing specific in it ("sick", "not well") reaches
  /// the AI analysis step and comes back looking like a confident, specific
  /// diagnosis, so it is caught here first. This used to be a word count,
  /// which also stopped short but perfectly good answers like "shoulder
  /// aches" or "headache"; the AI's follow-up questions handle those.
  static final _vague = RegExp(
    r"^(i'?m |i am |i feel |feeling |am )?"
    r'(sick|ill|unwell|not (feeling )?(well|good|ok|okay|fine)|'
    r'pain|in pain|aches?|bad|help|mgonjwa|naumwa|nimeugua|'
    r'sijisikii vizuri|si poa)[\s!.,?]*$',
    caseSensitive: false,
  );

  /// "Hi" is a greeting, not a symptom: it gets a greeting back and never
  /// counts as the one short answer that is let through to the AI.
  static final _greeting = RegExp(
    r'^(hi+|hey+|hello+|helo|hallo|good (morning|afternoon|evening)|'
    r'habari( yako)?|jambo|hujambo|mambo|sasa|niaje|salaam?|vipi)[\s!.,?]*$',
    caseSensitive: false,
  );

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
      () => _messages.add(
        const _Message(fromUser: false, text: '', typing: true),
      ),
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
          feeling: answers?.feeling,
          concern: answers?.concern,
          history: history,
        );

    if (!mounted) return;
    _hideTyping();

    // The AI's acknowledgement of what they just said, or a plain fallback
    // when the clarify call was unavailable.
    final ack = result.ack ?? 'Got it.';

    if (!result.done) {
      final question = result.question ?? 'Can you tell me a bit more?';
      setState(() {
        _currentQuestion = question;
        _currentOptions = result.options ?? const [];
        _stage = _Stage.clarify;
      });
      // One bubble, like the later steps: two in a row read as choppy.
      _append([
        _Message(
          fromUser: false,
          text: result.ack == null ? question : '${result.ack} $question',
        ),
      ]);
      return;
    }

    // "Not specified" is the model saying it could not tell, so ask.
    final duration = result.duration == 'Not specified'
        ? null
        : result.duration;

    if (duration != null) {
      setState(() {
        _durationAnswer = duration;
        _stage = _Stage.gender;
      });
      _append([
        _Message(fromUser: false, text: '$ack $_genderQuestion'),
      ]);
    } else {
      setState(() => _stage = _Stage.duration);
      _append([
        _Message(fromUser: false, text: '$ack How long have you had this?'),
      ]);
    }
  }

  Future<void> _sendSymptom() async {
    final text = _input.text.trim();
    if (text.isEmpty || _stage != _Stage.symptom) return;

    if (_greeting.hasMatch(text)) {
      _input.clear();
      _append([
        _Message(fromUser: true, text: text),
        const _Message(
          fromUser: false,
          text:
              "Hello! What's bothering you today? Describe it in your own "
              'words, for example "headache since yesterday" or '
              '"stomach pain after eating".',
        ),
      ]);
      return;
    }

    if (_vague.hasMatch(text) && _vagueAttempts == 0) {
      // Nudge once. If they submit another vague answer right after, don't
      // repeat the identical message — just proceed with it.
      _vagueAttempts++;
      _input.clear();
      _append([
        _Message(fromUser: true, text: text),
        const _Message(
          fromUser: false,
          text:
              'Could you tell me a bit more? For example, where it hurts, '
              'what it feels like, or when it started. A few more details '
              'help me give you a more useful answer.',
        ),
      ]);
      // Stage stays 'symptom' — the composer remains open for another try.
      return;
    }

    _vagueAttempts = 0;
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

  /// A typed answer to the AI's question, for when none of the options fit.
  Future<void> _sendClarifyText() async {
    final text = _input.text.trim();
    if (text.isEmpty || _stage != _Stage.clarify) return;
    _input.clear();
    await _pickClarify(text);
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
      const _Message(fromUser: false, text: _genderQuestion),
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
    context.go(Routes.analysisLoading);
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
              title: 'Symptom check',
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
    _Stage.symptom => _composer(
      onSend: _sendSymptom,
      hint: 'Describe how you feel…',
    ),
    // Options for a quick tap, plus the composer for an answer that none of
    // them fits.
    _Stage.clarify => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _chips(_currentOptions, _pickClarify),
        _composer(onSend: _sendClarifyText, hint: 'Or type your answer…'),
      ],
    ),
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
                  // 44px tall: these are the main way to answer, so they
                  // need a full-size tap target.
                  minimumSize: const Size(0, 44),
                  tapTargetSize: MaterialTapTargetSize.padded,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  side: const BorderSide(color: AppColors.ruleStrong),
                  shape: const StadiumBorder(),
                  foregroundColor: AppColors.ink,
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                child: Text(option),
              ),
          ],
        ),
      );

  Widget _composer({
    required Future<void> Function() onSend,
    required String hint,
  }) => Container(
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
            onSubmitted: (_) => onSend(),
            decoration: InputDecoration(hintText: hint, isDense: true),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filled(
          onPressed: onSend,
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
