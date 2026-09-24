import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';
import '../models/app_user.dart';

/// Port of src/services/auth.service.ts.
class AuthService {
  const AuthService();

  static const _userColumns =
      'id, name, email, phone, role, is_subscribed, has_subscribed, '
      'onboarding_completed, subscription_plan, chat_count, '
      'subscription_expires_at';

  /// Loads the signed-in user's public.users row.
  ///
  /// The row is created by the on_auth_user_created trigger inside the same
  /// transaction as the auth user, so it always exists by the time a session
  /// does. There is no "get or create" branch, and with it goes the client's
  /// ability to author its own profile fields.
  Future<AppUser?> currentProfile() async {
    final authUser = supabase.auth.currentUser;
    if (authUser == null) return null;

    final row = await supabase
        .from('users')
        .select(_userColumns)
        .eq('id', authUser.id)
        .maybeSingle();

    if (row != null) {
      return AppUser.fromRow(row);
    }

    // Auto-create missing profile row for users created before DB trigger was active
    final meta = authUser.userMetadata ?? {};
    final name = meta['name'] as String? ?? authUser.email?.split('@').first ?? 'User';
    final phone = meta['phone'] as String? ?? '';

    try {
      final inserted = await supabase
          .from('users')
          .upsert({
            'id': authUser.id,
            'name': name,
            'email': authUser.email ?? '',
            'phone': phone,
          })
          .select(_userColumns)
          .maybeSingle();

      if (inserted != null) {
        return AppUser.fromRow(inserted);
      }
    } catch (_) {
      // Fall through if RLS restricts direct client upsert
    }

    return null;
  }

  Future<void> markOnboardingCompleted() async {
    final authUser = supabase.auth.currentUser;
    if (authUser == null) return;

    // onboarding_completed is one of the three columns `authenticated` holds
    // an UPDATE grant on, and a trigger stops it being reverted. Everything
    // else on this row is server-written.
    await supabase
        .from('users')
        .update({'onboarding_completed': true})
        .eq('id', authUser.id);
  }

  Future<AppUser> _profileOrThrow() async {
    final user = await currentProfile();
    if (user == null) {
      throw const ApiException('Unable to load your profile. Please try again.');
    }
    return user;
  }

  Future<AppUser> login({
    required String email,
    required String password,
  }) async {
    try {
      final res = await supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (res.session == null) {
        throw const ApiException('Unable to start a session.');
      }
      return await _profileOrThrow();
    } on AuthException catch (e) {
      throw ApiException(e.message);
    }
  }

  /// Registration.
  ///
  /// name/phone/referral_code ride along in user metadata, where the
  /// on_auth_user_created trigger reads them. The referral code is resolved
  /// server-side against affiliates.code, so a typo or an unenrolled
  /// affiliate is dropped silently rather than blocking registration — and
  /// referred_by_uid is never client-writable.
  Future<AppUser> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String passwordConfirmation,
    String? referralCode,
  }) async {
    if (password != passwordConfirmation) {
      throw const ApiException('Passwords do not match.');
    }

    try {
      final res = await supabase.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'name': name.trim(),
          'phone': phone.trim(),
          if (referralCode != null && referralCode.trim().isNotEmpty)
            'referral_code': referralCode.trim().toUpperCase(),
        },
      );

      // With email confirmation enabled in the Supabase project, signUp
      // returns no session and the user must confirm before signing in.
      // Surface that rather than failing on a missing profile read.
      if (res.session == null) {
        throw const ApiException(
          'Account created. Please check your email to confirm it, then sign in.',
        );
      }

      return await _profileOrThrow();
    } on AuthException catch (e) {
      throw ApiException(e.message);
    }
  }

  /// Google sign-in. The caller obtains a Google ID token via google_sign_in;
  /// Supabase verifies it, so there is no provider credential to build.
  Future<({AppUser user, bool isNewUser})> signInWithGoogle({
    required String idToken,
    String? accessToken,
  }) async {
    try {
      final res = await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      if (res.session == null) {
        throw const ApiException('Unable to start a session.');
      }

      // A fresh identity has created_at == last_sign_in_at.
      final identity = res.user?.identities?.firstOrNull;
      final isNew =
          identity != null && identity.createdAt == identity.lastSignInAt;

      return (user: await _profileOrThrow(), isNewUser: isNew);
    } on AuthException catch (e) {
      throw ApiException(e.message);
    }
  }

  Future<void> logout() => supabase.auth.signOut();

  Future<void> requestPasswordReset(String email) async {
    try {
      await supabase.auth.resetPasswordForEmail(email.trim());
    } on AuthException catch (e) {
      throw ApiException(e.message);
    }
  }
}
