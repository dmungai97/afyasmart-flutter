import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/admin_service.dart';
import '../services/affiliate_service.dart';
import '../services/auth_service.dart';
import '../services/catalogue_service.dart';
import '../services/chat_service.dart';
import '../services/mpesa_service.dart';
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
