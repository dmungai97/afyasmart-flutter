import { supabase, functionsBaseUrl, getAccessToken, getCurrentUserId } from "./supabase";
import {
  FREE_CHAT_LIMIT,
  canUseFreeChats,
  isSubscriptionActive,
} from "./subscription.model";

export interface ChatMessage {
  role: "user" | "ai";
  text: string;
  time?: string;
}

export interface SendMessageResponse {
  reply: string;
  chat_count: number;
  limit: number;
  is_subscribed: boolean;
}

export interface ChatStatusResponse {
  chat_count: number;
  limit: number;
  is_subscribed: boolean;
  free_chat_eligible: boolean;
  limit_reached: boolean;
  remaining: number;
}

export interface ChatHistoryResponse {
  messages: ChatMessage[];
}

export class ChatLimitError extends Error {
  constructor() {
    super("LIMIT_REACHED");
    this.name = "ChatLimitError";
  }
}

// ── Public API ───────────────────────────────────────────────────────────────

const requireUserId = async () => {
  const id = await getCurrentUserId();
  if (!id) throw new Error("You must be signed in to use chat.");
  return id;
};

export const getChatStatus = async (
  token: string | null,
): Promise<ChatStatusResponse> => {
  void token;
  await requireUserId();

  const { getCurrentUserProfile } = await import("./auth.service");
  const user = await getCurrentUserProfile();
  const chatCount = user?.chat_count ?? 0;
  const isSubscribed = isSubscriptionActive(user);
  const freeChatEligible = canUseFreeChats(user);

  return {
    chat_count: chatCount,
    limit: FREE_CHAT_LIMIT,
    is_subscribed: isSubscribed,
    free_chat_eligible: freeChatEligible,
    limit_reached: !isSubscribed && (!freeChatEligible || chatCount >= FREE_CHAT_LIMIT),
    remaining: isSubscribed || freeChatEligible
      ? Math.max(0, FREE_CHAT_LIMIT - chatCount)
      : 0,
  };
};

export const sendMessage = async (
  message: string,
  token: string | null,
  history: ChatMessage[] = [],
): Promise<SendMessageResponse> => {
  void token;
  await requireUserId();

  // Pre-flight limit check using the local profile (fast, avoids a
  // round-trip). The edge function re-checks authoritatively.
  const status = await getChatStatus(null);
  if (!status.is_subscribed && status.limit_reached) {
    throw new ChatLimitError();
  }

  // The dual Firebase-Functions / Supabase-Functions branch is gone: there is
  // only one backend now. The OpenAI key stays server-side either way.
  const accessToken = await getAccessToken();
  const response = await fetch(`${functionsBaseUrl}/chat/send`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
    },
    body: JSON.stringify({ message, history }),
  });

  const data = await response.json().catch(() => null);

  if (!response.ok) {
    if (response.status === 403 && data?.limit_reached) throw new ChatLimitError();
    throw new Error(data?.message ?? "Chat request failed.");
  }

  return data as SendMessageResponse;
};

const formatMessageTime = (value: string | null): string => {
  if (!value) return "";
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? ""
    : date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
};

export const getChatHistory = async (
  token: string | null,
): Promise<ChatHistoryResponse> => {
  void token;
  const userId = await requireUserId();

  // chat_messages_select scopes this to the caller's own rows, so the
  // user_id filter is belt-and-braces rather than the security boundary.
  const { data, error } = await supabase
    .from("chat_messages")
    .select("role, text, created_at")
    .eq("user_id", userId)
    .order("created_at", { ascending: true })
    .limit(100);

  if (error) throw new Error(error.message);

  return {
    messages: (data ?? []).map((item) => ({
      role: item.role,
      text: item.text,
      time: formatMessageTime(item.created_at),
    })) as ChatMessage[],
  };
};
