import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/supabase_client.dart';
import '../models/app_user.dart';

/// Port of src/services/chat.service.ts.

class ChatMessage {
  const ChatMessage({required this.role, required this.text, this.time});

  /// 'user' or 'ai', matching the chat_role enum.
  final String role;
  final String text;
  final String? time;

  bool get isUser => role == 'user';

  Map<String, dynamic> toWire() => {'role': role, 'text': text};
}

class SendMessageResult {
  const SendMessageResult({
    required this.reply,
    required this.chatCount,
    required this.limit,
    required this.isSubscribed,
  });

  final String reply;
  final int chatCount;
  final int limit;
  final bool isSubscribed;
}

/// Raised when the free-chat allowance is exhausted, so the UI can show the
/// subscribe prompt rather than a generic error.
class ChatLimitException implements Exception {
  const ChatLimitException();

  @override
  String toString() => 'LIMIT_REACHED';
}

class ChatService {
  const ChatService();

  Future<SendMessageResult> send({
    required String message,
    required List<ChatMessage> history,
    required AppUser? user,
  }) async {
    if (currentUserId == null) {
      throw const ApiException('You must be signed in to use chat.');
    }

    // Pre-flight check against the local profile (fast, avoids a round-trip).
    // The edge function re-checks authoritatively — this is convenience, not
    // the limit itself.
    if (user != null && !user.isSubscribed && user.chatLimitReached) {
      throw const ChatLimitException();
    }

    final token = currentAccessToken;
    final response = await http.post(
      Uri.parse('${SupabaseConfig.resolvedFunctionsBaseUrl}/chat/send'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'message': message,
        'history': history.map((m) => m.toWire()).toList(),
      }),
    );

    final body = _decode(response.body);

    if (response.statusCode != 200) {
      if (response.statusCode == 403 && body?['limit_reached'] == true) {
        throw const ChatLimitException();
      }
      throw ApiException(
        body?['message'] as String? ?? 'Chat request failed.',
      );
    }

    return SendMessageResult(
      reply: body?['reply'] as String? ?? '',
      chatCount: (body?['chat_count'] as num?)?.toInt() ?? 0,
      limit: (body?['limit'] as num?)?.toInt() ?? freeChatLimit,
      isSubscribed: body?['is_subscribed'] as bool? ?? false,
    );
  }

  /// Chat history.
  ///
  /// chat_messages_select scopes this to the caller's own rows, so the
  /// user_id filter is belt-and-braces rather than the security boundary.
  Future<List<ChatMessage>> history() async {
    final userId = currentUserId;
    if (userId == null) {
      throw const ApiException('You must be signed in to use chat.');
    }

    final rows = await supabase
        .from('chat_messages')
        .select('role, text, created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: true)
        .limit(100);

    return rows
        .map(
          (row) => ChatMessage(
            role: row['role'] as String,
            text: row['text'] as String? ?? '',
            time: _formatTime(row['created_at'] as String?),
          ),
        )
        .toList();
  }

  static Map<String, dynamic>? _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static String? _formatTime(String? iso) {
    if (iso == null) return null;
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return null;
    final local = parsed.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
