import { Ionicons } from "@expo/vector-icons";
import { useRouter } from "expo-router";
import { useEffect, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  Modal,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
  useWindowDimensions,
} from "react-native";
import { KeyboardAvoidingView } from "react-native-keyboard-controller";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import Sidebar from "../components/Sidebar";
import {
  AdminUser,
  fetchUsersPage,
  updateAdminUser,
} from "@admin/services/admin.service";
import { useAuthStore } from "@/src/store/authStore";

const BLUE = "#16302B";
const GREEN = "#3F7A5C";
const RED = "#9C3B2E";
const ORANGE = "#C9A227";
const BORDER = "#EEF1EA";
const NAVY = "#16302B";
const MUTED = "#4B5C50";

const STRINGS = {
  title: "All Users",
  subtitle: "Manage platform users, subscriptions & roles",
  search: "Search by name, email or phone...",
  filter: "Filter",
  all: "All",
  subscribed: "Subscribed",
  free: "Free",
  admins: "Admins",
  editUser: "Edit User",
  name: "Name",
  email: "Email",
  phone: "Phone",
  role: "Role",
  plan: "Subscription Plan",
  subscriptionStatus: "Subscription Status",
  active: "Active",
  inactive: "Inactive",
  save: "Save Changes",
  cancel: "Cancel",
  saving: "Saving...",
  noUsers: "No users found",
  free2: "Free",
  joined: "Joined",
  admin: "Admin",
};

const getAvatarColor = (name: string) => {
  const colors = [
    { bg: "#E4E7E2", text: "#16302B" }, // Ink
    { bg: "#E4EAE0", text: "#3F7A5C" }, // Sage
    { bg: "#F4EBD3", text: "#C9A227" }, // Gold
    { bg: "#DEE7E4", text: "#6B8F82" }, // Teal
    { bg: "#F1E3DE", text: "#9C3B2E" }, // Rose
    { bg: "#E9E2D8", text: "#4B5C50" }, // Warm neutral
  ];
  const charSum = name.split("").reduce((acc, char) => acc + char.charCodeAt(0), 0);
  const index = Math.abs(charSum) % colors.length;
  return colors[index];
};

