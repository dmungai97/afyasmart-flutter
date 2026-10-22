import 'package:supabase_flutter/supabase_flutter.dart';

/// Port of src/services/supabase.ts.
///
/// Config comes from --dart-define rather than app.json, so the values are
/// baked in at build time and there is no runtime config file to ship:
///
///   flutter run \
///     --dart-define=SUPABASE_URL=https://YOUR_REF.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
///
/// Only the URL and the ANON key belong here. The anon key is safe to ship
/// because RLS is what actually protects the data; the service role key must
/// never appear in the client bundle.
abstract final class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://hayxmaxchdoyeqebeeam.supabase.co',
  );
  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_KLGP2mKWAFJQinf3F3Ue5A_fudyOiGn',
  );

  /// Edge functions are addressed explicitly rather than via
  /// `functions.invoke()`, so the existing "/chat/send", "/mpesa/initiate"
  /// path shapes the deployed functions already serve keep working.
  static const functionsBaseUrl = String.fromEnvironment(
    'SUPABASE_FUNCTIONS_BASE_URL',
    defaultValue: '',
  );

  static String get resolvedFunctionsBaseUrl =>
      functionsBaseUrl.isNotEmpty ? functionsBaseUrl : '$url/functions/v1';

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}

Future<void> initSupabase() async {
  if (!SupabaseConfig.isConfigured) {
    throw StateError(
      'Missing Supabase config. Pass --dart-define=SUPABASE_URL=... and '
      '--dart-define=SUPABASE_ANON_KEY=...',
    );
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    // Named anonKey everywhere else in this codebase and in the Supabase
    // dashboard; the Dart SDK renamed the parameter to publishableKey.
    publishableKey: SupabaseConfig.anonKey,
    // supabase_flutter persists the session itself, which is what the long
    // comment in the old firebase.ts was fighting for: without persistence
    // the user looks signed in until the process dies, then every cold start
    // sees no session and routes them back through onboarding as if they had
    // never registered.
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
}

SupabaseClient get supabase => Supabase.instance.client;

String? get currentUserId => supabase.auth.currentUser?.id;

String? get currentAccessToken => supabase.auth.currentSession?.accessToken;

/// Thrown when the catalogue is read without an active subscription.
///
/// This exists because of a genuine behavioural difference between Firestore
/// and Postgres: Firestore rules REJECTED an unauthorised read, so services
/// could detect a permission error. Postgres RLS does not reject — it
/// filters, so a non-subscriber's query succeeds and returns zero rows,
/// which is indistinguishable from an empty table.
///
/// Left alone that silently defeats the paywall, because an empty result
/// looks exactly like an empty catalogue. Subscription state is therefore
/// checked explicitly before every paywalled query and this is raised
/// instead. The RLS policies still enforce it server-side; this only makes
/// the client fail in a way the screens can show.
class PaywallException implements Exception {
  const PaywallException();

  @override
  String toString() => 'An active subscription is required to view this.';
}

/// Raised for anything the backend rejected, carrying a message already fit
/// to show the user.
class ApiException implements Exception {
  const ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
