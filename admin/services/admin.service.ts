import { supabase } from "@/src/services/supabase";
import { formatDate, paymentAmount } from "@admin/utils/format";

export { formatDate, paymentAmount };

// ── Constants ────────────────────────────────────────────────────────────────

// Users and payment_requests grow unboundedly with platform usage (unlike
// doctors/pharmacies, which are curated by admins and stay small), so those
// two lists are paginated instead of fetched in full.
//
// Firestore paginated by passing the last DocumentSnapshot to startAfter().
// Postgres uses a numeric offset via .range(), so the cursor is now a row
// offset — simpler, and it supports jumping backwards.
const ADMIN_PAGE_SIZE = 50;

export type PagedResult<T> = {
  items: T[];
  cursor: number | null;
  hasMore: boolean;
};

// ── Types ─────────────────────────────────────────────────────────────────────

export type AdminMetric = {
  totalUsers: number;
  activeUsers: number;
  subscriptions: number;
  doctors: number;
  pharmacies: number;
  drugs: number;
  totalFacilities: number;
  totalRevenue: number;
  pendingPayouts: number;
  pendingPayoutsValue: number;
  planCounts: { daily: number; weekly: number; monthly: number };
  conversionRate: number;
};

export type AdminRecentUser = {
  id: string;
  name: string;
  email: string;
  plan: string;
  subscribed: boolean;
};

export type AdminTransaction = {
  id: string;
  name: string;
  type: string;
  amount: number;
  status: string;
  time: string;
};

export type AdminDashboardData = {
  metrics: AdminMetric;
  recentUsers: AdminRecentUser[];
  recentTransactions: AdminTransaction[];
  weeklyRevenue?: number[];
  weeklySubscribers?: number[];
};

export type AdminUser = {
  id: string;
  name: string;
  email: string;
  phone: string;
  role: string;
  subscriptionPlan: string;
  isSubscribed: boolean;
  hasSubscribed: boolean;
  subscriptionExpiresAt: string | null;
  isExpired?: boolean;
  onboardingCompleted: boolean;
  createdAt: string;
};

export type AdminFacility = {
  id: string;
  type: "doctor" | "pharmacy";
  name: string;
  location: string;
  phone: string;
  email: string;
  specialization?: string;    // doctor only
  hospital?: string;          // doctor only
  rating?: number;            // doctor only
  available?: boolean;        // doctor only
  experienceYears?: number;   // doctor only
  address?: string;           // pharmacy only
  openingHours?: string;      // pharmacy only
  open24hrs?: boolean;        // pharmacy only
  open?: boolean;             // pharmacy only
};

export type AdminPayment = {
  id: string;
  phone: string;
  uid: string;
  plan: string;
  amount: number;
  status: string;
  paid: boolean;
  createdAt: string;
  paidAt: string | null;
};

// ── Helpers ───────────────────────────────────────────────────────────────────

const unwrap = <T>(data: T | null, error: { message: string } | null, what: string): T => {
  if (error) throw new Error(`${what}: ${error.message}`);
  return (data ?? []) as T;
};

const isActive = (row: { is_subscribed?: boolean; subscription_expires_at?: string | null }) => {
  if (!row.is_subscribed) return false;
  if (!row.subscription_expires_at) return true;
  return new Date(row.subscription_expires_at).getTime() > Date.now();
};

// head:true fetches the count without transferring any rows — the direct
// equivalent of Firestore's getCountFromServer().
const countRows = async (
  table: string,
  filter?: (q: any) => any,
): Promise<number> => {
  let query = supabase.from(table).select("*", { count: "exact", head: true });
  if (filter) query = filter(query);
  const { count, error } = await query;
  if (error) throw new Error(`Could not count ${table}: ${error.message}`);
  return count ?? 0;
};

// ── Dashboard data ───────────────────────────────────────────────────────────

