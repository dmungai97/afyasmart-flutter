import AsyncStorage from "@react-native-async-storage/async-storage";
import { functionsBaseUrl, getCurrentUserId } from "./supabase";

export interface SymptomsAnalysisRequest {
  symptoms: string[];
  age: number;
  gender: string;
  duration: string;
  severity: string;
  answers: Record<string, string>;
}

export interface ConditionResult {
  name: string;
  likelihood: "High" | "Medium" | "Low";
  percent: number;
  color: string;
}

export interface MedicationResult {
  name: string;
  desc: string;
  icon: string;
}

export interface SymptomsAnalysisResponse {
  urgency: "High" | "Medium" | "Low";
  urgency_desc: string;
  conditions: ConditionResult[];
  medications: MedicationResult[];
  self_care: string[];
}

export interface SymptomsClarifyResponse {
  done: boolean;
  question?: string;
  options?: string[];
  duration?: string;
}

// Onboarding lets users check symptoms before creating an account, so these
// endpoints identify the caller by a locally persisted guest id rather than
// requiring a session.
const resolveSubjectId = async (): Promise<string> => {
  const existing = await getCurrentUserId();
  if (existing) return existing;

  const guestUuid = await AsyncStorage.getItem("guest_uuid");
  if (guestUuid) return guestUuid;

  const generated = `guest_${Math.random().toString(36).substring(2, 11)}_${Date.now()}`;
  await AsyncStorage.setItem("guest_uuid", generated);
  return generated;
};

export const requestSymptomsAnalysis = async (
  input: SymptomsAnalysisRequest,
): Promise<SymptomsAnalysisResponse> => {
  const subjectId = await resolveSubjectId();

  const response = await fetch(`${functionsBaseUrl}/symptoms/analyze`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ ...input, subject_id: subjectId }),
  });

  const body = await response.json().catch(() => null);

  if (!response.ok) {
    throw new Error(body?.message ?? "Failed to analyze symptoms. Please try again.");
  }

  if (body?.status === "success" && body?.data) {
    return body.data as SymptomsAnalysisResponse;
  }

  throw new Error("Invalid response format received from the server.");
};

// Best-effort — fails safe to `{ done: true }` on any error so a flaky or
// unreachable endpoint never blocks the onboarding funnel. Callers
// should treat a missing `duration` on a `done: true` result as
// "clarification wasn't available", not "the user has no symptom duration".
export const requestSymptomsClarification = async (params: {
  symptom: string;
  age: number;
  severity: string;
  history: { question: string; answer: string }[];
}): Promise<SymptomsClarifyResponse> => {
  try {
    const subjectId = await resolveSubjectId();

    const response = await fetch(`${functionsBaseUrl}/symptoms/clarify`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ subject_id: subjectId, ...params }),
    });

    const body = await response.json().catch(() => null);

    if (!response.ok || body?.status !== "success" || !body?.data) {
      return { done: true };
    }

    return body.data as SymptomsClarifyResponse;
  } catch {
    return { done: true };
  }
};
