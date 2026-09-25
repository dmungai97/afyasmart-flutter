import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import '../auth/widgets/auth_backdrop.dart';
import 'widgets/profile_widgets.dart';

/// Sets a new password on the current session. There is no "current
/// password" field: Supabase does not verify one on updateUser, so asking for
/// it would only look like a check. Its own "secure password change" setting
/// is what forces re-authentication on a stale session.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  static const _minLength = 6;

  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Rebuild on each keystroke so the checklist and button track the input.
    _password.addListener(_changed);
    _confirm.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _longEnough => _password.text.length >= _minLength;
  bool get _matches =>
      _confirm.text.isNotEmpty && _password.text == _confirm.text;

  Future<void> _save() async {
    if (!_longEnough || !_matches || _saving) return;
    FocusScope.of(context).unfocus();

    setState(() => _saving = true);
    try {
      await ref.read(authServiceProvider).changePassword(_password.text);
      _password.clear();
      _confirm.clear();
      _toast('Your password has been changed.');
    } on ApiException catch (e) {
      _toast(e.message);
    } on Exception {
      _toast('Could not change your password. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => ProfileSubpage(
    title: 'Change Password',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      children: [
        const _Intro(),
        const SizedBox(height: 24),
        AuthField(
          label: 'New password',
          hint: 'Enter a new password',
          icon: Icons.lock_outline,
          controller: _password,
          obscure: true,
          enabled: !_saving,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        AuthField(
          label: 'Confirm new password',
          hint: 'Re-enter the new password',
          icon: Icons.lock_outline,
          controller: _confirm,
          obscure: true,
          enabled: !_saving,
          textInputAction: TextInputAction.done,
          onSubmitted: _save,
        ),
        const SizedBox(height: 16),
        _Check(met: _longEnough, text: 'At least $_minLength characters'),
        const SizedBox(height: 6),
        _Check(met: _matches, text: 'Both passwords match'),
        const SizedBox(height: 28),
        ProfilePrimaryButton(
          label: 'Update password',
          onPressed: _longEnough && _matches ? _save : null,
          busy: _saving,
        ),
        const SizedBox(height: 20),
        const _GoogleNote(),
      ],
    ),
  );
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Color(0xFFE0F2F1),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.shield_outlined, color: AppColors.brand),
      ),
      const SizedBox(width: 14),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose a new password',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppPalette.textStrong,
              ),
            ),
            SizedBox(height: 2),
            Text(
              "You'll use it the next time you sign in.",
              style: TextStyle(fontSize: 13, color: AppPalette.textMuted),
            ),
          ],
        ),
      ),
    ],
  );
}

/// One live requirement line: grey until satisfied, then a teal tick.
class _Check extends StatelessWidget {
  const _Check({required this.met, required this.text});

  final bool met;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        met ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 16,
        color: met ? AppColors.brand : AppPalette.textMuted,
      ),
      const SizedBox(width: 8),
      Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: met ? AppPalette.textStrong : AppPalette.textMuted,
        ),
      ),
    ],
  );
}

class _GoogleNote extends StatelessWidget {
  const _GoogleNote();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppPalette.hairline),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 18, color: AppPalette.textMuted),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Signed up with Google? Setting a password here lets you also '
            'sign in with your email address.',
            style: TextStyle(fontSize: 12, color: AppPalette.textMuted),
          ),
        ),
      ],
    ),
  );
}
