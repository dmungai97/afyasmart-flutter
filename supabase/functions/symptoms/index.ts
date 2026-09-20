// symptomsAnalyze/symptomsClarify, backed by Supabase Auth + Postgres.
//
// Both routes remain deliberately unauthenticated: onboarding lets a guest
// check symptoms before an account exists, identifying itself by a
// client-generated id. See requestSymptomsAnalysis/requestSymptomsClarification
// in src/services/symptoms.service.ts.
//
// That is exactly why the daily quota exists — without it, anyone could call
// these with an arbitrary id and run up unbounded OpenAI cost. The quota is
// now a single atomic consume_symptom_quota() call rather than a read,
// compare, then write: two concurrent requests previously both read the same
// count and both proceeded, so the limit could be overrun.
//
// verify_jwt is OFF at deploy time, since no Authorization header is sent.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { adminClient } from "../_shared/supabase.ts";
import { json, preflight } from "../_shared/http.ts";
import { SYMPTOM_FREE_DAILY_LIMIT, isSubscribed } from "../_shared/subscription.ts";

// deno-lint-ignore no-explicit-any
function mockSymptomsResponse(): any {
  return {
    urgency: "High",
    urgency_desc: "Your symptoms may need medical attention. Seek advice from a professional.",
    conditions: [
      { name: "Malaria", likelihood: "High", percent: 80, color: "#EF4444" },
      { name: "Flu (Influenza)", likelihood: "Medium", percent: 45, color: "#F59E0B" },
      { name: "Typhoid", likelihood: "Low", percent: 20, color: "#0B6E6E" },
    ],
    medications: [
      { name: "Paracetamol 500mg", desc: "For fever and pain", icon: "💊" },
      { name: "ORS", desc: "To prevent dehydration", icon: "🧃" },
      { name: "Antimalarial", desc: "Seek doctor's advice first", icon: "💉" },
    ],
    self_care: [
      "Rest and drink plenty of fluids",
      "Take paracetamol for fever",
      "Eat light and healthy meals",
    ],
  };
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Looks up the subject's subscription state.
 *
 * A subject is either a signed-in user's uuid or a client-generated guest id.
 * A guest has no account, so anything that is not a uuid resolves to null and
 * is treated as unsubscribed — which is what puts it under the daily quota.
 */
// deno-lint-ignore no-explicit-any
async function loadSubject(subjectId: string): Promise<Record<string, any> | null> {
  if (!UUID_RE.test(subjectId)) return null;

  const supabase = adminClient();
  const { data, error } = await supabase
    .from("users")
    .select("is_subscribed, has_subscribed, subscription_plan, subscription_expires_at")
    .eq("id", subjectId)
    .maybeSingle();

  if (error) {
    console.error("Could not load symptom subject", error);
    return null;
  }
  return data;
}

/** Returns true when the call is within quota (and has been counted). */
async function withinQuota(
  subjectId: string,
  kind: "analyze" | "clarify",
  limit: number,
): Promise<boolean> {
  const supabase = adminClient();
  const { data, error } = await supabase.rpc("consume_symptom_quota", {
    p_subject_id: subjectId,
    p_kind: kind,
    p_limit: limit,
  });

  if (error) {
    // Fail closed. The whole point of this quota is cost control, so an
    // unavailable quota table must not become an open door.
    console.error("consume_symptom_quota failed", error);
    return false;
  }
  return data === true;
}

const ANALYZE_SYSTEM_PROMPT =
  'You are a professional medical analysis assistant. Your role is to suggest possible conditions based on symptoms.\n' +
  'You must return a raw JSON response representing the diagnosis.\n\n' +
  'JSON SCHEMA:\n' +
  '{\n' +
  '  "urgency": "High" | "Medium" | "Low",\n' +
  '  "urgency_desc": "Explanation of urgency based on symptoms.",\n' +
  '  "conditions": [\n' +
  '    { "name": "Condition Name", "likelihood": "High" | "Medium" | "Low", "percent": integer_between_0_and_100, "color": "#EF4444" for High | "#F59E0B" for Medium | "#0B6E6E" for Low }\n' +
  '  ],\n' +
  '  "medications": [\n' +
  '    { "name": "Medication Name", "desc": "Short description of what it does", "icon": "💊" | "🧃" | "💉" }\n' +
  '  ],\n' +
  '  "self_care": [\n' +
  '    "Actionable advice line 1",\n' +
  '    "Actionable advice line 2"\n' +
  '  ]\n' +
  '}\n' +
  'IMPORTANT — calibrate to how much detail you actually have: if the ' +
  'symptom description and any follow-up answers are vague, minimal, or ' +
  'just a few words with no specifics (location, sensation, triggers, ' +
  'etc.), you MUST use noticeably lower percent values (all under 40) and ' +
  'make urgency_desc explicitly say the input was too limited for a ' +
  'confident read, encouraging the user to describe their symptoms in ' +
  'more detail. Never present specific-sounding conditions or ' +
  'medications with high confidence when the underlying description is ' +
  'this thin.\n' +
  'Do not include any text, backticks, or wrapping outside the JSON object.';

const CLARIFY_SYSTEM_PROMPT =
  "You are a medical intake assistant narrowing down a symptom description " +
  "before a doctor-style analysis. Return raw JSON only, no other text.\n\n" +
  "JSON SCHEMA:\n" +
  "{\n" +
  '  "done": boolean,\n' +
  '  "question": "short clarifying question, present only if done is false",\n' +
  '  "options": ["3 to 4 short tappable answers, present only if done is false"],\n' +
  "  \"duration\": \"best estimate of how long the symptom has lasted, one of " +
  "'Today', '1-3 days', '4-7 days', 'Longer than a week', or 'Not specified' if " +
  "unclear — always present regardless of done\"\n" +
  "}\n" +
  "Keep questions and options under 6 words each. Never ask about gender — that " +
  "is collected separately.";

// deno-lint-ignore no-explicit-any
async function askOpenAI(systemPrompt: string, userPrompt: string, maxTokens: number, temperature: number): Promise<any> {
  const openaiKey = Deno.env.get("OPENAI_API_KEY");
  if (!openaiKey) return null;

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${openaiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      max_tokens: maxTokens,
      temperature,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
    }),
  });

  if (!response.ok) {
    console.error("OpenAI request failed", { status: response.status });
    return null;
  }

  const data = await response.json();
  return JSON.parse(data.choices?.[0]?.message?.content || "null");
}

