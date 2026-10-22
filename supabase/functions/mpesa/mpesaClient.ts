// Safaricom Daraja API helpers — ported 1:1 from functions/index.js, with
// defineSecret(...).value() swapped for Deno.env.get(...).

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required secret: ${name}`);
  return value;
}

export function mpesaBaseUrl(): string {
  return Deno.env.get("MPESA_ENV") === "production"
    ? "https://api.safaricom.co.ke"
    : "https://sandbox.safaricom.co.ke";
}

export function mpesaTimestamp(): string {
  const date = new Date();
  const pad = (value: number) => String(value).padStart(2, "0");
  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate()),
    pad(date.getHours()),
    pad(date.getMinutes()),
    pad(date.getSeconds()),
  ].join("");
}

export function normalizePhone(phone: string): string {
  const trimmed = String(phone || "").trim().replace(/\s+/g, "");
  return trimmed.replace(/^0/, "254").replace(/^\+/, "");
}

export function isValidKenyanPhone(phone: string): boolean {
  const normalized = normalizePhone(phone);
  return /^254[17]\d{8}$/.test(normalized);
}

export function planAmount(plan: string | undefined): number | null {
  if (plan === "daily") return 20;
  if (plan === "weekly") return 100;
  if (plan === "monthly") return 200;
  return null;
}

// getSubscriptionExpiry() lived here too, but expiry is now computed by
// subscription_expiry() in the database, where activate_subscription() uses
// it. Keeping a second copy here would let the two drift apart.

// Safaricom Daraja STK push result codes that mean the payment is
// definitively done for (insufficient funds, wrong PIN too many times,
// request expired, subscriber unreachable) as opposed to codes that just
// mean "still waiting".
export const MPESA_TERMINAL_ERROR_CODES = new Set(["1", "1032", "1037", "2001", "1019"]);

async function getMpesaAccessToken(): Promise<string> {
  const credentials = btoa(`${env("MPESA_CONSUMER_KEY")}:${env("MPESA_CONSUMER_SECRET")}`);
  const response = await fetch(`${mpesaBaseUrl()}/oauth/v1/generate?grant_type=client_credentials`, {
    headers: { Authorization: `Basic ${credentials}` },
  });
  if (!response.ok) throw new Error("Could not get M-Pesa access token.");
  const data = await response.json();
  return data.access_token;
}

// deno-lint-ignore no-explicit-any
export async function stkPush({ phone, amount, reference }: { phone: string; amount: number; reference: string }): Promise<any> {
  const token = await getMpesaAccessToken();
  const timestamp = mpesaTimestamp();
  const shortcode = env("MPESA_SHORTCODE");
  const password = btoa(`${shortcode}${env("MPESA_PASSKEY")}${timestamp}`);

  const response = await fetch(`${mpesaBaseUrl()}/mpesa/stkpush/v1/processrequest`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      BusinessShortCode: shortcode,
      Password: password,
      Timestamp: timestamp,
      TransactionType: "CustomerPayBillOnline",
      Amount: amount,
      PartyA: normalizePhone(phone),
      PartyB: shortcode,
      PhoneNumber: normalizePhone(phone),
      CallBackURL: env("MPESA_CALLBACK_URL"),
      AccountReference: reference,
      TransactionDesc: `AfyaSmart ${reference} subscription`,
    }),
  });
  return response.json();
}

// deno-lint-ignore no-explicit-any
export async function stkQuery(checkoutRequestId: string): Promise<any> {
  const token = await getMpesaAccessToken();
  const timestamp = mpesaTimestamp();
  const shortcode = env("MPESA_SHORTCODE");
  const password = btoa(`${shortcode}${env("MPESA_PASSKEY")}${timestamp}`);

  const response = await fetch(`${mpesaBaseUrl()}/mpesa/stkpushquery/v1/query`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      BusinessShortCode: shortcode,
      Password: password,
      Timestamp: timestamp,
      CheckoutRequestID: checkoutRequestId,
    }),
  });
  return response.json();
}
