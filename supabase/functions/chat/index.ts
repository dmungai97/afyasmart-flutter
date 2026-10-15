import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { adminClient, requireUser, getAppUser, AuthError } from "../_shared/supabase.ts";
import { json, preflight } from "../_shared/http.ts";
import { FREE_CHAT_LIMIT, isSubscribed, canUseFreeChats } from "../_shared/subscription.ts";

function mockReply(message: string): string {
  const text = message.toLowerCase();

  if (
    text.includes("calorie") ||
    text.includes("diet") ||
    text.includes("nutrition") ||
    text.includes("meal")
  ) {
    return "In a Kenyan context, a healthy calorie deficit involves balancing staples: reduce portion size of ugali or rice, fill half your plate with traditional greens like **sukuma wiki**, **managu**, or **terere**, and include lean protein like **ndengu** (green grams), **beans**, or **grilled tilapia**.";
  }
  if (text.includes("headache")) {
    return "Headaches can be caused by dehydration, stress, or lack of sleep. Try drinking water and resting. If it persists, consult a doctor.";
  }
  if (text.includes("fever")) {
    return "A fever above 38°C may indicate infection. Rest, stay hydrated, and seek medical attention if it exceeds 39.5°C or lasts more than 3 days.";
  }
  // Whole words: a bare includes("hi") also matched "this", "which", "high".
  if (/\b(hello|hi|hey|habari|jambo)\b/.test(text)) {
    return "Hello! I am AfyaSmart AI. How can I help you with your health question today?";
  }
  return "Thank you for your question. For accurate medical advice, please consult a licensed healthcare provider.";
}

const SYSTEM_PROMPT = [
  "You are AfyaSmart AI, a health assistant for people in Kenya. Talk like a knowledgeable, caring clinician who has time for the patient: specific, practical and warm, never a pamphlet.",
  "",
  "HOW TO HELP:",
  "- Answer about this person, not people in general. Use what you know about them: their symptom check below and what they said earlier in this chat. Refer back to those details by name (\"since your headache started 3 days ago...\").",
  "- When the answer depends on something you do not know (how long, how bad, where exactly, what makes it worse, pregnancy, other conditions, medicines already taken), ask ONE short, targeted question instead of listing every possibility.",
  "- Give concrete next steps: what to do now, what to watch for, and the specific signs that mean they should see a doctor and how soon. Name medicines by generic name with ordinary adult dosing from the label when it is appropriate for over-the-counter use, and say when a medicine needs a prescription or a test first (for example, antimalarials need a malaria test).",
  "- Use local context where it helps: common conditions in Kenya (malaria, typhoid, UTIs, amoebiasis), local foods, and where to go (a pharmacy, a clinic, a level 4/5 hospital).",
  "- Do not open with filler (\"Great question\", \"I understand your concern\") and do not end every reply with \"consult a doctor\". Say it once, specifically, when it actually applies.",
  "",
  "SCOPE:",
  "- Health, symptoms, medicines, nutrition, fitness, mental wellbeing, and finding care in Kenya. Greetings and small talk are fine.",
  "- For clearly unrelated requests (coding, homework, politics, stocks), say briefly that you can only help with health questions, and offer to help with one.",
].join("\n");

// Checked before anything else the model says. A health assistant that
// answers "crushing chest pain" with hydration tips is the failure that
// matters most, so the escalation is spelled out rather than left to the
// model's judgement.
const EMERGENCY_RULES = [
  "",
  "",
  "EMERGENCIES (this rule overrides every other rule, including formatting):",
  "- If the user describes any possible emergency, your FIRST sentence must tell them to call **999 or 112** now or go to the nearest hospital, before any other advice. Do not soften or delay this.",
  "- Treat as emergencies: chest pain or pressure; difficulty breathing; signs of stroke (face drooping, arm weakness, slurred speech); fainting or unresponsiveness; seizures; heavy bleeding; severe allergic reaction or swelling of the face or throat; severe burns; head injury with confusion or vomiting; poisoning or overdose; a very high fever with a stiff neck, confusion or a rash that does not fade; a baby or young child who is very drowsy, not feeding or struggling to breathe; and in pregnancy, heavy bleeding, severe abdominal pain, severe headache with blurred vision, or the baby moving much less.",
  "- If the user mentions suicide, self-harm, or wanting to die, respond with care, urge them to reach someone now, and give the **Kenya Red Cross free helpline 1199** and emergency **999 / 112**. Encourage them to contact someone they trust.",
  "- Never tell someone with emergency symptoms to wait and see, and never diagnose them with certainty.",
].join("\n");

