import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../models/app_user.dart';
import '../../services/chat_service.dart';
import '../../state/auth_controller.dart';
import '../../state/providers.dart';

/// Port of src/user/screens/ChatScreen.tsx.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

const _suggestions = [
  'I have a headache',
  'What causes fever?',
  'Is my cough serious?',
  'Help me sleep better',
];

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  List<ChatMessage> _messages = [
    const ChatMessage(
      role: 'ai',
      text:
          "Hello! I'm your AfyaSmart health assistant. "
          'How can I help you today?',
    ),
  ];

  bool _sending = false;
  bool _historyLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Loads the stored conversation once on open.
  ///
  /// getChatHistory existed in the RN app but nothing ever called it — every
  /// reopen reset to the canned greeting, silently discarding a history that
  /// was being saved correctly the whole time. Only replaces the greeting
  /// when there is real history; a brand-new chat keeps it.
  Future<void> _loadHistory() async {
    try {
      final history = await ref.read(chatServiceProvider).history();
      if (!mounted || history.isEmpty) return;
      setState(() => _messages = history);
      _scrollToBottom();
    } on Exception {
      // Fall back silently to the greeting already in state.
    } finally {
      if (mounted) setState(() => _historyLoaded = true);
    }
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

  String _now() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;

    final user = ref.read(currentUserProvider);
    if (user != null && !user.isSubscribed && user.chatLimitReached) {
      _showLimitSheet();
      return;
    }

    _input.clear();
    setState(() {
      _messages = [
        ..._messages,
        ChatMessage(role: 'user', text: text, time: _now()),
      ];
      _sending = true;
    });
    _scrollToBottom();

    try {
      final result = await ref
          .read(chatServiceProvider)
          .send(
            message: text,
            user: user,
          );

      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages,
          ChatMessage(role: 'ai', text: result.reply, time: _now()),
        ];
      });

      // The reply carries the authoritative chat_count, so refresh the
      // profile rather than guessing at the new remaining count locally.
      await ref.read(authControllerProvider.notifier).refresh();
    } on ChatLimitException {
      if (!mounted) return;
      await ref.read(authControllerProvider.notifier).refresh();
      if (mounted) _showLimitSheet();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages,
          ChatMessage(
            role: 'ai',
            text: e.message.isNotEmpty
                ? e.message
                : 'Sorry, I could not process your request. Please try again.',
            time: _now(),
          ),
        ];
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages,
          ChatMessage(
            role: 'ai',
            text: 'Sorry, I could not process your request. Please try again.',
            time: _now(),
          ),
        ];
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _showLimitSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppPalette.purpleBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.lock_outline,
                  size: 28,
                  color: AppPalette.purple,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "You've used your free chats",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textStrong,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Subscribe to keep chatting with the AfyaSmart assistant, '
                'and unlock doctors, pharmacies and the drug database.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppPalette.textMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  context.go(Routes.subscription);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('View plans'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _header(user),
          if (!_historyLoaded)
            const LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(AppColors.brand),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              // +1 for the disclaimer that heads the conversation.
              itemCount: _messages.length + 1 + (_sending ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == 0) return const _Disclaimer();
                if (i == _messages.length + 1) return const _TypingIndicator();
                return _bubble(_messages[i - 1]);
              },
            ),
          ),
          // The starter prompts only make sense on an empty conversation.
          if (_messages.length <= 1 && !_sending) _suggestionRow(),
          _composer(user),
        ],
      ),
    );
  }

  Widget _header(AppUser? user) {
    final remaining = user?.remainingFreeChats ?? 0;
    final subscribed = user?.isSubscribed ?? false;

    // Flat, white, same surface as the conversation: the header is a label,
    // not a banner. Dark status-bar icons to match.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          20,
          MediaQuery.viewPaddingOf(context).top + 10,
          12,
          10,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: AppPalette.hairline)),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AfyaSmart',
                    style: TextStyle(
                      color: AppPalette.textStrong,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  SizedBox(height: 1),
                  Text(
                    'Health assistant',
                    style: TextStyle(
                      color: AppPalette.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (!subscribed)
              remaining == 0
                  ? TextButton(
                      onPressed: () => context.go(Routes.subscription),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.brand,
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Upgrade'),
                    )
                  : Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        remaining == 1 ? '1 free chat' : '$remaining free chats',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppPalette.textMuted,
                        ),
                      ),
                    ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(ChatMessage m) {
    final isUser = m.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser ? AppColors.brand : const Color(0xFFF2F4F5),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (isUser)
              Text(
                m.text,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Colors.white,
                ),
              )
            else
              _FormattedReply(m.text),
            if (m.time != null && m.time!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                m.time!,
                style: TextStyle(
                  fontSize: 9,
                  color: isUser ? Colors.white70 : AppPalette.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _suggestionRow() => SizedBox(
    height: 44,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      children: [
        for (final s in _suggestions)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              label: Text(s),
              onPressed: () => _send(s),
              backgroundColor: Colors.white,
              side: const BorderSide(color: AppPalette.hairline),
              labelStyle: const TextStyle(
                fontSize: 12,
                color: AppColors.brand,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    ),
  );

  /// Replaces the composer once the free chats are used: a disabled text
  /// field with a padlock read as broken rather than as "subscribe".
  Widget _limitBar() => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: AppPalette.hairline)),
    ),
    child: Row(
      children: [
        const Icon(Icons.lock_outline, size: 18, color: AppPalette.textMuted),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            "You've used your free chats",
            style: TextStyle(fontSize: 13, color: AppPalette.textBody),
          ),
        ),
        FilledButton(
          onPressed: () => context.go(Routes.subscription),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brand,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            minimumSize: const Size(0, 38),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
          ),
          child: const Text('Subscribe'),
        ),
      ],
    ),
  );

  Widget _composer(AppUser? user) {
    final blocked =
        user != null && !user.isSubscribed && user.chatLimitReached;

    if (blocked) return _limitBar();

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.viewPaddingOf(context).bottom * 0,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppPalette.hairline)),
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
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Ask a health question…',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF5F7FA),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filled(
            onPressed: _sending ? null : _send,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
              minimumSize: const Size(46, 46),
            ),
            icon: const Icon(Icons.send_rounded, size: 19),
          ),
        ],
      ),
    );
  }
}

