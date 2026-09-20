import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../state/auth_controller.dart';
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
            referralCode: widget.referralCode,
          );
      if (!mounted) return;

      // A brand-new account is flagged isNewUser, so the router normally
      // sends it into the onboarding survey — unless they arrived via a
      // ?plan= link, in which case go straight to that plan's checkout.
      if (widget.plan != null) {
        context.go('${Routes.subscription}?plan=${widget.plan}');
      }
    } on Exception catch (e) {
      _showMessage(e.toString());
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
              (insets.top < 36 ? 36 : insets.top) + 24,
              20,
              24,
            ),
            child: Column(
              children: [
                const AuthLogo(),
                const SizedBox(height: 14),
                const Text(
                  'Create your account',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Join AfyaSmart and take charge of your health',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 24),
                _card(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card() => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 4, color: AuthPalette.teal),
        Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.referralCode != null) _referralBanner(),
              AuthField(
                label: 'Full name',
                hint: 'Jane Wanjiru',
                icon: Icons.person_outline,
                controller: _name,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
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
                label: 'Phone number',
                hint: '0712 345 678',
                icon: Icons.phone_outlined,
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              AuthField(
                label: 'Password',
                hint: 'Choose a password',
                icon: Icons.lock_outline,
                controller: _password,
                obscure: true,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              AuthField(
                label: 'Confirm password',
                hint: 'Re-enter your password',
                icon: Icons.lock_outline,
                controller: _confirm,
                obscure: true,
                textInputAction: TextInputAction.done,
                onSubmitted: _submit,
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AuthPalette.teal,
                    disabledBackgroundColor: AuthPalette.teal.withValues(
                      alpha: 0.6,
                    ),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Create Account',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 18),
              GoogleSignInButton(
                enabled: !_loading,
                onStart: () => setState(() => _loading = true),
                onFinish: () {
                  if (mounted) setState(() => _loading = false);
                },
                onError: _showMessage,
              ),
              const SizedBox(height: 18),
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    const Text(
                      'Already have an account? ',
                      style: TextStyle(fontSize: 14, color: Color(0xFF718096)),
                    ),
                    GestureDetector(
                      onTap: () => context.go(
                        widget.plan == null
                            ? Routes.login
                            : '${Routes.login}?plan=${widget.plan}',
                      ),
                      child: const Text(
                        'Sign in',
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

  Widget _referralBanner() => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFE4EAE0),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFB9C9BC)),
    ),
    child: Row(
      children: [
        const Icon(Icons.card_giftcard, size: 18, color: Color(0xFF3F7A5C)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Referred with code ${widget.referralCode}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF2D3748)),
          ),
        ),
      ],
    ),
  );
}