// Formatting and context rules, appended to SYSTEM_PROMPT. The app renders
// **bold** and "- " / "1. " lists and nothing else, so anything richer would
// show up as raw symbols.
const STYLE_RULES = [
  "",
  "",
  "CONVERSATION CONTEXT:",
  '- The earlier messages in this conversation are real; use them. When the user says "it", "that" or "the pain", resolve it from what they said before, or from their symptom check, rather than asking again.',
  "- Do not repeat advice you already gave unless asked; build on it.",
  "",
  "FORMATTING:",
  "- Keep replies conversational and focused: a few sentences for simple questions, a short list when there are steps or warning signs. Do not pad.",
  '- You may use **bold** for key terms and lines starting with "- " or "1. " for lists. Do not use headings (#), tables, links or code blocks.',
].join("\n");

// How much stored conversation goes to the model. Messages are the unit, but
// a character budget stops a few very long replies from crowding out the rest.
const HISTORY_MESSAGES = 20;
const HISTORY_CHAR_BUDGET = 12000;

type Turn = { role: "user" | "ai"; text: string };

/**
 * The conversation as stored, oldest first, within the budget.
 *
 * Read from chat_messages rather than taken from the request body: the app's
 * own list includes things the model never said (the canned greeting, local
 * "could not process" errors), and a client-supplied history is not something
 * to feed a model unchecked anyway.
 */
// deno-lint-ignore no-explicit-any
async function loadHistory(db: any, userId: string): Promise<Turn[]> {
  const { data, error } = await db
    .from("chat_messages")
    .select("role, text")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(HISTORY_MESSAGES);

  if (error) {
    console.error("Could not load chat history", error);
    return [];
  }

  const turns: Turn[] = [];
  let used = 0;
  for (const row of data ?? []) {
    const text = String(row.text ?? "");
    if (!text) continue;
    if (used + text.length > HISTORY_CHAR_BUDGET) break;
    used += text.length;
    turns.push({ role: row.role === "ai" ? "ai" : "user", text });
  }
  return turns.reverse();
}

// How far back a symptom check still counts as "the thing they are asking
// about". Older checks are history, not context.
const DIAGNOSIS_MAX_AGE_DAYS = 7;

type Diagnosis = {
  symptoms: string;
  summary: string;
  urgency: string;
  conditions: { name?: string; probability?: number; level?: string }[];
  medications: { name?: string; note?: string }[];
  created_at: string;
};

/** The user's most recent symptom check, if it is recent enough to matter. */
// deno-lint-ignore no-explicit-any
async function loadLatestDiagnosis(db: any, userId: string): Promise<Diagnosis | null> {
  const since = new Date(Date.now() - DIAGNOSIS_MAX_AGE_DAYS * 86400000).toISOString();
  const { data, error } = await db
    .from("diagnoses")
    .select("symptoms, summary, urgency, conditions, medications, created_at")
    .eq("user_id", userId)
    .gte("created_at", since)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) {
    console.error("Could not load latest diagnosis", error);
    return null;
  }
  return data;
}

/**
 * The symptom check as the model should see it. Without this, "Continue AI
 * chat" from the results screen opened a conversation that knew nothing
 * about the results, so every answer was generic.
 */
function diagnosisNote(d: Diagnosis | null): string {
  if (!d) return "";

  const when = new Date(d.created_at).toLocaleString("en-KE", {
    weekday: "long",
    day: "numeric",
    month: "long",
    hour: "numeric",
    minute: "2-digit",
    timeZone: "Africa/Nairobi",
  });
  const conditions = (Array.isArray(d.conditions) ? d.conditions : [])
    .filter((c) => c?.name)
    .map((c) => `  - ${c.name}: ${c.level ?? "?"} likelihood (${c.probability ?? "?"}%)`)
    .join("\n");
  const medications = (Array.isArray(d.medications) ? d.medications : [])
    .filter((m) => m?.name)
    .map((m) => `  - ${m.name}${m.note ? `: ${m.note}` : ""}`)
    .join("\n");

  return (
    `\n\nTHE USER'S LATEST SYMPTOM CHECK (${when}):\n` +
    `- What they reported: ${d.symptoms || "not recorded"}\n` +
    `- Urgency given: ${d.urgency}${d.summary ? ` (${d.summary})` : ""}\n` +
    (conditions ? `- Possible conditions suggested:\n${conditions}\n` : "") +
    (medications ? `- Medicines and remedies suggested:\n${medications}\n` : "") +
    "- They can see these results in the app. Unless they clearly change the subject, assume their questions are about this check. " +
    "These were automated suggestions, not a diagnosis: build on them, but correct them if what the user tells you now points elsewhere, " +
    "and if the urgency was High or their symptoms sound worse now, say plainly that they should be seen today."
  );
}

function contextNote(user?: Record<string, any> | null): string {
  const today = new Date().toLocaleDateString("en-KE", {
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
    timeZone: "Africa/Nairobi",
  });
  const name =
    user?.name && user.name !== "AfyaSmart User" ? user.name : "Patient";
  const plan = user?.subscription_plan
    ? `- Membership Plan: ${user.subscription_plan}.\n`
    : "";

  return (
    "\n\nUSER & SESSION CONTEXT:\n" +
    `- Patient Name: ${name}\n` +
    `- Today's Date: ${today}\n` +
    `- Location: Kenya (East Africa). Currency: Ksh / KES. Emergency: 999 or 112.\n` +
    plan +
    "- Multilingual Capabilities: Fluently comprehend and respond in English, Swahili, or Sheng based on the user's input.\n" +
    "- Local Medical & Dietary Knowledge: Understand Kenyan dietary staples (ugali, sukuma wiki, managu, terere, ndengu, githeri, chapati, tilapia, mukimo, cassava) and local healthcare practices."
  );
}

