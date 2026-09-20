import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../state/auth_controller.dart';
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
      _showError(e.toString());
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

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewPaddingOf(context);

    return Scaffold(
      body: AuthBackdrop(
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              20,
              (insets.top < 36 ? 36 : insets.top) + 32,
              20,
              24,
            ),
            child: Column(
              children: [
                const AuthLogo(),
                const SizedBox(height: 16),
                const Text(
                  'AfyaSmart',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your Personal Health Companion',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 28),
                _card(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The accent bar across the top of the card.
          Container(height: 4, color: AuthPalette.teal),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome back 👋',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A202C),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Sign in to access your health dashboard',
                  style: TextStyle(fontSize: 13, color: Color(0xFF718096)),
                ),
                const SizedBox(height: 20),
                AuthField(
                  label: 'Email address',
                  hint: 'your@email.com',
                  icon: Icons.mail_outline,
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  showCheckWhenFilled: true,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),
                AuthField(
                  label: 'Password',
                  hint: 'Enter your password',
                  icon: Icons.lock_outline,
                  controller: _password,
                  obscure: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: _submit,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _loading ? null : _forgotPassword,
                    child: const Text(
                      'Forgot password?',
                      style: TextStyle(
                        fontSize: 13,
                        color: AuthPalette.teal,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                _signInButton(),
                const SizedBox(height: 20),
                _divider(),
                const SizedBox(height: 16),
                GoogleSignInButton(
                  enabled: !_loading,
                  onStart: () => setState(() => _loading = true),
                  onFinish: () {
                    if (mounted) setState(() => _loading = false);
                  },
                  onError: _showError,
                ),
                const SizedBox(height: 18),
                Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        "Don't have an account? ",
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF718096),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => context.push(
                          widget.plan == null
                              ? Routes.register
                              : '${Routes.register}?plan=${widget.plan}',
                        ),
                        child: const Text(
                          'Register',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AuthPalette.teal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _signInButton() => SizedBox(
    height: 52,
    child: FilledButton(
      onPressed: _loading ? null : _submit,
      style: FilledButton.styleFrom(
        backgroundColor: AuthPalette.teal,
        disabledBackgroundColor: AuthPalette.teal.withValues(alpha: 0.6),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_loading) ...[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Signing in...', style: _btnText),
          ] else ...[
            const Text('Sign In', style: _btnText),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward, size: 18),
          ],
        ],
      ),
    ),
  );

  Widget _divider() => Row(
    children: [
      const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          'or continue with',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ),
      const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
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
      await ref.read(authControllerProvider.notifier).requestPasswordReset(email);
      _showError('Password reset link sent to $email.');
    } on Exception catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

const _btnText = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w700,
  color: Colors.white,
);
