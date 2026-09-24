import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { adminClient, requireUser, getAppUser, AuthError } from "../_shared/supabase.ts";
import { json, preflight } from "../_shared/http.ts";

// Self-service account deletion, required by Google Play and the App Store
// for any app that lets users create an account.
//
// Deleting the auth.users row is the whole operation: public.users and
// everything keyed to it (chat history, payment requests, affiliate record,
// payouts) cascade from there. Commissions an affiliate earned from this user
// survive with referred_id nulled — see 20260924000000_account_deletion.sql.
async function handleDelete(req: Request): Promise<Response> {
  if (req.method !== "POST") {
    return json({ status: "error", message: "Method not allowed" }, 405);
  }

  const authUser = await requireUser(req);
  const db = adminClient();

  const user = await getAppUser(db, authUser.id);

  // Losing the only admin would leave the console unreachable, so admins are
  // demoted by another admin first rather than deleting themselves.
  if (user?.role === "admin" || user?.role === "super_admin") {
    return json(
      {
        status: "error",
        message: "Admin accounts cannot be deleted from the app. Ask another admin to remove your admin role first.",
      },
      409,
    );
  }

  // A pending payout has already been deducted from available_balance and is
  // waiting on an admin to send the money. Cascading it away would lose the
  // request mid-flight.
  const { data: pendingPayout, error: payoutError } = await db
    .from("payout_requests")
    .select("id")
    .eq("affiliate_id", authUser.id)
    .eq("status", "pending")
    .limit(1)
    .maybeSingle();

  if (payoutError) throw new Error(`Could not check payouts: ${payoutError.message}`);
  if (pendingPayout) {
    return json(
      {
        status: "error",
        message: "You have a payout that is still being processed. Please try again once it has been paid.",
      },
      409,
    );
  }

  // symptom_check_quota is keyed by a text subject id (not an FK, because
  // guests use it too), so it does not cascade.
  const { error: quotaError } = await db
    .from("symptom_check_quota")
    .delete()
    .eq("subject_id", authUser.id);

  if (quotaError) throw new Error(`Could not clear symptom quota: ${quotaError.message}`);

  const { error: deleteError } = await db.auth.admin.deleteUser(authUser.id);
  if (deleteError) throw new Error(`Could not delete account: ${deleteError.message}`);

  return json({ status: "success" });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();

  const path = new URL(req.url).pathname;

  try {
    if (path.endsWith("/delete")) return await handleDelete(req);
    return json({ status: "error", message: "Not found" }, 404);
  } catch (error) {
    if (error instanceof AuthError) {
      return json({ status: "error", message: error.message }, error.status);
    }
    console.error("Unhandled account function error", error);
    return json(
      { status: "error", message: `Server error: ${(error as Error).message || String(error)}` },
      500,
    );
  }
});
