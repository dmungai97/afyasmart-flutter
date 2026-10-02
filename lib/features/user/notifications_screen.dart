import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../services/notifications_service.dart';
import '../../state/notifications_controller.dart';
import 'widgets/profile_widgets.dart';

/// Notifications settings screen providing subtle controls for push alerts,
/// health reminders, and account notifications.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notificationPrefsProvider).value ?? const NotificationPrefs();

    // Saved to Supabase, where the push function reads it. On failure the
    // switch flips back and the user is told, rather than silently showing
    // a setting the server never received.
    ValueChanged<bool> toggle(NotificationPrefs Function(NotificationPrefs, bool) apply) =>
        (value) => ref
            .read(notificationPrefsProvider.notifier)
            .change((p) => apply(p, value))
            .catchError((_) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not save. Check your connection and try again.')),
              );
            });
    final all = settings.enabled;

    return ProfileSubpage(
      title: 'Notifications',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          _SectionTitle('General'),
          const SizedBox(height: 8),
          ProfileCard(
            child: _SwitchRow(
              icon: Icons.notifications_active_outlined,
              title: 'Allow Notifications',
              subtitle: 'Enable or disable all app push alerts',
              value: settings.enabled,
              onChanged: toggle((p, v) => p.copyWith(enabled: v)),
            ),
          ),
          const SizedBox(height: 20),
          _SectionTitle('Health & Symptoms'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppPalette.hairline),
            ),
            child: Column(
              children: [
                _SwitchRow(
                  icon: Icons.medical_services_outlined,
                  title: 'Symptom Follow-ups',
                  subtitle: 'Reminders regarding recent AI health evaluations',
                  value: all && settings.symptom,
                  onChanged: all ? toggle((p, v) => p.copyWith(symptom: v)) : null,
                ),
                const Divider(height: 1, indent: 56, color: AppPalette.hairline),
                _SwitchRow(
                  icon: Icons.spa_outlined,
                  title: 'Wellness & Health Insights',
                  subtitle: 'Periodic preventive health tips and updates',
                  value: all && settings.wellness,
                  onChanged: all ? toggle((p, v) => p.copyWith(wellness: v)) : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionTitle('Account & Billing'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppPalette.hairline),
            ),
            child: Column(
              children: [
                _SwitchRow(
                  icon: Icons.receipt_long_outlined,
                  title: 'M-Pesa & Subscription Receipts',
                  subtitle: 'Payment confirmations and plan expiry reminders',
                  value: all && settings.subscription,
                  onChanged: all ? toggle((p, v) => p.copyWith(subscription: v)) : null,
                ),
                const Divider(height: 1, indent: 56, color: AppPalette.hairline),
                _SwitchRow(
                  icon: Icons.card_giftcard_outlined,
                  title: 'Affiliate Activity',
                  subtitle: 'Commission payouts and referral updates',
                  value: all && settings.affiliate,
                  onChanged: all ? toggle((p, v) => p.copyWith(affiliate: v)) : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppPalette.textMuted,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            icon,
            size: 22,
            color: enabled ? AppColors.brand : AppPalette.textMuted,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: enabled
                        ? AppPalette.textStrong
                        : AppPalette.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppPalette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.brand,
            activeTrackColor: AppColors.brand.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }
}