export const fetchAdminDashboardData = async (): Promise<AdminDashboardData> => {
  const [totalUsers, subscriptions, doctors, pharmacies, drugs] = await Promise.all([
    countRows("users"),
    countRows("users", (q) => q.eq("has_subscribed", true)),
    countRows("doctors"),
    countRows("pharmacies"),
    countRows("drugs"),
  ]);

  const { data: activeRows, error: activeError } = await supabase
    .from("users")
    .select("subscription_plan, is_subscribed, subscription_expires_at")
    .eq("is_subscribed", true);

  const activeCandidates = unwrap(activeRows, activeError, "Could not load subscribers");

  let daily = 0;
  let weekly = 0;
  let monthly = 0;
  const activeUsers = activeCandidates.filter((row: any) => {
    if (!isActive(row)) return false;
    if (row.subscription_plan === "daily") daily++;
    else if (row.subscription_plan === "weekly") weekly++;
    else if (row.subscription_plan === "monthly") monthly++;
    return true;
  }).length;

  const now = new Date();
  const day = now.getDay();
  const diff = now.getDate() - day + (day === 0 ? -6 : 1);
  const startOfWeek = new Date(now.setDate(diff));
  startOfWeek.setHours(0, 0, 0, 0);

  const weeklyRevenue = [0, 0, 0, 0, 0, 0, 0];
  const weeklySubscribers = [0, 0, 0, 0, 0, 0, 0];

  // The Firestore version wrapped each of these in try/catch and degraded to
  // zero on failure, which made a broken dashboard look like a quiet week.
  // They now propagate.
  const { data: paidRows, error: paidError } = await supabase
    .from("payment_requests")
    .select("id, phone, user_id, plan, amount, status, paid_at, created_at, updated_at")
    .eq("paid", true);

  let totalRevenue = 0;
  const paidTransactions: AdminTransaction[] = unwrap(
    paidRows,
    paidError,
    "Could not load payments",
  ).map((row: any) => {
    const amount = paymentAmount(row);
    totalRevenue += amount;

    const date = new Date(row.paid_at ?? row.created_at);
    if (!Number.isNaN(date.getTime()) && date >= startOfWeek) {
      const dayIndex = date.getDay() === 0 ? 6 : date.getDay() - 1;
      if (dayIndex >= 0 && dayIndex < 7) {
        weeklyRevenue[dayIndex] += amount;
        weeklySubscribers[dayIndex] += 1;
      }
    }

    return {
      id: row.id,
      name: row.phone ?? row.user_id ?? "Payment",
      type: row.plan ? `${row.plan} subscription` : "Subscription",
      amount,
      status: row.status ?? "paid",
      time: formatDate(row.paid_at ?? row.updated_at ?? row.created_at),
    };
  });

  const { data: pendingRows, error: pendingError } = await supabase
    .from("payment_requests")
    .select("amount, plan")
    .eq("status", "pending");

  const pending = unwrap(pendingRows, pendingError, "Could not load pending payments");
  const pendingPayouts = pending.length;
  const pendingPayoutsValue = pending.reduce(
    (sum: number, row: any) => sum + paymentAmount(row),
    0,
  );

  const { data: recentRows, error: recentError } = await supabase
    .from("users")
    .select("id, name, email, subscription_plan, is_subscribed, subscription_expires_at")
    .order("created_at", { ascending: false })
    .limit(5);

  const recentUsers: AdminRecentUser[] = unwrap(
    recentRows,
    recentError,
    "Could not load recent users",
  ).map((row: any) => ({
    id: row.id,
    name: row.name ?? "AfyaSmart User",
    email: row.email ?? "",
    plan: row.subscription_plan ?? "free",
    subscribed: isActive(row),
  }));

  const recentTransactions = paidTransactions
    .sort((a, b) => b.time.localeCompare(a.time))
    .slice(0, 5);

  const conversionRate =
    totalUsers > 0 ? Number(((activeUsers / totalUsers) * 100).toFixed(1)) : 0;

  return {
    metrics: {
      totalUsers,
      activeUsers,
      subscriptions,
      doctors,
      pharmacies,
      drugs,
      totalFacilities: doctors + pharmacies,
      totalRevenue,
      pendingPayouts,
      pendingPayoutsValue,
      planCounts: { daily, weekly, monthly },
      conversionRate,
    },
    recentUsers,
    recentTransactions,
    weeklyRevenue,
    weeklySubscribers,
  };
};

