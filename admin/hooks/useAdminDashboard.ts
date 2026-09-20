import { useEffect, useState, useRef, useCallback } from "react";
import { supabase } from "@/src/services/supabase";
import {
  fetchAdminDashboardData,
  AdminDashboardData,
} from "@admin/services/admin.service";
import { useAuthStore } from "@/src/store/authStore";

const emptyDashboard: AdminDashboardData = {
  metrics: {
    totalUsers: 0,
    activeUsers: 0,
    subscriptions: 0,
    doctors: 0,
    pharmacies: 0,
    drugs: 0,
    totalFacilities: 0,
    totalRevenue: 0,
    pendingPayouts: 0,
    pendingPayoutsValue: 0,
    planCounts: { daily: 0, weekly: 0, monthly: 0 },
    conversionRate: 0,
  },
  recentUsers: [],
  recentTransactions: [],
};

/**
 * Live admin dashboard.
 *
 * This used to carry its own full copy of the aggregation logic —
 * counts, weekly revenue buckets, recent users — duplicating
 * fetchAdminDashboardData() line for line, so the two drifted apart as either
 * was edited. It now calls that one function and simply re-runs it when the
 * underlying tables change.
 *
 * The realtime subscriptions replace two onSnapshot listeners. Firestore
 * pushed whole result sets, which is why the old version recomputed
 * everything from the snapshot; Postgres pushes row-level change events, so
 * the natural shape is "something changed, re-read the aggregate".
 */
export const useAdminDashboard = () => {
  const token = useAuthStore((s) => s.token);
  const [dashboard, setDashboard] = useState<AdminDashboardData>(emptyDashboard);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const activeRef = useRef(true);
  // Coalesces bursts of change events into one refetch: a single M-Pesa
  // settlement touches users and payment_requests within milliseconds.
  const refetchTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const load = useCallback(async () => {
    try {
      const data = await fetchAdminDashboardData();
      if (!activeRef.current) return;
      setDashboard(data);
      setError(null);
    } catch (err) {
      if (!activeRef.current) return;
      console.error("Error loading admin dashboard:", err);
      setError((err as Error)?.message ?? "Error loading dashboard.");
    } finally {
      if (activeRef.current) setLoading(false);
    }
  }, []);

  useEffect(() => {
    activeRef.current = true;

    if (!token) {
      setLoading(false);
      return () => {
        activeRef.current = false;
      };
    }

    setLoading(true);
    void load();

    const scheduleRefetch = () => {
      if (refetchTimer.current) clearTimeout(refetchTimer.current);
      refetchTimer.current = setTimeout(() => {
        if (activeRef.current) void load();
      }, 500);
    };

    // Both tables are in the supabase_realtime publication (see the realtime
    // migration). RLS applies to these streams, so a non-admin subscribing
    // here simply receives nothing.
    const channel = supabase
      .channel("admin-dashboard")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "payment_requests" },
        scheduleRefetch,
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "users" },
        scheduleRefetch,
      )
      .subscribe();

    return () => {
      activeRef.current = false;
      if (refetchTimer.current) clearTimeout(refetchTimer.current);
      void supabase.removeChannel(channel);
    };
  }, [token, load]);

  return { dashboard, loading, error };
};
