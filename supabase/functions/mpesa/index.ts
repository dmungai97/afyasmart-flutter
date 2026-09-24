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
  failure_reason?: string | null;
};

const PAYMENT_COLUMNS = "id, user_id, plan, amount, status, paid, failure_reason";

async function resolvePaymentWithMpesa(
  supabase: SupabaseClient,
  payment: PaymentRow,
  checkoutId: string,
) {
  const nowIso = new Date().toISOString();

  if (!payment.plan) {
    return { status: "error", paid: false, message: "Payment has no plan to activate." };
  }

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

  await supabase
    .from("payment_requests")
    .update({ paid: true, status: "paid", paid_at: nowIso })
    .eq("id", payment.id);

  return { status: "success", paid: true, message: "Payment confirmed." };
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
    amount = planAmount(plan);

    if (!phone || !amount) {
      return json({ status: "error", message: "Phone and a valid plan are required." }, 422);
    }

    const hasMpesaKeys = Boolean(Deno.env.get("MPESA_CONSUMER_KEY"));

    // Check if user has a recent pending payment request within the last 15 minutes that was already paid
    if (hasMpesaKeys) {
      const fifteenMinsAgo = new Date(Date.now() - 15 * 60 * 1000).toISOString();
      const { data: recentPending } = await supabase
        .from("payment_requests")
        .select(PAYMENT_COLUMNS)
        .eq("user_id", userId)
        .eq("status", "pending")
        .gte("created_at", fifteenMinsAgo)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (recentPending && (recentPending as PaymentRow).id) {
        const checkoutIdToCheck = (recentPending as { checkout_request_id?: string }).checkout_request_id;
        if (checkoutIdToCheck) {
          try {
            const queryResult = await stkQuery(checkoutIdToCheck);
            if (queryResult?.ResultCode === "0") {
              await resolvePaymentWithMpesa(
                supabase,
                recentPending as PaymentRow,
                checkoutIdToCheck,
              );
              return json({
                status: "success",
                already_paid: true,
                message: "Payment confirmed from recent transaction! Subscription activated.",
                checkout_request_id: checkoutIdToCheck,
              });
            }
          } catch (queryErr) {
            console.error("Auto-check for recent pending payment failed:", queryErr);
          }
        }
      }
    }

    let checkoutId = "ws_CO_MOCK_" + Date.now();
    let merchantRequestId: string | null = null;

    if (hasMpesaKeys) {
      let result;
      try {
        result = await stkPush({ phone, amount, reference: String(plan).toUpperCase() });
      } catch (stkErr) {
        console.error("stkPush network/oauth error:", stkErr);
        return json(
          {
            status: "error",
            message: (stkErr as Error).message || "Could not connect to M-Pesa. Please try again.",
          },
          500,
        );
      }

      // Explicitly validate Safaricom's response code before recording payment or returning
      if (result.ResponseCode === "0" && result.CheckoutRequestID) {
        checkoutId = result.CheckoutRequestID;
        merchantRequestId = result.MerchantRequestID ?? null;
      } else {
        const errorMsg =
          result.errorMessage ||
          result.ResponseDescription ||
          "M-Pesa push request rejected by Safaricom.";
        console.error("Safaricom STK Push rejected:", result);
        return json({ status: "error", message: errorMsg }, 400);
      }
    }

    const { error: dbError } = await supabase.from("payment_requests").insert({
      user_id: userId,
      phone: normalizePhone(phone),
      plan,
      amount,
      status: "pending",
      paid: false,
      provider: "mpesa",
      checkout_request_id: checkoutId,
      merchant_request_id: merchantRequestId,
    });

    if (dbError) {
      console.error("Could not record payment request:", dbError);
      throw new Error(`Could not record payment request: ${dbError.message}`);
    }

    return json({
      status: "success",
      message: "STK Push sent. Enter your M-Pesa PIN.",
      checkout_request_id: checkoutId,
    });
  } catch (error) {
    if (error instanceof AuthError) throw error;

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

    if (payment.user_id !== authUser.id) {
      return json(
        { status: "error", paid: false, message: "You cannot access this payment request." },
        403,
      );
    }

    if (payment.paid || payment.status === "paid") {
      return json({ status: "success", paid: true, message: "Payment confirmed." });
    }

    // Reconcile pending, failed, or cancelled payment with Safaricom if keys are configured
    const hasMpesaKeys = Boolean(Deno.env.get("MPESA_CONSUMER_KEY"));
    if (hasMpesaKeys) {
      try {
        const queryResult = await stkQuery(checkoutId);
        console.log("stkQuery result for checkout", checkoutId, queryResult);

        const resultCode =
          queryResult?.ResultCode !== undefined && queryResult?.ResultCode !== null
            ? String(queryResult.ResultCode)
            : (queryResult?.errorCode ? String(queryResult.errorCode) : "");

        const resultDesc =
          queryResult?.ResultDesc || queryResult?.errorMessage || queryResult?.ResponseDescription || "";

        if (resultCode === "0") {
          return json(await resolvePaymentWithMpesa(supabase, payment as PaymentRow, checkoutId));
        } else if (resultCode && MPESA_TERMINAL_ERROR_CODES.has(resultCode)) {
          const isCancelled = resultCode === "1032";
          const newStatus = isCancelled ? "cancelled" : "failed";
          const reason = resultDesc || (isCancelled ? "Payment cancelled by user." : "Payment failed on M-Pesa.");

          await supabase
            .from("payment_requests")
            .update({ status: newStatus, failure_reason: reason, result: queryResult })
            .eq("id", payment.id);

          return json({ status: newStatus, paid: false, message: reason });
        }
      } catch (stkQueryErr) {
        console.error("stkQuery error during status poll:", stkQueryErr);
      }
    }

    if (payment.status === "failed" || payment.status === "cancelled") {
      return json({
        status: "failed",
        paid: false,
        message: payment.failure_reason || "Payment was cancelled or failed.",
      });
    }

    return json({ status: "pending", paid: false, message: "Awaiting confirmation." });

    return json({ status: "pending", paid: false, message: "Awaiting confirmation." });
  } catch (error) {
    if (error instanceof AuthError) throw error;
    const status = (error as { status?: number }).status || 500;
    return json(
      { status: "pending", paid: false, message: (error as Error).message || "Awaiting confirmation." },
      status,
    );
  }
}

async function handleCallback(req: Request): Promise<Response> {
  try {
    const body = await req.json().catch(() => ({}));
    const stkCallback = body?.Body?.stkCallback;
    const checkoutId = stkCallback?.CheckoutRequestID;
    const resultCode = stkCallback?.ResultCode;
    const resultDesc = stkCallback?.ResultDesc;

    if (checkoutId) {
      const supabase = adminClient();
      const { data: payment } = await supabase
        .from("payment_requests")
        .select(PAYMENT_COLUMNS)
        .eq("checkout_request_id", checkoutId)
        .maybeSingle();

      if (payment && !payment.paid && payment.status !== "paid") {
        if (resultCode === 0) {
          await resolvePaymentWithMpesa(supabase, payment as PaymentRow, checkoutId);
        } else {
          await supabase
            .from("payment_requests")
            .update({
              status: "failed",
              failure_reason: resultDesc || "Payment failed or cancelled on M-Pesa.",
              result: stkCallback,
            })
            .eq("id", payment.id);
        }
      }
    }
  } catch (error) {
    console.error("M-Pesa callback error", error);
  }

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