/// Small print at the top of every conversation. A health assistant should
/// say what it is not, once, without nagging on every reply.
class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(24, 4, 24, 16),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.info_outline, size: 13, color: AppPalette.textMuted),
        ),
        SizedBox(width: 6),
        Flexible(
          child: Text(
            'AfyaSmart gives general health information, not a diagnosis. '
            'In an emergency call 999 or 112.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: AppPalette.textMuted,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Renders the small subset of Markdown the assistant is told to use:
/// **bold** spans and "- " / "* " / "1. " list lines. Anything else is shown
/// as plain text; stray heading markers are turned into bold lines.
class _FormattedReply extends StatelessWidget {
  const _FormattedReply(this.text);

  final String text;

  static const _style = TextStyle(
    fontSize: 14,
    height: 1.45,
    color: AppPalette.textBody,
  );

  static final _bullet = RegExp(r'^\s*[-*•]\s+');
  static final _numbered = RegExp(r'^\s*(\d+)[.)]\s+');
  static final _heading = RegExp(r'^\s*#{1,6}\s+');

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    for (final raw in text.trim().split('\n')) {
      if (raw.trim().isEmpty) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 6));
        continue;
      }

      final bullet = _bullet.firstMatch(raw);
      final numbered = _numbered.firstMatch(raw);

      if (bullet != null || numbered != null) {
        final marker = bullet != null ? '•' : '${numbered!.group(1)}.';
        final body = raw.substring((bullet ?? numbered)!.end);
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 20,
                  child: Text(
                    marker,
                    style: _style.copyWith(
                      color: AppColors.brand,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(child: Text.rich(_spans(body), style: _style)),
              ],
            ),
          ),
        );
      } else {
        final heading = _heading.firstMatch(raw);
        final body =
            heading != null ? '**${raw.substring(heading.end)}**' : raw;
        children.add(Text.rich(_spans(body), style: _style));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  /// Splits on ** pairs. An unbalanced line is shown as-is rather than
  /// guessing which marker was meant.
  static TextSpan _spans(String line) {
    final parts = line.split('**');
    if (parts.length.isEven) return TextSpan(text: line);
    return TextSpan(
      children: [
        for (var i = 0; i < parts.length; i++)
          if (parts[i].isNotEmpty)
            TextSpan(
              text: parts[i],
              style: i.isOdd
                  ? const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textStrong,
                    )
                  : null,
            ),
      ],
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
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
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            AnimatedBuilder(
              animation: _c,
              builder: (_, _) {
                final t = (_c.value - i * (150 / 900)) % 1.0;
                final lift = t < 0.5 ? -6 * (t * 2) : -6 * (2 - t * 2);
                return Transform.translate(
                  offset: Offset(0, lift),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppPalette.textMuted,
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
