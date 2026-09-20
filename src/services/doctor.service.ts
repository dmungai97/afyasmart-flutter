import { supabase, PaywallError } from "./supabase";
import { getCurrentUserProfile } from "./auth.service";
import { isSubscriptionActive } from "./subscription.model";

const seededDoctors = require("../../seed-data/doctors.json") as any[];

export interface Doctor {
  id: number;
  name: string;
  specialization: string;
  hospital: string;
  location: string;
  region?: string;
  phone: string;
  email: string;
  latitude: number;
  longitude: number;
  experience_years: number;
  rating: number;
  availability: string;
  available: boolean;
  distance_km?: number;
}

export interface DoctorsResponse {
  status: string;
  count: number;
  data: Doctor[];
}

export interface ListResponse {
  status: string;
  data: string[];
}

const distanceKm = (lat1: number, lon1: number, lat2: number, lon2: number) => {
  const toRad = (value: number) => (value * Math.PI) / 180;
  const radius = 6371;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return radius * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
};

const mapDoctor = (data: any, index = 0): Doctor => ({
  // Postgres ids are already numbers, so the numericId() coercion the
  // Firestore document ids needed is gone. Seed rows still index from 1.
  id: Number(data.id ?? index + 1),
  name: data.name ?? "",
  specialization: data.specialization ?? "",
  hospital: data.hospital ?? "",
  location: data.location ?? "",
  region: data.region ?? undefined,
  phone: data.phone ?? "",
  email: data.email ?? "",
  latitude: Number(data.latitude ?? 0),
  longitude: Number(data.longitude ?? 0),
  experience_years: Number(data.experience_years ?? 0),
  rating: Number(data.rating ?? 0),
  availability: data.availability ?? "",
  available: Boolean(data.available),
});

/**
 * The paywall gate.
 *
 * Firestore rules REJECTED an unauthorised read, so these services could
 * detect `permission-denied` and let it propagate past the seed-data
 * fallback. Postgres RLS does not reject — it filters, so a non-subscriber's
 * query succeeds and returns zero rows, which is indistinguishable from an
 * empty table. Falling back to seed data on empty would therefore hand the
 * full directory to everyone.
 *
 * So the check is explicit and happens first. `doctors_select` in the RLS
 * migration still enforces it server-side; this only makes the client fail
 * the same way it used to.
 */
const requireSubscription = async () => {
  const user = await getCurrentUserProfile();
  if (!isSubscriptionActive(user)) throw new PaywallError();
};

// Local-only, unauthenticated doctor list — used by screens (e.g. the map)
// that intentionally show generic seeded data to everyone regardless of
// subscription. Never route this through anything that also serves the
// paywalled directory (fetchNearbyDoctors below).
export const fetchSeededDoctors = (): Doctor[] =>
  seededDoctors.map((item, index) => mapDoctor({ ...item, id: index + 1 }, index));

export const fetchNearbyDoctors = async (
  token: string,
  options?: {
    specialization?: string;
    search?: string;
    available?: boolean;
    region?: string;
    lat?: number;
    lng?: number;
    radius?: number;
  },
): Promise<DoctorsResponse> => {
  void token;
  await requireSubscription();

  // Filtering that used to happen in JS over every document now runs in the
  // query. Only the distance sort stays client-side.
  let query = supabase.from("doctors").select("*");

  if (options?.available !== undefined) query = query.eq("available", options.available);
  if (options?.region) query = query.ilike("region", options.region.trim());
  if (options?.specialization) {
    query = query.ilike("specialization", options.specialization.trim());
  }
  if (options?.search) {
    const term = `%${options.search.trim()}%`;
    query = query.or(
      `name.ilike.${term},specialization.ilike.${term},` +
        `hospital.ilike.${term},location.ilike.${term},region.ilike.${term}`,
    );
  }

  const { data, error } = await query;
  if (error) throw new Error(error.message);

  let doctors = (data ?? []).map((item, index) => mapDoctor(item, index));

  if (options?.lat != null && options?.lng != null) {
    doctors = doctors
      .map((doctor) => ({
        ...doctor,
        distance_km: Number(
          distanceKm(options.lat!, options.lng!, doctor.latitude, doctor.longitude).toFixed(1),
        ),
      }))
      .filter(
        (doctor) => options.radius == null || (doctor.distance_km ?? Infinity) <= options.radius,
      )
      .sort((a, b) => (a.distance_km ?? 0) - (b.distance_km ?? 0));
  }

  return { status: "success", count: doctors.length, data: doctors };
};

export const fetchDoctor = async (id: number, token: string): Promise<Doctor> => {
  void token;
  await requireSubscription();

  const { data, error } = await supabase
    .from("doctors")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (error) throw new Error(error.message);
  if (!data) throw new Error("Doctor not found.");

  return mapDoctor(data);
};

/**
 * Distinct region/specialization lists.
 *
 * These deliberately do NOT require a subscription: they populate the filter
 * chips on the doctors screen, which renders (behind the paywall) before any
 * directory data is fetched. They read from the bundled seed data rather than
 * the database, because RLS would return an empty list to exactly the
 * non-subscribers who need the chips rendered.
 */
const seededValues = (field: "region" | "specialization"): string[] => {
  const values = new Set<string>();
  seededDoctors.forEach((item) => {
    const value = item[field];
    if (value) {
      values.add(
        field === "region" ? value.charAt(0).toUpperCase() + value.slice(1) : value,
      );
    }
  });
  return [...values].sort();
};

export const fetchRegions = async (token: string): Promise<string[]> => {
  void token;
  const { data, error } = await supabase.from("doctors").select("region");
  if (error || !data?.length) return seededValues("region");

  const regions = new Set<string>();
  data.forEach((item: { region: string | null }) => {
    if (item.region) regions.add(item.region.charAt(0).toUpperCase() + item.region.slice(1));
  });
  return regions.size > 0 ? [...regions].sort() : seededValues("region");
};

export const fetchSpecializations = async (token: string): Promise<string[]> => {
  void token;
  const { data, error } = await supabase.from("doctors").select("specialization");
  if (error || !data?.length) return seededValues("specialization");

  const specializations = new Set<string>();
  data.forEach((item: { specialization: string | null }) => {
    if (item.specialization) specializations.add(item.specialization);
  });
  return specializations.size > 0
    ? [...specializations].sort()
    : seededValues("specialization");
};
