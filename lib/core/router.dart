import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/admin_dashboard_screen.dart';
import '../features/admin/admin_facilities_screen.dart';
import '../features/admin/admin_payouts_screen.dart';
import '../features/admin/admin_shell.dart';
import '../features/admin/admin_transactions_screen.dart';
import '../features/admin/admin_users_screen.dart';
import '../features/affiliate/affiliate_dashboard_screen.dart';
import '../features/affiliate/affiliate_earnings_screen.dart';
import '../features/affiliate/affiliate_profile_screen.dart';
import '../features/affiliate/affiliate_referrals_screen.dart';
import '../features/affiliate/affiliate_shell.dart';
import '../features/affiliate/affiliate_withdraw_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/onboarding/analysis_loading_screen.dart';
import '../features/onboarding/health_check_screen.dart';
import '../features/onboarding/locked_results_screen.dart';
import '../features/onboarding/symptom_chat_screen.dart';
import '../features/onboarding/welcome_screen.dart';
import '../features/shell/tab_shell.dart';
import '../features/user/chat_screen.dart';
import '../features/user/diagnosis_results_screen.dart';
import '../features/user/doctors_screen.dart';
import '../features/user/drugs_screen.dart';
import '../features/user/home_screen.dart';
import '../features/user/map_screen.dart';
import '../features/user/pharmacy_screen.dart';
import '../features/user/profile_screen.dart';
import '../features/user/subscription_screen.dart';
import '../features/user/symptoms_screen.dart';
import '../state/auth_controller.dart';

/// Port of the redirect logic in app/_layout.tsx.
///
/// expo-router decided routing from a `segments` array inside a useEffect,
/// calling router.replace() as a side effect of rendering. go_router has a
/// real redirect hook, so the same rules become one pure function of
/// (location, auth state) — which also removes the flash of the wrong screen
/// the effect-based version could produce before its replace() landed.

abstract final class Routes {
  static const welcome = '/welcome';
  static const healthCheck = '/health-check';
  static const symptomChat = '/symptom-chat';
  static const analysisLoading = '/analysis-loading';
  static const lockedResults = '/locked-results';

  static const login = '/login';
  static const register = '/register';

  static const home = '/home';
  static const chat = '/chat';
  static const symptoms = '/symptoms';
  static const diagnosisResults = '/diagnosis-results';
  static const doctors = '/doctors';
  static const drugs = '/drugs';
  static const pharmacy = '/pharmacy';
  static const map = '/map';
  static const subscription = '/subscription';
  static const profile = '/profile';

  static const admin = '/admin';
  static const adminUsers = '/admin/users';
  static const adminFacilities = '/admin/facilities';
  static const adminTransactions = '/admin/transactions';
  static const adminPayouts = '/admin/payouts';

  static const affiliate = '/affiliate';
  static const affiliateReferrals = '/affiliate/referrals';
  static const affiliateEarnings = '/affiliate/earnings';
  static const affiliateWithdraw = '/affiliate/withdraw';
  static const affiliateProfile = '/affiliate/profile';

  static const onboarding = {
    welcome,
    healthCheck,
    symptomChat,
    analysisLoading,
    lockedResults,
  };

  static const auth = {login, register};

  static const tabs = {
    home,
    chat,
    symptoms,
    diagnosisResults,
    doctors,
    drugs,
    pharmacy,
    map,
    subscription,
    profile,
  };

