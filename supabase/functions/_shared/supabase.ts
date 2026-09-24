// Replaces firestore.ts — the hand-rolled Firestore REST client each function
// carried a copy of. Supabase's own client talks to the same Postgres the
// functions run beside, so there is no REST shim to maintain and no
// value-type encoding/decoding to get wrong.
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required secret: ${name}`);
  return value;
}

// Service role: bypasses RLS entirely. This is the edge-function equivalent of
// the Firebase Admin SDK, and the reason every money-moving path lives out
// here rather than in the client. It must never be constructed from, or
// leaked into, anything a request body can influence.
export function adminClient(): SupabaseClient {
  const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");
  return createClient(env("SUPABASE_URL"), serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: {
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
      },
    },
  });
}

export class AuthError extends Error {
  status: number;
  constructor(message: string, status = 401) {
    super(message);
    this.name = "AuthError";
    this.status = status;
  }
}

export type AuthUser = { id: string; email: string | null };

/**
 * Verifies the caller's Supabase access token using an isolated auth client
 * so that user bearer tokens never mutate or contaminate service_role clients.
 */
export async function requireUser(req: Request, _client?: SupabaseClient): Promise<AuthUser> {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.toLowerCase().startsWith("bearer ") ? header.slice(7).trim() : "";

  if (!token) throw new AuthError("Missing Authorization header.");

  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || env("SUPABASE_SERVICE_ROLE_KEY");
  const authClient = createClient(env("SUPABASE_URL"), anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data, error } = await authClient.auth.getUser(token);
  if (error || !data?.user) throw new AuthError("Invalid or expired session.");

  return { id: data.user.id, email: data.user.email ?? null };
}

/** The public.users row, or null. Shape matches the old Firestore document. */
// deno-lint-ignore no-explicit-any
export async function getAppUser(client: SupabaseClient, userId: string): Promise<Record<string, any> | null> {
  const { data, error } = await client
    .from("users")
    .select("id, name, email, phone, role, is_subscribed, has_subscribed, subscription_plan, chat_count, subscription_expires_at, referred_by_uid")
    .eq("id", userId)
    .maybeSingle();

  if (error) throw new Error(`Could not load user: ${error.message}`);
  return data;
}
