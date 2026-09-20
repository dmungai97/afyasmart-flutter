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
  AdminFacility,
  addFacility,
  deleteFacility,
  fetchAllFacilities,
  updateFacility,
} from "@admin/services/admin.service";
import { useAuthStore } from "@/src/store/authStore";

const BLUE = "#16302B";
const GREEN = "#3F7A5C";
const RED = "#9C3B2E";
const BORDER = "#C7CFC2";
const NAVY = "#16302B";
const MUTED = "#4B5C50";

const STRINGS = {
  title: "Facilities",
  subtitle: "Manage doctors and pharmacies listed on the platform",
  all: "All",
  doctors: "Doctors",
  pharmacies: "Pharmacies",
  search: "Search by name or location...",
  addFacility: "Add Facility",
  editFacility: "Edit Facility",
  deleteFacility: "Remove Facility",
  confirmDelete: "Are you sure you want to remove this facility?",
  confirm: "Confirm",
  cancel: "Cancel",
  save: "Save Changes",
  add: "Add",
  saving: "Saving...",
  noFacilities: "No facilities found",
  name: "Name",
  location: "Location",
  phone: "Phone",
  email: "Email",
  specialization: "Specialization",
  hospital: "Hospital",
  experienceYears: "Experience (years)",
  address: "Address",
  openingHours: "Opening Hours",
  type: "Type",
  doctor: "Doctor",
  pharmacy: "Pharmacy",
  available: "Available",
  yes: "Yes",
  no: "No",
  open24: "Open 24hrs",
  admin: "Admin",
};

const emptyDoctor = {
  type: "doctor" as const,
  name: "",
  location: "",
  phone: "",
  email: "",
  specialization: "",
  hospital: "",
  experienceYears: 0,
  available: true,
};

const emptyPharmacy = {
  type: "pharmacy" as const,
  name: "",
  location: "",
  phone: "",
  email: "",
  address: "",
  openingHours: "",
  open24hrs: false,
  open: true,
};

