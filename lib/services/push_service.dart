import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../core/supabase_client.dart';

/// Firebase is used for one thing only: receiving FCM pushes. Auth, data and
/// the decision to send all stay in Supabase (see the push edge function).
///
/// Config follows the same --dart-define pattern as [SupabaseConfig]:
///
///   --dart-define=FIREBASE_PROJECT_ID=...
///   --dart-define=FIREBASE_SENDER_ID=...
///   --dart-define=FIREBASE_API_KEY=...
///   --dart-define=FIREBASE_ANDROID_APP_ID=...
///   --dart-define=FIREBASE_IOS_APP_ID=...
///
/// All values come from the Firebase console (Project settings → Your apps).
/// They identify the app to Firebase and are not secrets. Without them,
/// initialisation falls back to google-services.json / GoogleService-Info.plist
/// if present, and otherwise push is simply off — the app and the in-app
/// inbox work either way.
abstract final class FirebaseConfig {
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');

  static FirebaseOptions? get options {
    final appId = defaultTargetPlatform == TargetPlatform.iOS ? iosAppId : androidAppId;
    if (projectId.isEmpty || senderId.isEmpty || apiKey.isEmpty || appId.isEmpty) {
      return null;
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: senderId,
      projectId: projectId,
      iosBundleId: 'com.afyasmart.afyasmart',
    );
  }
}

class PushService {
  bool _ready = false;
  StreamSubscription<String>? _refreshSub;

  /// Only Android and iOS receive pushes; web and Windows use the inbox.
  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static String get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  bool get isReady => _ready;

  Future<void> init() async {
    if (!_supported || _ready) return;
    try {
      final options = FirebaseConfig.options;
      if (options != null) {
        await Firebase.initializeApp(options: options);
      } else {
        await Firebase.initializeApp();
      }
      _ready = true;
    } on Object catch (e) {
      debugPrint('[Push] disabled: $e');
    }
  }

  /// Foreground messages. FCM does not show a system notification while the
  /// app is open, so the app surfaces these itself.
  Stream<RemoteMessage> get onForegroundMessage =>
      _ready ? FirebaseMessaging.onMessage : const Stream.empty();

  /// Taps on a notification while the app was in the background.
  Stream<RemoteMessage> get onOpened =>
      _ready ? FirebaseMessaging.onMessageOpenedApp : const Stream.empty();

  /// The notification that launched the app from terminated, if any.
  Future<RemoteMessage?> initialMessage() async =>
      _ready ? FirebaseMessaging.instance.getInitialMessage() : null;

  /// Asks for permission (Android 13+, iOS) and links this install's token
  /// to the signed-in account. Safe to call on every sign-in.
  Future<void> registerForUser() async {
    if (!_ready || currentUserId == null) return;
    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await messaging.getToken();
    if (token != null) await _save(token);

    await _refreshSub?.cancel();
    _refreshSub = messaging.onTokenRefresh.listen((t) => unawaited(_save(t)));
  }

  /// Unlinks this install before sign-out, so whoever signs in next on this
  /// phone does not get the previous account's notifications. Must run while
  /// the session is still valid.
  Future<void> unregisterForUser() async {
    await _refreshSub?.cancel();
    _refreshSub = null;
    if (!_ready || currentUserId == null) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    await supabase.rpc('unregister_device_token', params: {'p_token': token});
  }

  Future<void> _save(String token) async {
    if (currentUserId == null) return;
    try {
      await supabase.rpc(
        'register_device_token',
        params: {'p_token': token, 'p_platform': _platform},
      );
    } on Object catch (e) {
      debugPrint('[Push] token registration failed: $e');
    }
  }
}
