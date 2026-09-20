-- Row Level Security: the port of firestore.rules.
--
-- Two mechanics replace what Firestore rules expressed inline:
--
--   * WHICH ROWS a caller may touch -> RLS policies below.
--   * WHICH COLUMNS a caller may write -> column-level GRANTs. Firestore's
--     isSafeUserUpdate() whitelisted affectedKeys(); Postgres expresses the
--     same thing as `grant update (name, phone, ...)`. This matters most for
--     the subscription fields: a user writing is_subscribed themselves would
--     grant themselves a free subscription, exactly as the original rules
--     comment warned.
--
-- Anything a GRANT cannot express per-row (admin edits, marking a payment
-- paid, crediting commissions) is not client-writable at all and goes through
-- a security definer RPC in the functions migration — the same role the
-- Admin SDK Cloud Functions played, which bypassed the rules entirely.

alter table public.users            enable row level security;
alter table public.doctors          enable row level security;
alter table public.drugs            enable row level security;
alter table public.pharmacies       enable row level security;
alter table public.chat_messages    enable row level security;
alter table public.chat_logs        enable row level security;
alter table public.symptom_check_quota enable row level security;
alter table public.payment_requests enable row level security;
alter table public.affiliates       enable row level security;
alter table public.commissions      enable row level security;
alter table public.payout_requests  enable row level security;

-- ── Predicate helpers ───────────────────────────────────────────────────────
-- security definer so they read public.users with RLS bypassed. Without that,
-- a policy on users that calls is_admin() — which itself selects from users —
-- recurses infinitely. firestore.rules hit the same problem and worked around
-- it by short-circuiting (`!isOwnUser(userId) && isAdmin()`); this is the
-- Postgres equivalent and does not need the caller to be careful.
--
-- search_path is pinned because a security definer function that resolves
-- unqualified names through a caller-controlled search_path is hijackable.

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select exists (
    select 1 from public.users
    where id = auth.uid() and role in ('admin', 'super_admin')
  );
$$;

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select exists (
    select 1 from public.users
    where id = auth.uid() and role = 'super_admin'
  );
$$;

-- The paywall. src/services/doctor.service.ts depends on catalogue reads
-- actually FAILING for non-subscribers (isPermissionDenied there deliberately
-- re-raises instead of falling back to bundled seed data) — so this must stay
-- a hard deny, not an empty result set, for that client path to keep working.
create or replace function public.has_active_subscription()
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select exists (
    select 1 from public.users
    where id = auth.uid()
      and is_subscribed
      and (subscription_expires_at is null or subscription_expires_at > now())
  );
$$;

revoke execute on function public.is_admin()                from public;
revoke execute on function public.is_super_admin()          from public;
revoke execute on function public.has_active_subscription() from public;
grant  execute on function public.is_admin()                to authenticated;
grant  execute on function public.is_super_admin()          to authenticated;
grant  execute on function public.has_active_subscription() to authenticated;

-- ── users ───────────────────────────────────────────────────────────────────

-- Read: own row; admins read everyone; an affiliate reads the users they
-- referred (firestore.rules allowed this only via a query filtered on
-- referred_by_uid — RLS enforces it on every row regardless of the query).
create policy users_select on public.users
  for select to authenticated
  using (
    id = auth.uid()
    or referred_by_uid = auth.uid()
    or public.is_admin()
  );

-- Write: own row only, and only the columns granted below. No INSERT policy
-- at all: rows are created by the on_auth_user_created trigger.
create policy users_update_self on public.users
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

revoke all on public.users from authenticated;
grant select on public.users to authenticated;
grant update (name, phone, onboarding_completed) on public.users to authenticated;

-- Mirrors the second half of isSafeUserUpdate(): onboarding_completed may be
-- set, never unset. A column GRANT alone cannot express a directional
-- constraint, so it needs a trigger.
create or replace function public.guard_user_self_update()
returns trigger
language plpgsql
as $$
begin
  if old.onboarding_completed and not new.onboarding_completed then
    raise exception 'onboarding_completed cannot be reverted';
  end if;
  return new;
end;
$$;

create trigger users_guard_self_update
  before update on public.users
  for each row execute function public.guard_user_self_update();

-- ── Catalogue (the paywall) ─────────────────────────────────────────────────
-- Reads require an active subscription; writes are admin-only and go through
-- the RPCs, so no client write grants exist.

create policy doctors_select on public.doctors
  for select to authenticated
  using (public.has_active_subscription() or public.is_admin());

create policy drugs_select on public.drugs
  for select to authenticated
  using (public.has_active_subscription() or public.is_admin());

create policy pharmacies_select on public.pharmacies
  for select to authenticated
  using (public.has_active_subscription() or public.is_admin());

revoke all on public.doctors, public.drugs, public.pharmacies from authenticated;
grant select on public.doctors, public.drugs, public.pharmacies to authenticated;

-- ── Chat ────────────────────────────────────────────────────────────────────
-- Messages are written by the chat edge function (service role) after it has
-- checked the free-chat limit. A client that could insert its own rows could
-- not forge a reply, but it could desynchronise chat_count from the history,
-- so inserts stay server-side.

create policy chat_messages_select on public.chat_messages
  for select to authenticated
  using (user_id = auth.uid());

create policy chat_logs_select on public.chat_logs
  for select to authenticated
  using (user_id = auth.uid());

revoke all on public.chat_messages, public.chat_logs from authenticated;
grant select on public.chat_messages, public.chat_logs to authenticated;

-- Quota rows are the rate limit itself. No policy and no grant: a client that
-- could read them learns nothing useful, and one that could write them could
-- reset its own limit. RLS with zero policies denies everything, and the
-- symptoms function touches this table through a service-role RPC only.
revoke all on public.symptom_check_quota from authenticated, anon;

-- ── payment_requests ────────────────────────────────────────────────────────
-- Read-only for clients. Every write path (initiate, callback, poll, admin
-- reconcile) runs server-side against the real M-Pesa result, because that is
-- the only path that also credits the referring affiliate — the original
-- rules made the same point about adminReconcilePayment.

create policy payment_requests_select on public.payment_requests
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

revoke all on public.payment_requests from authenticated;
grant select on public.payment_requests to authenticated;

-- ── Affiliate program ───────────────────────────────────────────────────────
-- Balances and commissions are derived from payments; all mutation is
-- server-side. Clients read their own rows only.

create policy affiliates_select on public.affiliates
  for select to authenticated
  using (id = auth.uid() or public.is_admin());

create policy commissions_select on public.commissions
  for select to authenticated
  using (affiliate_id = auth.uid() or public.is_admin());

create policy payout_requests_select on public.payout_requests
  for select to authenticated
  using (affiliate_id = auth.uid() or public.is_admin());

revoke all on public.affiliates, public.commissions, public.payout_requests from authenticated;
grant select on public.affiliates, public.commissions, public.payout_requests to authenticated;

-- ── Anonymous role ──────────────────────────────────────────────────────────
-- Nothing is readable before sign-in. Referral codes were "public-ish" in
-- Firestore (affiliateCodes was readable by any signed-in user); registration
-- resolves them through resolve_referral_code() instead, which exposes only
-- the mapping and none of the affiliate's balances.

revoke all on all tables in schema public from anon;