export default function AdminUsersScreen() {
  const router = useRouter();
  const { width } = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const isMobile = width < 768;
  const [menuOpen, setMenuOpen] = useState(false);

  const user = useAuthStore((s) => s.user);
  const clearAuth = useAuthStore((s) => s.clearAuth);
  const isSuperAdmin = user?.role === "super_admin";

  const [users, setUsers] = useState<AdminUser[]>([]);
  const [filtered, setFiltered] = useState<AdminUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [cursor, setCursor] = useState<number | null>(null);
  const [hasMore, setHasMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [activeFilter, setActiveFilter] = useState<"all" | "subscribed" | "free" | "admin">("all");

  const [editTarget, setEditTarget] = useState<AdminUser | null>(null);
  const [editName, setEditName] = useState("");
  const [editRole, setEditRole] = useState("");
  const [editPlan, setEditPlan] = useState("");
  const [editSubscribed, setEditSubscribed] = useState(false);
  const [saving, setSaving] = useState(false);

  const handleSignOut = async () => {
    await clearAuth();
    router.replace("/(auth)/login" as any);
  };

  const load = async () => {
    setLoading(true);
    setError(null);
    try {
      const page = await fetchUsersPage();
      setUsers(page.items);
      setCursor(page.cursor);
      setHasMore(page.hasMore);
    } catch (err: any) {
      setUsers([]);
      setCursor(null);
      setHasMore(false);
      setError(err?.message ?? "Failed to load users. Pull to refresh to try again.");
    } finally {
      setLoading(false);
    }
  };

  // Search/filter below only run over users loaded so far — "Load more"
  // fetches the next page from the server rather than the whole collection,
  // so a search term won't match rows that haven't been paged in yet.
  const loadMore = async () => {
    if (!hasMore || loadingMore) return;
    setLoadingMore(true);
    try {
      const page = await fetchUsersPage(cursor);
      setUsers((prev) => [...prev, ...page.items]);
      setCursor(page.cursor);
      setHasMore(page.hasMore);
    } catch (err: any) {
      setError(err?.message ?? "Failed to load more users.");
    } finally {
      setLoadingMore(false);
    }
  };

  useEffect(() => {
    load();
  }, []);

  useEffect(() => {
    let result = users;
    if (activeFilter === "subscribed") result = result.filter((u) => u.isSubscribed);
    if (activeFilter === "free") result = result.filter((u) => !u.isSubscribed);
    if (activeFilter === "admin") result = result.filter((u) => u.role === "admin" || u.role === "super_admin");
    if (search.trim()) {
      const q = search.toLowerCase();
      result = result.filter(
        (u) =>
          u.name.toLowerCase().includes(q) ||
          u.email.toLowerCase().includes(q) ||
          u.phone.toLowerCase().includes(q),
      );
    }
    setFiltered(result);
  }, [search, activeFilter, users]);

  const openEdit = (u: AdminUser) => {
    setEditTarget(u);
    setEditName(u.name);
    setEditRole(u.role);
    setEditPlan(u.subscriptionPlan);
    setEditSubscribed(u.isSubscribed);
  };

  const saveEdit = async () => {
    if (!editTarget) return;
    setSaving(true);
    try {
      let newExpiresAt: string | null = editTarget.subscriptionExpiresAt;

      const wasActive = editTarget.isSubscribed && !editTarget.isExpired;
      const isNowActive = editSubscribed && editPlan !== "free";
      const planChanged = editTarget.subscriptionPlan !== editPlan;

      if (isNowActive && (!wasActive || planChanged)) {
        const now = new Date();
        let days = 0;
        if (editPlan === "daily") days = 1;
        else if (editPlan === "weekly") days = 7;
        else if (editPlan === "monthly") days = 30;

        if (days > 0) {
          const expiryDate = new Date(now.getTime() + days * 24 * 60 * 60 * 1000);
          newExpiresAt = expiryDate.toISOString();
        } else {
          newExpiresAt = null;
        }
      } else if (!editSubscribed || editPlan === "free") {
        newExpiresAt = null;
      }

      await updateAdminUser(editTarget.id, {
        name: editName.trim(),
        // Only a super_admin is allowed to change roles (enforced in
        // firestore.rules too) — a regular admin sending this would just be
        // rejected, so keep the field out of the payload entirely for them.
        ...(isSuperAdmin ? { role: editRole } : {}),
        is_subscribed: editSubscribed && editPlan !== "free",
        subscription_plan: editPlan,
        subscription_expires_at: newExpiresAt,
      });

      // Format ISO string back for local UI representation
      const formattedExpires = newExpiresAt
        ? new Intl.DateTimeFormat("en-KE", {
            day: "2-digit",
            month: "short",
            hour: "2-digit",
            minute: "2-digit",
          }).format(new Date(newExpiresAt))
        : null;

      const isExpiredNow = newExpiresAt ? new Date(newExpiresAt) < new Date() : false;

      setUsers((prev) =>
        prev.map((u) =>
          u.id === editTarget.id
            ? {
                ...u,
                name: editName.trim(),
                role: editRole,
                isSubscribed: editSubscribed && editPlan !== "free",
                subscriptionPlan: editPlan,
                subscriptionExpiresAt: formattedExpires,
                isExpired: isExpiredNow,
              }
            : u,
        ),
      );
      setEditTarget(null);
    } catch (error) {
      Alert.alert("Error", "Failed to save changes. Please try again.");
    } finally {
      setSaving(false);
    }
  };

  const filters: { key: typeof activeFilter; label: string }[] = [
    { key: "all", label: STRINGS.all },
    { key: "subscribed", label: STRINGS.subscribed },
    { key: "free", label: STRINGS.free },
    { key: "admin", label: STRINGS.admins },
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
            <Ionicons name="refresh-outline" size={18} color={BLUE} />
          </TouchableOpacity>
        </View>

        {error ? (
          <View style={styles.errorBanner}>
            <Ionicons name="alert-circle-outline" size={18} color={RED} />
            <Text style={styles.errorText}>{error}</Text>
          </View>
        ) : null}

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

        {/* Filter Chips */}
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
        </View>

        {/* Stats bar */}
        <View style={styles.statsBar}>
          <View style={styles.statsCardMini}>
            <Text style={styles.statsLabelMini}>Filtered Users</Text>
            <Text style={styles.statsValMini}>
              {filtered.length} <Text style={{ color: MUTED, fontSize: 11, fontWeight: "500" }}>of {users.length}</Text>
            </Text>
          </View>
          <View style={styles.statsCardMini}>
            <Text style={styles.statsLabelMini}>Active Subscribers</Text>
            <Text style={[styles.statsValMini, { color: GREEN }]}>
              {users.filter((u) => u.isSubscribed && !u.isExpired).length}
            </Text>
          </View>
        </View>

        {/* Users list */}
        {loading ? (
          <ActivityIndicator size="large" color={BLUE} style={{ marginTop: 40 }} />
        ) : filtered.length === 0 ? (
          <View style={styles.empty}>
            <Ionicons name="people-outline" size={48} color={MUTED} />
            <Text style={styles.emptyText}>{STRINGS.noUsers}</Text>
          </View>
        ) : (
          <View style={styles.table}>
            {filtered.map((u, index) => {
              const avatarColors = getAvatarColor(u.name);
              const renderBadges = () => (
                <>
                  {u.isSubscribed ? (
                    u.isExpired ? (
                      <View style={[styles.badge, styles.badgeRed]}>
                        <Text style={[styles.badgeText, styles.badgeTextRed]}>
                          Expired
                        </Text>
                      </View>
                    ) : (
                      <View style={[styles.badge, styles.badgeGreen]}>
                        <Text style={[styles.badgeText, styles.badgeTextGreen]}>
                          {STRINGS.active}
                        </Text>
                      </View>
                    )
                  ) : (
                    <View style={[styles.badge, styles.badgeGray]}>
                      <Text style={[styles.badgeText, styles.badgeTextGray]}>
                        {STRINGS.free2}
                      </Text>
                    </View>
                  )}
                  {(u.role === "admin" || u.role === "super_admin") ? (
                    <View style={[styles.badge, styles.badgeBlue]}>
                      <Text style={[styles.badgeText, styles.badgeTextBlue]}>{STRINGS.admin}</Text>
                    </View>
                  ) : null}
                  {u.subscriptionPlan !== "free" ? (
                    <View style={[styles.badge, styles.badgeOrange]}>
                      <Text style={[styles.badgeText, styles.badgeTextOrange]}>{u.subscriptionPlan}</Text>
                    </View>
                  ) : null}
                </>
              );

              if (isMobile) {
                return (
                  <View key={u.id} style={styles.mobileUserCard}>
                    <View style={styles.mobileUserTop}>
                      <View style={[styles.rowAvatar, { backgroundColor: avatarColors.bg }]}>
                        <Text style={[styles.avatarText, { color: avatarColors.text }]}>{(u.name[0] ?? "U").toUpperCase()}</Text>
                      </View>
                      <View style={styles.rowInfo}>
                        <Text style={styles.rowName} numberOfLines={1}>{u.name}</Text>
                        <Text style={styles.rowEmail} numberOfLines={1}>{u.email}</Text>
                        {u.phone ? <Text style={styles.rowPhone}>{u.phone}</Text> : null}
                        <Text style={styles.rowDate}>
                          {STRINGS.joined}: {u.createdAt}
                          {u.isSubscribed && u.subscriptionExpiresAt ? (
                            u.isExpired ? (
                              <Text style={{ color: "#9C3B2E", fontWeight: "600" }}>
                                {"\n"}Expired: {u.subscriptionExpiresAt}
                              </Text>
                            ) : (
                              <Text style={{ color: "#3F7A5C", fontWeight: "600" }}>
                                {"\n"}Expires: {u.subscriptionExpiresAt}
                              </Text>
                            )
                          ) : null}
                        </Text>
                      </View>
                      <TouchableOpacity style={styles.editBtn} onPress={() => openEdit(u)} activeOpacity={0.7}>
                        <Ionicons name="create" size={16} color={BLUE} />
                      </TouchableOpacity>
                    </View>
                    <View style={styles.mobileUserBottom}>
                      <View style={styles.mobileBadgesRow}>
                        {renderBadges()}
                      </View>
                    </View>
                  </View>
                );
              }

              return (
                <View key={u.id} style={[styles.row, index % 2 === 1 && styles.rowAlt]}>
                  {/* Avatar + Info */}
                  <View style={[styles.rowAvatar, { backgroundColor: avatarColors.bg }]}>
                    <Text style={[styles.avatarText, { color: avatarColors.text }]}>{(u.name[0] ?? "U").toUpperCase()}</Text>
                  </View>
                  <View style={styles.rowInfo}>
                    <Text style={styles.rowName} numberOfLines={1}>{u.name}</Text>
                    <Text style={styles.rowEmail} numberOfLines={1}>{u.email}</Text>
                    {u.phone ? <Text style={styles.rowPhone}>{u.phone}</Text> : null}
                    <Text style={styles.rowDate}>
                      {STRINGS.joined}: {u.createdAt}
                      {u.isSubscribed && u.subscriptionExpiresAt ? (
                        u.isExpired ? (
                          <Text style={{ color: "#9C3B2E", fontWeight: "600" }}>
                            {"  •  "}Expired: {u.subscriptionExpiresAt}
                          </Text>
                        ) : (
                          <Text style={{ color: "#3F7A5C", fontWeight: "600" }}>
                            {"  •  "}Expires: {u.subscriptionExpiresAt}
                          </Text>
                        )
                      ) : null}
                    </Text>
                  </View>

                  {/* Badges */}
                  <View style={styles.rowBadges}>
                    {renderBadges()}
                  </View>

                  {/* Edit button */}
                  <TouchableOpacity style={styles.editBtn} onPress={() => openEdit(u)} activeOpacity={0.7}>
                    <Ionicons name="create" size={16} color={BLUE} />
                  </TouchableOpacity>
                </View>
              );
            })}
          </View>
        )}

        {!loading && hasMore ? (
          <TouchableOpacity style={styles.loadMoreBtn} onPress={loadMore} disabled={loadingMore} activeOpacity={0.7}>
            {loadingMore ? (
              <ActivityIndicator size="small" color={BLUE} />
            ) : (
              <Text style={styles.loadMoreText}>Load more users</Text>
            )}
          </TouchableOpacity>
        ) : null}
      </ScrollView>

      {/* Edit Modal */}
      <Modal visible={!!editTarget} animationType="slide" transparent statusBarTranslucent onRequestClose={() => setEditTarget(null)}>
        <KeyboardAvoidingView
          style={styles.modalKeyboard}
          behavior="padding"
          keyboardVerticalOffset={0}
        >
          <View style={styles.modalOverlay}>
            <ScrollView
              contentContainerStyle={styles.modalScroll}
              keyboardShouldPersistTaps="handled"
              keyboardDismissMode={Platform.OS === "ios" ? "interactive" : "on-drag"}
              showsVerticalScrollIndicator={false}
            >
          <View style={[styles.modalCard, { paddingBottom: Math.max(insets.bottom, 16) + 16 }]}>
            <View style={styles.modalHeader}>
              <View>
                <Text style={styles.modalTitle}>{STRINGS.editUser}</Text>
                <Text style={styles.modalSub}>Update credential & access controls</Text>
              </View>
              <TouchableOpacity style={styles.modalCloseBtn} onPress={() => setEditTarget(null)} activeOpacity={0.7}>
                <Ionicons name="close" size={20} color={MUTED} />
              </TouchableOpacity>
            </View>

            <View style={styles.fieldGroup}>
              <Text style={styles.fieldLabel}>{STRINGS.name}</Text>
              <TextInput
                style={styles.field}
                value={editName}
                onChangeText={setEditName}
                returnKeyType="done"
              />
            </View>

            {isSuperAdmin && (
              <View style={styles.fieldGroup}>
                <Text style={styles.fieldLabel}>{STRINGS.role}</Text>
                <View style={styles.roleRow}>
                  {["user", "admin", "super_admin"].map((r) => (
                    <TouchableOpacity
                      key={r}
                      style={[styles.roleChip, editRole === r && styles.roleChipActive]}
                      onPress={() => setEditRole(r)}
                      activeOpacity={0.7}
                    >
                      <Text style={[styles.roleChipText, editRole === r && styles.roleChipTextActive]}>{r}</Text>
                    </TouchableOpacity>
                  ))}
                </View>
              </View>
            )}

            <View style={styles.fieldGroup}>
              <Text style={styles.fieldLabel}>{STRINGS.plan}</Text>
              <View style={styles.roleRow}>
                {["free", "daily", "weekly", "monthly"].map((p) => (
                  <TouchableOpacity
                    key={p}
                    style={[styles.roleChip, editPlan === p && styles.roleChipActive]}
                    onPress={() => {
                      setEditPlan(p);
                      if (p === "free") {
                        setEditSubscribed(false);
                      } else {
                        setEditSubscribed(true);
                      }
                    }}
                    activeOpacity={0.7}
                  >
                    <Text style={[styles.roleChipText, editPlan === p && styles.roleChipTextActive]}>{p}</Text>
                  </TouchableOpacity>
                ))}
              </View>
            </View>

            <View style={styles.fieldGroup}>
              <Text style={styles.fieldLabel}>{STRINGS.subscriptionStatus}</Text>
              <View style={styles.roleRow}>
                <TouchableOpacity
                  style={[styles.roleChip, editSubscribed && styles.roleChipActive]}
                  onPress={() => {
                    setEditSubscribed(true);
                    if (editPlan === "free") {
                      setEditPlan("daily");
                    }
                  }}
                  activeOpacity={0.7}
                >
                  <Text style={[styles.roleChipText, editSubscribed && styles.roleChipTextActive]}>{STRINGS.active}</Text>
                </TouchableOpacity>
                <TouchableOpacity
                  style={[styles.roleChip, !editSubscribed && styles.roleChipRed]}
                  onPress={() => {
                    setEditSubscribed(false);
                    setEditPlan("free");
                  }}
                  activeOpacity={0.7}
                >
                  <Text style={[styles.roleChipText, !editSubscribed && styles.roleChipTextRed]}>{STRINGS.inactive}</Text>
                </TouchableOpacity>
              </View>
            </View>

            <View style={styles.modalActions}>
              <TouchableOpacity style={styles.cancelBtn} onPress={() => setEditTarget(null)} activeOpacity={0.7}>
                <Text style={styles.cancelText}>{STRINGS.cancel}</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.saveBtn} onPress={saveEdit} activeOpacity={0.8} disabled={saving}>
                {saving ? (
                  <ActivityIndicator size="small" color="#EEF1EA" />
                ) : (
                  <Text style={styles.saveText}>{STRINGS.save}</Text>
                )}
              </TouchableOpacity>
            </View>
          </View>
            </ScrollView>
          </View>
        </KeyboardAvoidingView>
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, flexDirection: "row", backgroundColor: "#EEF1EA" },
  main: { flex: 1 },
  content: { padding: 24, gap: 20 },
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
    borderColor: "#C7CFC2",
  },
  backBtn: {
    padding: 6,
  },
  menuBtn: { width: 44, height: 44, borderRadius: 12, backgroundColor: "#FBFCF9", borderWidth: 1, borderColor: "#C7CFC2", alignItems: "center", justifyContent: "center" },
  title: { color: "#16302B", fontSize: 24, fontWeight: "700" },
  titleMobile: { fontSize: 20 },
  subtitle: { color: "#4B5C50", fontSize: 13, marginTop: 4, fontWeight: "500" },
  refreshBtn: { width: 44, height: 44, borderRadius: 12, backgroundColor: "#FBFCF9", borderWidth: 1, borderColor: "#C7CFC2", alignItems: "center", justifyContent: "center" },
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
  searchRow: { flexDirection: "row", alignItems: "center", backgroundColor: "#FBFCF9", borderRadius: 10, borderWidth: 1, borderColor: "#C7CFC2", height: 44, gap: 8 },
  searchInput: { flex: 1, color: "#16302B", fontSize: 13, fontWeight: "500", paddingRight: 12 },
  filterRow: { flexDirection: "row", flexWrap: "wrap", gap: 8 },
  filterChip: { paddingHorizontal: 14, paddingVertical: 7, borderRadius: 20, backgroundColor: "#FBFCF9", borderWidth: 1, borderColor: "#C7CFC2" },
  filterChipActive: { backgroundColor: "#16302B", borderColor: "#16302B" },
  filterChipText: { color: "#4B5C50", fontSize: 12, fontWeight: "600" },
  filterChipTextActive: { color: "#EEF1EA" },
  statsBar: { flexDirection: "row", gap: 12 },
  statsCardMini: {
    flex: 1,
    backgroundColor: "#FBFCF9",
    borderWidth: 1,
    borderColor: "#C7CFC2",
    borderRadius: 12,
    padding: 12
  },
  statsLabelMini: { color: "#4B5C50", fontSize: 10, fontWeight: "600", textTransform: "uppercase", letterSpacing: 0.4 },
  statsValMini: { color: "#16302B", fontSize: 16, fontWeight: "700", marginTop: 4 },
  empty: { alignItems: "center", paddingTop: 60, gap: 12 },
  emptyText: { color: "#4B5C50", fontSize: 15, fontWeight: "600" },
  loadMoreBtn: {
    height: 44,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: "#C7CFC2",
    backgroundColor: "#FBFCF9",
    alignItems: "center",
    justifyContent: "center",
  },
  loadMoreText: { color: "#16302B", fontSize: 13, fontWeight: "700" },
  table: { gap: 10 },
  row: { backgroundColor: "#FBFCF9", borderRadius: 12, padding: 14, borderWidth: 1, borderColor: "#C7CFC2", flexDirection: "row", alignItems: "center", gap: 12 },
  rowAlt: { backgroundColor: "#EEF1EA" },
  rowAvatar: { width: 38, height: 38, borderRadius: 19, backgroundColor: "#EEF1EA", alignItems: "center", justifyContent: "center" },
  avatarText: { fontWeight: "700", fontSize: 15, color: "#16302B" },
  rowInfo: { flex: 1, gap: 2, minWidth: 0 },
  rowName: { color: "#16302B", fontSize: 14, fontWeight: "600" },
  rowEmail: { color: "#4B5C50", fontSize: 12, fontWeight: "500" },
  rowPhone: { color: "#4B5C50", fontSize: 11, fontWeight: "500" },
  rowDate: { color: "#6B7A70", fontSize: 10, fontWeight: "500", marginTop: 2 },
  rowBadges: { gap: 4, alignItems: "flex-end" },
  badge: { paddingHorizontal: 10, paddingVertical: 4, borderRadius: 20, borderWidth: 1 },
  badgeText: { fontSize: 10, fontWeight: "600" },
  badgeGreen: { backgroundColor: "#E4EAE0", borderColor: "#B9C9BC" },
  badgeTextGreen: { color: "#3F7A5C" },
  badgeGray: { backgroundColor: "#EEF1EA", borderColor: "#C7CFC2" },
  badgeTextGray: { color: "#4B5C50" },
  badgeRed: { backgroundColor: "#F1E3DE", borderColor: "#D9B3A8" },
  badgeTextRed: { color: "#9C3B2E" },
  badgeBlue: { backgroundColor: "#EEF1EA", borderColor: "#B9C9BC" },
  badgeTextBlue: { color: "#16302B" },
  badgeOrange: { backgroundColor: "#F4EBD3", borderColor: "#DDC98A" },
  badgeTextOrange: { color: "#C9A227" },
  editBtn: { width: 40, height: 40, borderRadius: 10, backgroundColor: "#EEF1EA", alignItems: "center", justifyContent: "center" },
  modalKeyboard: { flex: 1 },
  modalOverlay: { flex: 1, backgroundColor: "rgba(22, 48, 43, 0.55)", justifyContent: "flex-end" },
  modalScroll: { flexGrow: 1, justifyContent: "flex-end" },
  modalCard: { backgroundColor: "#FBFCF9", borderTopLeftRadius: 24, borderTopRightRadius: 24, padding: 20, gap: 16 },
  modalHeader: { flexDirection: "row", justifyContent: "space-between", alignItems: "center", borderBottomWidth: 1, borderBottomColor: "#EEF1EA", paddingBottom: 14 },
  modalTitle: { color: "#16302B", fontSize: 18, fontWeight: "700", letterSpacing: -0.5 },
  modalSub: { color: "#4B5C50", fontSize: 11, fontWeight: "500", marginTop: 2 },
  modalCloseBtn: { width: 38, height: 38, borderRadius: 10, backgroundColor: "#EEF1EA", alignItems: "center", justifyContent: "center", borderWidth: 1, borderColor: "#C7CFC2" },
  fieldGroup: { gap: 6 },
  fieldLabel: { color: "#4B5C50", fontSize: 10, fontWeight: "600", textTransform: "uppercase", letterSpacing: 0.8 },
  field: { height: 44, borderRadius: 10, borderWidth: 1, borderColor: "#C7CFC2", paddingHorizontal: 14, color: "#16302B", fontSize: 13, fontWeight: "600", backgroundColor: "#EEF1EA" },
  roleRow: { flexDirection: "row", flexWrap: "wrap", gap: 8 },
  roleChip: { paddingHorizontal: 14, paddingVertical: 8, borderRadius: 10, backgroundColor: "#EEF1EA", borderWidth: 1, borderColor: "#C7CFC2" },
  roleChipActive: { backgroundColor: "#16302B", borderColor: "#16302B" },
  roleChipText: { color: "#4B5C50", fontSize: 12, fontWeight: "700", textTransform: "capitalize" },
  roleChipTextActive: { color: "#EEF1EA" },
  roleChipRed: { backgroundColor: "#F1E3DE", borderColor: "#D9B3A8" },
  roleChipTextRed: { color: "#9C3B2E" },
  modalActions: { flexDirection: "row", gap: 12, marginTop: 12 },
  cancelBtn: { flex: 1, height: 46, borderRadius: 12, borderWidth: 1, borderColor: "#C7CFC2", alignItems: "center", justifyContent: "center" },
  cancelText: { color: "#4B5C50", fontWeight: "700", fontSize: 13 },
  saveBtn: { flex: 2, height: 46, borderRadius: 12, backgroundColor: "#16302B", alignItems: "center", justifyContent: "center" },
  saveText: { color: "#EEF1EA", fontWeight: "700", fontSize: 13 },
  mobileUserCard: {
    backgroundColor: "#FBFCF9",
    borderRadius: 12,
    padding: 14,
    borderWidth: 1,
    borderColor: "#C7CFC2",
    marginBottom: 4,
    gap: 12
  },
  mobileUserTop: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
  },
  mobileUserBottom: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    borderTopWidth: 1,
    borderTopColor: "#EEF1EA",
    paddingTop: 10,
  },
  mobileBadgesRow: {
    flexDirection: "row",
    flexWrap: "wrap",
    gap: 6,
  },
});
