import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';
import '../models/app_user.dart';
import 'providers.dart';

/// Port of src/store/authStore.ts.
///
/// The RN store persisted a JSON copy of the user to AsyncStorage so a cold
/// start had something to render before the network came back. That is kept,
/// but the session itself is supabase_flutter's business — this never stores
/// a token.

class AuthState {
  const AuthState({
    this.user,
    this.hasCompletedOnboarding = false,
    this.isNewUser = false,
    this.loading = true,
  });

  final AppUser? user;
  final bool hasCompletedOnboarding;

  /// In-memory only, deliberately.
  ///
  /// It exists to nudge a brand-new registration into the onboarding survey
  /// once, in that same live session. Restoring it from storage on a cold
  /// start used to mean any registered user who reopened the app before
  /// finishing the survey got bounced back to the welcome screen on every
  /// single launch — effectively "forgetting" a real account.
  final bool isNewUser;

  final bool loading;

  bool get isSignedIn => user != null;

  AuthState copyWith({
    AppUser? user,
    bool? hasCompletedOnboarding,
    bool? isNewUser,
    bool? loading,
    bool clearUser = false,
  }) => AuthState(
    user: clearUser ? null : (user ?? this.user),
    hasCompletedOnboarding: hasCompletedOnboarding ?? this.hasCompletedOnboarding,
    isNewUser: isNewUser ?? this.isNewUser,
    loading: loading ?? this.loading,
  );
}

class AuthController extends Notifier<AuthState> {
  static const _onboardedKey = 'hasCompletedOnboarding';

  @override
  AuthState build() {
    // Keeps local state in step when supabase_flutter refreshes or drops the
    // session on its own — the RN app used onAuthStateChanged for this.
    final sub = supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) {
        _clearLocal();
      }
    });
    ref.onDispose(sub.cancel);

    unawaited(_hydrate());
    return const AuthState();
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final onboarded = prefs.getBool(_onboardedKey) ?? false;

    // No session means nothing to load; the router sends them to onboarding
    // or login.
    if (supabase.auth.currentSession == null) {
      state = AuthState(hasCompletedOnboarding: onboarded, loading: false);
      return;
    }

    try {
      final user = await ref.read(authServiceProvider).currentProfile();
      state = AuthState(
        user: user,
        hasCompletedOnboarding: onboarded || (user?.onboardingCompleted ?? false),
        loading: false,
      );
    } on Exception {
      // A failed profile read on a live session is not a reason to sign the
      // user out — keep the session and let the screen retry.
      state = AuthState(hasCompletedOnboarding: onboarded, loading: false);
    }
  }

  /// Re-reads the profile. Call after login or a settled payment.
  Future<void> refresh() async {
    if (supabase.auth.currentSession == null) {
      await _clearLocal();
      return;
    }

    final user = await ref.read(authServiceProvider).currentProfile();
    if (user == null) return;

    final onboarded = state.hasCompletedOnboarding || user.onboardingCompleted;
    if (onboarded) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onboardedKey, true);
    }

    state = state.copyWith(
      user: user,
      hasCompletedOnboarding: onboarded,
      loading: false,
      // Preserved rather than hardcoded false: this runs on every app open
      // with an active session, and hardcoding would clobber the flag set by
      // a registration that happened moments earlier.
      isNewUser: onboarded ? false : state.isNewUser,
    );
  }

  Future<void> _setSignedIn(AppUser user, {bool isNew = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final onboarded =
        (prefs.getBool(_onboardedKey) ?? false) || user.onboardingCompleted;

    if (onboarded) await prefs.setBool(_onboardedKey, true);

    state = AuthState(
      user: user,
      hasCompletedOnboarding: onboarded,
      isNewUser: isNew,
      loading: false,
    );

    // The survey is normally finished before an account exists, so sync the
    // locally-recorded completion up now that there is somewhere to put it.
    if (onboarded && !user.onboardingCompleted) {
      try {
        await ref.read(authServiceProvider).markOnboardingCompleted();
      } on Exception {
        // Local onboarding state is enough to continue; the next refresh or
        // sign-in retries the sync.
      }
    }
  }

  Future<void> login({required String email, required String password}) async {
    final user = await ref
        .read(authServiceProvider)
        .login(email: email, password: password);
    await _setSignedIn(user);
  }

  Future<void> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String passwordConfirmation,
    String? referralCode,
  }) async {
    final user = await ref
        .read(authServiceProvider)
        .register(
          name: name,
          email: email,
          phone: phone,
          password: password,
          passwordConfirmation: passwordConfirmation,
          referralCode: referralCode,
        );
    await _setSignedIn(user, isNew: true);
  }

  Future<void> signInWithGoogle({
    required String idToken,
    String? accessToken,
  }) async {
    final result = await ref
        .read(authServiceProvider)
        .signInWithGoogle(idToken: idToken, accessToken: accessToken);
    await _setSignedIn(result.user, isNew: result.isNewUser);
  }

  /// Marks the onboarding survey complete.
  ///
  /// Usually runs before the user has registered, so there may be no session
  /// to write to. markOnboardingCompleted() no-ops safely in that case and
  /// the flag persisted here is replayed by [_setSignedIn] once they do.
  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardedKey, true);

    state = state.copyWith(
      user: state.user?.copyWith(onboardingCompleted: true),
      hasCompletedOnboarding: true,
      isNewUser: false,
    );

    try {
      await ref.read(authServiceProvider).markOnboardingCompleted();
    } on Exception {
      // Keep local completion even if the database is temporarily unavailable.
    }
  }

  /// Sends the password-reset email. Every account migrated off Firebase
  /// needs this at least once, since scrypt hashes cannot become bcrypt ones.
  Future<void> requestPasswordReset(String email) =>
      ref.read(authServiceProvider).requestPasswordReset(email);

  Future<void> logout() async {
    try {
      await ref.read(authServiceProvider).logout();
    } on Exception {
      // Local state should still clear if sign-out is unavailable.
    }
    await _clearLocal();
  }

  Future<void> _clearLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_onboardedKey);
    state = const AuthState(loading: false);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// Convenience selector used across screens.
final currentUserProvider = Provider<AppUser?>(
  (ref) => ref.watch(authControllerProvider).user,
);
