import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../state/auth_controller.dart';
import 'auth_backdrop.dart';

/// Google sign-in.
///
/// The RN screens used expo-auth-session to run the OAuth dance in a web
/// browser and hand back an ID token. google_sign_in does the same thing
/// through the native account picker, and the token still goes to
/// supabase.auth.signInWithIdToken — only the way it is obtained changes.
///
/// The client ids come from --dart-define, mirroring how the RN app read them
/// from expo.extra.google:
///
/// ```sh
/// --dart-define=GOOGLE_SERVER_CLIENT_ID=...  # the WEB client id
/// --dart-define=GOOGLE_IOS_CLIENT_ID=...
/// ```
///
/// serverClientId must be the **web** client id even on Android: it is what
/// Google audiences the ID token to, and Supabase validates that audience
/// against the provider config. Passing the Android client id yields a token
/// Supabase rejects.
///
/// Note: the RN screens also rendered an Apple button, but it had no handler
/// attached and did nothing. It is deliberately not carried over rather than
/// shipped as a dead control.
class GoogleSignInButton extends ConsumerStatefulWidget {
  const GoogleSignInButton({
    required this.onStart,
    required this.onFinish,
    required this.onError,
    this.enabled = true,
    super.key,
  });

  final VoidCallback onStart;
  final VoidCallback onFinish;
  final void Function(String message) onError;
  final bool enabled;

  static const _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );
  static const _iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  @override
  ConsumerState<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends ConsumerState<GoogleSignInButton> {
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      clientId: GoogleSignInButton._iosClientId.isEmpty
          ? null
          : GoogleSignInButton._iosClientId,
      serverClientId: GoogleSignInButton._serverClientId.isEmpty
          ? null
          : GoogleSignInButton._serverClientId,
    );
    _initialized = true;
  }

  Future<void> _signIn() async {
    if (GoogleSignInButton._serverClientId.isEmpty) {
      widget.onError(
        'Google sign-in is not configured for this build.',
      );
      return;
    }

    widget.onStart();
    try {
      await _ensureInitialized();

      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;

      if (idToken == null) {
        widget.onError('Google did not return an ID token.');
        return;
      }

      await ref
          .read(authControllerProvider.notifier)
          .signInWithGoogle(idToken: idToken);
    } on GoogleSignInException catch (e) {
      // A cancelled picker is not an error worth shouting about.
      if (e.code != GoogleSignInExceptionCode.canceled) {
        widget.onError(e.description ?? 'Google sign-in failed.');
      }
    } on Exception catch (e) {
      widget.onError(e.toString());
    } finally {
      widget.onFinish();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton.icon(
        onPressed: widget.enabled ? _signIn : null,
        icon: const Icon(Icons.g_mobiledata, size: 28, color: Color(0xFFEA4335)),
        label: const Text(
          'Continue with Google',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2D3748),
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFE2E8F0)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          foregroundColor: AuthPalette.teal,
        ),
      ),
    );
  }
}
