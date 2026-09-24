// Subscription predicates, kept byte-for-byte equivalent to
// src/services/subscription.model.ts and the copies in functions/index.js.
//
// These are duplicated in SQL (has_active_subscription) on purpose: the SQL
// one gates row access, this one shapes the response body. They must agree —
// if you change the rule, change both.

// deno-lint-ignore no-explicit-any
type User = Record<string, any> | null;

export const FREE_CHAT_LIMIT = 50;
export const SYMPTOM_FREE_DAILY_LIMIT = 100;

export function isSubscribed(user: User): boolean {
  if (!user) return false;
  const raw = user.subscription_expires_at;
  const expiresAt = raw instanceof Date ? raw : raw ? new Date(raw) : null;
  return user.is_subscribed === true && (!expiresAt || expiresAt > new Date());
}

export function hasEverSubscribed(user: User): boolean {
  if (!user) return false;
  if (user.has_subscribed === true || user.is_subscribed === true) return true;
  if (user.subscription_expires_at) return true;
  return ["daily", "weekly", "monthly"].includes(user.subscription_plan);
}

export function canUseFreeChats(user: User): boolean {
  return !isSubscribed(user) && !hasEverSubscribed(user);
}
