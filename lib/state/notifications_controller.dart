import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/notifications_service.dart';
import 'auth_controller.dart';
import 'providers.dart';

/// The signed-in user's inbox, newest first, kept live by Realtime: every
/// insert or read-mark re-fetches the list. Keyed on the user id so another
/// account's rows can never linger after a switch.
final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final userId = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (userId == null) return Stream.value(const []);

  final service = ref.read(notificationsServiceProvider);
  return service.changes().asyncMap((_) => service.list());
});

final unreadNotificationsProvider = Provider<int>((ref) {
  final list = ref.watch(notificationsProvider).value ?? const [];
  return list.where((n) => !n.read).length;
});

/// Notification settings, stored in Supabase so the push function honours
/// them. Toggles apply optimistically and roll back if the save fails.
class NotificationPrefsController extends AsyncNotifier<NotificationPrefs> {
  @override
  Future<NotificationPrefs> build() {
    ref.watch(authControllerProvider.select((s) => s.user?.id));
    return ref.read(notificationsServiceProvider).prefs();
  }

  Future<void> change(NotificationPrefs Function(NotificationPrefs) apply) async {
    final previous = state.value ?? const NotificationPrefs();
    final next = apply(previous);
    state = AsyncData(next);
    try {
      await ref.read(notificationsServiceProvider).savePrefs(next);
    } on Object {
      state = AsyncData(previous);
      rethrow;
    }
  }
}

final notificationPrefsProvider =
    AsyncNotifierProvider<NotificationPrefsController, NotificationPrefs>(
      NotificationPrefsController.new,
    );
