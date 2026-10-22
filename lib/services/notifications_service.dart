import '../core/supabase_client.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.route,
    required this.createdAt,
    required this.read,
  });

  final String id;
  final String category;
  final String title;
  final String body;

  /// Where tapping it should go, set by the server (e.g. /affiliate/earnings).
  final String? route;
  final DateTime createdAt;
  final bool read;

  factory AppNotification.fromRow(Map<String, dynamic> row) => AppNotification(
    id: row['id'] as String,
    category: row['category'] as String? ?? '',
    title: row['title'] as String? ?? '',
    body: row['body'] as String? ?? '',
    route: (row['data'] as Map?)?['route'] as String?,
    createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
    read: row['read_at'] != null,
  );
}

/// Notification preferences, mirrored from public.notification_preferences.
/// The push function reads the same row, so a toggle here actually stops the
/// push rather than only being remembered on this phone.
class NotificationPrefs {
  const NotificationPrefs({
    this.enabled = true,
    this.symptom = true,
    this.wellness = true,
    this.subscription = true,
    this.affiliate = true,
  });

  final bool enabled;
  final bool symptom;
  final bool wellness;
  final bool subscription;
  final bool affiliate;

  NotificationPrefs copyWith({
    bool? enabled,
    bool? symptom,
    bool? wellness,
    bool? subscription,
    bool? affiliate,
  }) => NotificationPrefs(
    enabled: enabled ?? this.enabled,
    symptom: symptom ?? this.symptom,
    wellness: wellness ?? this.wellness,
    subscription: subscription ?? this.subscription,
    affiliate: affiliate ?? this.affiliate,
  );

  factory NotificationPrefs.fromRow(Map<String, dynamic> row) => NotificationPrefs(
    enabled: row['enabled'] as bool? ?? true,
    symptom: row['symptom'] as bool? ?? true,
    wellness: row['wellness'] as bool? ?? true,
    subscription: row['subscription'] as bool? ?? true,
    affiliate: row['affiliate'] as bool? ?? true,
  );

  Map<String, dynamic> toRow() => {
    'enabled': enabled,
    'symptom': symptom,
    'wellness': wellness,
    'subscription': subscription,
    'affiliate': affiliate,
  };
}

class NotificationsService {
  const NotificationsService();

  Future<List<AppNotification>> list() async {
    if (currentUserId == null) return const [];
    final rows = await supabase
        .from('notifications')
        .select('id, category, title, body, data, read_at, created_at')
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map(AppNotification.fromRow).toList();
  }

  /// Fires whenever a notification is added or changed for this user, so the
  /// bell badge and inbox stay live while the app is open.
  Stream<void> changes() {
    final userId = currentUserId;
    if (userId == null) return const Stream.empty();
    return supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .map((_) {});
  }

  Future<void> markRead(String id) => supabase
      .from('notifications')
      .update({'read_at': DateTime.now().toUtc().toIso8601String()})
      .eq('id', id);

  Future<void> markAllRead() async {
    if (currentUserId == null) return;
    await supabase
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .isFilter('read_at', null);
  }

  Future<NotificationPrefs> prefs() async {
    if (currentUserId == null) return const NotificationPrefs();
    final row = await supabase
        .from('notification_preferences')
        .select()
        .maybeSingle();
    return row == null ? const NotificationPrefs() : NotificationPrefs.fromRow(row);
  }

  Future<void> savePrefs(NotificationPrefs prefs) async {
    final userId = currentUserId;
    if (userId == null) return;
    await supabase.from('notification_preferences').upsert({
      'user_id': userId,
      ...prefs.toRow(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
