import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/router.dart';
import '../../core/supabase_client.dart';
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

  /// Opens the Play Store listing, in the Play Store app when there is one.
  /// The package id is com.afyasmart.app (see android/app/build.gradle.kts).
  Future<void> _rateApp() async {
    const storeApp = 'market://details?id=com.afyasmart.app';
    const storeWeb =
        'https://play.google.com/store/apps/details?id=com.afyasmart.app';

    final opened =
        await _tryLaunch(storeApp) || await _tryLaunch(storeWeb);
    if (!opened && mounted) _notBuilt('Rating');
  }

  static Future<bool> _tryLaunch(String url) async {
    try {
      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } on Exception {
      return false;
    }
  }

  Future<void> _deleteAccount() async {
    // Captured up front: the app-level messenger outlives this screen, which
    // the router tears down as soon as the session is cleared.
    final messenger = ScaffoldMessenger.of(context);

    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DeleteAccountDialog(),
    );

    if (deleted == true) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Your account has been deleted.')),
        );
    }
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
            onTap: () => context.push(Routes.personalInfo),
          ),
          (
            icon: Icons.lock_outline,
            label: 'Change Password',
            sub: 'Update your password',
            onTap: () => context.push(Routes.changePassword),
          ),
          (
            icon: Icons.notifications_outlined,
            label: 'Notifications',
            sub: 'Manage alerts',
            onTap: () => context.push(Routes.notifications),
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
            onTap: () => context.push(Routes.medicalHistory),
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
            onTap: () => context.push(Routes.paymentHistory),
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
            onTap: () => context.push(Routes.helpSupport),
          ),
          (
            icon: Icons.verified_user_outlined,
            label: 'Privacy Policy',
            sub: 'How we use your data',
            onTap: () => context.push(Routes.privacyPolicy),
          ),
          (
            icon: Icons.article_outlined,
            label: 'Terms & Conditions',
            sub: 'Read our terms',
            onTap: () => context.push(Routes.termsConditions),
          ),
          (
            icon: Icons.star_outline,
            label: 'Rate AfyaSmart',
            sub: 'Share your feedback',
            onTap: _rateApp,
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

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.brand, AppColors.accent],
            ),
          ),
        ),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Profile',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: () => context.push(Routes.personalInfo),
          ),
        ],
      ),
      body: Stack(
        children: [
          Container(
            height: 140,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.brand, AppColors.accent],
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
          ),
          ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              _profileCard(user?.name ?? 'User', user?.email ?? '',
                  user?.phone, initials.isEmpty ? 'U' : initials, user?.isSubscribed ?? false, user?.chatCount ?? 0),
              const SizedBox(height: 24),
              for (final (_, items) in sections) ...[
                _section(items),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 16),
              _logoutButton(),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _deleteAccount,
                style: TextButton.styleFrom(
                  foregroundColor: AppPalette.textMuted,
                ),
                child: const Text('Delete account'),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ],
      ),
    );
  }

  Widget _profileCard(String name, String email, String? phone, String initials, bool isSubscribed, int chatCount) =>
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppPalette.hairline),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppColors.brand,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.textStrong,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSubscribed ? const Color(0xFF1E293B) : AppPalette.hairline,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isSubscribed ? 'Premium member' : 'Free plan',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isSubscribed ? Colors.white : AppPalette.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => context.go(Routes.chat),
                    child: _Stat(value: '$chatCount', label: 'consultations'),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => context.push(Routes.medicalHistory),
                    child: const _Stat(value: '0', label: 'prescriptions'), // Hardcoded till data model
                  ),
                ),
              ],
            ),
          ],
        ),
      );


  Widget _section(List<_MenuItem> items) => Material(
    color: Colors.white,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: AppPalette.hairline),
    ),
    child: Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            const Divider(
              height: 1,
              indent: 64,
              color: AppPalette.hairline,
            ),
          _menuRow(items[i]),
        ],
      ],
    ),
  );

  Widget _menuRow(_MenuItem item) => ListTile(
    onTap: item.onTap ?? () => _notBuilt(item.label),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    leading: Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: Color(0xFFF3F4F6),
        shape: BoxShape.circle,
      ),
      child: Icon(item.icon, size: 20, color: const Color(0xFF4B5563)),
    ),
    title: Text(
      item.label,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppPalette.textStrong,
      ),
    ),
    trailing: const Icon(
      Icons.chevron_right,
      size: 20,
      color: AppPalette.textMuted,
    ),
  );

  Widget _logoutButton() => OutlinedButton.icon(
    onPressed: _logout,
    icon: const Icon(Icons.logout, size: 18),
    label: const Text('Logout'),
    style: OutlinedButton.styleFrom(
      foregroundColor: AppPalette.alert,
      side: const BorderSide(color: AppPalette.alert),
      minimumSize: const Size.fromHeight(56),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// Asks the user to type DELETE before the irreversible call, and keeps the
/// dialog open with the server's message if it refuses (admin account,
/// payout in flight) so they know what to do next.
class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  static const _confirmWord = 'DELETE';

  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).deleteAccount();
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Exception {
      if (mounted) {
        setState(() => _error = 'Could not reach the server. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final confirmed = _controller.text.trim().toUpperCase() == _confirmWord;

    return AlertDialog(
      title: const Text('Delete account'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This permanently deletes your account, chat history, payment '
            'history and any affiliate balance you have not withdrawn. '
            'An active subscription ends immediately and is not refunded. '
            'This cannot be undone.',
          ),
          const SizedBox(height: 16),
          const Text('Type $_confirmWord to confirm.'),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            enabled: !_busy,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: _confirmWord),
            onChanged: (_) => setState(() {}),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppPalette.alert)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: confirmed && !_busy ? _submit : null,
          style: TextButton.styleFrom(foregroundColor: AppPalette.alert),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Delete'),
        ),
      ],
    );
  }
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
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: AppPalette.textStrong,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: const TextStyle(
          fontSize: 13, 
          fontWeight: FontWeight.w500,
          color: AppPalette.textMuted,
        ),
      ),
    ],
  );
}