/** The model could not produce a reply. Nothing is recorded for the turn. */
class ReplyError extends Error {}

/**
 * The model's reply.
 *
 * Throws [ReplyError] on failure rather than returning an apology string:
 * an apology returned here used to be stored as a real exchange, spending
 * one of the user's free chats and feeding the apology back to the model as
 * part of the conversation on every later turn.
 */
async function generateReply(
  message: string,
  history: Turn[],
  user?: Record<string, any> | null,
  diagnosis: Diagnosis | null = null,
): Promise<string> {
  const openaiKey = Deno.env.get("OPENAI_API_KEY");
  if (!openaiKey) return mockReply(message);

  let data;
  try {
    // deno-lint-ignore no-explicit-any
    const messages: any[] = [
      {
        role: "system",
        content:
          SYSTEM_PROMPT + EMERGENCY_RULES + STYLE_RULES + contextNote(user) + diagnosisNote(diagnosis),
      },
    ];

    for (const turn of history) {
      messages.push({ role: turn.role === "ai" ? "assistant" : "user", content: turn.text });
    }

    messages.push({ role: "user", content: message });

    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${openaiKey}` },
      // Low temperature: the same symptoms should get the same advice.
      body: JSON.stringify({ model: "gpt-4o-mini", messages, max_tokens: 700, temperature: 0.3 }),
    });

    if (!response.ok) {
      console.error("OpenAI API error:", await response.json().catch(() => null));
      throw new ReplyError();
    }
    data = await response.json();
  } catch (err) {
    if (err instanceof ReplyError) throw err;
    console.error("OpenAI request failed:", err);
    throw new ReplyError();
  }

  const reply = data.choices?.[0]?.message?.content;
  if (!reply) {
    console.error("OpenAI returned no content:", data);
    throw new ReplyError();
  }
  return reply;
}

async function handleSend(req: Request): Promise<Response> {
  if (req.method !== "POST") {
    return json({ status: "error", message: "Method not allowed" }, 405);
  }

  // Auth verification uses an isolated client instance
  const authClient = adminClient();
  const authUser = await requireUser(req, authClient);

  // Database operations use a fresh service_role client instance so
  // permissions and RLS bypass stay intact.
  const db = adminClient();

  const body = await req.json().catch(() => ({}));
  const { message } = body;

  if (!message || typeof message !== "string" || message.length > 1000) {
    return json({ status: "error", message: "Message is required" }, 422);
  }

  const user = await getAppUser(db, authUser.id);
  const chatCount = user?.chat_count ?? 0;
  const subscribed = isSubscribed(user);

  if (!subscribed && (!canUseFreeChats(user) || chatCount >= FREE_CHAT_LIMIT)) {
    return json(
      {
        status: "error",
        limit_reached: true,
        message: "Subscribe to continue chatting.",
        chat_count: chatCount,
        limit: FREE_CHAT_LIMIT,
      },
      403,
    );
  }

  const [history, diagnosis] = await Promise.all([
    loadHistory(db, authUser.id),
    loadLatestDiagnosis(db, authUser.id),
  ]);

  let reply: string;
  try {
    reply = await generateReply(message, history, user, diagnosis);
  } catch (err) {
    if (!(err instanceof ReplyError)) throw err;
    // Not recorded and not counted: the user keeps their free chat and can
    // simply resend.
    return json(
      {
        status: "error",
        message: "I'm having trouble connecting right now. Please try again in a moment.",
      },
      502,
    );
  }

  const { data: newCount, error } = await db.rpc("record_chat_exchange", {
    p_user_id: authUser.id,
    p_message: message,
    p_reply: reply,
  });

  if (error) {
    console.error("record_chat_exchange failed", error);
    return json(
      { status: "error", message: `Could not save conversation: ${error.message || JSON.stringify(error)}` },
      500,
    );
  }

  return json({
    status: "success",
    reply,
    chat_count: newCount ?? chatCount + 1,
    limit: FREE_CHAT_LIMIT,
    is_subscribed: subscribed,
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return preflight();

  const path = new URL(req.url).pathname;

  try {
    if (path.endsWith("/send")) return await handleSend(req);
    return json({ status: "error", message: "Not found" }, 404);
  } catch (error) {
    if (error instanceof AuthError) {
      return json({ status: "error", message: error.message }, error.status);
    }
    console.error("Unhandled chat function error", error);
    return json(
      { status: "error", message: `Server error: ${(error as Error).message || String(error)}` },
      500,
    );
  }
});
