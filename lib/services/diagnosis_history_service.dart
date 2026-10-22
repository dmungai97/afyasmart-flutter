import '../core/supabase_client.dart';

/// Reads and writes the signed-in user's symptom-check history
/// (public.diagnoses). RLS limits every query to the caller's own rows.
///
/// Rows are exchanged as the same JSON shape PendingDiagnosis.toJson()
/// produces, so the local "latest result" and the history share one model.
class DiagnosisHistoryService {
  const DiagnosisHistoryService();

  static const _limit = 50;

  Future<List<Map<String, dynamic>>> list() async {
    if (currentUserId == null) return const [];

    final rows = await supabase
        .from('diagnoses')
        .select('id, symptoms, summary, urgency, conditions, medications, created_at')
        .order('created_at', ascending: false)
        .limit(_limit);

    return [
      for (final row in rows)
        {
          'id': row['id'],
          'symptoms': row['symptoms'],
          'summary': row['summary'],
          'urgency': row['urgency'],
          'conditions': row['conditions'],
          'medications': row['medications'],
          'preparedAt': row['created_at'],
        },
    ];
  }

  /// Saves one result. A no-op when signed out, since there is no one to own
  /// the row.
  Future<void> save(Map<String, dynamic> diagnosis) async {
    final userId = currentUserId;
    if (userId == null) return;

    await supabase.from('diagnoses').insert({
      'user_id': userId,
      'symptoms': diagnosis['symptoms'] ?? '',
      'summary': diagnosis['summary'] ?? '',
      'urgency': diagnosis['urgency'] ?? 'Low',
      'conditions': diagnosis['conditions'] ?? const [],
      'medications': diagnosis['medications'] ?? const [],
    });
  }
}
