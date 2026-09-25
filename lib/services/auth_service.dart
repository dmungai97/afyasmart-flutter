import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';
import '../models/app_user.dart';

/// One row of payment_requests, as shown in Payment History.
class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.plan,
    required this.amount,
    required this.status,
    this.phone,
    this.failureReason,
    this.createdAt,
  });

  factory PaymentRecord.fromRow(Map<String, dynamic> row) => PaymentRecord(
    id: row['id'] as String,
    plan: row['plan'] as String? ?? '',
    amount: (row['amount'] as num?)?.toDouble() ?? 0,
    status: row['status'] as String? ?? 'pending',
    phone: row['phone'] as String?,
    failureReason: row['failure_reason'] as String?,
    createdAt: DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal(),
  );

  final String id;
  final String plan;
  final double amount;

  /// 'pending', 'paid', 'failed' or 'cancelled' (the payment_status enum).
  final String status;
  final String? phone;
  final String? failureReason;
  final DateTime? createdAt;
}

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

  /// Kenyan mobile number in any of the forms people type it: 07.., 01..,
  /// 2547.., +2547... Mirrors isValidKenyanPhone() in the mpesa function, so
  /// a number saved here is one an STK push will accept.
  static bool isValidKenyanPhone(String phone) {
    final digits = phone.trim().replaceAll(RegExp(r'[\s-]'), '');
    final normalized = digits
        .replaceFirst(RegExp(r'^\+'), '')
        .replaceFirst(RegExp(r'^0'), '254');
    return RegExp(r'^254[17]\d{8}$').hasMatch(normalized);
  }

  /// Updates the caller's name and phone. RLS limits this to their own row
  /// and a column grant limits it to these fields.
  Future<void> updateProfile({
    required String name,
    required String phone,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      throw const ApiException('You must be signed in to update your profile.');
    }

    final trimmedName = name.trim();
    // Stored without spaces or dashes: the mpesa function strips whitespace
    // but not dashes when it normalizes a number.
    final trimmedPhone = phone.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (trimmedName.isEmpty) throw const ApiException('Enter your name.');
    if (!isValidKenyanPhone(trimmedPhone)) {
      throw const ApiException(
        'Enter a valid Safaricom or Airtel number, e.g. 0712 345 678.',
      );
    }

    try {
      await supabase
          .from('users')
          .update({'name': trimmedName, 'phone': trimmedPhone})
          .eq('id', userId);
    } on PostgrestException catch (e) {
      throw ApiException(e.message);
    }
  }

  /// Sets a new password for the signed-in user. Also works for accounts
  /// created with Google, giving them a password they can sign in with.
  Future<void> changePassword(String newPassword) async {
    if (newPassword.length < 6) {
      throw const ApiException('Password must be at least 6 characters.');
    }

    try {
      await supabase.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      // With "secure password change" on, Supabase refuses on a session
      // older than 24h until the user re-authenticates.
      if (e.code == 'reauthentication_needed' ||
          e.message.toLowerCase().contains('reauthenticat')) {
        throw const ApiException(
          'For your security, please log out and sign in again, then change '
          'your password.',
        );
      }
      if (e.code == 'same_password') {
        throw const ApiException(
          'Your new password must be different from the current one.',
        );
      }
      throw ApiException(e.message);
    }
  }

  /// The caller's M-Pesa payment attempts, newest first. RLS scopes the
  /// rows to the caller; the filter is for clarity, not security.
  Future<List<PaymentRecord>> paymentHistory() async {
    final userId = currentUserId;
    if (userId == null) {
      throw const ApiException('You must be signed in to view payments.');
    }

    final rows = await supabase
        .from('payment_requests')
        .select('id, plan, amount, status, phone, failure_reason, created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(100);

    return rows.map(PaymentRecord.fromRow).toList();
  }

  /// Permanently deletes the signed-in account and everything keyed to it.
  ///
  /// Runs in the account edge function because deleting an auth user needs
  /// the service role. The session is dead once this returns.
  Future<void> deleteAccount() async {
    final token = currentAccessToken;
    if (token == null) {
      throw const ApiException('You must be signed in to delete your account.');
    }

    final response = await http.post(
      Uri.parse('${SupabaseConfig.resolvedFunctionsBaseUrl}/account/delete'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      String? message;
      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) message = body['message'] as String?;
      } on FormatException {
        // Non-JSON error page; fall through to the generic message.
      }
      throw ApiException(message ?? 'Could not delete your account.');
    }
  }
}