async function handleAnalyze(req: Request): Promise<Response> {
  try {
    if (req.method !== "POST") {
      return json({ status: "error", message: "Method not allowed" }, 405);
    }

    const body = await req.json().catch(() => ({}));
    const { symptoms, age, gender, duration, severity, answers } = body;
    const subjectId = body.subject_id;

    if (
      !subjectId ||
      typeof subjectId !== "string" ||
      !Array.isArray(symptoms) ||
      symptoms.length === 0 ||
      age === undefined ||
      age === null ||
      !gender ||
      !duration ||
      !severity
    ) {
      return json({ status: "error", message: "Missing required fields." }, 422);
    }

    if (!isSubscribed(await loadSubject(subjectId))) {
      if (!(await withinQuota(subjectId, "analyze", SYMPTOM_FREE_DAILY_LIMIT))) {
        return json(
          {
            status: "error",
            message: "Daily free check limit reached. Subscribe for unlimited checks.",
          },
          429,
        );
      }
    }

    let answersText = "";
    if (answers && typeof answers === "object") {
      for (const [qId, ans] of Object.entries(answers)) {
        answersText += `- Question ID ${qId}: Answer: ${ans}\n`;
      }
    }

    const prompt =
      "Analyze the following patient profile and symptom context:\n" +
      `- Symptoms: ${symptoms.join(", ")}\n` +
      `- Age: ${age} years old\n` +
      `- Gender: ${gender}\n` +
      `- Duration: ${duration}\n` +
      `- Severity: ${severity}\n` +
      (answersText ? `- Follow-up Questions:\n${answersText}` : "") +
      "\nBased on this information, provide the top 3 possible medical conditions (with likelihood and probability percentage), self-care instructions, and commonly suggested medications/remedies.";

    const result = await askOpenAI(ANALYZE_SYSTEM_PROMPT, prompt, 1020, 0.3);

    if (!result || !result.conditions) {
      return json({ status: "success", data: mockSymptomsResponse() });
    }
    return json({ status: "success", data: result });
  } catch (error) {
    // Onboarding must never dead-end on a backend problem, so every failure
    // degrades to the mock result rather than an error screen.
    console.error("symptomsAnalyze failed", error);
    return json({ status: "success", data: mockSymptomsResponse() });
  }
}

async function handleClarify(req: Request): Promise<Response> {
  try {
    if (req.method !== "POST") {
      return json({ status: "error", message: "Method not allowed" }, 405);
    }

    const body = await req.json().catch(() => ({}));
    const { symptom, age, severity, history } = body;
    const subjectId = body.subject_id;

    if (!subjectId || typeof subjectId !== "string" || !symptom || typeof symptom !== "string") {
      return json({ status: "error", message: "Missing required fields." }, 422);
    }

    const priorQA = Array.isArray(history) ? history.slice(0, 2) : [];
    if (priorQA.length >= 2) {
      return json({ status: "success", data: { done: true } });
    }

    // Twice the analyze limit, since one analysis can involve up to two
    // clarify round-trips.
    if (!isSubscribed(await loadSubject(subjectId))) {
      if (!(await withinQuota(subjectId, "clarify", SYMPTOM_FREE_DAILY_LIMIT * 2))) {
        return json({ status: "success", data: { done: true } });
      }
    }

    const historyText = priorQA.length
      ? priorQA
          .map(
            (qa: { question: string; answer: string }, i: number) =>
              `Q${i + 1}: ${qa.question}\nA${i + 1}: ${qa.answer}`,
          )
          .join("\n")
      : "(none yet)";

    const prompt =
      "A patient described this symptom during intake:\n" +
      `"${symptom}"\n\n` +
      `Age: ${age ?? "unknown"}, self-reported severity: ${severity ?? "unknown"}\n\n` +
      `Follow-up questions already asked this session:\n${historyText}\n\n` +
      "Decide if ONE more short clarifying question would meaningfully help a doctor " +
      "(e.g. specific location, what makes it better or worse, associated symptoms, how " +
      "long it's lasted). If you already have enough to proceed, stop.";

    const result = await askOpenAI(CLARIFY_SYSTEM_PROMPT, prompt, 300, 0.4);

    if (!result || typeof result.done !== "boolean") {
      return json({ status: "success", data: { done: true } });
    }

    if (!result.done && (!result.question || !Array.isArray(result.options) || result.options.length === 0)) {
      return json({ status: "success", data: { done: true, duration: result.duration } });
    }

    return json({ status: "success", data: result });
  } catch (error) {
    console.error("symptomsClarify failed", error);
    return json({ status: "success", data: { done: true } });
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();

  const path = new URL(req.url).pathname;

  if (path.endsWith("/analyze")) return await handleAnalyze(req);
  if (path.endsWith("/clarify")) return await handleClarify(req);
  return json({ status: "error", message: "Not found" }, 404);
});
