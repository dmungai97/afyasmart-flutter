import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/symptoms_service.dart';

/// Port of src/store/diagnosisStore.ts.
///
/// Persisted, not just in-memory, because the onboarding funnel's own next
/// step after locked-results is backgrounding the app to approve an M-Pesa
/// STK push — exactly the kind of backgrounding event that can get the
/// process reclaimed on lower-end Android devices. Without persistence that
/// silently drops the user's answers and the screens fall back to generic
/// placeholder data instead of their actual results.

class DiagnosisCondition {
  const DiagnosisCondition({
    required this.name,
    required this.probability,
    required this.level,
    required this.color,
  });

  final String name;
  final int probability;

  /// 'High' | 'Medium' | 'Low'
  final String level;

  /// Hex string as returned by the analysis endpoint, e.g. '#EF4444'.
  final String color;

  Map<String, dynamic> toJson() => {
    'name': name,
    'probability': probability,
    'level': level,
    'color': color,
  };

  factory DiagnosisCondition.fromJson(Map<String, dynamic> json) =>
      DiagnosisCondition(
        name: json['name'] as String? ?? '',
        probability: (json['probability'] as num?)?.toInt() ?? 0,
        level: json['level'] as String? ?? 'Low',
        color: json['color'] as String? ?? '#0B6E6E',
      );
}

class DiagnosisMedication {
  const DiagnosisMedication({required this.name, required this.note});

  final String name;
  final String note;

  Map<String, dynamic> toJson() => {'name': name, 'note': note};

  factory DiagnosisMedication.fromJson(Map<String, dynamic> json) =>
      DiagnosisMedication(
        name: json['name'] as String? ?? '',
        note: json['note'] as String? ?? '',
      );
}

class PendingDiagnosis {
  const PendingDiagnosis({
    required this.symptoms,
    required this.summary,
    required this.urgency,
    required this.conditions,
    required this.medications,
    required this.preparedAt,
  });

  final String symptoms;
  final String summary;
  final String urgency;
  final List<DiagnosisCondition> conditions;
  final List<DiagnosisMedication> medications;
  final DateTime preparedAt;

  Map<String, dynamic> toJson() => {
    'symptoms': symptoms,
    'summary': summary,
    'urgency': urgency,
    'conditions': conditions.map((c) => c.toJson()).toList(),
    'medications': medications.map((m) => m.toJson()).toList(),
    'preparedAt': preparedAt.toIso8601String(),
  };