export default function AdminFacilitiesScreen() {
  const router = useRouter();
  const { width } = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const isMobile = width < 768;
  const [menuOpen, setMenuOpen] = useState(false);

  const user = useAuthStore((s) => s.user);
  const clearAuth = useAuthStore((s) => s.clearAuth);

  const [facilities, setFacilities] = useState<AdminFacility[]>([]);
  const [filtered, setFiltered] = useState<AdminFacility[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [activeFilter, setActiveFilter] = useState<"all" | "doctor" | "pharmacy">("all");

  const [editTarget, setEditTarget] = useState<AdminFacility | null>(null);
  const [addType, setAddType] = useState<"doctor" | "pharmacy">("doctor");
  const [form, setForm] = useState<Record<string, any>>(emptyDoctor);
  const [showModal, setShowModal] = useState<"none" | "edit" | "add">("none");
  const [saving, setSaving] = useState(false);

  const handleSignOut = async () => {
    await clearAuth();
    router.replace("/(auth)/login" as any);
  };

  const load = async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await fetchAllFacilities();
      setFacilities(data);
      setFiltered(data);
    } catch (err: any) {
      setFacilities([]);
      setError(err?.message ?? "Failed to load facilities. Pull to refresh to try again.");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    load();
  }, []);

  useEffect(() => {
    let result = facilities;
    if (activeFilter !== "all") result = result.filter((f) => f.type === activeFilter);
    if (search.trim()) {
      const q = search.toLowerCase();
      result = result.filter(
        (f) =>
          f.name.toLowerCase().includes(q) ||
          f.location.toLowerCase().includes(q) ||
          (f.specialization?.toLowerCase().includes(q) ?? false),
      );
    }
    setFiltered(result);
  }, [search, activeFilter, facilities]);

  const openEdit = (f: AdminFacility) => {
    setEditTarget(f);
    setForm({ ...f });
    setShowModal("edit");
  };

  const openAdd = (t: "doctor" | "pharmacy") => {
    setAddType(t);
    setForm(t === "doctor" ? { ...emptyDoctor } : { ...emptyPharmacy });
    setShowModal("add");
  };

  const saveEdit = async () => {
    if (!editTarget) return;
    setSaving(true);
    try {
      const { id, type, ...data } = form;
      await updateFacility(editTarget.type, editTarget.id, data);
      setFacilities((prev) =>
        prev.map((f) => (f.id === editTarget.id ? ({ ...f, ...data }) : f)),
      );
      setShowModal("none");
    } catch {
      Alert.alert("Error", "Failed to save changes.");
    } finally {
      setSaving(false);
    }
  };

  const saveAdd = async () => {
    setSaving(true);
    try {
      const { type, ...data } = form;
      await addFacility(addType, data);
      await load();
      setShowModal("none");
    } catch {
      Alert.alert("Error", "Failed to add facility.");
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = (f: AdminFacility) => {
    Alert.alert(STRINGS.deleteFacility, `${STRINGS.confirmDelete}\n\n"${f.name}"`, [
      { text: STRINGS.cancel, style: "cancel" },
      {
        text: STRINGS.confirm,
        style: "destructive",
        onPress: async () => {
          try {
            await deleteFacility(f.type, f.id);
            setFacilities((prev) => prev.filter((x) => x.id !== f.id));
          } catch {
            Alert.alert("Error", "Failed to remove facility.");
          }
        },
      },
    ]);
  };

  const filters = [
    { key: "all" as const, label: STRINGS.all },
    { key: "doctor" as const, label: STRINGS.doctors },
    { key: "pharmacy" as const, label: STRINGS.pharmacies },
  ];

  const isEdit = showModal === "edit";

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
        <View style={[styles.topbar, isMobile && { flexDirection: "column", alignItems: "stretch", gap: 12 }]}>
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
              {!isMobile && <Text style={styles.subtitle} numberOfLines={1}>{STRINGS.subtitle}</Text>}
            </View>
          </View>
          <View style={[styles.headerActions, isMobile && { width: "100%", justifyContent: "space-between" }]}>
            <TouchableOpacity style={[styles.addBtn, isMobile && { flex: 1, justifyContent: "center" }]} onPress={() => openAdd("doctor")} activeOpacity={0.8}>
              <Ionicons name="medkit-outline" size={15} color="#EEF1EA" />
              <Text style={styles.addBtnText}>+ Doctor</Text>
            </TouchableOpacity>
            <TouchableOpacity style={[styles.addBtn, styles.addBtnSecondary, isMobile && { flex: 1, justifyContent: "center" }]} onPress={() => openAdd("pharmacy")} activeOpacity={0.8}>
              <Ionicons name="business-outline" size={15} color="#4B5C50" />
              <Text style={[styles.addBtnText, { color: "#4B5C50" }]}>+ Pharmacy</Text>
            </TouchableOpacity>
          </View>
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

        {/* Facility list */}
        {loading ? (
          <ActivityIndicator size="large" color="#16302B" style={{ marginTop: 40 }} />
        ) : filtered.length === 0 ? (
          <View style={styles.empty}>
            <Ionicons name="business-outline" size={48} color={MUTED} />
            <Text style={styles.emptyText}>{STRINGS.noFacilities}</Text>
          </View>
        ) : (
          <View style={styles.grid}>
            {filtered.map((f) => (
              <View key={f.id} style={styles.card}>
                <View style={styles.cardBody}>
                  <View style={[styles.cardTop, isMobile && { flexDirection: "column", alignItems: "stretch", gap: 8 }]}>
                    <View style={{ flexDirection: "row", gap: 12, alignItems: "center", flex: 1 }}>
                      <View style={styles.cardIcon}>
                        <Ionicons
                          name={f.type === "doctor" ? "medkit" : "business"}
                          size={20}
                          color="#4B5C50"
                        />
                      </View>
                      <View style={styles.cardInfo}>
                        <Text style={styles.cardName}>{f.name}</Text>
                        {f.specialization ? <Text style={styles.cardSpec}>{f.specialization}</Text> : null}
                        {f.hospital ? <Text style={styles.cardSub}>{f.hospital}</Text> : null}
                        <Text style={styles.cardSub}>{f.location}</Text>
                        <Text style={styles.cardPhone}>{f.phone}</Text>
                      </View>
                    </View>
                    <View style={[styles.cardBadge, isMobile && { flexDirection: "row", flexWrap: "wrap", justifyContent: "flex-start", marginTop: 4, paddingLeft: 56, gap: 6 }]}>
                      <View style={styles.typeBadge}>
                        <Text style={styles.typeBadgeText}>
                          {f.type === "doctor" ? STRINGS.doctor : STRINGS.pharmacy}
                        </Text>
                      </View>
                      {f.type === "doctor" && (
                        <View style={[styles.availBadge, f.available ? styles.availGreen : styles.availRed]}>
                          <Text style={[styles.availText, { color: f.available ? GREEN : RED }]}>
                            {f.available ? "Available" : "Away"}
                          </Text>
                        </View>
                      )}
                      {f.type === "pharmacy" && f.open24hrs && (
                        <View style={styles.open24Badge}>
                           <Text style={styles.open24Text}>24 Hrs</Text>
                        </View>
                      )}
                    </View>
                  </View>
                  <View style={styles.cardActions}>
                    <TouchableOpacity style={styles.editAction} onPress={() => openEdit(f)} activeOpacity={0.7}>
                      <Ionicons name="create" size={14} color="#16302B" />
                      <Text style={styles.editActionText}>Edit Details</Text>
                    </TouchableOpacity>
                    <TouchableOpacity style={styles.deleteAction} onPress={() => handleDelete(f)} activeOpacity={0.7}>
                      <Ionicons name="trash" size={14} color={RED} />
                      <Text style={styles.deleteActionText}>Remove</Text>
                    </TouchableOpacity>
                  </View>
                </View>
              </View>
            ))}
          </View>
        )}
      </ScrollView>

      {/* Edit / Add Modal */}
      <Modal
        visible={showModal !== "none"}
        animationType="slide"
        transparent
        statusBarTranslucent
        onRequestClose={() => setShowModal("none")}
      >
        <KeyboardAvoidingView
          style={styles.modalKeyboard}
          behavior="padding"
          keyboardVerticalOffset={0}
        >
          <View style={styles.modalOverlay}>
            <ScrollView
              contentContainerStyle={[
                styles.modalScroll,
                { paddingBottom: Math.max(insets.bottom, 16) },
              ]}
              keyboardShouldPersistTaps="handled"
              keyboardDismissMode={Platform.OS === "ios" ? "interactive" : "on-drag"}
              showsVerticalScrollIndicator={false}
            >
              <View
                style={[
                  styles.modalCard,
                  { paddingBottom: Math.max(insets.bottom, 16) + 16 },
                ]}
              >
              <View style={styles.modalHeader}>
                <View>
                  <Text style={styles.modalTitle}>{isEdit ? STRINGS.editFacility : STRINGS.addFacility}</Text>
                  <Text style={styles.modalSub}>Save provider profiles to the network</Text>
                </View>
                <TouchableOpacity style={styles.modalCloseBtn} onPress={() => setShowModal("none")} activeOpacity={0.7}>
                  <Ionicons name="close" size={20} color={MUTED} />
                </TouchableOpacity>
              </View>

              {!isEdit && (
                <View style={styles.fieldGroup}>
                  <Text style={styles.fieldLabel}>{STRINGS.type}</Text>
                  <View style={styles.roleRow}>
                    {(["doctor", "pharmacy"] as const).map((t) => (
                      <TouchableOpacity
                        key={t}
                        style={[styles.roleChip, addType === t && styles.roleChipActive]}
                        onPress={() => {
                          setAddType(t);
                          setForm(t === "doctor" ? { ...emptyDoctor } : { ...emptyPharmacy });
                        }}
                        activeOpacity={0.7}
                      >
                        <Text style={[styles.roleChipText, addType === t && styles.roleChipTextActive]}>
                          {t === "doctor" ? STRINGS.doctor : STRINGS.pharmacy}
                        </Text>
                      </TouchableOpacity>
                    ))}
                  </View>
                </View>
              )}

              {/* Common fields */}
              {[
                { key: "name", label: STRINGS.name },
                { key: "location", label: STRINGS.location },
                { key: "phone", label: STRINGS.phone },
                { key: "email", label: STRINGS.email },
              ].map(({ key, label }) => (
                <View key={key} style={styles.fieldGroup}>
                  <Text style={styles.fieldLabel}>{label}</Text>
                  <TextInput
                    style={styles.field}
                    value={String(form[key] ?? "")}
                    onChangeText={(v) => setForm((prev) => ({ ...prev, [key]: v }))}
                    keyboardType={key === "phone" ? "phone-pad" : "default"}
                    returnKeyType="next"
                    blurOnSubmit={false}
                  />
                </View>
              ))}

              {/* Doctor-only fields */}
              {(isEdit ? editTarget?.type === "doctor" : addType === "doctor") && (
                <>
                  {[
                    { key: "specialization", label: STRINGS.specialization },
                    { key: "hospital", label: STRINGS.hospital },
                    { key: "experienceYears", label: STRINGS.experienceYears },
                  ].map(({ key, label }) => (
                    <View key={key} style={styles.fieldGroup}>
                      <Text style={styles.fieldLabel}>{label}</Text>
                      <TextInput
                        style={styles.field}
                        value={String(form[key] ?? "")}
                        onChangeText={(v) => setForm((prev) => ({ ...prev, [key]: key === "experienceYears" ? Number(v) || 0 : v }))}
                        keyboardType={key === "experienceYears" ? "numeric" : "default"}
                        returnKeyType="next"
                        blurOnSubmit={false}
                      />
                    </View>
                  ))}
                  <View style={styles.fieldGroup}>
                    <Text style={styles.fieldLabel}>{STRINGS.available}</Text>
                    <View style={styles.roleRow}>
                      <TouchableOpacity style={[styles.roleChip, form.available && styles.roleChipActive]} onPress={() => setForm((prev) => ({ ...prev, available: true }))} activeOpacity={0.7}>
                        <Text style={[styles.roleChipText, form.available && styles.roleChipTextActive]}>{STRINGS.yes}</Text>
                      </TouchableOpacity>
                      <TouchableOpacity style={[styles.roleChip, !form.available && { backgroundColor: "#F1E3DE", borderColor: "#D9B3A8" }]} onPress={() => setForm((prev) => ({ ...prev, available: false }))} activeOpacity={0.7}>
                        <Text style={[styles.roleChipText, !form.available && { color: RED }]}>{STRINGS.no}</Text>
                      </TouchableOpacity>
                    </View>
                  </View>
                </>
              )}

              {/* Pharmacy-only fields */}
              {(isEdit ? editTarget?.type === "pharmacy" : addType === "pharmacy") && (
                <>
                  <View style={styles.fieldGroup}>
                    <Text style={styles.fieldLabel}>{STRINGS.address}</Text>
                    <TextInput
                      style={styles.field}
                      value={String(form.address ?? "")}
                      onChangeText={(v) => setForm((prev) => ({ ...prev, address: v }))}
                      returnKeyType="next"
                      blurOnSubmit={false}
                    />
                  </View>
                  <View style={styles.fieldGroup}>
                    <Text style={styles.fieldLabel}>{STRINGS.openingHours}</Text>
                    <TextInput
                      style={styles.field}
                      value={String(form.openingHours ?? "")}
                      onChangeText={(v) => setForm((prev) => ({ ...prev, openingHours: v }))}
                      returnKeyType="done"
                    />
                  </View>
                  <View style={styles.fieldGroup}>
                    <Text style={styles.fieldLabel}>{STRINGS.open24}</Text>
                    <View style={styles.roleRow}>
                      <TouchableOpacity style={[styles.roleChip, form.open24hrs && styles.roleChipActive]} onPress={() => setForm((prev) => ({ ...prev, open24hrs: true }))} activeOpacity={0.7}>
                        <Text style={[styles.roleChipText, form.open24hrs && styles.roleChipTextActive]}>{STRINGS.yes}</Text>
                      </TouchableOpacity>
                      <TouchableOpacity style={[styles.roleChip, !form.open24hrs && { backgroundColor: "#F1E3DE", borderColor: "#D9B3A8" }]} onPress={() => setForm((prev) => ({ ...prev, open24hrs: false }))} activeOpacity={0.7}>
                        <Text style={[styles.roleChipText, !form.open24hrs && { color: RED }]}>{STRINGS.no}</Text>
                      </TouchableOpacity>
                    </View>
                  </View>
                </>
              )}

              <View style={styles.modalActions}>
                <TouchableOpacity style={styles.cancelBtn} onPress={() => setShowModal("none")} activeOpacity={0.7}>
                  <Text style={styles.cancelText}>{STRINGS.cancel}</Text>
                </TouchableOpacity>
                <TouchableOpacity
                  style={styles.saveBtn}
                  onPress={isEdit ? saveEdit : saveAdd}
                  activeOpacity={0.8}
                  disabled={saving}
                >
                  {saving ? (
                    <ActivityIndicator size="small" color="#EEF1EA" />
                  ) : (
                    <Text style={styles.saveText}>{isEdit ? STRINGS.save : STRINGS.add}</Text>
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
  content: { padding: 24, gap: 16 },
  topbar: { flexDirection: "row", justifyContent: "space-between", alignItems: "flex-start" },
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
  headerActions: { flexDirection: "row", gap: 8 },
  addBtn: { flexDirection: "row", alignItems: "center", gap: 6, backgroundColor: "#16302B", paddingHorizontal: 14, paddingVertical: 9, borderRadius: 12 },
  addBtnSecondary: { backgroundColor: "#EEF1EA", borderWidth: 1, borderColor: "#C7CFC2" },
  addBtnText: { color: "#EEF1EA", fontSize: 12, fontWeight: "700" },
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
  grid: { gap: 14 },
  card: { backgroundColor: "#FBFCF9", borderRadius: 12, borderWidth: 1, borderColor: BORDER, flexDirection: "row", overflow: "hidden" },
  cardBody: { flex: 1, padding: 16 },
  cardTop: { flexDirection: "row", gap: 12, alignItems: "flex-start" },
  cardIcon: { width: 44, height: 44, borderRadius: 22, alignItems: "center", justifyContent: "center", backgroundColor: "#EEF1EA" },
  cardInfo: { flex: 1, minWidth: 0 },
  cardBadge: { alignItems: "flex-end", gap: 4 },
  cardName: { color: "#16302B", fontSize: 15, fontWeight: "600" },
  cardSpec: { color: "#4B5C50", fontSize: 12, fontWeight: "600", marginTop: 2 },
  cardSub: { color: MUTED, fontSize: 11, fontWeight: "500", marginTop: 2 },
  cardPhone: { color: MUTED, fontSize: 11, fontWeight: "500", marginTop: 3 },
  typeBadge: { paddingHorizontal: 10, paddingVertical: 4, borderRadius: 20, borderWidth: 1, borderColor: "#C7CFC2", backgroundColor: "#EEF1EA" },
  typeBadgeText: { fontSize: 10, fontWeight: "600", color: "#4B5C50" },
  availBadge: { paddingHorizontal: 10, paddingVertical: 4, borderRadius: 20, borderWidth: 1 },
  availGreen: { backgroundColor: "#E4EAE0", borderColor: "#B9C9BC" },
  availRed: { backgroundColor: "#F1E3DE", borderColor: "#D9B3A8" },
  availText: { fontSize: 10, fontWeight: "600" },
  open24Badge: { backgroundColor: "#F4EBD3", paddingHorizontal: 10, paddingVertical: 4, borderRadius: 20, borderWidth: 1, borderColor: "#F4EBD3" },
  open24Text: { color: "#C9A227", fontSize: 10, fontWeight: "600" },
  cardActions: { flexDirection: "row", gap: 12, marginTop: 14, borderTopWidth: 1, borderTopColor: BORDER, paddingTop: 12 },
  editAction: { flexDirection: "row", alignItems: "center", gap: 6, backgroundColor: "#EEF1EA", paddingHorizontal: 12, paddingVertical: 6, borderRadius: 8, borderWidth: 1, borderColor: "#C7CFC2" },
  editActionText: { color: "#16302B", fontSize: 11, fontWeight: "600" },
  deleteAction: { flexDirection: "row", alignItems: "center", gap: 6, backgroundColor: "#F1E3DE", paddingHorizontal: 12, paddingVertical: 6, borderRadius: 8, borderWidth: 1, borderColor: "#D9B3A8" },
  deleteActionText: { color: RED, fontSize: 11, fontWeight: "600" },
  modalKeyboard: { flex: 1 },
  modalOverlay: { flex: 1, backgroundColor: "rgba(22, 48, 43, 0.55)", justifyContent: "flex-end" },
  modalScroll: { flexGrow: 1, justifyContent: "flex-end" },
  modalCard: { backgroundColor: "#FBFCF9", borderTopLeftRadius: 24, borderTopRightRadius: 24, padding: 20, gap: 14 },
  modalHeader: { flexDirection: "row", justifyContent: "space-between", alignItems: "center", borderBottomWidth: 1, borderBottomColor: "#EEF1EA", paddingBottom: 14 },
  modalTitle: { color: "#16302B", fontSize: 18, fontWeight: "700", letterSpacing: -0.5 },
  modalSub: { color: MUTED, fontSize: 11, fontWeight: "500", marginTop: 2 },
  modalCloseBtn: { width: 38, height: 38, borderRadius: 10, backgroundColor: "#EEF1EA", alignItems: "center", justifyContent: "center", borderWidth: 1, borderColor: "#C7CFC2" },
  fieldGroup: { gap: 6 },
  fieldLabel: { color: MUTED, fontSize: 10, fontWeight: "600", textTransform: "uppercase", letterSpacing: 0.8 },
  field: { height: 44, borderRadius: 10, borderWidth: 1, borderColor: "#C7CFC2", paddingHorizontal: 14, color: "#16302B", fontSize: 13, fontWeight: "600", backgroundColor: "#EEF1EA" },
  roleRow: { flexDirection: "row", flexWrap: "wrap", gap: 8 },
  roleChip: { paddingHorizontal: 14, paddingVertical: 8, borderRadius: 10, backgroundColor: "#EEF1EA", borderWidth: 1, borderColor: "#C7CFC2" },
  roleChipActive: { backgroundColor: "#16302B", borderColor: "#16302B" },
  roleChipText: { color: MUTED, fontSize: 12, fontWeight: "600", textTransform: "capitalize" },
  roleChipTextActive: { color: "#EEF1EA" },
  modalActions: { flexDirection: "row", gap: 12, marginTop: 12 },
  cancelBtn: { flex: 1, height: 46, borderRadius: 12, borderWidth: 1, borderColor: "#C7CFC2", alignItems: "center", justifyContent: "center" },
  cancelText: { color: MUTED, fontWeight: "600", fontSize: 13 },
  saveBtn: { flex: 2, height: 46, borderRadius: 12, backgroundColor: "#16302B", alignItems: "center", justifyContent: "center" },
  saveText: { color: "#EEF1EA", fontWeight: "600", fontSize: 13 },
});
