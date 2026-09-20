import { supabase, PaywallError } from "./supabase";
import { getCurrentUserProfile } from "./auth.service";
import { isSubscriptionActive } from "./subscription.model";

const seededPharmacies = require("../../seed-data/pharmacies.json") as any[];

const mapPharmacy = (data: any, index = 0) => ({
  id: Number(data.id ?? index + 1),
  name: data.name ?? "",
  location: data.location ?? "",
  address: data.address ?? "",
  phone: data.phone ?? "",
  email: data.email ?? null,
  latitude: Number(data.latitude ?? 0),
  longitude: Number(data.longitude ?? 0),
  opening_hours: data.opening_hours ?? "",
  open_24hrs: Boolean(data.open_24hrs),
  open: Boolean(data.open),
});

// Local-only, unauthenticated pharmacy list — used by screens (e.g. the map)
// that intentionally show generic seeded data to everyone regardless of
// subscription. Never route this through anything that also serves the
// paywalled directory (getPharmacies below).
export const fetchSeededPharmacies = () =>
  seededPharmacies.map((item, index) => mapPharmacy({ ...item, id: index + 1 }, index));

// See the long note on requireSubscription() in doctor.service.ts: RLS
// filters rather than rejects, so an unsubscribed read returns zero rows
// instead of an error. Without this explicit check the seed-data fallback
// below would serve the paywalled directory to everyone.
const requireSubscription = async () => {
  const user = await getCurrentUserProfile();
  if (!isSubscriptionActive(user)) throw new PaywallError();
};

export const getPharmacies = async (token: string, search?: string) => {
  void token;
  await requireSubscription();

  let query = supabase.from("pharmacies").select("*");

  if (search?.trim()) {
    const term = `%${search.trim()}%`;
    query = query.or(`name.ilike.${term},location.ilike.${term},address.ilike.${term}`);
  }

  const { data, error } = await query;
  if (error) throw new Error(error.message);

  const pharmacies = (data ?? []).map((item, index) => mapPharmacy(item, index));

  return { status: "success", count: pharmacies.length, data: pharmacies };
};
