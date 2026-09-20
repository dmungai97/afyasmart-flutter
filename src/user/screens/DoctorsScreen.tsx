import { useState, useEffect, useCallback, useRef } from 'react';
import {
  View, Text, TextInput, TouchableOpacity,
  FlatList, StyleSheet, ActivityIndicator,
  Modal, ScrollView, Linking,
} from 'react-native';
import * as Location from 'expo-location';
import { useRouter } from 'expo-router';
import { useAuthStore } from '@/src/store/authStore';
import {
  fetchNearbyDoctors,
  fetchRegions,
  fetchSpecializations,
  type Doctor,
} from '@/src/services/doctor.service';

const TEAL = '#0B6E6E';

function getInitials(name: string): string {
  return name
    .replace(/^Dr\.\s*/i, '')
    .split(' ')
    .slice(0, 2)
    .map((n) => n[0])
    .join('');
}

function renderStars(rating: number): string {
  const full = Math.floor(rating);
  return '★'.repeat(full) + '☆'.repeat(5 - full);
}

export function DoctorsScreen() {
  const router = useRouter();
  const token = useAuthStore((s) => s.token);

  const [doctors,         setDoctors]        = useState<Doctor[]>([]);
  const [loading,         setLoading]        = useState(true);
  const [selected,        setSelected]       = useState<Doctor | null>(null);
  const [accessLocked,    setAccessLocked]   = useState(false);

  const [search,          setSearch]         = useState('');
  const [activeRegion,    setActiveRegion]   = useState<string | null>(null);
  const [activeSpec,      setActiveSpec]     = useState<string | null>(null);
  const [nearMeOnly,      setNearMeOnly]     = useState(false);

  const [coords,          setCoords]         = useState<{ lat: number; lng: number } | null>(null);
  const coordsRef = useRef<{ lat: number; lng: number } | null>(null);

  const [regions,         setRegions]        = useState<string[]>([]);
  const [specializations, setSpecializations]= useState<string[]>([]);
  const [filtersLoading,  setFiltersLoading] = useState(true);

  const hasMounted = useRef(false);

  const loadFilters = useCallback(async () => {
    setFiltersLoading(true);
    try {
      const [r, s] = await Promise.all([
        fetchRegions(token!),
        fetchSpecializations(token!),
      ]);
      setRegions(r);
      setSpecializations(s);
    } catch {
      // non-critical
    } finally {
      setFiltersLoading(false);
    }
  }, [token]);

  const loadDoctors = useCallback(async (
    query?: string,
    overrideCoords?: { lat: number; lng: number } | null,
  ) => {
    setLoading(true);
    try {
      const gps = overrideCoords !== undefined ? overrideCoords : coordsRef.current;

      const data = await fetchNearbyDoctors(token!, {
        search:         query,
        region:         activeRegion?.toLowerCase() ?? undefined,
        specialization: activeSpec   ?? undefined,
        ...(nearMeOnly && gps ? { lat: gps.lat, lng: gps.lng, radius: 50 } : {}),
      });
      setAccessLocked(false);
      setDoctors(data.data);
    } catch (error: any) {
      setAccessLocked(error?.code === 'permission-denied');
      setDoctors([]);
    } finally {
      setLoading(false);
    }
  }, [token, activeRegion, activeSpec, nearMeOnly]);

  useEffect(() => {
    (async () => {
      loadFilters();

      let resolvedCoords: { lat: number; lng: number } | null = null;
      try {
        const { status } = await Location.requestForegroundPermissionsAsync();
        if (status === 'granted') {
          const loc = await Location.getCurrentPositionAsync({
            accuracy: Location.Accuracy.Balanced,
          });
          resolvedCoords = {
            lat: loc.coords.latitude,
            lng: loc.coords.longitude,
          };
          coordsRef.current = resolvedCoords;
          setCoords(resolvedCoords);
        }
      } catch { /* GPS unavailable */ }

      await loadDoctors(undefined, resolvedCoords);
    })();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!hasMounted.current) {
      hasMounted.current = true;
      return;
    }
    loadDoctors();
  }, [activeRegion, activeSpec, nearMeOnly, loadDoctors]);

  const handleSearch = () => loadDoctors(search.trim() || undefined);

  const handleRegionPress = (region: string) => {
    const next = activeRegion === region ? null : region;
    setActiveRegion(next);
    setActiveSpec(null);
    setSearch('');
  };

  const handleSpecPress = (spec: string) => {
    setActiveSpec(activeSpec === spec ? null : spec);
  };

  const clearAllFilters = () => {
    setActiveRegion(null);
    setActiveSpec(null);
    setNearMeOnly(false);
    setSearch('');
  };

  const hasActiveFilters = !!(activeRegion || activeSpec || nearMeOnly || search.trim());

  return (
    <View style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Find Doctors</Text>
        <Text style={styles.headerSub}>
          {coords && nearMeOnly ? 'Filtered by distance from you' : 'Kenya-based healthcare professionals'}
        </Text>
      </View>

      {/* Search row */}
      <View style={styles.searchRow}>
        <TextInput
          style={styles.searchInput}
          placeholder="Search by name or specialization..."
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

      {/* Near Me toggle */}
      {coords ? (
        <View style={styles.nearMeRow}>
          <TouchableOpacity
            style={[styles.nearMeBtn, nearMeOnly && styles.nearMeBtnActive]}
            onPress={() => setNearMeOnly((v) => !v)}
          >
            <Text style={[styles.nearMeBtnText, nearMeOnly && styles.nearMeBtnTextActive]}>
              📍 {nearMeOnly ? 'Near Me (50 km) ✓' : 'Near Me'}
            </Text>
          </TouchableOpacity>
        </View>
      ) : null}

      {/* Region chips */}
      {filtersLoading ? (
        <View style={styles.filterSection}>
          <Text style={styles.filterLabel}>Region</Text>
          <View style={styles.chipRow}>
            {[80, 90, 70, 85, 75, 95].map((w, i) => (
              <View key={i} style={[styles.chip, styles.chipSkeleton, { width: w }]} />
            ))}
          </View>
        </View>
      ) : regions.length > 0 ? (
        <View style={styles.filterSection}>
          <Text style={styles.filterLabel}>Region</Text>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.chipRow}>
            {regions.map((region) => (
              <TouchableOpacity
                key={region}
                style={[styles.chip, activeRegion === region && styles.chipActive]}
                onPress={() => handleRegionPress(region)}
              >
                <Text style={[styles.chipText, activeRegion === region && styles.chipTextActive]}>
                  {region}
                </Text>
              </TouchableOpacity>
            ))}
          </ScrollView>
        </View>
      ) : null}

      {/* Specialization chips */}
      {filtersLoading ? (
        <View style={styles.filterSection}>
          <Text style={styles.filterLabel}>Specialization</Text>
          <View style={styles.chipRow}>
            {[110, 95, 120, 100, 130, 105].map((w, i) => (
              <View key={i} style={[styles.chip, styles.chipSkeleton, { width: w }]} />
            ))}
          </View>
        </View>
      ) : specializations.length > 0 ? (
        <View style={styles.filterSection}>
          <Text style={styles.filterLabel}>Specialization</Text>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.chipRow}>
            {specializations.map((spec) => (
              <TouchableOpacity
                key={spec}
                style={[styles.chip, activeSpec === spec && styles.chipActive]}
                onPress={() => handleSpecPress(spec)}
              >
                <Text style={[styles.chipText, activeSpec === spec && styles.chipTextActive]}>
                  {spec}
                </Text>
              </TouchableOpacity>
            ))}
          </ScrollView>
        </View>
      ) : null}

      {/* Active filter summary bar */}
      {hasActiveFilters ? (
        <View style={styles.filterSummary}>
          <Text style={styles.filterSummaryText} numberOfLines={1}>
            {[
              activeRegion,
              activeSpec,
              nearMeOnly ? 'Near Me (50km)' : null,
              search.trim() || null,
            ].filter(Boolean).join(' · ')}
          </Text>
          <TouchableOpacity onPress={clearAllFilters}>
            <Text style={styles.clearText}>Clear all</Text>
          </TouchableOpacity>
        </View>
      ) : null}

      {/* Doctor list */}
      {loading ? (
        <ActivityIndicator size="large" color={TEAL} style={{ marginTop: 40 }} />
      ) : (
        <FlatList
          data={doctors}
          keyExtractor={(item) => item.id.toString()}
          contentContainerStyle={styles.list}
          keyboardShouldPersistTaps="handled"
          keyboardDismissMode="on-drag"
          ListEmptyComponent={
            accessLocked ? (
              <View style={styles.empty}>
                <Text style={styles.emptyIcon}>🔒</Text>
                <Text style={styles.emptyText}>Subscribe to view doctors near you</Text>
                <TouchableOpacity
                  onPress={() => router.push('/(tabs)/subscription' as any)}
                  style={styles.clearAllBtn}
                >
                  <Text style={styles.clearAllBtnText}>View plans</Text>
                </TouchableOpacity>
              </View>
            ) : (
              <View style={styles.empty}>
                <Text style={styles.emptyIcon}>👨‍⚕️</Text>
                <Text style={styles.emptyText}>No doctors found</Text>
                {hasActiveFilters ? (
                  <TouchableOpacity onPress={clearAllFilters} style={styles.clearAllBtn}>
                    <Text style={styles.clearAllBtnText}>Clear filters</Text>
                  </TouchableOpacity>
                ) : null}
              </View>
            )
          }
          renderItem={({ item }) => (
            <TouchableOpacity style={styles.card} onPress={() => setSelected(item)}>
              <View style={styles.cardTop}>
                <View style={styles.avatar}>
                  <Text style={styles.avatarText}>{getInitials(item.name)}</Text>
                </View>
                <View style={styles.cardInfo}>
                  <View style={styles.nameRow}>
                    <Text style={styles.doctorName} numberOfLines={1}>{item.name}</Text>
                    <View style={[styles.availBadge, item.available ? styles.availTrue : styles.availFalse]}>
                      <Text style={[styles.availText, item.available ? styles.availTrueText : styles.availFalseText]}>
                        {item.available ? 'Available' : 'Unavailable'}
                      </Text>
                    </View>
                  </View>
                  <Text style={styles.specialization}>{item.specialization}</Text>
                  <Text style={styles.hospital}>{item.hospital}</Text>
                  <View style={styles.ratingRow}>
                    <Text style={styles.stars}>{renderStars(item.rating)}</Text>
                    <Text style={styles.ratingText}>
                      {item.rating} · {item.experience_years} yrs exp
                    </Text>
                    {item.distance_km != null && (
                      <View style={styles.distanceBadge}>
                        <Text style={styles.distanceText}>📍 {item.distance_km} km</Text>
                      </View>
                    )}
                  </View>
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
              <View style={styles.modalAvatar}>
                <Text style={styles.modalAvatarText}>{getInitials(selected.name)}</Text>
              </View>
              <Text style={styles.modalName}>{selected.name}</Text>
              <Text style={styles.modalSpec}>{selected.specialization}</Text>
              <Text style={styles.modalStars}>{renderStars(selected.rating)} {selected.rating}</Text>

              {selected.distance_km != null && (
                <Text style={styles.modalDistance}>📍 {selected.distance_km} km away</Text>
              )}

              <View style={[
                styles.availBadge,
                selected.available ? styles.availTrue : styles.availFalse,
                { alignSelf: 'center', marginBottom: 20 },
              ]}>
                <Text style={[styles.availText, selected.available ? styles.availTrueText : styles.availFalseText]}>
                  {selected.available ? 'Currently Available' : 'Currently Unavailable'}
                </Text>
              </View>

              <View style={styles.infoCard}>
                <InfoRow label="Hospital"     value={selected.hospital} />
                <InfoRow label="Location"     value={selected.location} />
                <InfoRow label="Experience"   value={`${selected.experience_years} years`} />
                <InfoRow label="Availability" value={selected.availability} />
              </View>

              <TouchableOpacity
                style={styles.callBtn}
                onPress={() => Linking.openURL(`tel:${selected.phone}`)}
              >
                <Text style={styles.callBtnText}>📞 Call {selected.phone}</Text>
              </TouchableOpacity>

              {selected.email ? (
                <TouchableOpacity
                  style={styles.emailBtn}
                  onPress={() => Linking.openURL(`mailto:${selected.email}`)}
                >
                  <Text style={styles.emailBtnText}>✉️ Send Email</Text>
                </TouchableOpacity>
              ) : null}
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
  container:    { flex: 1, backgroundColor: '#f7f9f9' },
  header: {
    backgroundColor: TEAL,
    paddingTop: 52, paddingBottom: 16, paddingHorizontal: 20,
  },
  headerTitle:  { color: '#fff', fontSize: 16, fontWeight: '700' },
  headerSub:    { color: 'rgba(255,255,255,0.7)', fontSize: 12, marginTop: 2 },
  searchRow: {
    flexDirection: 'row', padding: 16, gap: 10,
    backgroundColor: '#fff',
    borderBottomWidth: 0.5, borderBottomColor: '#e8e8e8',
  },
  searchInput: {
    flex: 1, minHeight: 48, backgroundColor: '#F4F8F8',
    borderWidth: 1.5, borderColor: '#DCE3E3', borderRadius: 12,
    paddingHorizontal: 16, paddingVertical: 12,
    fontSize: 15, color: '#12201F',
  },
  searchBtn: {
    backgroundColor: TEAL, borderRadius: 10,
    paddingHorizontal: 16, justifyContent: 'center',
  },
  searchBtnText:  { color: '#fff', fontWeight: '600', fontSize: 14 },
  nearMeRow: {
    paddingHorizontal: 16, paddingVertical: 8,
    backgroundColor: '#fff',
    borderBottomWidth: 0.5, borderBottomColor: '#e8e8e8',
  },
  nearMeBtn: {
    alignSelf: 'flex-start',
    paddingHorizontal: 14, paddingVertical: 7,
    borderRadius: 20, borderWidth: 0.5, borderColor: TEAL,
    backgroundColor: '#fff',
  },
  nearMeBtnActive:     { backgroundColor: TEAL },
  nearMeBtnText:       { fontSize: 13, color: TEAL, fontWeight: '600' },
  nearMeBtnTextActive: { color: '#fff', fontWeight: '600', fontSize: 13 },
  filterSection: {
    backgroundColor: '#fff',
    paddingTop: 10, paddingBottom: 10,
    borderBottomWidth: 0.5, borderBottomColor: '#e8e8e8',
  },
  filterLabel: {
    fontSize: 11, fontWeight: '600', color: '#888',
    textTransform: 'uppercase', letterSpacing: 0.5,
    paddingHorizontal: 16, marginBottom: 6,
  },
  chipRow:        { paddingHorizontal: 16, gap: 8, flexDirection: 'row' },
  chip: {
    paddingHorizontal: 14, paddingVertical: 7,
    borderRadius: 20, borderWidth: 0.5, borderColor: '#ddd',
    backgroundColor: '#f7f9f9',
  },
  chipActive:     { backgroundColor: TEAL, borderColor: TEAL },
  chipText:       { fontSize: 13, color: '#555', fontWeight: '500' },
  chipTextActive: { color: '#fff', fontWeight: '600' },
  chipSkeleton:   { height: 32, backgroundColor: '#ececec', borderColor: '#ececec' },
  filterSummary: {
    flexDirection: 'row', justifyContent: 'space-between',
    alignItems: 'center', paddingHorizontal: 16, paddingVertical: 8,
    backgroundColor: 'rgba(11,110,110,0.06)',
    borderBottomWidth: 0.5, borderBottomColor: '#e0eeee',
  },
  filterSummaryText: { fontSize: 12, color: TEAL, fontWeight: '500', flex: 1 },
  clearText:      { fontSize: 12, color: TEAL, fontWeight: '700', marginLeft: 8 },
  list:           { padding: 16, gap: 12 },
  empty:          { alignItems: 'center', paddingTop: 60 },
  emptyIcon:      { fontSize: 48, marginBottom: 12 },
  emptyText:      { fontSize: 16, fontWeight: '600', color: '#1a1a1a', marginBottom: 12 },
  clearAllBtn: {
    borderWidth: 1, borderColor: TEAL, borderRadius: 8,
    paddingHorizontal: 20, paddingVertical: 8,
  },
  clearAllBtnText: { color: TEAL, fontWeight: '600', fontSize: 14 },
  card: {
    backgroundColor: '#fff', borderRadius: 14,
    padding: 16, borderWidth: 0.5, borderColor: '#e8e8e8',
  },
  cardTop:        { flexDirection: 'row', gap: 12 },
  avatar: {
    width: 52, height: 52, borderRadius: 26,
    backgroundColor: 'rgba(11,110,110,0.12)',
    alignItems: 'center', justifyContent: 'center',
  },
  avatarText:     { fontSize: 16, fontWeight: '700', color: TEAL },
  cardInfo:       { flex: 1 },
  nameRow: {
    flexDirection: 'row', justifyContent: 'space-between',
    alignItems: 'center', marginBottom: 2,
  },
  doctorName:     { fontSize: 15, fontWeight: '700', color: '#1a1a1a', flex: 1, marginRight: 6 },
  specialization: { fontSize: 13, color: TEAL, fontWeight: '600', marginBottom: 2 },
  hospital:       { fontSize: 12, color: '#888', marginBottom: 4 },
  ratingRow:      { flexDirection: 'row', alignItems: 'center', gap: 6, flexWrap: 'wrap' },
  stars:          { color: '#F4B942', fontSize: 12 },
  ratingText:     { fontSize: 12, color: '#666' },
  distanceBadge: {
    backgroundColor: 'rgba(11,110,110,0.08)',
    borderRadius: 20, paddingHorizontal: 7, paddingVertical: 2,
  },
  distanceText:   { fontSize: 11, color: TEAL, fontWeight: '600' },
  availBadge:     { paddingHorizontal: 8, paddingVertical: 3, borderRadius: 20 },
  availTrue:      { backgroundColor: '#E8F5E9' },
  availFalse:     { backgroundColor: '#FFEBEE' },
  availText:      { fontSize: 11, fontWeight: '600' },
  availTrueText:  { color: '#2E7D32' },
  availFalseText: { color: '#C62828' },
  modal:        { flex: 1, backgroundColor: '#f7f9f9' },
  modalHeader: {
    backgroundColor: TEAL,
    paddingTop: 52, paddingBottom: 16, paddingHorizontal: 20,
  },
  backBtn:        { color: '#fff', fontSize: 15, fontWeight: '600' },
  modalContent:   { padding: 20, alignItems: 'center', paddingBottom: 40 },
  modalAvatar: {
    width: 80, height: 80, borderRadius: 40,
    backgroundColor: 'rgba(11,110,110,0.12)',
    alignItems: 'center', justifyContent: 'center', marginBottom: 12,
  },
  modalAvatarText: { fontSize: 28, fontWeight: '700', color: TEAL },
  modalName:      { fontSize: 22, fontWeight: '700', color: '#1a1a1a', marginBottom: 4 },
  modalSpec:      { fontSize: 15, color: TEAL, fontWeight: '600', marginBottom: 6 },
  modalStars:     { fontSize: 16, color: '#F4B942', marginBottom: 4 },
  modalDistance:  { fontSize: 13, color: TEAL, fontWeight: '600', marginBottom: 12 },
  infoCard: {
    backgroundColor: '#fff', borderRadius: 12, padding: 16,
    width: '100%', borderWidth: 0.5, borderColor: '#e8e8e8', marginBottom: 16,
  },
  infoRow: {
    flexDirection: 'row', justifyContent: 'space-between',
    paddingVertical: 8, borderBottomWidth: 0.5, borderBottomColor: '#f0f0f0',
  },
  infoLabel:    { fontSize: 13, color: '#888' },
  infoValue:    { fontSize: 13, color: '#1a1a1a', fontWeight: '500', flex: 1, textAlign: 'right' },
  callBtn: {
    backgroundColor: TEAL, borderRadius: 10, paddingVertical: 13,
    alignItems: 'center', width: '100%', marginBottom: 10,
  },
  callBtnText:  { color: '#fff', fontSize: 15, fontWeight: '600' },
  emailBtn: {
    backgroundColor: '#fff', borderRadius: 10, paddingVertical: 13,
    alignItems: 'center', width: '100%', borderWidth: 0.5, borderColor: '#ddd',
  },
  emailBtnText: { color: '#555', fontSize: 15, fontWeight: '600' },
});
