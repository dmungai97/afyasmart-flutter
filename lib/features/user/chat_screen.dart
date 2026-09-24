import 'package:flutter/material.dart';
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
            // The context passed to the model excludes the message just
            // typed — the edge function appends it itself.
            history: _messages.sublist(0, _messages.length - 1),
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
      color: const Color(0xFFF5F7FA),
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
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _messages.length) return const _TypingIndicator();
                return _bubble(_messages[i]);
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

    return Container(
      color: AppColors.brand,
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.viewPaddingOf(context).top + 12,
        16,
        14,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AfyaSmart Assistant',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Online',
                  style: TextStyle(color: Color(0xFF9FE8C8), fontSize: 11),
                ),
              ],
            ),
          ),
          if (!subscribed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Text(
                '$remaining left',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
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
          color: isUser ? AppColors.brand : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isUser ? null : Border.all(color: AppPalette.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              m.text,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: isUser ? Colors.white : AppPalette.textBody,
              ),
            ),
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

  Widget _composer(AppUser? user) {
    final blocked =
        user != null && !user.isSubscribed && user.chatLimitReached;

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
              enabled: !blocked,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: blocked
                    ? 'Subscribe to keep chatting'
                    : 'Ask a health question…',
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
            onPressed: _sending
                ? null
                : blocked
                ? _showLimitSheet
                : _send,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
              minimumSize: const Size(46, 46),
            ),
            icon: Icon(blocked ? Icons.lock_outline : Icons.send, size: 19),
          ),
        ],
      ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.hairline),
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
