import { Ionicons } from "@expo/vector-icons";
import { useRouter } from "expo-router";
import { useEffect, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
  useWindowDimensions,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import Sidebar from "../components/Sidebar";
import {
  AdminPayment,
  fetchPaymentsPage,
  reconcilePayment,
  rejectPayment,
} from "@admin/services/admin.service";
import { useAuthStore } from "@/src/store/authStore";

const BLUE = "#16302B";
const GREEN = "#3F7A5C";
const RED = "#9C3B2E";
const ORANGE = "#C9A227";
const BORDER = "#C7CFC2";
const NAVY = "#16302B";
const MUTED = "#4B5C50";

const STRINGS = {
  title: "Transactions",
  subtitle: "All M-Pesa payment requests on the platform",
  search: "Search by phone or plan...",
  all: "All",
  paid: "Paid",
  pending: "Pending",
  failed: "Other",
  noTransactions: "No transactions found",
  phone: "Phone / User",
  plan: "Plan",
  amount: "Amount",
  status: "Status",
  date: "Date",
  paidAt: "Paid At",
  totalRevenue: "Total Revenue",
  totalPaid: "Paid Transactions",
  totalPending: "Pending",
  admin: "Admin",
};

const formatMoney = (v: number) =>
  `Ksh ${new Intl.NumberFormat("en-KE").format(v)}`;

export default function AdminTransactionsScreen() {
  const router = useRouter();
  const { width } = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const isMobile = width < 768;
  const [menuOpen, setMenuOpen] = useState(false);

  const user = useAuthStore((s) => s.user);
  const clearAuth = useAuthStore((s) => s.clearAuth);

  const [payments, setPayments] = useState<AdminPayment[]>([]);
  const [filtered, setFiltered] = useState<AdminPayment[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [cursor, setCursor] = useState<number | null>(null);
  const [hasMore, setHasMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [activeFilter, setActiveFilter] = useState<"all" | "paid" | "pending" | "other">("all");
  const [reconciling, setReconciling] = useState<string | null>(null);

  const handleReconcile = (p: AdminPayment) => {
    Alert.alert(
      "Reconcile Transaction",
      `Are you sure you want to mark this request from ${p.phone} as PAID?\n\nThis will manually activate their ${p.plan} plan in the database.`,
      [
        { text: "Cancel", style: "cancel" },
        {
          text: "Confirm",
          onPress: async () => {
            setReconciling(p.id);
            try {
              await reconcilePayment(p.id);
              await load();
            } catch (err) {
              console.error("Reconcile payment error:", err);
              Alert.alert("Error", "Failed to reconcile payment request.");
            } finally {
              setReconciling(null);
            }
          },
        },
      ],
    );
  };

  const [rejecting, setRejecting] = useState<string | null>(null);

  const handleReject = (p: AdminPayment) => {
    Alert.alert(
      "Cancel Transaction",
      `Are you sure you want to cancel this request from ${p.phone}?\n\nThis will mark it as failed and remove it from the pending list.`,
      [
        { text: "No", style: "cancel" },
        {
          text: "Cancel Request",
          style: "destructive",
          onPress: async () => {
            setRejecting(p.id);
            try {
              await rejectPayment(p.id);
              await load();
            } catch (err) {
              console.error("Cancel payment request error:", err);
              Alert.alert("Error", "Failed to cancel request.");
            } finally {
              setRejecting(null);
            }
          },
        },
      ],
    );
  };

  const handleSignOut = async () => {
    await clearAuth();
    router.replace("/(auth)/login" as any);
  };

  const load = async () => {
    setLoading(true);
    setError(null);
    try {
      const page = await fetchPaymentsPage();
      setPayments(page.items);
      setCursor(page.cursor);
      setHasMore(page.hasMore);
    } catch (err: any) {
      setPayments([]);
      setCursor(null);
      setHasMore(false);
      setError(err?.message ?? "Failed to load transactions. Pull to refresh to try again.");
    } finally {
      setLoading(false);
    }
  };

  // KPI totals below are computed from whatever's loaded so far, not the
  // whole platform — accurate once hasMore is false, an undercount otherwise
  // ("Load more" to see the running total grow). AdminDashboardScreen shows
  // the true platform-wide total revenue if you need that instead.
  const loadMore = async () => {
    if (!hasMore || loadingMore) return;
    setLoadingMore(true);
    try {
      const page = await fetchPaymentsPage(cursor);
      setPayments((prev) => [...prev, ...page.items]);
      setCursor(page.cursor);
      setHasMore(page.hasMore);
    } catch (err: any) {
      setError(err?.message ?? "Failed to load more transactions.");
    } finally {
      setLoadingMore(false);
    }
  };

  useEffect(() => {
    load();
  }, []);

  useEffect(() => {
    let result = payments;
    if (activeFilter === "paid") result = result.filter((p) => p.paid);
    if (activeFilter === "pending") result = result.filter((p) => p.status === "pending");
    if (activeFilter === "other") result = result.filter((p) => !p.paid && p.status !== "pending");
    if (search.trim()) {
      const q = search.toLowerCase();
      result = result.filter(
        (p) =>
          p.phone.toLowerCase().includes(q) ||
          p.plan.toLowerCase().includes(q),
      );
    }
    setFiltered(result);
  }, [search, activeFilter, payments]);

  const totalRevenue = payments.filter((p) => p.paid).reduce((sum, p) => sum + p.amount, 0);
  const totalPaid = payments.filter((p) => p.paid).length;
  const totalPending = payments.filter((p) => p.status === "pending").length;

  const statusColor = (p: AdminPayment) => {
    if (p.paid) return GREEN;
    if (p.status === "pending") return ORANGE;
    return RED;
  };

  const statusBg = (p: AdminPayment) => {
    if (p.paid) return "#E4EAE0";
    if (p.status === "pending") return "#F4EBD3";
    return "#F1E3DE";
  };

  const statusLabel = (p: AdminPayment) => {
    if (p.paid) return "Paid";
    if (p.status === "pending") return "Pending";
    return p.status;
  };

  const filters = [
    { key: "all" as const, label: STRINGS.all },
    { key: "paid" as const, label: STRINGS.paid },
    { key: "pending" as const, label: STRINGS.pending },
    { key: "other" as const, label: STRINGS.failed },
  ];

  return (
    <View style={styles.root}>
      <Sidebar
        userName={user?.name ?? STRINGS.admin}
        onSignOut={handleSignOut}
        isMobile={isMobile}
        visible={isMobile ? menuOpen : true}
        onClose={() => setMenuOpen(false)}
      />

      <ScrollView
        style={styles.main}
        contentContainerStyle={[
          styles.content,
          isMobile && {
            paddingTop: Math.max(insets.top, 12) + 8,
            paddingHorizontal: 12,
            paddingBottom: Math.max(insets.bottom, 16) + 20,
            gap: 14,
          },
        ]}
        showsVerticalScrollIndicator={false}
      >
        {/* Header */}
        <View style={[styles.topbar, isMobile && styles.topbarMobile]}>
          <View style={styles.titleRow}>
            {isMobile && (
              <TouchableOpacity style={styles.menuBtn} onPress={() => setMenuOpen(true)} activeOpacity={0.7}>
                <Ionicons name="menu-outline" size={24} color="#16302B" />
              </TouchableOpacity>
            )}
            <View style={styles.backBtnWrap}>
              <TouchableOpacity
                style={styles.backBtn}
                onPress={() => {
                  if (router.canGoBack()) {
                    router.back();
                  } else {
                    router.replace("/admin");
                  }
                }}
                activeOpacity={0.7}
              >
                <Ionicons name="arrow-back" size={18} color="#16302B" />
              </TouchableOpacity>
            </View>
            <View style={styles.titleTextWrap}>
              <Text style={[styles.title, isMobile && styles.titleMobile]} numberOfLines={1}>{STRINGS.title}</Text>
              {!isMobile && <Text style={styles.subtitle}>{STRINGS.subtitle}</Text>}
            </View>
          </View>
          <TouchableOpacity style={styles.refreshBtn} onPress={load} activeOpacity={0.8}>
            <Ionicons name="refresh-outline" size={18} color="#16302B" />
          </TouchableOpacity>
        </View>

        {error ? (
          <View style={styles.errorBanner}>
            <Ionicons name="alert-circle-outline" size={18} color={RED} />
            <Text style={styles.errorText}>{error}</Text>
          </View>
        ) : null}

        {/* KPI Summary */}
        {hasMore ? (
          <Text style={styles.kpiCaveat}>Totals reflect the {payments.length} transactions loaded so far — load more to see the full total.</Text>
        ) : null}
        <View style={[styles.kpiRow, isMobile && styles.kpiRowMobile]}>
          <View style={[styles.kpiCard, isMobile && styles.kpiCardMobile]}>
            <View style={styles.kpiContent}>
              <Text style={styles.kpiLabel}>{STRINGS.totalRevenue}</Text>
              <Text style={styles.kpiValue}>{formatMoney(totalRevenue)}</Text>
            </View>
            <View style={styles.kpiIcon}>
              <Ionicons name="wallet" size={20} color="#4B5C50" />
            </View>
          </View>
          <View style={[styles.kpiCard, isMobile && styles.kpiCardMobile]}>
            <View style={styles.kpiContent}>
              <Text style={styles.kpiLabel}>{STRINGS.totalPaid}</Text>
              <Text style={styles.kpiValue}>{totalPaid}</Text>
            </View>
            <View style={styles.kpiIcon}>
              <Ionicons name="checkmark-circle" size={20} color="#4B5C50" />
            </View>
          </View>
          <View style={[styles.kpiCard, isMobile && styles.kpiCardMobile]}>
            <View style={styles.kpiContent}>
              <Text style={styles.kpiLabel}>{STRINGS.totalPending}</Text>
              <Text style={styles.kpiValue}>{totalPending}</Text>
            </View>
            <View style={styles.kpiIcon}>
              <Ionicons name="time" size={20} color="#4B5C50" />
            </View>
          </View>
        </View>

        {/* Search */}
        <View style={styles.searchRow}>
          <Ionicons name="search-outline" size={16} color={MUTED} style={{ marginLeft: 12 }} />
          <TextInput
            style={styles.searchInput}
            placeholder={STRINGS.search}
            placeholderTextColor={MUTED}
            value={search}
            onChangeText={setSearch}
          />
        </View>

        {/* Filters */}
        <View style={styles.filterRow}>
          {filters.map((f) => (
            <TouchableOpacity
              key={f.key}
              style={[styles.filterChip, activeFilter === f.key && styles.filterChipActive]}
              onPress={() => setActiveFilter(f.key)}
              activeOpacity={0.7}
            >
              <Text style={[styles.filterChipText, activeFilter === f.key && styles.filterChipTextActive]}>
                {f.label}
              </Text>
            </TouchableOpacity>
          ))}
          <Text style={styles.countText}>{filtered.length} shown</Text>
        </View>

        {/* Table */}
        {loading ? (
          <ActivityIndicator size="large" color="#16302B" style={{ marginTop: 40 }} />
        ) : filtered.length === 0 ? (
          <View style={styles.empty}>
            <Ionicons name="receipt-outline" size={48} color={MUTED} />
            <Text style={styles.emptyText}>{STRINGS.noTransactions}</Text>
          </View>
        ) : isMobile ? (
          <View style={styles.mobileList}>
            {filtered.map((p) => (
              <View key={p.id} style={styles.mobileCard}>
                <View style={styles.mobileCardHeader}>
                  <Text style={styles.mobilePhone} numberOfLines={1}>{p.phone}</Text>
                  <View style={[styles.statusBadge, { backgroundColor: statusBg(p), borderColor: statusColor(p) + "30" }]}>
                    <Text style={[styles.statusText, { color: statusColor(p) }]}>{statusLabel(p)}</Text>
                  </View>
                </View>
                <View style={styles.mobileCardBody}>
                  <View style={{ flex: 1 }}>
                    <Text style={styles.mobilePlanText}>{p.plan}</Text>
                    <Text style={styles.mobileDateText}>{p.createdAt}</Text>
                  </View>
                  <Text style={styles.mobileAmountText}>{formatMoney(p.amount)}</Text>
                </View>
                {!p.paid && (
                  <View style={styles.mobileActionsRow}>
                    <TouchableOpacity
                      style={[styles.mobileReconcileBtn, { flex: 1 }]}
                      onPress={() => handleReconcile(p)}
                      activeOpacity={0.7}
                      disabled={reconciling === p.id || rejecting === p.id}
                    >
                      {reconciling === p.id ? (
                        <ActivityIndicator size="small" color="#EEF1EA" />
                      ) : (
                        <>
                          <Ionicons name="checkmark-circle-outline" size={14} color="#EEF1EA" />
                          <Text style={styles.reconcileBtnText}>Approve</Text>
                        </>
                      )}
                    </TouchableOpacity>
                    {p.status === "pending" && (
                      <TouchableOpacity
                        style={[styles.mobileRejectBtn, { flex: 1 }]}
                        onPress={() => handleReject(p)}
                        activeOpacity={0.7}
                        disabled={reconciling === p.id || rejecting === p.id}
                      >
                        {rejecting === p.id ? (
                          <ActivityIndicator size="small" color="#EEF1EA" />
                        ) : (
                          <>
                            <Ionicons name="close-circle-outline" size={14} color="#EEF1EA" />
                            <Text style={styles.reconcileBtnText}>Cancel</Text>
                          </>
                        )}
                      </TouchableOpacity>
                    )}
                  </View>
                )}
              </View>
            ))}
          </View>
        ) : (
          <View style={styles.table}>
            {/* Table header */}
            <View style={styles.tableHeader}>
              <Text style={[styles.thCell, { flex: 2 }]}>{STRINGS.phone}</Text>
              <Text style={styles.thCell}>{STRINGS.plan}</Text>
              <Text style={styles.thCell}>{STRINGS.amount}</Text>
              <Text style={styles.thCell}>{STRINGS.status}</Text>
              <Text style={[styles.thCell, { textAlign: "right", paddingRight: 8 }]}>Action</Text>
            </View>
            {filtered.map((p, i) => (
              <View key={p.id} style={[styles.tableRow, i % 2 === 1 && styles.tableRowAlt]}>
                <View style={{ flex: 2 }}>
                  <Text style={styles.cellPrimary}>{p.phone}</Text>
                  <Text style={styles.cellSub}>{p.createdAt}</Text>
                </View>
                <Text style={[styles.tdCell, { textTransform: "capitalize" }]}>{p.plan}</Text>
                <Text style={[styles.tdCell, { color: "#16302B", fontWeight: "600" }]}>{formatMoney(p.amount)}</Text>
                <View style={{ flex: 1, flexDirection: "row", alignItems: "center" }}>
                  <View style={[styles.statusBadge, { backgroundColor: statusBg(p), borderColor: statusColor(p) + "30" }]}>
                    <Text style={[styles.statusText, { color: statusColor(p) }]}>{statusLabel(p)}</Text>
                  </View>
                </View>
                <View style={{ flex: 1, alignItems: "flex-end", paddingRight: 8 }}>
                  {!p.paid ? (
                    <View style={{ flexDirection: "row", gap: 8 }}>
                      <TouchableOpacity
                        style={styles.reconcileTableBtn}
                        onPress={() => handleReconcile(p)}
                        activeOpacity={0.7}
                        disabled={reconciling === p.id || rejecting === p.id}
                      >
                        {reconciling === p.id ? (
                          <ActivityIndicator size="small" color={GREEN} />
                        ) : (
                          <Ionicons name="checkmark-circle-outline" size={18} color={GREEN} />
                        )}
                      </TouchableOpacity>
                      {p.status === "pending" && (
                        <TouchableOpacity
                          style={styles.rejectTableBtn}
                          onPress={() => handleReject(p)}
                          activeOpacity={0.7}
                          disabled={reconciling === p.id || rejecting === p.id}
                        >
                          {rejecting === p.id ? (
                            <ActivityIndicator size="small" color={RED} />
                          ) : (
                            <Ionicons name="close-circle-outline" size={18} color={RED} />
                          )}
                        </TouchableOpacity>
                      )}
                    </View>
                  ) : null}
                </View>
              </View>
            ))}
          </View>
        )}

        {!loading && hasMore ? (
          <TouchableOpacity style={styles.loadMoreBtn} onPress={loadMore} disabled={loadingMore} activeOpacity={0.7}>
            {loadingMore ? (
              <ActivityIndicator size="small" color="#16302B" />
            ) : (
              <Text style={styles.loadMoreText}>Load more transactions</Text>
            )}
          </TouchableOpacity>
        ) : null}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, flexDirection: "row", backgroundColor: "#EEF1EA" },
  main: { flex: 1 },
  content: { padding: 24, gap: 16 },
  topbar: { flexDirection: "row", justifyContent: "space-between", alignItems: "center" },
  topbarMobile: { alignItems: "flex-start", gap: 10 },
  titleRow: { flexDirection: "row", alignItems: "center", gap: 12, flex: 1, minWidth: 0 },
  titleTextWrap: { flex: 1, minWidth: 0 },
  backBtnWrap: {
    width: 36,
    height: 36,
    borderRadius: 10,
    backgroundColor: "#FBFCF9",
    alignItems: "center",
    justifyContent: "center",
    borderWidth: 1,
    borderColor: BORDER,
  },
  backBtn: {
    padding: 6,
  },
  menuBtn: { width: 44, height: 44, borderRadius: 12, backgroundColor: "#FBFCF9", borderWidth: 1, borderColor: BORDER, alignItems: "center", justifyContent: "center" },
  title: { color: "#16302B", fontSize: 24, fontWeight: "700" },
  titleMobile: { fontSize: 20 },
  subtitle: { color: MUTED, fontSize: 13, marginTop: 4, fontWeight: "500" },
  refreshBtn: { width: 44, height: 44, borderRadius: 12, backgroundColor: "#FBFCF9", borderWidth: 1, borderColor: BORDER, alignItems: "center", justifyContent: "center" },
  kpiRow: { flexDirection: "row", gap: 12, flexWrap: "wrap" },
  kpiRowMobile: { gap: 8 },
  kpiCard: { flex: 1, minWidth: 140, backgroundColor: "#FBFCF9", borderRadius: 12, padding: 18, borderWidth: 1, borderColor: BORDER, flexDirection: "row", alignItems: "center", justifyContent: "space-between" },
  kpiCardMobile: { flexBasis: "100%", minWidth: 0, padding: 12 },
  kpiContent: { flex: 1, paddingRight: 10 },
  kpiLabel: { color: MUTED, fontSize: 10, fontWeight: "600", textTransform: "uppercase", letterSpacing: 0.6 },
  kpiValue: { color: "#16302B", fontSize: 22, fontWeight: "700", marginTop: 6, letterSpacing: -0.5 },
  kpiIcon: { width: 40, height: 40, borderRadius: 20, alignItems: "center", justifyContent: "center", backgroundColor: "#EEF1EA" },
  errorBanner: {
    backgroundColor: "#F1E3DE",
    borderWidth: 1,
    borderColor: "#D9B3A8",
    borderRadius: 12,
    padding: 12,
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
  },
  errorText: { color: "#9C3B2E", fontSize: 12, fontWeight: "600", flex: 1 },
  kpiCaveat: { color: MUTED, fontSize: 11, fontWeight: "500", fontStyle: "italic" },
  loadMoreBtn: {
    height: 44,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: BORDER,
    backgroundColor: "#FBFCF9",
    alignItems: "center",
    justifyContent: "center",
  },
  loadMoreText: { color: "#16302B", fontSize: 13, fontWeight: "700" },
  searchRow: { flexDirection: "row", alignItems: "center", backgroundColor: "#FBFCF9", borderRadius: 10, borderWidth: 1, borderColor: BORDER, height: 44, gap: 8 },
  searchInput: { flex: 1, color: "#16302B", fontSize: 13, fontWeight: "500", paddingRight: 12 },
  filterRow: { flexDirection: "row", flexWrap: "wrap", gap: 8, alignItems: "center" },
  filterChip: { paddingHorizontal: 14, paddingVertical: 7, borderRadius: 20, backgroundColor: "#FBFCF9", borderWidth: 1, borderColor: BORDER },
  filterChipActive: { backgroundColor: "#16302B", borderColor: "#16302B" },
  filterChipText: { color: MUTED, fontSize: 12, fontWeight: "600" },
  filterChipTextActive: { color: "#EEF1EA" },
  countText: { color: MUTED, fontSize: 11, fontWeight: "600", marginLeft: "auto" },
  empty: { alignItems: "center", paddingTop: 60, gap: 12 },
  emptyText: { color: MUTED, fontSize: 15, fontWeight: "600" },
  table: { backgroundColor: "#FBFCF9", borderRadius: 12, borderWidth: 1, borderColor: BORDER, overflow: "hidden" },
  tableHeader: { flexDirection: "row", alignItems: "center", paddingHorizontal: 16, paddingVertical: 12, backgroundColor: "#EEF1EA", borderBottomWidth: 1, borderBottomColor: BORDER },
  thCell: { flex: 1, color: MUTED, fontSize: 10, fontWeight: "600", textTransform: "uppercase", letterSpacing: 0.5 },
  tableRow: { flexDirection: "row", alignItems: "center", paddingHorizontal: 16, paddingVertical: 14, borderBottomWidth: 1, borderBottomColor: "#EEF1EA" },
  tableRowAlt: { backgroundColor: "#EEF1EA" },
  cellPrimary: { color: "#16302B", fontSize: 13, fontWeight: "600" },
  cellSub: { color: "#6B7A70", fontSize: 10, fontWeight: "500", marginTop: 2 },
  tdCell: { flex: 1, color: MUTED, fontSize: 12, fontWeight: "600" },
  statusBadge: { paddingHorizontal: 10, paddingVertical: 4, borderRadius: 20, borderWidth: 1, borderColor: "#C7CFC2" },
  statusText: { fontSize: 10, fontWeight: "600" },
  mobileList: { gap: 10 },
  mobileCard: {
    backgroundColor: "#FBFCF9",
    borderRadius: 12,
    padding: 16,
    borderWidth: 1,
    borderColor: BORDER,
    gap: 8
  },
  mobileCardHeader: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  mobileCardBody: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "flex-end",
    borderTopWidth: 1,
    borderTopColor: "#EEF1EA",
    paddingTop: 8,
  },
  mobilePhone: {
    color: "#16302B",
    fontSize: 13,
    fontWeight: "700",
    flex: 1,
    marginRight: 8,
  },
  mobilePlanText: {
    color: "#4B5C50",
    fontSize: 12,
    fontWeight: "600",
    textTransform: "capitalize",
  },
  mobileDateText: {
    color: "#6B7A70",
    fontSize: 10,
    fontWeight: "500",
    marginTop: 2,
  },
  mobileAmountText: {
    color: "#16302B",
    fontSize: 14,
    fontWeight: "700",
  },
  mobileReconcileBtn: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    backgroundColor: "#3F7A5C",
    borderRadius: 8,
    paddingVertical: 8,
    gap: 6,
  },
  reconcileBtnText: {
    color: "#EEF1EA",
    fontSize: 11,
    fontWeight: "700",
  },
  reconcileTableBtn: {
    width: 32,
    height: 32,
    borderRadius: 6,
    backgroundColor: "#E4EAE0",
    alignItems: "center",
    justifyContent: "center",
    borderWidth: 1,
    borderColor: "#B9C9BC",
  },
  mobileActionsRow: {
    flexDirection: "row",
    gap: 8,
    marginTop: 10,
  },
  mobileRejectBtn: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    backgroundColor: RED,
    borderRadius: 8,
    paddingVertical: 8,
    gap: 6,
  },
  rejectTableBtn: {
    width: 32,
    height: 32,
    borderRadius: 6,
    backgroundColor: "#F1E3DE",
    alignItems: "center",
    justifyContent: "center",
    borderWidth: 1,
    borderColor: "#D9B3A8",
  },
});
