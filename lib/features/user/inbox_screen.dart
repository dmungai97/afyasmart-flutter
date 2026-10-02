import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../../services/notifications_service.dart';
import '../../state/notifications_controller.dart';
import '../../state/providers.dart';
import 'widgets/profile_widgets.dart';

/// Every notification the user has been sent, whether or not the push
/// reached them — a muted category, a denied permission or a phone without
/// Google Play services still leaves the message here.
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationsProvider);
    final service = ref.read(notificationsServiceProvider);

    void open(AppNotification n) {
      if (!n.read) service.markRead(n.id).catchError((_) {});
      final route = n.route;
      if (route != null && route.startsWith('/')) context.push(route);
    }

    return ProfileSubpage(
      title: 'Notifications',
      child: inbox.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _Message(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load notifications',
          body: 'Check your connection and try again.',
          action: TextButton(
            onPressed: () => ref.invalidate(notificationsProvider),
            child: const Text('Retry'),
          ),
        ),
        data: (items) => items.isEmpty
            ? const _Message(
                icon: Icons.notifications_none,
                title: 'No notifications yet',
                body: 'Payment confirmations, subscription reminders and '
                    'affiliate earnings will appear here.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          unread == 0 ? 'All caught up' : '$unread unread',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.textMuted,
                          ),
                        ),
                      ),
                      if (unread > 0)
                        TextButton(
                          onPressed: () => service.markAllRead().catchError((_) {}),
                          child: const Text('Mark all as read'),
                        ),
                      IconButton(
                        tooltip: 'Notification settings',
                        onPressed: () => context.push(Routes.notifications),
                        icon: const Icon(Icons.tune, size: 20, color: AppPalette.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final n in items) ...[
                    _NotificationTile(notification: n, onTap: () => open(n)),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final (icon, fg, bg) = switch (n.category) {
      'subscription' => (Icons.receipt_long_outlined, AppPalette.teal, const Color(0xFFE0F2F1)),
      'affiliate' => (Icons.card_giftcard_outlined, AppPalette.purple, AppPalette.purpleBg),
      'symptom' => (Icons.medical_services_outlined, AppPalette.orange, AppPalette.orangeBg),
      _ => (Icons.spa_outlined, AppPalette.green, AppPalette.greenBg),
    };

    return Material(
      color: n.read ? Colors.white : const Color(0xFFF2FAF9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppPalette.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: fg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: n.read ? FontWeight.w600 : FontWeight.w700,
                              color: AppPalette.textStrong,
                            ),
                          ),
                        ),
                        if (!n.read)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppPalette.teal,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      n.body,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppPalette.textBody,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _ago(n.createdAt),
                      style: const TextStyle(fontSize: 11, color: AppPalette.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t.toLocal());
    if (d.inMinutes < 1) return 'Just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    if (d.inDays < 7) return '${d.inDays} d ago';
    final l = t.toLocal();
    return '${l.day}/${l.month}/${l.year}';
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body, this.action});

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: AppPalette.textMuted),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppPalette.textStrong,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, height: 1.4, color: AppPalette.textMuted),
          ),
          ?action,
        ],
      ),
    ),
  );
}
