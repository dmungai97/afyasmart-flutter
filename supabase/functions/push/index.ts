import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { adminClient } from "../_shared/supabase.ts";
import { json } from "../_shared/http.ts";

// Sends one stored notification to the user's devices through FCM.
//
// Called only by the dispatch_push() trigger on public.notifications (via
// pg_net), never by the app. The trigger authenticates with a shared secret
// in x-push-secret rather than a JWT, so deploy with --no-verify-jwt.
//
// Secrets:
//   PUSH_WEBHOOK_SECRET   same value as the push_webhook_secret Vault secret
//   FCM_SERVICE_ACCOUNT   the Firebase service-account JSON, as one string
//
// FCM is used purely as the delivery pipe: it also forwards to APNs for iOS,
// so there is one sending path for both platforms.

type ServiceAccount = { project_id: string; client_email: string; private_key: string };

const PREF_COLUMN: Record<string, string> = {
  subscription: "subscription",
  affiliate: "affiliate",
  symptom: "symptom",
  wellness: "wellness",
};

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required secret: ${name}`);
  return value;
}

// FCM_SERVICE_ACCOUNT may be the JSON itself or the JSON base64-encoded.
// Base64 exists because Windows PowerShell 5.1 strips the double quotes from
// the JSON when passing it to `supabase secrets set`, leaving it unparseable.
function serviceAccount(): ServiceAccount {
  const raw = env("FCM_SERVICE_ACCOUNT").trim();
  const text = raw.startsWith("{") ? raw : new TextDecoder().decode(
    Uint8Array.from(atob(raw), (c) => c.charCodeAt(0)),
  );

  let sa: ServiceAccount;
  try {
    sa = JSON.parse(text);
  } catch {
    // Never echo the value: it holds a private key.
    throw new Error(
      "FCM_SERVICE_ACCOUNT is not valid JSON (or base64 of it). Re-set it base64-encoded.",
    );
  }
  if (!sa.project_id || !sa.client_email || !sa.private_key) {
    throw new Error("FCM_SERVICE_ACCOUNT is missing project_id, client_email or private_key.");
  }
  return sa;
}

// Constant-time compare, so the secret cannot be recovered by timing.
function safeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  if (ea.length !== eb.length) return false;
  let diff = 0;
  for (let i = 0; i < ea.length; i++) diff |= ea[i] ^ eb[i];
  return diff === 0;
}

function base64url(bytes: Uint8Array | string): string {
  const raw = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let bin = "";
  for (const b of raw) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// Google OAuth access tokens last an hour; reuse one across warm invocations.
let cachedToken: { value: string; expiresAt: number } | null = null;

async function googleAccessToken(sa: ServiceAccount): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) return cachedToken.value;

  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));

  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`)),
  );

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claims}.${base64url(signature)}`,
    }),
  });
  if (!res.ok) throw new Error(`Google token exchange failed: ${res.status} ${await res.text()}`);

  const body = await res.json();
  cachedToken = { value: body.access_token, expiresAt: Date.now() + body.expires_in * 1000 };
  return cachedToken.value;
}

// Errors are returned in the body (pg_net stores it in net._http_response),
// so a failed push can be diagnosed from SQL rather than only from logs.
Deno.serve(async (req) => {
  try {
    return await handle(req);
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    console.error(`push failed: ${message}`);
    return json({ status: "error", message }, 500);
  }
});

async function handle(req: Request): Promise<Response> {
  if (req.method !== "POST") return json({ status: "error", message: "Method not allowed" }, 405);

  if (!safeEqual(req.headers.get("x-push-secret") ?? "", env("PUSH_WEBHOOK_SECRET"))) {
    return json({ status: "error", message: "Forbidden" }, 403);
  }

  const { notification_id } = await req.json().catch(() => ({}));
  if (typeof notification_id !== "string") {
    return json({ status: "error", message: "notification_id is required" }, 400);
  }

  const db = adminClient();

  const { data: note, error: noteError } = await db
    .from("notifications")
    .select("id, user_id, category, title, body, data, pushed_at")
    .eq("id", notification_id)
    .maybeSingle();
  if (noteError) throw new Error(noteError.message);
  if (!note || note.pushed_at) return json({ status: "skipped", reason: "missing or already pushed" });

  // No row means the user never touched the settings: everything is on.
  const { data: prefs } = await db
    .from("notification_preferences")
    .select("*")
    .eq("user_id", note.user_id)
    .maybeSingle();
  if (prefs && (!prefs.enabled || prefs[PREF_COLUMN[note.category]] === false)) {
    return json({ status: "skipped", reason: "muted by preferences" });
  }

  const { data: devices, error: deviceError } = await db
    .from("device_tokens")
    .select("token")
    .eq("user_id", note.user_id);
  if (deviceError) throw new Error(deviceError.message);
  if (!devices?.length) return json({ status: "skipped", reason: "no devices" });

  const sa = serviceAccount();
  const accessToken = await googleAccessToken(sa);
  const endpoint = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

  // FCM data values must be strings.
  const data: Record<string, string> = { notification_id: note.id, category: note.category };
  for (const [k, v] of Object.entries(note.data ?? {})) data[k] = String(v);

  let delivered = 0;
  const stale: string[] = [];
  const errors: string[] = [];

  await Promise.all(devices.map(async ({ token }) => {
    const res = await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${accessToken}` },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: note.title, body: note.body },
          data,
          android: { priority: "high" },
          apns: { payload: { aps: { sound: "default" } } },
        },
      }),
    });

    if (res.ok) {
      delivered++;
      return;
    }

    // An uninstalled app or a rotated token: drop it so it is not retried
    // on every future notification.
    const text = await res.text();
    if (res.status === 404 || text.includes("UNREGISTERED") || text.includes("registration token is not a valid")) {
      stale.push(token);
    } else {
      console.error(`FCM send failed (${res.status}): ${text}`);
      errors.push(`${res.status}: ${text.slice(0, 300)}`);
    }
  }));

  if (stale.length) await db.from("device_tokens").delete().in("token", stale);
  if (delivered) await db.from("notifications").update({ pushed_at: new Date().toISOString() }).eq("id", note.id);

  return json({ status: delivered ? "ok" : "failed", delivered, removed: stale.length, errors });
}