  factory PendingDiagnosis.fromJson(Map<String, dynamic> json) =>
      PendingDiagnosis(
        symptoms: json['symptoms'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        urgency: json['urgency'] as String? ?? 'Low',
        conditions: ((json['conditions'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(DiagnosisCondition.fromJson)
            .toList(),
        medications: ((json['medications'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(DiagnosisMedication.fromJson)
            .toList(),
        preparedAt:
            DateTime.tryParse(json['preparedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

class HealthCheckAnswers {
  const HealthCheckAnswers({this.age, this.feeling, this.concern});

  final String? age;
  final String? feeling;
  final String? concern;

  Map<String, dynamic> toJson() => {
    'age': age,
    'feeling': feeling,
    'concern': concern,
  };

  factory HealthCheckAnswers.fromJson(Map<String, dynamic> json) =>
      HealthCheckAnswers(
        age: json['age'] as String?,
        feeling: json['feeling'] as String?,
        concern: json['concern'] as String?,
      );
}

/// The analysis request, held between symptom-chat and analysis-loading.
class PendingAnalysisRequest {
  const PendingAnalysisRequest({
    required this.symptoms,
    required this.age,
    required this.gender,
    required this.duration,
    required this.severity,
    required this.answers,
  });

  final List<String> symptoms;
  final int age;
  final String gender;
  final String duration;
  final String severity;
  final Map<String, String> answers;

  Map<String, dynamic> toJson() => {
    'symptoms': symptoms,
    'age': age,
    'gender': gender,
    'duration': duration,
    'severity': severity,
    'answers': answers,
  };

  factory PendingAnalysisRequest.fromJson(Map<String, dynamic> json) =>
      PendingAnalysisRequest(
        symptoms: ((json['symptoms'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        age: (json['age'] as num?)?.toInt() ?? 25,
        gender: json['gender'] as String? ?? 'other',
        duration: json['duration'] as String? ?? '1-3 days',
        severity: json['severity'] as String? ?? 'Moderate',
        answers: ((json['answers'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
      );
}

class DiagnosisState {
  const DiagnosisState({
    this.pendingDiagnosis,
    this.healthCheckAnswers,
    this.pendingAnalysisRequest,
    this.hydrated = false,
  });

  final PendingDiagnosis? pendingDiagnosis;
  final HealthCheckAnswers? healthCheckAnswers;
  final PendingAnalysisRequest? pendingAnalysisRequest;

  /// SharedPreferences reads are async, so there is a brief window on start
  /// where this still holds its defaults before the persisted blob loads. A
  /// screen that checks "is there a pending request?" during that window
  /// would wrongly conclude there isn't one and navigate the user away —
  /// analysis-loading in particular must wait for this.
  final bool hydrated;
}

class DiagnosisController extends Notifier<DiagnosisState> {
  static const _key = 'afyasmart-diagnosis';

  @override
  DiagnosisState build() {
    unawaited(_load());
    return const DiagnosisState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);

    if (raw == null) {
      state = const DiagnosisState(hydrated: true);
      return;
    }

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      state = DiagnosisState(
        hydrated: true,
        pendingDiagnosis: json['pendingDiagnosis'] == null
            ? null
            : PendingDiagnosis.fromJson(
                json['pendingDiagnosis'] as Map<String, dynamic>,
              ),
        healthCheckAnswers: json['healthCheckAnswers'] == null
            ? null
            : HealthCheckAnswers.fromJson(
                json['healthCheckAnswers'] as Map<String, dynamic>,
              ),
        pendingAnalysisRequest: json['pendingAnalysisRequest'] == null
            ? null
            : PendingAnalysisRequest.fromJson(
                json['pendingAnalysisRequest'] as Map<String, dynamic>,
              ),
      );
    } on Object {
      // A malformed blob (an older shape, a truncated write) must not brick
      // onboarding — drop it and start clean.
      await prefs.remove(_key);
      state = const DiagnosisState(hydrated: true);
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'pendingDiagnosis': state.pendingDiagnosis?.toJson(),
        'healthCheckAnswers': state.healthCheckAnswers?.toJson(),
        'pendingAnalysisRequest': state.pendingAnalysisRequest?.toJson(),
      }),
    );
  }

  Future<void> setHealthCheckAnswers(HealthCheckAnswers answers) async {
    state = DiagnosisState(
      hydrated: true,
      pendingDiagnosis: state.pendingDiagnosis,
      healthCheckAnswers: answers,
      pendingAnalysisRequest: state.pendingAnalysisRequest,
    );
    await _persist();
  }

  Future<void> setPendingAnalysisRequest(PendingAnalysisRequest request) async {
    state = DiagnosisState(
      hydrated: true,
      pendingDiagnosis: state.pendingDiagnosis,
      healthCheckAnswers: state.healthCheckAnswers,
      pendingAnalysisRequest: request,
    );
    await _persist();
  }

  Future<void> setPendingDiagnosis(PendingDiagnosis diagnosis) async {
    state = DiagnosisState(
      hydrated: true,
      pendingDiagnosis: diagnosis,
      healthCheckAnswers: state.healthCheckAnswers,
      pendingAnalysisRequest: state.pendingAnalysisRequest,
    );
    await _persist();
  }

  Future<void> clearPendingAnalysisRequest() async {
    state = DiagnosisState(
      hydrated: true,
      pendingDiagnosis: state.pendingDiagnosis,
      healthCheckAnswers: state.healthCheckAnswers,
    );
    await _persist();
  }

  Future<void> clearPendingDiagnosis() async {
    state = DiagnosisState(
      hydrated: true,
      healthCheckAnswers: state.healthCheckAnswers,
      pendingAnalysisRequest: state.pendingAnalysisRequest,
    );
    await _persist();
  }
}

final diagnosisControllerProvider =
    NotifierProvider<DiagnosisController, DiagnosisState>(
      DiagnosisController.new,
    );

/// Maps the health-check answers onto the fields the analysis endpoint wants.
/// Ported from the lookup tables at the top of SymptomChatScreen.tsx.
abstract final class HealthCheckMapping {
  static const ageGroupToAge = {
    'Under 18': 16,
    '18 – 30': 24,
    '31 – 45': 38,
    '46 – 60': 53,
    'Over 60': 68,
  };

  static const feelingToSeverity = {
    'Very unwell': 'Severe',
    'Unwell': 'Moderate',
    'Okay': 'Mild',
    'Good': 'Mild',
    'Great': 'Mild',
  };

  static int age(HealthCheckAnswers? answers) =>
      ageGroupToAge[answers?.age ?? ''] ?? 25;

  static String severity(HealthCheckAnswers? answers) =>
      feelingToSeverity[answers?.feeling ?? ''] ?? 'Moderate';
}

/// Convenience wrapper so analysis-loading can hand the stored request
/// straight to the service.
extension PendingAnalysisRequestCall on PendingAnalysisRequest {
  Future<SymptomsAnalysis> run(SymptomsService service) => service.analyze(
    symptoms: symptoms,
    age: age,
    gender: gender,
    duration: duration,
    severity: severity,
    answers: answers,
  );
}

/// Port of buildDiagnosisFromSymptoms() in diagnosisStore.ts.
///
/// A keyword heuristic used only as a fallback when a screen needs something
/// to render and the stored analysis is gone (a cold start that lost it).
/// It is not a diagnosis and never reaches the AI — it exists so the results
/// screen shows a plausible shape rather than an empty panel.
PendingDiagnosis buildDiagnosisFromSymptoms(String symptoms) {
  final text = symptoms.toLowerCase();
  bool has(List<String> words) => words.any(text.contains);

  final hasFever = has(['fever', 'chills', 'sweat']);
  final hasCough = has(['cough', 'cold', 'throat']);
  final hasStomach = has(['stomach', 'diarrhea', 'vomit', 'nausea']);
  final hasChest = has(['chest', 'breath']);

  final urgency = hasChest
      ? 'High'
      : (hasFever || hasStomach)
      ? 'Medium'
      : 'Low';

  const red = '#DC2626';
  const amber = '#D97706';
  const teal = '#0B6E6E';

  final conditions = hasStomach
      ? const [
          DiagnosisCondition(
            name: 'Gastroenteritis or food poisoning',
            probability: 72,
            level: 'High',
            color: red,
          ),
          DiagnosisCondition(
            name: 'Acid reflux or gastritis',
            probability: 48,
            level: 'Medium',
            color: amber,
          ),
          DiagnosisCondition(
            name: 'Typhoid or other infection',
            probability: 31,
            level: 'Low',
            color: teal,
          ),
        ]
      : hasCough
      ? const [
          DiagnosisCondition(
            name: 'Flu or upper respiratory infection',
            probability: 76,
            level: 'High',
            color: red,
          ),
          DiagnosisCondition(
            name: 'Allergic irritation',
            probability: 42,
            level: 'Medium',
            color: amber,
          ),
          DiagnosisCondition(
            name: 'Bronchitis',
            probability: 28,
            level: 'Low',
            color: teal,
          ),
        ]
      : hasFever
      ? const [
          DiagnosisCondition(
            name: 'Malaria or viral fever',
            probability: 68,
            level: 'High',
            color: red,
          ),
          DiagnosisCondition(
            name: 'Flu-like illness',
            probability: 47,
            level: 'Medium',
            color: amber,
          ),
          DiagnosisCondition(
            name: 'Bacterial infection',
            probability: 24,
            level: 'Low',
            color: teal,
          ),
        ]
      : const [
          DiagnosisCondition(
            name: 'General viral illness',
            probability: 61,
            level: 'High',
            color: red,
          ),
          DiagnosisCondition(
            name: 'Fatigue or dehydration',
            probability: 39,
            level: 'Medium',
            color: amber,
          ),
          DiagnosisCondition(
            name: 'Stress-related symptoms',
            probability: 22,
            level: 'Low',
            color: teal,
          ),
        ];

  return PendingDiagnosis(
    symptoms: symptoms,
    urgency: urgency,
    conditions: conditions,
    preparedAt: DateTime.now(),
    summary:
        'Your symptoms have been analysed against common patterns. This is '
        'not a final medical diagnosis, but it helps you decide what to do next.',
    medications: [
      const DiagnosisMedication(
        name: 'Paracetamol 500mg',
        note: 'For fever or pain. Follow label directions and avoid overdose.',
      ),
      const DiagnosisMedication(
        name: 'Oral rehydration salts',
        note:
            'Useful if you have vomiting, diarrhea, fever, or signs of '
            'dehydration.',
      ),
      DiagnosisMedication(
        name: 'Doctor review',
        note: urgency == 'High'
            ? 'Recommended urgently because of your symptom pattern.'
            : 'Recommended if symptoms persist or worsen.',
      ),
    ],
  );
}
