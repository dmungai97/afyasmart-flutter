import { Ionicons } from "@expo/vector-icons";
import { useRouter } from "expo-router";
import { useEffect, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
  useWindowDimensions,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import Sidebar from "../components/Sidebar";
import {
  AdminAffiliatePayout,
  approveAffiliatePayout,
  fetchAffiliatePayoutRequests,
  rejectAffiliatePayout,
} from "@admin/services/admin.service";
import { useAuthStore } from "@/src/store/authStore";

const GREEN = "#3F7A5C";
const RED = "#9C3B2E";
const ORANGE = "#C9A227";
const BORDER = "#C7CFC2";
const NAVY = "#16302B";
const MUTED = "#4B5C50";

const formatMoney = (v: number) => `Ksh ${new Intl.NumberFormat("en-KE").format(v)}`;

export default function AdminAffiliatePayoutsScreen() {
  const router = useRouter();
  const { width } = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const isMobile = width < 768;
  const [menuOpen, setMenuOpen] = useState(false);

  const user = useAuthStore((s) => s.user);
  const clearAuth = useAuthStore((s) => s.clearAuth);

  const [payouts, setPayouts] = useState<AdminAffiliatePayout[]>([]);
  const [loading, setLoading] = useState(true);
  const [approving, setApproving] = useState<string | null>(null);
  const [rejecting, setRejecting] = useState<string | null>(null);

  const load = async () => {
    setLoading(true);
    try {
      setPayouts(await fetchAffiliatePayoutRequests());
    } catch {
      setPayouts([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    load();
  }, []);

  const handleApprove = (p: AdminAffiliatePayout) => {
    Alert.alert(
      "Approve Payout",
      `Confirm you've sent Ksh ${p.amount.toLocaleString()} to ${p.phone} outside the app before approving.`,
      [
        { text: "Cancel", style: "cancel" },
        {
          text: "Confirm",
          onPress: async () => {
            setApproving(p.id);
            try {
              await approveAffiliatePayout(p.id);
              await load();
            } catch {
              Alert.alert("Error", "Failed to approve payout.");
            } finally {
              setApproving(null);
            }
          },
        },
      ],
    );
  };

  const handleReject = (p: AdminAffiliatePayout) => {
    Alert.alert(
      "Reject Payout",
      `Reject this request from ${p.phone}? Ksh ${p.amount.toLocaleString()} will be refunded to their available balance.`,
      [
        { text: "Cancel", style: "cancel" },
        {
          text: "Reject",
          style: "destructive",
          onPress: async () => {
            setRejecting(p.id);
            try {
              await rejectAffiliatePayout(p.id);
              await load();
            } catch {
              Alert.alert("Error", "Failed to reject payout.");
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

  const pending = payouts.filter((p) => p.status === "pending");
  const pendingValue = pending.reduce((sum, p) => sum + p.amount, 0);
  const paidCount = payouts.filter((p) => p.status === "paid").length;

  const statusColor = (status: string) => {
    if (status === "paid") return GREEN;
    if (status === "pending") return ORANGE;
    return RED;
  };

  const statusBg = (status: string) => {
    if (status === "paid") return "#E4EAE0";
    if (status === "pending") return "#F4EBD3";
    return "#F1E3DE";
  };

  return (
    <View style={styles.root}>
      <Sidebar
        userName={user?.name ?? "Admin"}
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
        <View style={[styles.topbar, isMobile && styles.topbarMobile]}>
          <View style={styles.titleRow}>
            {isMobile && (
              <TouchableOpacity style={styles.menuBtn} onPress={() => setMenuOpen(true)} activeOpacity={0.7}>
                <Ionicons name="menu-outline" size={24} color="#16302B" />
              </TouchableOpacity>
            )}
            <View style={styles.titleTextWrap}>
              <Text style={styles.title}>Affiliate Payouts</Text>
              {!isMobile && <Text style={styles.subtitle}>Review and approve withdrawal requests</Text>}
            </View>
          </View>
          <TouchableOpacity style={styles.refreshBtn} onPress={load} activeOpacity={0.8}>
            <Ionicons name="refresh-outline" size={18} color="#16302B" />
          </TouchableOpacity>
        </View>

        <View style={styles.kpiRow}>
          <View style={styles.kpiCard}>
            <Text style={styles.kpiLabel}>Pending Requests</Text>
            <Text style={styles.kpiValue}>{pending.length}</Text>
          </View>
          <View style={styles.kpiCard}>
            <Text style={styles.kpiLabel}>Pending Value</Text>
            <Text style={styles.kpiValue}>{formatMoney(pendingValue)}</Text>
          </View>
          <View style={styles.kpiCard}>
            <Text style={styles.kpiLabel}>Paid Out</Text>
            <Text style={styles.kpiValue}>{paidCount}</Text>
          </View>
        </View>

        {loading ? (
          <ActivityIndicator size="large" color="#16302B" style={{ marginTop: 40 }} />
        ) : payouts.length === 0 ? (
          <View style={styles.empty}>
            <Ionicons name="cash-outline" size={48} color={MUTED} />
            <Text style={styles.emptyText}>No payout requests yet</Text>
          </View>
        ) : (
          <View style={styles.list}>
            {payouts.map((p) => (
              <View key={p.id} style={styles.card}>
                <View style={styles.cardTop}>
                  <View>
                    <Text style={styles.cardPhone}>{p.phone}</Text>
                    <Text style={styles.cardDate}>{p.createdAt}</Text>
                  </View>
                  <View style={[styles.statusBadge, { backgroundColor: statusBg(p.status), borderColor: statusColor(p.status) + "30" }]}>
                    <Text style={[styles.statusText, { color: statusColor(p.status) }]}>{p.status}</Text>
                  </View>
                </View>
                <Text style={styles.cardAmount}>{formatMoney(p.amount)}</Text>
                {p.status === "pending" && (
                  <View style={styles.actionsRow}>
                    <TouchableOpacity
                      style={styles.approveBtn}
                      onPress={() => handleApprove(p)}
                      activeOpacity={0.8}
                      disabled={approving === p.id || rejecting === p.id}
                    >
                      {approving === p.id ? (
                        <ActivityIndicator size="small" color="#EEF1EA" />
                      ) : (
                        <>
                          <Ionicons name="checkmark-circle-outline" size={16} color="#EEF1EA" />
                          <Text style={styles.approveBtnText}>Approve</Text>
                        </>
                      )}
                    </TouchableOpacity>
                    <TouchableOpacity
                      style={styles.rejectBtn}
                      onPress={() => handleReject(p)}
                      activeOpacity={0.8}
                      disabled={approving === p.id || rejecting === p.id}
                    >
                      {rejecting === p.id ? (
                        <ActivityIndicator size="small" color={RED} />
                      ) : (
                        <>
                          <Ionicons name="close-circle-outline" size={16} color={RED} />
                          <Text style={styles.rejectBtnText}>Reject</Text>
                        </>
                      )}
                    </TouchableOpacity>
                  </View>
                )}
              </View>
            ))}
          </View>
        )}
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
  menuBtn: { width: 44, height: 44, borderRadius: 12, backgroundColor: "#FBFCF9", borderWidth: 1, borderColor: BORDER, alignItems: "center", justifyContent: "center" },
  title: { color: NAVY, fontSize: 24, fontWeight: "700" },
  subtitle: { color: MUTED, fontSize: 13, marginTop: 4, fontWeight: "500" },
  refreshBtn: { width: 44, height: 44, borderRadius: 12, backgroundColor: "#FBFCF9", borderWidth: 1, borderColor: BORDER, alignItems: "center", justifyContent: "center" },
  kpiRow: { flexDirection: "row", gap: 12, flexWrap: "wrap" },
  kpiCard: { flex: 1, minWidth: 140, backgroundColor: "#FBFCF9", borderRadius: 12, padding: 18, borderWidth: 1, borderColor: BORDER },
  kpiLabel: { color: MUTED, fontSize: 10, fontWeight: "600", textTransform: "uppercase", letterSpacing: 0.6 },
  kpiValue: { color: NAVY, fontSize: 20, fontWeight: "700", marginTop: 6 },
  empty: { alignItems: "center", paddingTop: 60, gap: 12 },
  emptyText: { color: MUTED, fontSize: 15, fontWeight: "600" },
  list: { gap: 10 },
  card: {
    backgroundColor: "#FBFCF9",
    borderRadius: 14,
    padding: 16,
    borderWidth: 1,
    borderColor: BORDER,
    gap: 10,
  },
  cardTop: { flexDirection: "row", justifyContent: "space-between", alignItems: "flex-start" },
  cardPhone: { color: NAVY, fontSize: 14, fontWeight: "700" },
  cardDate: { color: "#6B7A70", fontSize: 11, marginTop: 2, fontWeight: "500" },
  cardAmount: { color: NAVY, fontSize: 20, fontWeight: "800" },
  statusBadge: { paddingHorizontal: 10, paddingVertical: 4, borderRadius: 20, borderWidth: 1 },
  statusText: { fontSize: 10, fontWeight: "700", textTransform: "capitalize" },
  actionsRow: { flexDirection: "row", gap: 8 },
  approveBtn: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 6,
    backgroundColor: GREEN,
    borderRadius: 10,
    paddingVertical: 10,
  },
  approveBtnText: { color: "#EEF1EA", fontSize: 12, fontWeight: "700" },
  rejectBtn: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 6,
    backgroundColor: "#F1E3DE",
    borderRadius: 10,
    paddingVertical: 10,
    borderWidth: 1,
    borderColor: "#D9B3A8",
  },
  rejectBtnText: { color: RED, fontSize: 12, fontWeight: "700" },
});
