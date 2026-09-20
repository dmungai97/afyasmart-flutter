import { supabase, PaywallError } from "./supabase";
import { getCurrentUserProfile } from "./auth.service";
import { isSubscriptionActive } from "./subscription.model";

const mapDrug = (data: any, index = 0) => ({
  id: Number(data.id ?? index + 1),
  name: data.name ?? "",
  generic_name: data.generic_name ?? "",
  category: data.category ?? "Other",
  uses: data.uses ?? "",
  dosage: data.dosage ?? "",
  side_effects: data.side_effects ?? "",
  pregnancy_safe: Boolean(data.pregnancy_safe),
  alcohol_safe: Boolean(data.alcohol_safe),
  lactation_safe: Boolean(data.lactation_safe),
  prescription_required: data.prescription_required ?? "Yes",
});

// See the note on requireSubscription() in doctor.service.ts.
const requireSubscription = async () => {
  const user = await getCurrentUserProfile();
  if (!isSubscriptionActive(user)) throw new PaywallError();
};

export const searchDrugs = async (query: string, token: string) => {
  void token;
  await requireSubscription();

  // This used to fetch every drug and filter in JS. search_drugs() runs the
  // same match server-side against a GIN index, and is not security definer,
  // so the paywall policy still applies to its results.
  const { data, error } = await supabase.rpc("search_drugs", { q: query ?? "" });
  if (error) throw new Error(error.message);

  const drugs = (data ?? []).map((item: any, index: number) => mapDrug(item, index));
  return { status: "success", count: drugs.length, data: drugs };
};

export const getDrug = async (id: number, token: string) => {
  void token;
  await requireSubscription();

  const { data, error } = await supabase
    .from("drugs")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (error) throw new Error(error.message);
  if (!data) throw new Error("Drug not found.");

  return { status: "success", data: mapDrug(data) };
};
