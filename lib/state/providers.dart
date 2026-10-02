import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/admin_service.dart';
import '../services/affiliate_service.dart';
import '../services/auth_service.dart';
import '../services/catalogue_service.dart';
import '../services/chat_service.dart';
import '../services/diagnosis_history_service.dart';
import '../services/mpesa_service.dart';
import '../services/notifications_service.dart';
import '../services/push_service.dart';
import '../services/symptoms_service.dart';

/// Service locators. Each is overridable in tests with a fake, which the
/// RN services (module-level functions importing a singleton client) could
/// not be without mocking the module system.

final authServiceProvider = Provider<AuthService>((_) => const AuthService());

final catalogueServiceProvider = Provider<CatalogueService>(
  (ref) => CatalogueService(ref.watch(authServiceProvider)),
);

final chatServiceProvider = Provider<ChatService>((_) => const ChatService());

final mpesaServiceProvider = Provider<MpesaService>((_) => const MpesaService());

final symptomsServiceProvider = Provider<SymptomsService>(
  (_) => const SymptomsService(),
);

final affiliateServiceProvider = Provider<AffiliateService>(
  (_) => const AffiliateService(),
);

final adminServiceProvider = Provider<AdminService>((_) => const AdminService());

final notificationsServiceProvider = Provider<NotificationsService>(
  (_) => const NotificationsService(),
);

/// Overridden in main() with the instance initialised before runApp, since
/// Firebase must be up before the first frame can handle a launch tap.
final pushServiceProvider = Provider<PushService>((_) => PushService());

final diagnosisHistoryServiceProvider = Provider<DiagnosisHistoryService>(
  (_) => const DiagnosisHistoryService(),
);
