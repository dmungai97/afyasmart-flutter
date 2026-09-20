// mpesaInitiate/mpesaStatus/mpesaCallback, backed by Supabase Auth + Postgres.
//
// Routes on path suffix so the client's existing "/mpesa/initiate" and
// "/mpesa/status" shapes (src/services/mpesa.service.ts) work unchanged.
//
// The big structural change from the Firebase-backed version: subscription
// activation and affiliate commission crediting are no longer written here.
// Both are one call to the activate_subscription() RPC, which does the user
// update, the payment update and the commission credit in a single
// transaction. Previously those were three separate writes that could fail
// independently, and a commission failure was swallowed by a try/catch so the
// subscription still went through uncredited.
//
// verify_jwt is OFF at deploy time and auth is enforced per-route, because
// /callback must be reachable by Safaricom with no token at all.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { adminClient, requireUser, AuthError } from "../_shared/supabase.ts";
import { json, preflight } from "../_shared/http.ts";
import {
  stkPush,
  stkQuery,
  normalizePhone,
  planAmount,
  MPESA_TERMINAL_ERROR_CODES,
} from "./mpesaClient.ts";

type PaymentRow = {
  id: string;
  user_id: string;
  plan: string | null;
  amount: number | null;
  status: string;
  paid: boolean;
};

const PAYMENT_COLUMNS = "id, user_id, plan, amount, status, paid";

/**
 * Resolves a payment's outcome by querying Safaricom directly — never by
 * trusting caller-supplied result data — and persists it. Shared by the
 * user-facing polling route and the Safaricom callback, so both routes to
 * "mark this paid" go through the same authoritative check.
 */
async function resolvePaymentWithMpesa(
  supabase: SupabaseClient,
  payment: PaymentRow,
  checkoutId: string,
) {
  const result = await stkQuery(checkoutId);
  const resultCode = String(result.ResultCode ?? "");

  if (resultCode === "0") {
    if (!payment.plan) {
      console.error("Paid payment has no plan", payment.id);
      return { status: "error", paid: false, message: "Payment has no plan to activate." };
    }

    // Marks the payment paid, activates the subscription and credits the
    // referring affiliate, atomically. Re-running it is safe: the
    // commissions_one_per_payment index makes a second credit a no-op, which
    // matters because the callback and the client's poll routinely race.
    const { error } = await supabase.rpc("activate_subscription", {
      p_user_id: payment.user_id,
      p_plan: payment.plan,
      p_amount: payment.amount,
      p_payment_id: payment.id,
    });

    if (error) {
      console.error("activate_subscription failed", error);
      return { status: "pending", paid: false, message: "Awaiting confirmation." };
    }

    await supabase.from("payment_requests").update({ result }).eq("id", payment.id);
    return { status: "success", paid: true, message: "Payment confirmed." };
  }

  if (resultCode === "1032") {
    await supabase
      .from("payment_requests")
      .update({ paid: false, status: "cancelled", result })
      .eq("id", payment.id);
    return { status: "cancelled", paid: false, message: "Payment cancelled by user." };
  }

  if (MPESA_TERMINAL_ERROR_CODES.has(resultCode)) {
    await supabase
      .from("payment_requests")
      .update({ paid: false, status: "failed", result })
      .eq("id", payment.id);
    return {
      status: "failed",
      paid: false,
      message: result.ResultDesc || "M-Pesa payment failed.",
    };
  }

  return { status: "pending", paid: false, message: "Waiting for payment confirmation." };
}