// ── Users Management ──────────────────────────────────────────────────────────

export const fetchUsersPage = async (
  cursor?: number | null,
): Promise<PagedResult<AdminUser>> => {
  const from = cursor ?? 0;
  // One extra row tells us whether another page exists, as before.
  const { data, error } = await supabase
    .from("users")
    .select("*")
    .order("created_at", { ascending: false })
    .range(from, from + ADMIN_PAGE_SIZE);

  const rows = unwrap(data, error, "Could not load users");
  const page = rows.slice(0, ADMIN_PAGE_SIZE);

  const items = page.map((row: any) => {
    const expiresDate = row.subscription_expires_at
      ? new Date(row.subscription_expires_at)
      : null;

    return {
      id: row.id,
      name: row.name ?? "AfyaSmart User",
      email: row.email ?? "",
      phone: row.phone ?? "",
      role: row.role ?? "user",
      subscriptionPlan: row.subscription_plan ?? "free",
      isSubscribed: isActive(row),
      hasSubscribed: Boolean(row.has_subscribed),
      subscriptionExpiresAt: row.subscription_expires_at
        ? formatDate(row.subscription_expires_at)
        : null,
      isExpired: Boolean(expiresDate && expiresDate < new Date()),
      onboardingCompleted: Boolean(row.onboarding_completed),
      createdAt: formatDate(row.created_at),
    };
  });

  return {
    items,
    cursor: page.length > 0 ? from + page.length : null,
    hasMore: rows.length > ADMIN_PAGE_SIZE,
  };
};

// Goes through the admin_update_user RPC rather than a direct table write.
// `authenticated` holds an UPDATE grant on only three columns of users, so a
// direct write of role or subscription fields would be rejected outright —
// and the RPC is also where "only a super_admin may change a role" lives.
export const updateAdminUser = async (
  userId: string,
  updates: Partial<{
    name: string;
    role: string;
    is_subscribed: boolean;
    subscription_plan: string;
    subscription_expires_at: string | null;
  }>,
) => {
  const { error } = await supabase.rpc("admin_update_user", {
    p_user_id: userId,
    p_name: updates.name ?? null,
    p_role: updates.role ?? null,
    p_is_subscribed: updates.is_subscribed ?? null,
    p_subscription_plan: updates.subscription_plan ?? null,
    p_subscription_expires_at: updates.subscription_expires_at ?? null,
  });

  if (error) throw new Error(error.message);
};

// ── Facilities Management ─────────────────────────────────────────────────────

export const fetchAllFacilities = async (): Promise<AdminFacility[]> => {
  const [doctorsRes, pharmaciesRes] = await Promise.all([
    supabase.from("doctors").select("*"),
    supabase.from("pharmacies").select("*"),
  ]);

  const doctors: AdminFacility[] = unwrap(
    doctorsRes.data,
    doctorsRes.error,
    "Could not load doctors",
  ).map((row: any) => ({
    id: String(row.id),
    type: "doctor" as const,
    name: row.name ?? "Unknown Doctor",
    location: row.location ?? "",
    phone: row.phone ?? "",
    email: row.email ?? "",
    specialization: row.specialization ?? "",
    hospital: row.hospital ?? "",
    rating: Number(row.rating ?? 0),
    available: Boolean(row.available),
    experienceYears: Number(row.experience_years ?? 0),
  }));

  const pharmacies: AdminFacility[] = unwrap(
    pharmaciesRes.data,
    pharmaciesRes.error,
    "Could not load pharmacies",
  ).map((row: any) => ({
    id: String(row.id),
    type: "pharmacy" as const,
    name: row.name ?? "Unknown Pharmacy",
    location: row.location ?? "",
    phone: row.phone ?? "",
    email: row.email ?? "",
    address: row.address ?? "",
    openingHours: row.opening_hours ?? "",
    open24hrs: Boolean(row.open_24hrs),
    open: Boolean(row.open),
  }));

  return [...doctors, ...pharmacies];
};

const facilityTable = (type: "doctor" | "pharmacy") =>
  type === "doctor" ? "doctors" : "pharmacies";

