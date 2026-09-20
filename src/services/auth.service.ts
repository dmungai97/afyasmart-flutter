import { supabase } from "./supabase";

export interface AuthUser {
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
}

export interface AuthResponse {
  token: string;
  user: AuthUser;
  isNewUser?: boolean;
}

const USER_COLUMNS =
  "id, name, email, phone, role, is_subscribed, has_subscribed, " +
  "onboarding_completed, subscription_plan, chat_count, subscription_expires_at";

const isStoredSubscriptionActive = (isSubscribed: unknown, expiresAt: string | null) => {
  if (!isSubscribed) return false;
  if (!expiresAt) return true;

  const expiryTime = new Date(expiresAt).getTime();
  return Number.isFinite(expiryTime) && expiryTime > Date.now();
};

// Postgres returns timestamptz as an ISO string already, so the Firestore
// Timestamp.toDate() handling this used to need is gone.
export const normalizeUser = (id: string, data: any): AuthUser => {
  const subscriptionExpiresAt = data?.subscription_expires_at ?? null;
  const isSubscribed = isStoredSubscriptionActive(
    data?.is_subscribed,
    subscriptionExpiresAt,
  );

  return {
    id,
    name: data?.name ?? "AfyaSmart User",
    email: data?.email ?? "",
    phone: data?.phone ?? undefined,
    role: data?.role === "admin" || data?.role === "super_admin" ? data.role : "user",
    is_subscribed: isSubscribed,
    has_subscribed: Boolean(
      data?.has_subscribed
        || data?.is_subscribed
        || subscriptionExpiresAt
        || ["daily", "weekly", "monthly"].includes(data?.subscription_plan),
    ),
    onboarding_completed: Boolean(data?.onboarding_completed),
    subscription_plan: data?.subscription_plan ?? "free",
    chat_count: Number(data?.chat_count ?? 0),
    subscription_expires_at: subscriptionExpiresAt,
  };
};

/**
 * Loads the signed-in user's public.users row.
 *
 * The row is created by the on_auth_user_created trigger inside the same
 * transaction as the auth user, so it always exists by the time a session
 * does — there is no "get or create" branch any more, and with it goes the
 * client's ability to author its own profile fields.
 */
export const getCurrentUserProfile = async (): Promise<AuthUser | null> => {
  const { data: sessionData } = await supabase.auth.getSession();
  const authUser = sessionData.session?.user;
  if (!authUser) return null;

  const { data, error } = await supabase
    .from("users")
    .select(USER_COLUMNS)
    .eq("id", authUser.id)
    .maybeSingle();

  if (error) throw new Error(`Unable to load user profile: ${error.message}`);
  if (!data) return null;

  return normalizeUser(authUser.id, data);
};

export const markOnboardingCompleted = async (): Promise<void> => {
  const { data: sessionData } = await supabase.auth.getSession();
  const authUser = sessionData.session?.user;
  if (!authUser) return;

  // onboarding_completed is one of the three columns `authenticated` holds an
  // UPDATE grant on, and a trigger stops it being reverted. Everything else
  // on this row is server-written.
  await supabase
    .from("users")
    .update({ onboarding_completed: true })
    .eq("id", authUser.id);
};

const profileOrThrow = async (): Promise<AuthUser> => {
  const user = await getCurrentUserProfile();
  if (!user) throw new Error("Unable to load your profile. Please try again.");
  return user;
};

export const loginUser = async (
  email: string,
  password: string,
): Promise<AuthResponse> => {
  const { data, error } = await supabase.auth.signInWithPassword({
    email: email.trim(),
    password,
  });

  if (error) throw new Error(error.message);
  if (!data.session) throw new Error("Unable to start a session.");

  return { token: data.session.access_token, user: await profileOrThrow() };
};

export const registerUser = async (
  name: string,
  email: string,
  phone: string,
  password: string,
  password_confirmation: string,
  referralCode?: string | null,
): Promise<AuthResponse> => {
  if (password !== password_confirmation) {
    throw new Error("Passwords do not match.");
  }

  // name/phone/referral_code ride along in user metadata, where the
  // on_auth_user_created trigger reads them. The referral code is resolved
  // server-side against affiliates.code, so a typo or an unenrolled affiliate
  // is dropped silently rather than blocking registration — same behaviour as
  // the old resolveReferrerUid(), but it no longer needs a second round-trip
  // after sign-up, and referred_by_uid is never client-writable.
  const { data, error } = await supabase.auth.signUp({
    email: email.trim(),
    password,
    options: {
      data: {
        name: name.trim(),
        phone: phone.trim(),
        ...(referralCode ? { referral_code: referralCode.trim().toUpperCase() } : {}),
      },
    },
  });

  if (error) throw new Error(error.message);

  // With email confirmation enabled in the Supabase project, signUp returns
  // no session and the user must confirm before signing in. Surface that
  // rather than failing on a missing profile read.
  if (!data.session) {
    throw new Error(
      "Account created. Please check your email to confirm it, then sign in.",
    );
  }

  return {
    token: data.session.access_token,
    user: await profileOrThrow(),
    isNewUser: true,
  };
};

/**
 * Google sign-in. The screen still obtains a Google ID token via
 * expo-auth-session; only the exchange changes — Supabase verifies the token
 * itself, so GoogleAuthProvider.credential() is gone.
 */
export const signInWithGoogleIdToken = async (
  idToken: string,
): Promise<AuthResponse> => {
  const { data, error } = await supabase.auth.signInWithIdToken({
    provider: "google",
    token: idToken,
  });

  if (error) throw new Error(error.message);
  if (!data.session) throw new Error("Unable to start a session.");

  // Supabase reports whether this was a first sign-in via the identity
  // timestamps; a fresh identity has created_at === last_sign_in_at.
  const identity = data.user?.identities?.[0];
  const isNewUser = Boolean(
    identity && identity.created_at === identity.last_sign_in_at,
  );

  return { token: data.session.access_token, user: await profileOrThrow(), isNewUser };
};

export const logoutUser = async (): Promise<void> => {
  await supabase.auth.signOut();
};

/** Sends the password-reset email. Migrated users need this at least once. */
export const requestPasswordReset = async (email: string): Promise<void> => {
  const { error } = await supabase.auth.resetPasswordForEmail(email.trim());
  if (error) throw new Error(error.message);
};
