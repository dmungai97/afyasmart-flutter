import AsyncStorage from "@react-native-async-storage/async-storage";
import { functionsBaseUrl, getAccessToken } from "./supabase";
import { useAuthStore } from "../store/authStore";

// The three-way branch between Firebase Functions, Supabase Functions and a
// hardcoded fallback URL is gone — there is one backend, and the path shapes
// ("/mpesa/initiate", "/mpesa/status") are what the edge function already
// serves, so no path remapping is needed either.

const checkoutPlans = new Map<string, string>();
const lastCheckoutKey = "mpesa_last_checkout_request_id";

const checkoutPlanKey = (checkoutRequestId: string) =>
  `mpesa_checkout_plan:${checkoutRequestId}`;

const requestMpesaBackend = async <T>(
  path: string,
  body: Record<string, unknown>,
  token: string | null,
): Promise<T> => {
  const accessToken = token ?? (await getAccessToken());

  const response = await fetch(`${functionsBaseUrl}${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
    },
    // The caller's identity comes from the verified access token alone.
    body: JSON.stringify(body),
  });

  const data = await response.json().catch(() => null);

  if (!response.ok) {
    throw new Error(data?.message ?? "M-Pesa request failed.");
  }

  return data as T;
};

export const initiateMpesa = async (
  token: string | null,
  phone: string,
  plan: string,
): Promise<{ checkout_request_id: string }> => {
  const data = await requestMpesaBackend<{ checkout_request_id: string }>(
    "/mpesa/initiate",
    { phone, plan },
    token,
  );

  checkoutPlans.set(data.checkout_request_id, plan);
  await AsyncStorage.setItem(lastCheckoutKey, data.checkout_request_id);
  await AsyncStorage.setItem(checkoutPlanKey(data.checkout_request_id), plan);

  return data;
};

export const pollMpesaStatus = async (
  token: string | null,
  checkoutRequestId: string,
): Promise<{ paid: boolean; status: string; message?: string }> => {
  const data = await requestMpesaBackend<{ paid: boolean; status: string; message?: string }>(
    "/mpesa/status",
    { checkout_request_id: checkoutRequestId },
    token,
  );

  if (data.paid) {
    const plan =
      checkoutPlans.get(checkoutRequestId) ??
      (await AsyncStorage.getItem(checkoutPlanKey(checkoutRequestId)));

    // Subscription activation always happens server-side, verified against
    // the actual M-Pesa result — just pull the fresh users row into local
    // state. A client-side fallback here would let anyone grant themselves a
    // subscription without paying; the column grants in the RLS migration
    // block it too, but this is intentionally not attempted at all.
    await useAuthStore.getState().refreshUser(token ?? "");

    if (plan) {
      checkoutPlans.delete(checkoutRequestId);
      await AsyncStorage.removeItem(lastCheckoutKey);
      await AsyncStorage.removeItem(checkoutPlanKey(checkoutRequestId));
    }
  }

  return data;
};

export const checkLatestMpesaPayment = async (
  token: string | null,
): Promise<{ paid: boolean; status: string; checkout_request_id: string; message?: string } | null> => {
  const checkoutRequestId = await AsyncStorage.getItem(lastCheckoutKey);
  if (!checkoutRequestId) return null;

  const result = await pollMpesaStatus(token, checkoutRequestId);
  return { ...result, checkout_request_id: checkoutRequestId };
};