  /// Routes that require an active subscription. Note that [subscription]
  /// itself is deliberately absent — sending a non-subscriber to the paywall
  /// from the paywall would be a redirect loop.
  static const premium = {
    diagnosisResults,
    doctors,
    drugs,
    map,
    pharmacy,
    symptoms,
  };
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: Routes.welcome,
    // Re-runs redirect whenever auth state changes, which is what makes
    // "sign out anywhere and land on welcome" work without each screen
    // handling it.
    refreshListenable: _AuthListenable(ref),
    redirect: (context, goState) {
      if (auth.loading) return null;

      final location = goState.matchedLocation;
      final user = auth.user;
      final signedIn = user != null;

      final inAuth = Routes.auth.contains(location);
      final inOnboarding = Routes.onboarding.contains(location);
      final inTabs = Routes.tabs.contains(location);
      final inAdmin = location.startsWith(Routes.admin);
      final inAffiliate = location.startsWith(Routes.affiliate);

      if (inAffiliate) return signedIn ? null : Routes.login;

      if (!signedIn) {
        if (inAdmin || inTabs) return Routes.login;
        if (inAuth || inOnboarding) return null;
        return Routes.welcome;
      }

      if (inAdmin) return user.isAdmin ? null : Routes.home;

      // Admins land in the console rather than the patient app.
      if (user.isAdmin && (inAuth || inTabs || inOnboarding)) {
        return Routes.admin;
      }

      if (user.isSubscribed) return inTabs ? null : Routes.home;

      // A non-subscriber may always reach the paywall itself.
      if (location == Routes.subscription) return null;

      if (Routes.premium.contains(location)) return Routes.subscription;

      // Only a brand-new registration is pushed through the survey; an
      // existing user who never finished it is not bounced on every launch.
      final needsOnboarding =
          auth.isNewUser &&
          !auth.hasCompletedOnboarding &&
          !user.onboardingCompleted;

      if (needsOnboarding) return inOnboarding ? null : Routes.welcome;

      // Existing users should not be forced through the new-user flow.
      if (inOnboarding || inAuth) return Routes.home;

      return null;
    },
    routes: [
      // ?plan= and ?ref= come from deep links and are carried between the
      // two auth screens, matching useLocalSearchParams() in the RN
      // originals: `ref` attributes the referral at sign-up, `plan` sends the
      // user straight to that plan's checkout once they have an account.
      GoRoute(
        path: Routes.login,
        builder: (_, goState) =>
            LoginScreen(plan: goState.uri.queryParameters['plan']),
      ),
      GoRoute(
        path: Routes.register,
        builder: (_, goState) => RegisterScreen(
          referralCode: goState.uri.queryParameters['ref'],
          plan: goState.uri.queryParameters['plan'],
        ),
      ),
      GoRoute(
        path: Routes.welcome,
        builder: (_, _) => const WelcomeScreen(),
      ),
      GoRoute(
        path: Routes.healthCheck,
        builder: (_, _) => const HealthCheckScreen(),
      ),
      GoRoute(
        path: Routes.symptomChat,
        builder: (_, _) => const SymptomChatScreen(),
      ),
      GoRoute(
        path: Routes.analysisLoading,
        builder: (_, _) => const AnalysisLoadingScreen(),
      ),
      GoRoute(
        path: Routes.lockedResults,
        builder: (_, _) => const LockedResultsScreen(),
      ),
      // The five bar routes live inside the shell so the bottom bar persists
      // across them. drugs/pharmacy/subscription/symptoms/diagnosis-results
      // had `href: null` in the RN tab layout — reachable, but no tab entry —
      // so they are registered outside it and push full-screen.
      ShellRoute(
        builder: (_, _, child) => TabShell(child: child),
        routes: [
          GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
          GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen()),
          GoRoute(path: Routes.doctors, builder: (_, _) => const DoctorsScreen()),
          GoRoute(path: Routes.chat, builder: (_, _) => const ChatScreen()),
          GoRoute(path: Routes.map, builder: (_, _) => const MapScreen()),
        ],
      ),
      GoRoute(
        path: Routes.diagnosisResults,
        builder: (_, _) => const DiagnosisResultsScreen(),
      ),
      GoRoute(
        path: Routes.pharmacy,
        builder: (_, _) => const PharmacyScreen(),
      ),
      GoRoute(path: Routes.drugs, builder: (_, _) => const DrugsScreen()),
      GoRoute(
        path: Routes.subscription,
        builder: (_, goState) => SubscriptionScreen(
          initialPlan: goState.uri.queryParameters['plan'],
        ),
      ),
      GoRoute(path: Routes.symptoms, builder: (_, _) => const SymptomsScreen()),
      // The affiliate section has its own shell: an enrollment gate, then a
      // five-tab bar. It sits outside the patient tab shell because it is a
      // separate area of the app, reached from the profile menu.
      ShellRoute(
        builder: (_, _, child) => AffiliateShell(child: child),
        routes: [
          GoRoute(
            path: Routes.affiliate,
            builder: (_, _) => const AffiliateDashboardScreen(),
          ),
          GoRoute(
            path: Routes.affiliateReferrals,
            builder: (_, _) => const AffiliateReferralsScreen(),
          ),
          GoRoute(
            path: Routes.affiliateEarnings,
            builder: (_, _) => const AffiliateEarningsScreen(),
          ),
          GoRoute(
            path: Routes.affiliateWithdraw,
            builder: (_, _) => const AffiliateWithdrawScreen(),
          ),
          GoRoute(
            path: Routes.affiliateProfile,
            builder: (_, _) => const AffiliateProfileScreen(),
          ),
        ],
      ),
      // The admin console has its own shell: a drawer on phones, a
      // persistent rail above 900px. The redirect above already keeps
      // non-admins out.
      ShellRoute(
        builder: (_, _, child) => AdminShell(child: child),
        routes: [
          GoRoute(
            path: Routes.admin,
            builder: (_, _) => const AdminDashboardScreen(),
          ),
          GoRoute(
            path: Routes.adminUsers,
            builder: (_, _) => const AdminUsersScreen(),
          ),
          GoRoute(
            path: Routes.adminFacilities,
            builder: (_, _) => const AdminFacilitiesScreen(),
          ),
          GoRoute(
            path: Routes.adminTransactions,
            builder: (_, _) => const AdminTransactionsScreen(),
          ),
          GoRoute(
            path: Routes.adminPayouts,
            builder: (_, _) => const AdminPayoutsScreen(),
          ),
        ],
      ),
    ],
  );
});

/// Bridges Riverpod state changes into go_router's Listenable-based refresh.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
  }
}
