import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';

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
import '../features/user/change_password_screen.dart';
import '../features/user/chat_screen.dart';
import '../features/user/diagnosis_results_screen.dart';
import '../features/user/doctors_screen.dart';
import '../features/user/drugs_screen.dart';
import '../features/user/home_screen.dart';
import '../features/user/map_screen.dart';
import '../features/user/payment_history_screen.dart';
import '../features/user/personal_info_screen.dart';
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
  static const splash = '/splash';
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
  static const personalInfo = '/profile/personal-info';
  static const changePassword = '/profile/change-password';
  static const paymentHistory = '/profile/payments';

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
    personalInfo,
    changePassword,
    paymentHistory,
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
  return GoRouter(
    initialLocation: Routes.splash,
    // Re-runs redirect whenever auth state changes, which is what makes
    // "sign out anywhere and land on welcome" work without each screen
    // handling it.
    refreshListenable: _AuthListenable(ref),
    redirect: (context, goState) {
      final auth = ref.read(authControllerProvider);
      if (auth.loading) return Routes.splash;

      final location = goState.matchedLocation;
      final user = auth.user;
      final signedIn = user != null;

      final inAuth = Routes.auth.contains(location);
      final inOnboarding = Routes.onboarding.contains(location);
      final inTabs = Routes.tabs.contains(location);
      final inAdmin = location.startsWith(Routes.admin);
      final inAffiliate = location.startsWith(Routes.affiliate);

      String? result;
      if (location == Routes.splash) {
        if (signedIn) {
          result = user.isAdmin ? Routes.admin : Routes.home;
        } else if (auth.hasCompletedOnboarding) {
          result = Routes.login;
        } else {
          result = Routes.welcome;
        }
      } else if (inAffiliate) {
        result = signedIn ? null : Routes.login;
      } else if (!signedIn) {
        if (inAdmin || inTabs) {
          result = Routes.login;
        } else if (inAuth || inOnboarding) {
          result = null;
        } else if (auth.hasCompletedOnboarding) {
          result = Routes.login;
        } else {
          result = Routes.welcome;
        }
      } else if (inAdmin) {
        result = user.isAdmin ? null : Routes.home;
      } else if (user.isAdmin && (inAuth || inOnboarding)) {
        result = Routes.admin;
      } else if (user.isSubscribed) {
        result = inTabs ? null : Routes.home;
      } else if (location == Routes.subscription) {
        result = null;
      } else if (Routes.premium.contains(location)) {
        result = Routes.subscription;
      } else if (auth.isNewUser && !auth.hasCompletedOnboarding && !user.onboardingCompleted) {
        result = inOnboarding ? null : Routes.welcome;
      } else if (inOnboarding || inAuth) {
        final plan = goState.uri.queryParameters['plan'];
        if (plan != null && plan.isNotEmpty && !user.isSubscribed) {
          result = '${Routes.subscription}?plan=$plan';
        } else {
          result = Routes.home;
        }
      }

      debugPrint('[Router] location: $location, signedIn: $signedIn, -> redirect: $result');
      return result;
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (_, _) => const _SplashOverlay(),
      ),
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
      // Profile sub-pages sit outside the tab shell, like subscription, so
      // they open full-screen with their own back arrow.
      GoRoute(
        path: Routes.personalInfo,
        builder: (_, _) => const PersonalInfoScreen(),
      ),
      GoRoute(
        path: Routes.changePassword,
        builder: (_, _) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: Routes.paymentHistory,
        builder: (_, _) => const PaymentHistoryScreen(),
      ),
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
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (prev?.user != next.user || prev?.loading != next.loading) {
        notifyListeners();
      }
    });
  }
}

class _SplashOverlay extends StatelessWidget {
  const _SplashOverlay();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.paper,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 120,
              height: 2,
              child: LinearProgressIndicator(
                backgroundColor: AppColors.rule,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
              ),
            ),
            SizedBox(height: 24),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Afya'),
                  TextSpan(
                    text: 'Smart',
                    style: TextStyle(color: AppColors.accent),
                  ),
                ],
              ),
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 32,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