export const addFacility = async (
  type: "doctor" | "pharmacy",
  data: Record<string, any>,
) => {
  const { error } = await supabase.from(facilityTable(type)).insert(data);
  if (error) throw new Error(error.message);
};

export const updateFacility = async (
  type: "doctor" | "pharmacy",
  id: string,
  data: Record<string, any>,
) => {
  const { error } = await supabase
    .from(facilityTable(type))
    .update(data)
    .eq("id", Number(id));
  if (error) throw new Error(error.message);
};

export const deleteFacility = async (type: "doctor" | "pharmacy", id: string) => {
  const { error } = await supabase
    .from(facilityTable(type))
    .delete()
    .eq("id", Number(id));
  if (error) throw new Error(error.message);
};

// ── Payments / Transactions ───────────────────────────────────────────────────

export const fetchPaymentsPage = async (
  cursor?: number | null,
): Promise<PagedResult<AdminPayment>> => {
  const from = cursor ?? 0;
  const { data, error } = await supabase
    .from("payment_requests")
    .select("*")
    .order("created_at", { ascending: false })
    .range(from, from + ADMIN_PAGE_SIZE);

  const rows = unwrap(data, error, "Could not load payments");
  const page = rows.slice(0, ADMIN_PAGE_SIZE);

  const items = page.map((row: any) => ({
    id: row.id,
    phone: row.phone ?? row.user_id ?? "Unknown",
    uid: row.user_id ?? "",
    plan: row.plan ?? "unknown",
    amount: paymentAmount(row),
    status: row.status ?? "unknown",
    paid: Boolean(row.paid),
    createdAt: formatDate(row.created_at),
    paidAt: row.paid_at ? formatDate(row.paid_at) : null,
  }));

  return {
    items,
    cursor: page.length > 0 ? from + page.length : null,
    hasMore: rows.length > ADMIN_PAGE_SIZE,
  };
};

// Reuses the exact same activate_subscription() path as the automated M-Pesa
// callback and poll, so the referring affiliate's commission is credited the
// same way a real payment would be. A direct write of paid:true here would
// silently skip that — and the check constraint on payment_requests would
// reject it anyway.
export const reconcilePayment = async (paymentId: string) => {
  const { error } = await supabase.rpc("admin_reconcile_payment", {
    p_payment_id: paymentId,
  });
  if (error) throw new Error(error.message);
};

export const rejectPayment = async (paymentId: string) => {
  const { error } = await supabase.rpc("admin_reject_payment", {
    p_payment_id: paymentId,
  });
  if (error) throw new Error(error.message);
};

// ── Affiliate payouts ──────────────────────────────────────────────────────
// Money movement itself happens outside the app (Safaricom portal or manual
// disbursement) — this just tracks and approves/rejects the request.

export type AdminAffiliatePayout = {
  id: string;
  affiliateUid: string;
  phone: string;
  amount: number;
  status: string;
  createdAt: string;
};

export const fetchAffiliatePayoutRequests = async (): Promise<AdminAffiliatePayout[]> => {
  const { data, error } = await supabase
    .from("payout_requests")
    .select("*")
    .order("created_at", { ascending: false });

  return unwrap(data, error, "Could not load payouts").map((row: any) => ({
    id: row.id,
    affiliateUid: row.affiliate_id ?? "",
    phone: row.phone ?? "",
    amount: Number(row.amount ?? 0),
    status: row.status ?? "pending",
    createdAt: formatDate(row.created_at),
  }));
};

// Approval and rejection are one RPC. The refund on rejection used to be a
// second, separate write that could be replayed — admin_resolve_payout
// refuses a payout that is not still pending, so a double-click can no longer
// refund twice.
export const approveAffiliatePayout = async (payoutId: string) => {
  const { error } = await supabase.rpc("admin_resolve_payout", {
    p_payout_id: payoutId,
    p_approve: true,
  });
  if (error) throw new Error(error.message);
};

export const rejectAffiliatePayout = async (payoutId: string) => {
  const { error } = await supabase.rpc("admin_resolve_payout", {
    p_payout_id: payoutId,
    p_approve: false,
  });
  if (error) throw new Error(error.message);
};
