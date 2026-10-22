import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand.dart';
import '../../core/errors.dart';
import '../../core/router.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../state/auth_controller.dart';
import '../onboarding/widgets/vitals_rule.dart';
import 'widgets/auth_backdrop.dart';
import 'widgets/google_button.dart';

/// Port of src/auth/screens/RegisterScreen.tsx.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.referralCode, this.plan});

  /// From a ?ref=AFYA-XXXXXX deep link. Resolved server-side by the
  /// on_auth_user_created trigger against affiliates.code, so a typo or an
  /// unenrolled affiliate is dropped rather than blocking registration.
  final String? referralCode;

  /// From a ?plan= deep link. Sends the new account straight to that plan's
  /// checkout instead of the home tab.
  final String? plan;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;

  /// The link's code, or one remembered from an earlier visit to this screen.
  late String? _referralCode = widget.referralCode;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authControllerProvider.notifier);
    if (widget.referralCode != null) {
      auth.rememberReferral(widget.referralCode!);
    } else {
      auth.pendingReferral().then((code) {
        if (mounted && code != null) setState(() => _referralCode = code);
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;

    if (_name.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _password.text.isEmpty) {
      _showMessage('Fill in your name, email and password.');
      return;
    }
    if (_password.text != _confirm.text) {
      _showMessage('Passwords do not match.');
      return;
    }
    // Optional, but a number given here is the one M-Pesa checkout offers
    // later, so a typo is caught now rather than at payment.
    final phone = _phone.text.trim();
    if (phone.isNotEmpty && !AuthService.isValidKenyanPhone(phone)) {
      _showMessage('Enter a Kenyan mobile number, like 0712 345 678.');
      return;
    }

    setState(() => _loading = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .register(
            name: _name.text,
            email: _email.text,
            phone: _phone.text,
            password: _password.text,
            passwordConfirmation: _confirm.text,
            referralCode: _referralCode,
          );
      if (!mounted) return;

      // A brand-new account is flagged isNewUser, so the router normally
      // sends it into the onboarding survey — unless they arrived via a
      // ?plan= link, in which case go straight to that plan's checkout.
      if (widget.plan != null) {
        context.go('${Routes.subscription}?plan=${widget.plan}');
      }
    } on Exception catch (e) {
      _showMessage(errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Same look as sign-in: paper, ink, thin rules, no card or teal backdrop.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              Insets.xl,
              Insets.lg,
              Insets.lg,
            ),
            child: ConstrainedBox(
              // Phone-width column on tablets and the web.
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(child: _form()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Align(alignment: Alignment.centerLeft, child: Wordmark()),
      const SizedBox(height: Insets.md),
      const Align(alignment: Alignment.centerLeft, child: VitalsRule()),
      const SizedBox(height: Insets.md),
      const Text(
        'Create your account',
        style: TextStyle(
          color: AppColors.ink,
          fontSize: 28,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: Insets.sm),
      const Text(
        'Keep your health checks and results in one place.',
        style: TextStyle(color: AppColors.inkMuted, fontSize: 16, height: 1.5),
      ),
      const SizedBox(height: Insets.lg),
      if (_referralCode != null) _referralBanner(),
      AuthField(
        label: 'Full name',
        hint: 'Jane Wanjiru',
        icon: Icons.person_outline,
        controller: _name,
        autofillHints: const [AutofillHints.name],
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: Insets.md),
      AuthField(
        label: 'Email address',
        hint: 'you@example.com',
        icon: Icons.mail_outline,
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: Insets.md),
      AuthField(
        // Not required by _submit, so the label says so.
        label: 'Phone number (optional)',
        hint: '0712 345 678',
        helperText: 'For M-Pesa payments',
        icon: Icons.phone_outlined,
        controller: _phone,
        keyboardType: TextInputType.phone,
        autofillHints: const [AutofillHints.telephoneNumber],
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: Insets.md),
      AuthField(
        label: 'Password',
        hint: 'Choose a password',
        icon: Icons.lock_outline,
        controller: _password,
        obscure: true,
        autofillHints: const [AutofillHints.newPassword],
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: Insets.md),
      AuthField(
        label: 'Confirm password',
        hint: 'Type it again',
        icon: Icons.lock_outline,
        controller: _confirm,
        obscure: true,
        autofillHints: const [AutofillHints.newPassword],
        textInputAction: TextInputAction.done,
        onSubmitted: _submit,
      ),
      const SizedBox(height: Insets.lg),
      // Shape, height and colours come from the app theme, as on sign-in.
      FilledButton(
        onPressed: _loading ? null : _submit,
        child: _loading
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.paper,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text('Creating account…'),
                ],
              )
            : const Text('Create account'),
      ),
      if (GoogleSignInButton.isSupported) ...[
        const SizedBox(height: Insets.lg),
        _divider(),
        const SizedBox(height: Insets.md),
        GoogleSignInButton(
          enabled: !_loading,
          onStart: () => setState(() => _loading = true),
          onFinish: () {
            if (mounted) setState(() => _loading = false);
          },
          onError: _showMessage,
        ),
      ],
      const SizedBox(height: Insets.lg),
      const Divider(),
      const SizedBox(height: Insets.sm),
      TextButton(
        onPressed: () => context.go(
          widget.plan == null
              ? Routes.login
              : '${Routes.login}?plan=${widget.plan}',
        ),
        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: const Text.rich(
          TextSpan(
            text: 'Already have an account? ',
            style: TextStyle(color: AppColors.inkMuted),
            children: [
              TextSpan(
                text: 'Sign in',
                style: TextStyle(
                  color: AppColors.brand,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          style: TextStyle(fontSize: 15),
        ),
      ),
    ],
  );

  Widget _divider() => const Row(
    children: [
      Expanded(child: Divider()),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          'or',
          style: TextStyle(fontSize: 14, color: AppColors.inkMuted),
        ),
      ),
      Expanded(child: Divider()),
    ],
  );

  Widget _referralBanner() => Container(
    margin: const EdgeInsets.only(bottom: Insets.md),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.tintSuccessBg,
      borderRadius: BorderRadius.circular(Radii.md),
      border: Border.all(color: AppColors.tintSuccessBorder),
    ),
    child: Row(
      children: [
        const Icon(Icons.card_giftcard, size: 20, color: AppColors.success),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Referred with code $_referralCode',
            style: const TextStyle(fontSize: 14, color: AppColors.ink),
          ),
        ),
      ],
    ),
  );
}
