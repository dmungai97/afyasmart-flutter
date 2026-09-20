import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/supabase_client.dart';

/// Port of src/services/symptoms.service.ts.

class ConditionResult {
  const ConditionResult({
    required this.name,
    required this.likelihood,
    required this.percent,
    required this.color,
  });

  final String name;
  final String likelihood;
  final int percent;
  final String color;

  factory ConditionResult.fromJson(Map<String, dynamic> json) =>
      ConditionResult(
        name: json['name'] as String? ?? '',
        likelihood: json['likelihood'] as String? ?? 'Low',
        percent: (json['percent'] as num?)?.toInt() ?? 0,
        color: json['color'] as String? ?? '#0B6E6E',
      );
}

class MedicationResult {
  const MedicationResult({
    required this.name,
    required this.desc,
    required this.icon,
  });

  final String name;
  final String desc;
  final String icon;

  factory MedicationResult.fromJson(Map<String, dynamic> json) =>
      MedicationResult(
        name: json['name'] as String? ?? '',
        desc: json['desc'] as String? ?? '',
        icon: json['icon'] as String? ?? '💊',
      );
}

class SymptomsAnalysis {
  const SymptomsAnalysis({
    required this.urgency,
    required this.urgencyDesc,
    required this.conditions,
    required this.medications,
    required this.selfCare,
  });

  final String urgency;
  final String urgencyDesc;
  final List<ConditionResult> conditions;
  final List<MedicationResult> medications;
  final List<String> selfCare;

  factory SymptomsAnalysis.fromJson(Map<String, dynamic> json) =>
      SymptomsAnalysis(
        urgency: json['urgency'] as String? ?? 'Low',
        urgencyDesc: json['urgency_desc'] as String? ?? '',
        conditions: ((json['conditions'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ConditionResult.fromJson)
            .toList(),
        medications: ((json['medications'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(MedicationResult.fromJson)
            .toList(),
        selfCare: ((json['self_care'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

class ClarifyResult {
  const ClarifyResult({
    required this.done,
    this.question,
    this.options,
    this.duration,
  });

  final bool done;
  final String? question;
  final List<String>? options;
  final String? duration;

  static const finished = ClarifyResult(done: true);
}

class SymptomsService {
  const SymptomsService();

  /// Onboarding lets users check symptoms before creating an account, so
  /// these endpoints identify the caller by a locally persisted guest id
  /// rather than requiring a session.
  Future<String> _subjectId() async {
    final signedIn = currentUserId;
    if (signedIn != null) return signedIn;

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('guest_uuid');
    if (existing != null) return existing;

    final random = Random();
    final suffix = List.generate(
      9,
      (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[random.nextInt(36)],
    ).join();
    final generated =
        'guest_${suffix}_${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString('guest_uuid', generated);
    return generated;
  }

  Future<SymptomsAnalysis> analyze({
    required List<String> symptoms,
    required int age,
    required String gender,
    required String duration,
    required String severity,
    Map<String, String> answers = const {},
  }) async {
    final subjectId = await _subjectId();

    final response = await http.post(
      Uri.parse('${SupabaseConfig.resolvedFunctionsBaseUrl}/symptoms/analyze'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'symptoms': symptoms,
        'age': age,
        'gender': gender,
        'duration': duration,
        'severity': severity,
        'answers': answers,
        'subject_id': subjectId,
      }),
    );

    final body = _decode(response.body);

    if (response.statusCode != 200) {
      throw ApiException(
        body?['message'] as String? ??
            'Failed to analyze symptoms. Please try again.',
      );
    }

    final data = body?['data'];
    if (body?['status'] == 'success' && data is Map<String, dynamic>) {
      return SymptomsAnalysis.fromJson(data);
    }

    throw const ApiException('Invalid response format received from the server.');
  }

  /// Best-effort — fails safe to "done" on any error so a flaky or
  /// unreachable endpoint never blocks the onboarding funnel. Callers should
  /// treat a missing [ClarifyResult.duration] on a done result as
  /// "clarification wasn't available", not "the user has no symptom
  /// duration".
  Future<ClarifyResult> clarify({
    required String symptom,
    int? age,
    String? severity,
    List<({String question, String answer})> history = const [],
  }) async {
    try {
      final subjectId = await _subjectId();

      final response = await http.post(
        Uri.parse(
          '${SupabaseConfig.resolvedFunctionsBaseUrl}/symptoms/clarify',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'subject_id': subjectId,
          'symptom': symptom,
          'age': age,
          'severity': severity,
          'history': history
              .map((qa) => {'question': qa.question, 'answer': qa.answer})
              .toList(),
        }),
      );

      final body = _decode(response.body);
      final data = body?['data'];

      if (response.statusCode != 200 ||
          body?['status'] != 'success' ||
          data is! Map<String, dynamic>) {
        return ClarifyResult.finished;
      }

      final done = data['done'];
      if (done is! bool) return ClarifyResult.finished;

      final options = (data['options'] as List?)
          ?.map((e) => e.toString())
          .toList();
      final question = data['question'] as String?;
      final durationHint = data['duration'] as String?;

      if (!done && (question == null || options == null || options.isEmpty)) {
        return ClarifyResult(done: true, duration: durationHint);
      }

      return ClarifyResult(
        done: done,
        question: question,
        options: options,
        duration: durationHint,
      );
    } on Exception {
      return ClarifyResult.finished;
    }
  }

  static Map<String, dynamic>? _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
