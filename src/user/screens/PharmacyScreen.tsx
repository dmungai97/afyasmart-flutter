import { useState, useEffect, useCallback } from 'react';
import {
  View, Text, TextInput, TouchableOpacity,
  FlatList, StyleSheet, ActivityIndicator,
  Modal, ScrollView, Linking
} from 'react-native';
import { useRouter } from 'expo-router';
import { useAuthStore } from '@/src/store/authStore';
import { getPharmacies } from '@/src/services/pharmacy.service';

const TEAL = '#0B6E6E';

type Pharmacy = {
  id: number;
  name: string;
  location: string;
  address: string;
  phone: string;
  email: string | null;
  opening_hours: string;
  open_24hrs: boolean;
  open: boolean;
};

export function PharmacyScreen() {
  const router = useRouter();
  const token = useAuthStore((state) => state.token);
  const [pharmacies, setPharmacies] = useState<Pharmacy[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<Pharmacy | null>(null);
  const [accessLocked, setAccessLocked] = useState(false);

  useEffect(() => {
    fetchPharmacies();
  }, []);

  const fetchPharmacies = useCallback(async (query?: string) => {
    setLoading(true);
    try {
      const data = await getPharmacies(token!, query);
      setAccessLocked(false);
      setPharmacies(data.data);
    } catch (error: any) {
      setAccessLocked(error?.code === 'permission-denied');
      setPharmacies([]);
    } finally {
      setLoading(false);
    }
  }, [token]);

  useEffect(() => {
    fetchPharmacies();
  }, [fetchPharmacies]);

  const handleSearch = () => fetchPharmacies(search.trim());

  return (
    <View style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Pharmacy Listings</Text>
        <Text style={styles.headerSub}>Find pharmacies near you in Nakuru</Text>
      </View>

      {/* Search */}
      <View style={styles.searchRow}>
        <TextInput
          style={styles.searchInput}
          placeholder="Search pharmacy or location..."
          placeholderTextColor="#9AA7A7"
          selectionColor={TEAL}
          cursorColor={TEAL}
          value={search}
          onChangeText={setSearch}
          onSubmitEditing={handleSearch}
          returnKeyType="search"
        />
        <TouchableOpacity style={styles.searchBtn} onPress={handleSearch}>
          <Text style={styles.searchBtnText}>Search</Text>
        </TouchableOpacity>
      </View>

      {/* List */}
      {loading ? (
        <ActivityIndicator size="large" color={TEAL} style={{ marginTop: 40 }} />
      ) : (
        <FlatList
          data={pharmacies}
          keyExtractor={(item) => item.id.toString()}
          contentContainerStyle={styles.list}
          keyboardShouldPersistTaps="handled"
          keyboardDismissMode="on-drag"
          ListEmptyComponent={
            accessLocked ? (
              <View style={styles.empty}>
                <Text style={styles.emptyIcon}>🔒</Text>
                <Text style={styles.emptyText}>Subscribe to view pharmacies near you</Text>
                <TouchableOpacity
                  onPress={() => router.push('/(tabs)/subscription' as any)}
                  style={[styles.searchBtn, { marginTop: 12 }]}
                >
                  <Text style={styles.searchBtnText}>View plans</Text>
                </TouchableOpacity>
              </View>
            ) : (
              <View style={styles.empty}>
                <Text style={styles.emptyIcon}>💊</Text>
                <Text style={styles.emptyText}>No pharmacies found</Text>
              </View>
            )
          }
          renderItem={({ item }) => (
            <TouchableOpacity style={styles.card} onPress={() => setSelected(item)}>
              <View style={styles.cardTop}>
                <View style={styles.iconCircle}>
                  <Text style={{ fontSize: 22 }}>🏪</Text>
                </View>
                <View style={styles.cardInfo}>
                  <View style={styles.nameRow}>
                    <Text style={styles.pharmName}>{item.name}</Text>
                    <View style={[styles.badge, item.open ? styles.badgeOpen : styles.badgeClosed]}>
                      <Text style={[styles.badgeText, item.open ? styles.badgeOpenText : styles.badgeClosedText]}>
                        {item.open ? 'Open' : 'Closed'}
                      </Text>
                    </View>
                  </View>
                  <Text style={styles.location}>📍 {item.location}</Text>
                  <Text style={styles.hours}>
                    {item.open_24hrs ? '🕐 Open 24 Hours' : `🕐 ${item.opening_hours}`}
                  </Text>
                </View>
              </View>
            </TouchableOpacity>
          )}
        />
      )}

      {/* Detail Modal */}
      <Modal visible={!!selected} animationType="slide" statusBarTranslucent onRequestClose={() => setSelected(null)}>
        {selected && (
          <View style={styles.modal}>
            <View style={styles.modalHeader}>
              <TouchableOpacity onPress={() => setSelected(null)}>
                <Text style={styles.backBtn}>← Back</Text>
              </TouchableOpacity>
            </View>
            <ScrollView contentContainerStyle={styles.modalContent}>
              <Text style={{ fontSize: 48, textAlign: 'center', marginBottom: 12 }}>🏪</Text>
              <Text style={styles.modalName}>{selected.name}</Text>

              <View style={[styles.badge, selected.open ? styles.badgeOpen : styles.badgeClosed, { alignSelf: 'center', marginBottom: 20 }]}>
                <Text style={[styles.badgeText, selected.open ? styles.badgeOpenText : styles.badgeClosedText]}>
                  {selected.open ? 'Currently Open' : 'Currently Closed'}
                </Text>
              </View>

              {selected.open_24hrs && (
                <View style={styles.badge24}>
                  <Text style={styles.badge24Text}>🕐 Open 24 Hours</Text>
                </View>
              )}

              <View style={styles.infoCard}>
                <InfoRow label="Address" value={selected.address} />
                <InfoRow label="Location" value={selected.location} />
                <InfoRow label="Hours" value={selected.open_24hrs ? 'Open 24 Hours' : selected.opening_hours} />
              </View>

              <TouchableOpacity
                style={styles.callBtn}
                onPress={() => Linking.openURL(`tel:${selected.phone}`)}
              >
                <Text style={styles.callBtnText}>📞 Call {selected.phone}</Text>
              </TouchableOpacity>

              {selected.email && (
                <TouchableOpacity
                  style={styles.emailBtn}
                  onPress={() => Linking.openURL(`mailto:${selected.email}`)}
                >
                  <Text style={styles.emailBtnText}>✉️ Send Email</Text>
                </TouchableOpacity>
              )}
            </ScrollView>
          </View>
        )}
      </Modal>
    </View>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.infoRow}>
      <Text style={styles.infoLabel}>{label}</Text>
      <Text style={styles.infoValue}>{value}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#f7f9f9' },
  header: {
    backgroundColor: TEAL,
    paddingTop: 52,
    paddingBottom: 16,
    paddingHorizontal: 20,
  },
  headerTitle: { color: '#fff', fontSize: 16, fontWeight: '700' },
  headerSub: { color: 'rgba(255,255,255,0.7)', fontSize: 12, marginTop: 2 },
  searchRow: {
    flexDirection: 'row',
    padding: 16,
    gap: 10,
    backgroundColor: '#fff',
    borderBottomWidth: 0.5,
    borderBottomColor: '#e8e8e8',
  },
  searchInput: {
    flex: 1,
    minHeight: 48,
    backgroundColor: '#F4F8F8',
    borderWidth: 1.5,
    borderColor: '#DCE3E3',
    borderRadius: 12,
    paddingHorizontal: 16,
    paddingVertical: 12,
    fontSize: 15,
    color: '#12201F',
  },
  searchBtn: {
    backgroundColor: TEAL,
    borderRadius: 10,
    paddingHorizontal: 16,
    justifyContent: 'center',
  },
  searchBtnText: { color: '#fff', fontWeight: '600', fontSize: 14 },
  list: { padding: 16, gap: 12 },
  empty: { alignItems: 'center', paddingTop: 60 },
  emptyIcon: { fontSize: 48, marginBottom: 12 },
  emptyText: { fontSize: 16, fontWeight: '600', color: '#1a1a1a' },
  card: {
    backgroundColor: '#fff',
    borderRadius: 14,
    padding: 16,
    borderWidth: 0.5,
    borderColor: '#e8e8e8',
  },
  cardTop: { flexDirection: 'row', gap: 12, alignItems: 'center' },
  iconCircle: {
    width: 52, height: 52, borderRadius: 26,
    backgroundColor: 'rgba(11,110,110,0.08)',
    alignItems: 'center', justifyContent: 'center',
  },
  cardInfo: { flex: 1 },
  nameRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 4 },
  pharmName: { fontSize: 15, fontWeight: '700', color: '#1a1a1a', flex: 1, marginRight: 8 },
  location: { fontSize: 12, color: '#888', marginBottom: 2 },
  hours: { fontSize: 12, color: '#555' },
  badge: { paddingHorizontal: 8, paddingVertical: 3, borderRadius: 20 },
  badgeOpen: { backgroundColor: '#E8F5E9' },
  badgeClosed: { backgroundColor: '#FFEBEE' },
  badgeText: { fontSize: 11, fontWeight: '600' },
  badgeOpenText: { color: '#2E7D32' },
  badgeClosedText: { color: '#C62828' },
  badge24: {
    backgroundColor: 'rgba(11,110,110,0.1)',
    borderRadius: 20,
    paddingHorizontal: 14,
    paddingVertical: 6,
    alignSelf: 'center',
    marginBottom: 16,
  },
  badge24Text: { color: TEAL, fontWeight: '600', fontSize: 13 },
  modal: { flex: 1, backgroundColor: '#f7f9f9' },
  modalHeader: {
    backgroundColor: TEAL,
    paddingTop: 52,
    paddingBottom: 16,
    paddingHorizontal: 20,
  },
  backBtn: { color: '#fff', fontSize: 15, fontWeight: '600' },
  modalContent: { padding: 20, alignItems: 'center', paddingBottom: 40 },
  modalName: { fontSize: 22, fontWeight: '700', color: '#1a1a1a', marginBottom: 12, textAlign: 'center' },
  infoCard: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    width: '100%',
    borderWidth: 0.5,
    borderColor: '#e8e8e8',
    marginBottom: 16,
  },
  infoRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 8,
    borderBottomWidth: 0.5,
    borderBottomColor: '#f0f0f0',
  },
  infoLabel: { fontSize: 13, color: '#888' },
  infoValue: { fontSize: 13, color: '#1a1a1a', fontWeight: '500', flex: 1, textAlign: 'right' },
  callBtn: {
    backgroundColor: TEAL,
    borderRadius: 10,
    paddingVertical: 13,
    alignItems: 'center',
    width: '100%',
    marginBottom: 10,
  },
  callBtnText: { color: '#fff', fontSize: 15, fontWeight: '600' },
  emailBtn: {
    backgroundColor: '#fff',
    borderRadius: 10,
    paddingVertical: 13,
    alignItems: 'center',
    width: '100%',
    borderWidth: 0.5,
    borderColor: '#ddd',
  },
  emailBtnText: { color: '#555', fontSize: 15, fontWeight: '600' },
});
