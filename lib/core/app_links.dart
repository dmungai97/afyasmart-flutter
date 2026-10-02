/// Public web links that open the app when it is installed (Android App Links
/// / iOS universal links) and the web build of the app when it is not.
///
/// The host defaults to the Firebase Hosting site, which is free and live.
/// To move to a custom domain, connect it in Firebase Hosting, add it to the
/// intent filter (AndroidManifest.xml) and associated domains
/// (Runner.entitlements), then build with --dart-define=APP_LINK_HOST=...
/// Keep the old host in those lists so links already shared keep working.
abstract final class AppLinks {
  static const host = String.fromEnvironment(
    'APP_LINK_HOST',
    defaultValue: 'afya-smart-377ad.web.app',
  );

  /// Sign-up link carrying an affiliate's code. Opens the register screen
  /// with the code pre-applied, in the app or on the web.
  static String referral(String code) =>
      Uri.https(host, '/register', {'ref': code}).toString();
}
