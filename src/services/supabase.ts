import "react-native-url-polyfill/auto";
import AsyncStorage from "@react-native-async-storage/async-storage";
import Constants from "expo-constants";
import { createClient } from "@supabase/supabase-js";

// Replaces src/services/firebase.ts.
//
// Config still reads from expo.extra, but under a `supabase` key rather than
// `firebase`. Only the URL and the ANON key belong here — the anon key is
// safe to ship because RLS is what actually protects the data. The service
// role key must never appear in the client bundle.

type SupabaseExtraConfig = {
  url?: string;
  anonKey?: string;
  functionsBaseUrl?: string;
};

const extra = (Constants.expoConfig?.extra?.supabase ?? {}) as SupabaseExtraConfig;

const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL ?? extra.url ?? "";
const supabaseAnonKey =
  process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY ?? extra.anonKey ?? "";

if (!supabaseUrl || !supabaseAnonKey) {
  console.warn(
    "Missing Supabase config. Set EXPO_PUBLIC_SUPABASE_URL / " +
      "EXPO_PUBLIC_SUPABASE_ANON_KEY or app.json expo.extra.supabase.",
  );
}

// Edge functions are addressed explicitly rather than via functions.invoke()
// so the existing "/chat/send", "/mpesa/initiate" path shapes keep working.
export const functionsBaseUrl =
  process.env.EXPO_PUBLIC_SUPABASE_FUNCTIONS_BASE_URL ??
  extra.functionsBaseUrl ??
  (supabaseUrl ? `${supabaseUrl}/functions/v1` : "");

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    // The AsyncStorage-backed session is what the long comment in
    // firebase.ts was fighting for: without it the user looks signed in until
    // the process dies, then every cold start sees no session and
    // app/_layout.tsx routes them back through onboarding as if they had
    // never registered. supabase-js takes it as a plain option.
    storage: AsyncStorage,
    autoRefreshToken: true,
    persistSession: true,
    // Must be false on native: there is no URL bar for the SDK to read a
    // session out of. The OAuth redirect is handled explicitly in
    // auth.service.ts instead.
    detectSessionInUrl: false,
  },
});

/** The caller's current access token, or null when signed out. */
export const getAccessToken = async (): Promise<string | null> => {
  const { data } = await supabase.auth.getSession();
  return data.session?.access_token ?? null;
};

/** The caller's user id, or null when signed out. */
export const getCurrentUserId = async (): Promise<string | null> => {
  const { data } = await supabase.auth.getSession();
  return data.session?.user?.id ?? null;
};

/**
 * Thrown when the catalogue is read without an active subscription.
 *
 * This exists because of a genuine behavioural difference between the two
 * backends: Firestore rules REJECTED an unauthorised read, so the services
 * could detect a `permission-denied` error and let it propagate. Postgres RLS
 * does not reject — it filters, so a non-subscriber's query succeeds and
 * simply returns zero rows.
 *
 * Left alone, that silently defeats the paywall: an empty result is
 * indistinguishable from an empty table, so the seed-data fallback in these
 * services would happily serve the full directory to everyone. Subscription
 * state is therefore checked explicitly before the query, and this is raised
 * in place of the old permission-denied error.
 */
export class PaywallError extends Error {
  code = "permission-denied";

  constructor() {
    super("An active subscription is required to view this.");
    this.name = "PaywallError";
  }
}

export const isPaywallError = (error: unknown): boolean =>
  error instanceof PaywallError ||
  (error as { code?: string } | null)?.code === "permission-denied";
