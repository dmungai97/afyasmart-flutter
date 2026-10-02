import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'core/router.dart';
import 'core/supabase_client.dart';
import 'core/theme.dart';
import 'services/push_service.dart';
import 'state/auth_controller.dart';
import 'state/notifications_controller.dart';
import 'state/providers.dart';

Future<void> main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();

  final push = PushService();
  await push.init();

  runApp(
    ProviderScope(
      overrides: [pushServiceProvider.overrideWithValue(push)],
      child: const AfyaSmartApp(),
    ),
  );
}

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class AfyaSmartApp extends ConsumerStatefulWidget {
  const AfyaSmartApp({super.key});

  @override
  ConsumerState<AfyaSmartApp> createState() => _AfyaSmartAppState();
}

class _AfyaSmartAppState extends ConsumerState<AfyaSmartApp> {
  final _subs = <StreamSubscription<Object?>>[];

  /// A tap that launched the app arrives while auth is still loading, when
  /// the router would bounce it to the splash screen. Held until auth settles.
  String? _pendingRoute;

  @override
  void initState() {
    super.initState();
    final push = ref.read(pushServiceProvider);

    _subs
      ..add(push.onForegroundMessage.listen(_onForeground))
      ..add(push.onOpened.listen((m) => _open(m.data)))
      ..add(push.onPanelTap.listen(_open));
    push.initialMessage().then((m) {
      if (m != null) _open(m.data);
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  /// FCM shows nothing while the app is in the foreground, so post it to the
  /// notification panel ourselves; a snackbar is only the fallback. The inbox
  /// has already updated through Realtime either way.
  Future<void> _onForeground(RemoteMessage message) async {
    if (await ref.read(pushServiceProvider).showInPanel(message)) return;
    final n = message.notification;
    if (n == null) return;
    scaffoldMessengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(n.title == null ? (n.body ?? '') : '${n.title}\n${n.body ?? ''}'),
          action: message.data['route'] == null
              ? null
              : SnackBarAction(label: 'View', onPressed: () => _open(message.data)),
        ),
      );
  }

  /// The router's redirect still applies, so a route the user may not see
  /// (signed out, unsubscribed) lands wherever it normally would.
  void _open(Map<String, dynamic> data) {
    final id = data['notification_id'];
    if (id is String) {
      unawaited(
        ref.read(notificationsServiceProvider).markRead(id).catchError((_) {}),
      );
    }
    final route = data['route'];
    if (route is! String || !route.startsWith('/')) return;
    if (ref.read(authControllerProvider).loading) {
      _pendingRoute = route;
    } else {
      ref.read(routerProvider).push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Link this install to whoever signs in, every time someone does. Auth
    // starts out loading with no user, so a session restored on launch
    // arrives here as a change too.
    ref.listen(authControllerProvider.select((s) => s.user?.id), (prev, next) {
      if (next != null && next != prev) {
        unawaited(ref.read(pushServiceProvider).registerForUser());
      }
    });
    ref.listen(authControllerProvider.select((s) => s.loading), (_, loading) {
      final route = _pendingRoute;
      if (loading || route == null) return;
      _pendingRoute = null;
      // After this frame, so the splash redirect has already resolved.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(routerProvider).push(route),
      );
    });
    // Keeps the inbox stream warm so the bell badge is live on every screen.
    // listen, not watch: the app root should not rebuild on every badge change.
    ref.listen(unreadNotificationsProvider, (_, _) {});

    return MaterialApp.router(
      title: 'AfyaSmart',
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
