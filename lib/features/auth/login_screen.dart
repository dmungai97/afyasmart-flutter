import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand.dart';
import '../../core/errors.dart';
import '../../core/router.dart';
import '../../core/theme.dart';
import '../../state/auth_controller.dart';
import '../onboarding/widgets/vitals_rule.dart';
import 'widgets/auth_backdrop.dart';
import 'widgets/google_button.dart';

/// Port of src/auth/screens/LoginScreen.tsx.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.plan});

  /// From a ?plan= deep link. Carried through to register so a user who
  /// arrived intending to buy a plan still lands on its checkout after
  /// creating an account.
  final String? plan;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;

    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      _showError('Enter your email and password.');
      return;
    }

    setState(() => _loading = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(email: email, password: _password.text);
      // The router's redirect takes it from here — a subscribed user lands on
      // home, an admin in the console.
    } on Exception catch (e) {
      _showError(errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Same "clinical stationery" look as the welcome screen that leads here:
  /// paper, ink, thin rules, no card. It used to be a teal gradient with
  /// glowing rings, a pulse dot and an accent-barred card, so moving from
  /// welcome to sign-in felt like switching apps.
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
        'Sign in',
        style: TextStyle(
          color: AppColors.ink,
          fontSize: 28,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: Insets.sm),
      const Text(
        'Welcome back. Sign in to see your health checks and results.',
        style: TextStyle(color: AppColors.inkMuted, fontSize: 16, height: 1.5),
      ),
      const SizedBox(height: Insets.lg),
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
        label: 'Password',
        hint: 'Your password',
        icon: Icons.lock_outline,
        controller: _password,
        obscure: true,
        autofillHints: const [AutofillHints.password],
        textInputAction: TextInputAction.done,
        onSubmitted: _submit,
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _loading ? null : _forgotPassword,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.brand,
            minimumSize: const Size(48, 48),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('Forgot password?'),
        ),
      ),
      const SizedBox(height: Insets.xs),
      // Shape, height and colours come from the app theme, as on welcome.
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
                  Text('Signing in…'),
                ],
              )
            : const Text('Sign in'),
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
          onError: _showError,
        ),
      ],
      const SizedBox(height: Insets.lg),
      const Divider(),
      const SizedBox(height: Insets.sm),
      TextButton(
        onPressed: () => context.push(
          widget.plan == null
              ? Routes.register
              : '${Routes.register}?plan=${widget.plan}',
        ),
        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: const Text.rich(
          TextSpan(
            text: "Don't have an account? ",
            style: TextStyle(color: AppColors.inkMuted),
            children: [
              TextSpan(
                text: 'Create one',
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

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      _showError('Enter your email address first, then tap Forgot password.');
      return;
    }

    setState(() => _loading = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .requestPasswordReset(email);
      _showError('Password reset link sent to $email.');
    } on Exception catch (e) {
      _showError(errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
