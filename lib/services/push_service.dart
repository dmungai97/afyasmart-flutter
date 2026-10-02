import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

  /// FCM posts to the notification panel only while the app is in the
  /// background. Foreground messages are re-posted through this on Android so
  /// they land in the panel too; iOS does it natively (see init).
  final _local = FlutterLocalNotificationsPlugin();
  final _localTaps = StreamController<Map<String, dynamic>>.broadcast();

  /// Must match default_notification_channel_id in AndroidManifest.xml, so
  /// background (FCM-posted) and foreground (re-posted) notifications share
  /// one high-importance channel and both show as heads-up.
  static const _channel = AndroidNotificationChannel(
    'afyasmart_default',
    'AfyaSmart notifications',
    description: 'Payments, subscription reminders and affiliate earnings',
    importance: Importance.high,
  );

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
      await _initPresentation();
    } on Object catch (e) {
      debugPrint('[Push] disabled: $e');
    }
  }

  Future<void> _initPresentation() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      return;
    }

    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (r) {
        final payload = r.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          _localTaps.add((jsonDecode(payload) as Map).cast<String, dynamic>());
        } on FormatException {
          // Not one of ours.
        }
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  /// Makes sure a foreground message reaches the notification panel: posts
  /// it on Android, and on iOS reports that the system already showed it.
  /// Returns false only when it could not be shown (push off, data-only
  /// message), so the caller can fall back to an in-app banner.
  Future<bool> showInPanel(RemoteMessage message) async {
    final n = message.notification;
    if (!_ready || n == null) return false;
    if (defaultTargetPlatform == TargetPlatform.iOS) return true;

    await _local.show(
      id: message.hashCode & 0x7fffffff,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode(message.data),
    );
    return true;
  }

  /// Message data from taps on notifications posted by [showInPanel], in the
  /// same shape as [RemoteMessage.data].
  Stream<Map<String, dynamic>> get onPanelTap => _localTaps.stream;

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
