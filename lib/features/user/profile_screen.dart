import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../core/theme.dart';
import '../../state/auth_controller.dart';

/// Port of src/user/screens/ProfileScreen.tsx.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

typedef _MenuItem = ({
  IconData icon,
  String label,
  String sub,
  VoidCallback? onTap,
});

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    // Pulls a fresh profile on open, so a subscription settled on another
    // device shows up here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(authControllerProvider.notifier).refresh();
    });
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppPalette.alert),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(authControllerProvider.notifier).logout();
    // The router's redirect handles where to go once the session is gone.
  }

  /// Several menu rows had no handler in the RN screen — tapping them did
  /// nothing at all. Rather than ship silent controls or delete rows and
  /// gut the screen, they say so.
  void _notBuilt(String label) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('$label is not available yet.')));
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final subscribed = user?.isSubscribed ?? false;

    final initials =
        (user?.name ?? '')
            .split(' ')
            .where((p) => p.isNotEmpty)
            .map((p) => p[0])
            .take(2)
            .join()
            .toUpperCase();

    final sections = <(String, List<_MenuItem>)>[
      (
        'Account',
        [
          (
            icon: Icons.person_outline,
            label: 'Personal Information',
            sub: 'Name, email, phone',
            onTap: null,
          ),
          (
            icon: Icons.lock_outline,
            label: 'Change Password',
            sub: 'Update your password',
            onTap: null,
          ),
          (
            icon: Icons.notifications_outlined,
            label: 'Notifications',
            sub: 'Manage alerts',
            onTap: null,
          ),
        ],
      ),
      (
        'Health',
        [
          (
            icon: Icons.description_outlined,
            label: 'Medical History',
            sub: 'Your health records',
            onTap: null,
          ),
          (
            icon: Icons.credit_card,
            label: 'Subscription Plan',
            sub: subscribed
                ? '${user!.effectivePlan} plan active'
                : 'Free plan · Upgrade',
            onTap: () => context.go(Routes.subscription),
          ),
          (
            icon: Icons.receipt_long_outlined,
            label: 'Payment History',
            sub: 'View transactions',
            onTap: null,
          ),
        ],
      ),
      (
        'Support',
        [
          (
            icon: Icons.help_outline,
            label: 'Help & Support',
            sub: 'Get assistance',
            onTap: null,
          ),
          (
            icon: Icons.verified_user_outlined,
            label: 'Privacy Policy',
            sub: 'How we use your data',
            onTap: null,
          ),
          (
            icon: Icons.article_outlined,
            label: 'Terms & Conditions',
            sub: 'Read our terms',
            onTap: null,
          ),
          (
            icon: Icons.star_outline,
            label: 'Rate AfyaSmart',
            sub: 'Share your feedback',
            onTap: null,
          ),
        ],
      ),
      (
        'Affiliate',
        [
          (
            icon: Icons.share_outlined,
            label: 'Affiliate Program',
            sub: 'Earn 30% commission on referrals',
            onTap: () => context.push(Routes.affiliate),
          ),
        ],
      ),
      if (user?.isAdmin == true)
        (
          'Admin',
          [
            (
              icon: Icons.admin_panel_settings_outlined,
              label: 'Admin Console',
              sub: 'Manage users, facilities, transactions, payouts',
              onTap: () => context.go(Routes.admin),
            ),
          ],
        ),
    ];

    return Container(
      color: const Color(0xFFF5F7FA),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _header(),
          Transform.translate(
            offset: const Offset(0, -36),
            child: Column(
              children: [
                _profileCard(user?.name ?? 'User', user?.email ?? '',
                    user?.phone, initials.isEmpty ? 'U' : initials),
                const SizedBox(height: 20),
                for (final (title, items) in sections) ...[
                  _section(title, items),
                  const SizedBox(height: 16),
                ],
                _logoutButton(),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() => Container(
    color: AppColors.brand,
    padding: EdgeInsets.fromLTRB(
      20,
      MediaQuery.viewPaddingOf(context).top + 16,
      20,
      56,
    ),
    child: const Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Profile',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        Icon(Icons.settings_outlined, size: 22, color: Colors.white),
      ],
    ),
  );

  Widget _profileCard(String name, String email, String? phone, String initials) =>
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppPalette.hairline),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: const BoxDecoration(
                    color: AppColors.brand,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.textStrong,
                        ),
                      ),
                      if (email.isNotEmpty)
                        Text(
                          email,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppPalette.textMuted,
                          ),
                        ),
                      if (phone != null && phone.isNotEmpty)
                        Text(
                          phone,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppPalette.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(color: AppPalette.hairline),
            const SizedBox(height: 14),
            // Both counters are hardcoded zero in the RN screen — there is no
            // consultations or prescriptions data model yet.
            const Row(
              children: [
                Expanded(child: _Stat(value: '0', label: 'Consultations')),
                SizedBox(
                  height: 32,
                  child: VerticalDivider(color: AppPalette.hairline),
                ),
                Expanded(child: _Stat(value: '0', label: 'Prescriptions')),
              ],
            ),
          ],
        ),
      );

  Widget _section(String title, List<_MenuItem> items) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppPalette.textMuted,
            letterSpacing: 0.6,
          ),
        ),
      ),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppPalette.hairline),
        ),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, indent: 56, color: AppPalette.hairline),
              _menuRow(items[i]),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _menuRow(_MenuItem item) => ListTile(
    onTap: item.onTap ?? () => _notBuilt(item.label),
    leading: Icon(item.icon, size: 22, color: AppColors.brand),
    title: Text(
      item.label,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppPalette.textStrong,
      ),
    ),
    subtitle: Text(
      item.sub,
      style: const TextStyle(fontSize: 12, color: AppPalette.textMuted),
    ),
    trailing: const Icon(
      Icons.chevron_right,
      size: 20,
      color: AppPalette.textMuted,
    ),
  );

  Widget _logoutButton() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: OutlinedButton.icon(
      onPressed: _logout,
      icon: const Icon(Icons.logout, size: 18),
      label: const Text('Logout'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppPalette.alert,
        side: const BorderSide(color: AppPalette.alert),
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.brand,
        ),
      ),
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: AppPalette.textMuted),
      ),
    ],
  );
}