async function handleInitiate(req: Request): Promise<Response> {
  if (req.method !== "POST") {
    return json({ status: "error", message: "Method not allowed" }, 405);
  }

  const supabase = adminClient();
  let userId: string | null = null;
  let phone: string | undefined;
  let plan: string | undefined;
  let amount: number | null = null;

  try {
    const authUser = await requireUser(req, supabase);
    userId = authUser.id;

    const body = await req.json().catch(() => ({}));
    phone = body.phone;
    plan = body.plan;
    // The amount is derived from the plan server-side and never read from the
    // request, so a client cannot pick its own price.
    amount = planAmount(plan);

    if (!phone || !amount) {
      return json({ status: "error", message: "Phone and a valid plan are required." }, 422);
    }

    const result = await stkPush({ phone, amount, reference: String(plan).toUpperCase() });

    if (result.ResponseCode !== "0") {
      // Log the failed attempt even though no checkout was created, so a
      // systemic issue (bad credentials, Safaricom outage) is visible on the
      // admin dashboard instead of vanishing silently.
      await supabase.from("payment_requests").insert({
        user_id: userId,
        phone: normalizePhone(phone),
        plan,
        amount,
        status: "failed",
        paid: false,
        provider: "mpesa",
        checkout_request_id: result.CheckoutRequestID || null,
        failure_reason:
          result.errorMessage || result.ResponseDescription || "STK Push failed.",
      });

      return json(
        {
          status: "error",
          message: result.errorMessage || "STK Push failed. Try again.",
          mpesa: result,
        },
        422,
      );
    }

    const checkoutId = result.CheckoutRequestID;
    const { error } = await supabase.from("payment_requests").insert({
      user_id: userId,
      phone: normalizePhone(phone),
      plan,
      amount,
      status: "pending",
      paid: false,
      provider: "mpesa",
      checkout_request_id: checkoutId,
      merchant_request_id: result.MerchantRequestID || null,
    });

    if (error) throw new Error(`Could not record the payment request: ${error.message}`);

    return json({
      status: "success",
      message: "STK Push sent. Enter your M-Pesa PIN.",
      checkout_request_id: checkoutId,
    });
  } catch (error) {
    if (error instanceof AuthError) throw error;

    if (userId) {
      try {
        await supabase.from("payment_requests").insert({
          user_id: userId,
          phone: phone ? normalizePhone(phone) : null,
          plan: plan ?? null,
          amount: amount ?? null,
          status: "failed",
          paid: false,
          provider: "mpesa",
          failure_reason: (error as Error).message || "Could not connect to M-Pesa.",
        });
      } catch (logError) {
        console.error("Failed to log failed M-Pesa initiation attempt", logError);
      }
    }

    const status = (error as { status?: number }).status || 500;
    return json(
      {
        status: "error",
        message: (error as Error).message || "Could not connect to M-Pesa. Please try again.",
      },
      status,
    );
  }
}

async function handleStatus(req: Request): Promise<Response> {
  const supabase = adminClient();

  try {
    const authUser = await requireUser(req, supabase);

    let checkoutId: string | null = null;
    if (req.method === "POST") {
      const body = await req.json().catch(() => ({}));
      checkoutId = body.checkout_request_id ?? null;
    } else {
      checkoutId = new URL(req.url).searchParams.get("checkout_request_id");
    }

    if (!checkoutId) {
      return json({ status: "error", message: "checkout_request_id is required." }, 422);
    }

    const { data: payment, error } = await supabase
      .from("payment_requests")
      .select(PAYMENT_COLUMNS)
      .eq("checkout_request_id", checkoutId)
      .maybeSingle();

    if (error) throw new Error(error.message);

    if (!payment) {
      return json({ status: "not_found", paid: false, message: "Payment request not found." }, 404);
    }

    // The service-role client bypasses RLS, so ownership is checked here by
    // hand — the same check payment_requests_select would have applied.
    if (payment.user_id !== authUser.id) {
      return json(
        { status: "error", paid: false, message: "You cannot access this payment request." },
        403,
      );
    }

    if (payment.paid || payment.status === "paid") {
      return json({ status: "success", paid: true, message: "Payment confirmed." });
    }

    return json(await resolvePaymentWithMpesa(supabase, payment as PaymentRow, checkoutId));
  } catch (error) {
    if (error instanceof AuthError) throw error;
    const status = (error as { status?: number }).status || 500;
    return json(
      { status: "pending", paid: false, message: (error as Error).message || "Awaiting confirmation." },
      status,
    );
  }
}

/**
 * Safaricom's callback body is unauthenticated — and the CheckoutRequestID it
 * carries is also handed to the paying client to poll with, so anyone could
 * POST a forged { ResultCode: 0 } here. The callback is therefore treated
 * purely as a "check now" trigger: the actual outcome always comes from
 * resolvePaymentWithMpesa's own query to Safaricom, authenticated with our
 * credentials, never from this request body.
 */
async function handleCallback(req: Request): Promise<Response> {
  try {
    const body = await req.json().catch(() => ({}));
    const checkoutId = body?.Body?.stkCallback?.CheckoutRequestID;

    if (checkoutId) {
      const supabase = adminClient();
      const { data: payment } = await supabase
        .from("payment_requests")
        .select(PAYMENT_COLUMNS)
        .eq("checkout_request_id", checkoutId)
        .maybeSingle();

      if (payment && !payment.paid && payment.status !== "paid") {
        await resolvePaymentWithMpesa(supabase, payment as PaymentRow, checkoutId);
      }
    }
  } catch (error) {
    console.error("M-Pesa callback error", error);
  }

  // Always acknowledge: a non-zero reply makes Safaricom retry, and the
  // outcome is re-derived from their API anyway.
  return json({ ResultCode: 0, ResultDesc: "Accepted" });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();

  const path = new URL(req.url).pathname;

  try {
    if (path.endsWith("/initiate")) return await handleInitiate(req);
    if (path.endsWith("/status")) return await handleStatus(req);
    if (path.endsWith("/callback")) return await handleCallback(req);
    return json({ status: "error", message: "Not found" }, 404);
  } catch (error) {
    if (error instanceof AuthError) {
      return json({ status: "error", message: error.message }, error.status);
    }
    console.error("Unhandled mpesa function error", error);
    return json({ status: "error", message: "Server error" }, 500);
  }
});
