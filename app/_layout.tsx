import { Slot, useRouter, useSegments } from "expo-router";
import { KeyboardProvider } from "react-native-keyboard-controller";
import { useEffect, useState } from "react";
import { useAuthStore } from "../src/store/authStore";
import { supabase } from "../src/services/supabase";
import { isSubscriptionActive } from "../src/services/subscription.model";

// onAuthStateChanged existed only to wait out Firebase's async session
// rehydration before deciding where to route. supabase-js exposes the
// restored session directly, so a single awaited read replaces the
// subscribe-once-then-unsubscribe dance.
const waitForSession = async () => {
  const { data } = await supabase.auth.getSession();
  return data.session;
};

export default function RootLayout() {
  const token = useAuthStore((s) => s.token);
  const user = useAuthStore((s) => s.user);
  const hasCompletedOnboarding = useAuthStore((s) => s.hasCompletedOnboarding);
  const isNewUser = useAuthStore((s) => s.isNewUser);
  const loadAuth = useAuthStore((s) => s.loadAuth);
  const refreshUser = useAuthStore((s) => s.refreshUser);
  const clearAuth = useAuthStore((s) => s.clearAuth);
  const segments = useSegments();
  const router = useRouter();
  const [authLoaded, setAuthLoaded] = useState(false);

  useEffect(() => {
    let mounted = true;

    const hydrateAuth = async () => {
      await loadAuth();
      const session = await waitForSession();
      const currentToken = useAuthStore.getState().token;
      const cachedUser = useAuthStore.getState().user;

      if (session) {
        await refreshUser(currentToken ?? session.access_token);
        return;
      }

      if (currentToken) {
        await clearAuth();
        return;
      }

      if (cachedUser) {
        await clearAuth();
      }
    };

    hydrateAuth().finally(() => {
      if (mounted) setAuthLoaded(true);
    });

    return () => {
      mounted = false;
    };
  }, [clearAuth, loadAuth, refreshUser]);

  useEffect(() => {
    if (!authLoaded) return;

    const seg = segments as string[];
    const first = seg[0] ?? "";
    const current = seg[seg.length - 1] ?? first;

    const authRoutes = ["login", "register"];
    const onboardingRoutes = [
      "welcome",
      "health-check",
      "analysis-loading",
      "locked-results",
      "symptom-chat",
    ];
    const inAuth = first === "(auth)" || authRoutes.includes(first) || authRoutes.includes(current);
    const inOnboarding =
      first === "(onboarding)" ||
      onboardingRoutes.includes(first) ||
      onboardingRoutes.includes(current);
    const inTabs = [
      "index",
      "chat",
      "diagnosis-results",
      "doctors",
      "drugs",
      "map",
      "pharmacy",
      "profile",
      "subscription",
      "symptoms",
    ].includes(first) || first === "(tabs)" || [
      "index",
      "chat",
      "diagnosis-results",
      "doctors",
      "drugs",
      "map",
      "pharmacy",
      "profile",
      "subscription",
      "symptoms",
    ].includes(current);
    const inSubscription = first === "subscription" || current === "subscription";
    const inAdmin = first === "admin";
    const inAffiliate = first === "affiliate";
    const onWelcome = first === "welcome" || current === "welcome";
    const onRoot = first === "index" || first === "";
    const premiumRoutes = ["diagnosis-results", "doctors", "drugs", "map", "pharmacy", "symptoms"];
    const hasFullAccess = isSubscriptionActive(user);
    const isAdmin = user?.role === "admin" || user?.role === "super_admin";
    const needsOnboarding =
      isNewUser && !hasCompletedOnboarding && !user?.onboarding_completed;

    if (inAffiliate) {
      if (!token) {
        router.replace("/(auth)/login" as any);
      }
      return;
    }

    if (!token) {
      if (inAdmin || inTabs) {
        router.replace("/(auth)/login" as any);
        return;
      }

      if (onRoot) {
        router.replace("/(onboarding)/welcome" as any);
        return;
      }

      if (!inAuth && !inOnboarding && !onWelcome)
        router.replace("/(onboarding)/welcome" as any);
      return;
    }

    if (inAdmin) {
      if (!isAdmin) router.replace("/(tabs)" as any);
      return;
    }

    if (isAdmin && (inAuth || onRoot || inTabs || inOnboarding)) {
      router.replace("/admin" as any);
      return;
    }

    if (hasFullAccess) {
      if (!inTabs) router.replace("/(tabs)" as any);
      return;
    }

    if (inSubscription) return;

    if (premiumRoutes.includes(first) || premiumRoutes.includes(current)) {
      router.replace("/(tabs)/subscription" as any);
      return;
    }

    if (needsOnboarding) {
      if (!inOnboarding) router.replace("/(onboarding)/welcome" as any);
      return;
    }

    if (inOnboarding) {
      // Existing users should not be forced through the new-user flow.
      router.replace("/(tabs)" as any);
      return;
    }

    if (inAuth || onRoot) {
      router.replace("/(tabs)" as any);
    }
  }, [authLoaded, token, user, hasCompletedOnboarding, isNewUser, segments, router]);

  if (!authLoaded) return null;

  return (
    <KeyboardProvider>
      <Slot />
    </KeyboardProvider>
  );
}
