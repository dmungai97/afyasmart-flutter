import AsyncStorage from "@react-native-async-storage/async-storage";
import { create } from "zustand";

type User = {
  id: string;
  name: string;
  email: string;
  phone?: string;
  role?: "user" | "admin" | "super_admin";
  is_subscribed: boolean;
  has_subscribed: boolean;
  onboarding_completed: boolean;
  subscription_plan?: string | null;
  chat_count: number;
  subscription_expires_at: string | null;
};

type AuthState = {
  token: string | null;
  user: User | null;
  hasCompletedOnboarding: boolean;
  isNewUser: boolean;

  // Actions
  setAuth: (token: string, user: User, isNew?: boolean) => Promise<void>;
  clearAuth: () => Promise<void>;
  loadAuth: () => Promise<void>;
  completeOnboarding: () => Promise<void>;
  refreshUser: (token: string) => Promise<void>;
};

const clearPersistedAuth = async () => {
  await AsyncStorage.multiRemove(["token", "user", "hasCompletedOnboarding", "isNewUser"]);
};

export const useAuthStore = create<AuthState>((set, get) => ({
  token: null,
  user: null,
  hasCompletedOnboarding: false,
  isNewUser: false,

  setAuth: async (token, user, isNew = false) => {
    const onboarded = await AsyncStorage.getItem("hasCompletedOnboarding");
    const hasOnboarded = onboarded === "true" || user.onboarding_completed;
    const updatedUser = { ...user, onboarding_completed: hasOnboarded };

    await AsyncStorage.setItem("user", JSON.stringify(updatedUser));
    if (hasOnboarded) {
      await AsyncStorage.setItem("hasCompletedOnboarding", "true");
    }
    // isNewUser is intentionally in-memory only (see loadAuth below) — it
    // drives the one-time "send this brand-new account into onboarding"
    // redirect right after registration, for the current app session only.
    await AsyncStorage.removeItem("isNewUser");
    set({
      token,
      user: updatedUser,
      hasCompletedOnboarding: hasOnboarded,
      isNewUser: isNew,
    });

    if (hasOnboarded && !user.onboarding_completed) {
      try {
        const { markOnboardingCompleted } = await import("../services/auth.service");
        await markOnboardingCompleted();
      } catch {
        // Local onboarding state is enough to continue; server sync can happen later.
      }
    }
  },

  clearAuth: async () => {
    try {
      const { logoutUser } = await import("../services/auth.service");
      await logoutUser();
    } catch {
      // Local state should still clear if sign-out is unavailable.
    }

    await clearPersistedAuth();
    set({
      token: null,
      user: null,
      hasCompletedOnboarding: false,
      isNewUser: false,
    });
  },

  loadAuth: async () => {
    try {
      // supabase-js persists the real session in AsyncStorage itself — this
      // store never writes a "token" key (the in-memory token here is always
      // re-derived fresh via refreshUser()), so there's nothing to clear.
      // token starts null below regardless.
      const raw = await AsyncStorage.getItem("user");
      const onboarded = await AsyncStorage.getItem("hasCompletedOnboarding");
      const user: User | null = raw ? JSON.parse(raw) : null;
      // isNewUser is never restored from storage on a cold start. It only
      // exists to nudge a brand-new registration into the onboarding survey
      // once, in that same live session. Restoring it as true here used to
      // mean any registered user who reopened the app before finishing that
      // survey got bounced back to the "welcome" screen and a blank chat on
      // every single launch, indefinitely — effectively "forgetting" a real,
      // already-registered account.
      set({
        token: null,
        user,
        hasCompletedOnboarding: onboarded === "true" || Boolean(user?.onboarding_completed),
        isNewUser: false,
      });
    } catch {
      await clearPersistedAuth();
      set({
        token: null,
        user: null,
        hasCompletedOnboarding: false,
        isNewUser: false,
      });
    }
  },

  completeOnboarding: async () => {
    const current = get().user;
    const updated = current ? { ...current, onboarding_completed: true } : current;

    await AsyncStorage.setItem("hasCompletedOnboarding", "true");
    await AsyncStorage.removeItem("isNewUser");
    if (updated) await AsyncStorage.setItem("user", JSON.stringify(updated));
    set({ user: updated, hasCompletedOnboarding: true, isNewUser: false });

    // The onboarding survey normally finishes (LockedResultsScreen) before
    // the user has registered, so `current`/get().user is usually still
    // null here — gating this call on it meant the server's
    // onboarding_completed field was never written for the ordinary signup
    // flow. markOnboardingCompleted() already no-ops safely if nobody is
    // signed in yet; setAuth() re-attempts this same sync once they do
    // register or log in, using the "true" flag persisted just above.
    try {
      const { markOnboardingCompleted } = await import("../services/auth.service");
      await markOnboardingCompleted();
    } catch {
      // Keep local completion even if the database is temporarily unavailable.
    }
  },

  // Call after login/payment to sync latest user state from Supabase
  refreshUser: async (token: string) => {
    try {
      const { getCurrentUserProfile } = await import("../services/auth.service");
      const { supabase } = await import("../services/supabase");
      const { data: sessionData } = await supabase.auth.getSession();
      const session = sessionData.session;

      if (!session) {
        await clearPersistedAuth();
        set({
          token: null,
          user: null,
          hasCompletedOnboarding: false,
          isNewUser: false,
        });
        return;
      }

      const user = await getCurrentUserProfile();
      if (!user) return;

      // supabase-js refreshes the access token itself, so this is a read of
      // the current session rather than a mint like getIdToken() was.
      const freshToken = session.access_token;
      const hasOnboarded = get().hasCompletedOnboarding || user.onboarding_completed;
      const updatedUser = { ...user, onboarding_completed: hasOnboarded };

      await AsyncStorage.setItem("user", JSON.stringify(updatedUser));
      if (hasOnboarded) {
        await AsyncStorage.setItem("hasCompletedOnboarding", "true");
        await AsyncStorage.removeItem("isNewUser");
      }
      set({
        user: updatedUser,
        token: freshToken ?? token,
        hasCompletedOnboarding: hasOnboarded,
        // Preserve rather than hardcode false — this runs on every app open
        // with an active session, so hardcoding false here would immediately
        // clobber the value loadAuth() just restored from AsyncStorage,
        // undoing the "isNewUser survives a restart" fix above.
        isNewUser: hasOnboarded ? false : get().isNewUser,
      });
    } catch (error) {
      console.error("Failed to refresh user", error);
      await clearPersistedAuth();
      set({
        token: null,
        user: null,
        hasCompletedOnboarding: false,
        isNewUser: false,
      });
    }
  },
}));
