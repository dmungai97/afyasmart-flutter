-- Business logic ported from functions/index.js.
--
-- Everything the Cloud Functions did with the Admin SDK (bypassing rules)
-- lives here as security definer functions. Two categories:
--
--   * `authenticated` RPCs — enroll_affiliate, request_payout, search_drugs.
--     These check auth.uid() themselves.
--   * service-role only — activate_subscription and the admin_* family.
--     Called by edge functions and the admin console, never by a client.
--
-- The transactional guarantees the originals got from db.runTransaction()
-- come free here: a plpgsql function body is already one transaction, and the
-- UPDATE ... WHERE balance >= amount pattern takes a row lock.

-- ── Constants ───────────────────────────────────────────────────────────────
-- Mirrors the consts at the top of functions/index.js.

create or replace function public.plan_amount(p subscription_plan)
returns numeric
language sql
immutable
as $$
  select case p
    when 'daily'   then 20
    when 'weekly'  then 100
    when 'monthly' then 200
    else null
  end::numeric;
$$;

create or replace function public.subscription_expiry(p subscription_plan)
returns timestamptz
language sql
stable
as $$
  select now() + case p
    when 'monthly' then interval '1 month'
    when 'weekly'  then interval '7 days'
    else                interval '1 day'
  end;
$$;

-- Matches normalizePhone() in functions/index.js: strip whitespace, leading
-- 0 -> 254, drop a leading +.
create or replace function public.normalize_phone(raw text)
returns text
language sql
immutable
as $$
  select regexp_replace(
           regexp_replace(
             regexp_replace(coalesce(raw, ''), '\s+', '', 'g'),
             '^0', '254'),
           '^\+', '');
$$;

-- ── New user provisioning ───────────────────────────────────────────────────
-- Replaces both the client-side user document create (isSafeUserCreate in
-- firestore.rules) and the onUserCreated trigger that kept referrals_count
-- accurate. Doing both in one trigger means a referral can never be recorded
-- without the counter moving with it.
--
-- The referral code travels in raw_user_meta_data as `referral_code`, set by
-- the client at sign-up from a ?ref=CODE deep link.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  referrer_id uuid;
  code        text;
begin
  code := nullif(trim(new.raw_user_meta_data ->> 'referral_code'), '');

  if code is not null then
    select id into referrer_id from public.affiliates where affiliates.code = upper(code);
  end if;

  -- A user cannot refer themselves; users_no_self_referral would reject the
  -- row outright and fail the whole sign-up, so drop it quietly instead.
  if referrer_id = new.id then
    referrer_id := null;
  end if;

  insert into public.users (id, email, name, phone, referred_by_uid)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'name'), ''), 'AfyaSmart User'),
    coalesce(new.raw_user_meta_data ->> 'phone', ''),
    referrer_id
  );

  if referrer_id is not null then
    update public.affiliates
       set referrals_count = referrals_count + 1
     where id = referrer_id;
  end if;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Exposes only code -> affiliate id, never balances. Replaces the
-- affiliateCodes collection, which firestore.rules made readable to every
-- signed-in user.
create or replace function public.resolve_referral_code(code text)
returns uuid
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select id from public.affiliates where affiliates.code = upper(trim(code));
$$;

-- ── Subscription activation ─────────────────────────────────────────────────
-- The single authoritative "this payment succeeded" path, shared by the
-- M-Pesa callback, the status poll and admin reconciliation — exactly as
-- activateSubscription() was in functions/index.js. Routing all three through
-- here is what guarantees the affiliate commission is credited identically
-- however the payment was confirmed.

create or replace function public.credit_affiliate_commission(
  p_referred_id uuid,
  p_plan        subscription_plan,
  p_amount      numeric,
  p_payment_id  uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  commission_rate constant numeric := 0.3;
  hold_days       constant integer := 7;
  referrer_id     uuid;
  commission      numeric;
begin
  if p_amount is null or p_amount <= 0 then
    return;
  end if;

  select u.referred_by_uid into referrer_id
    from public.users u
   where u.id = p_referred_id;

  if referrer_id is null then
    return;
  end if;

  -- The referrer must still be an enrolled affiliate, as in the original.
  if not exists (select 1 from public.affiliates where id = referrer_id) then
    return;
  end if;

  commission := round(p_amount * commission_rate, 2);

  -- commissions_one_per_payment_idx makes a repeated callback a no-op rather
  -- than a double credit. The original had no such guard.
  insert into public.commissions (
    affiliate_id, referred_id, payment_id, plan, amount, commission_amount,
    status, available_at
  )
  values (
    referrer_id, p_referred_id, p_payment_id, p_plan, p_amount, commission,
    'pending', now() + (hold_days || ' days')::interval
  )
  on conflict (payment_id) where payment_id is not null do nothing;

  if not found then
    return;
  end if;

  update public.affiliates
     set pending_balance = pending_balance + commission,
         total_earned    = total_earned    + commission
   where id = referrer_id;
end;
$$;

create or replace function public.activate_subscription(
  p_user_id    uuid,
  p_plan       subscription_plan,
  p_amount     numeric default null,
  p_payment_id uuid    default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  effective_amount numeric;
begin
  update public.users
     set is_subscribed           = true,
         has_subscribed          = true,
         chat_count              = 0,
         subscription_plan       = p_plan,
         subscription_expires_at = public.subscription_expiry(p_plan)
   where id = p_user_id;

  if not found then
    raise exception 'No such user: %', p_user_id;
  end if;

  if p_payment_id is not null then
    update public.payment_requests
       set status  = 'paid',
           paid    = true,
           paid_at = coalesce(paid_at, now())
     where id = p_payment_id;
  end if;

  effective_amount := coalesce(p_amount, public.plan_amount(p_plan), 0);

  -- The original wrapped this in try/catch so a commission failure could not
  -- fail the subscription. Here they share a transaction deliberately: a
  -- half-applied payment is worse than a retryable error.
  perform public.credit_affiliate_commission(
    p_user_id, p_plan, effective_amount, p_payment_id);
end;
$$;

-- ── Affiliate enrollment ────────────────────────────────────────────────────

create or replace function public.generate_affiliate_code()
returns text
language sql
volatile
as $$
  -- Excludes 0/O/1/I to avoid visual ambiguity when read aloud, as in
  -- generateAffiliateCode().
  select 'AFYA-' || string_agg(
    substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
           floor(random() * 32)::integer + 1, 1), '')
  from generate_series(1, 6);
$$;

create or replace function public.enroll_affiliate()
returns text
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  uid       uuid := auth.uid();
  candidate text;
begin
  if uid is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  select code into candidate from public.affiliates where id = uid;
  if candidate is not null then
    return candidate;
  end if;

  -- The unique index on affiliates.code settles collisions, so this needs no
  -- transaction of its own the way the Firestore version did.
  for attempt in 1 .. 5 loop
    candidate := public.generate_affiliate_code();
    begin
      insert into public.affiliates (id, code) values (uid, candidate);
      return candidate;
    exception
      when unique_violation then
        -- A concurrent call may have enrolled this same user; if so, return
        -- the code it won with rather than retrying forever.
        select code into candidate from public.affiliates where id = uid;
        if candidate is not null then
          return candidate;
        end if;
    end;
  end loop;

  raise exception 'Could not generate a referral code. Please try again.';
end;
$$;

-- ── Payouts ─────────────────────────────────────────────────────────────────

create or replace function public.request_payout(p_amount numeric, p_phone text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  min_withdrawal constant numeric := 100;
  uid       uuid := auth.uid();
  payout_id uuid;
begin
  if uid is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  if p_amount is null or p_amount < min_withdrawal or coalesce(trim(p_phone), '') = '' then
    raise exception 'Minimum withdrawal is Ksh %, and a phone number is required.',
      min_withdrawal;
  end if;

  if not exists (select 1 from public.affiliates where id = uid) then
    raise exception 'You are not enrolled as an affiliate.';
  end if;

  -- Deducting first, conditionally, is what makes two concurrent withdrawal
  -- requests against the same balance impossible: the UPDATE takes a row lock
  -- and the second one matches no row. Same intent as the runTransaction() in
  -- requestPayout, without the retry loop.
  update public.affiliates
     set available_balance = available_balance - p_amount
   where id = uid
     and available_balance >= p_amount;

  if not found then
    raise exception 'Insufficient available balance.';
  end if;

  insert into public.payout_requests (affiliate_id, amount, phone)
  values (uid, p_amount, public.normalize_phone(p_phone))
  returning id into payout_id;

  return payout_id;
end;
$$;

-- ── Scheduled jobs ──────────────────────────────────────────────────────────
-- Scheduled with pg_cron in the cron migration; these were onSchedule()
-- Cloud Functions.

create or replace function public.release_affiliate_commissions()
returns integer
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  released integer;
begin
  -- GET DIAGNOSTICS after the outer UPDATE would count affiliates, not
  -- commissions, so the released count is taken inside the CTE instead.
  with due as (
    update public.commissions
       set status = 'available'
     where status = 'pending'
       and available_at <= now()
    returning affiliate_id, commission_amount
  ), totals as (
    select affiliate_id, sum(commission_amount) as total, count(*) as n
      from due group by affiliate_id
  ), moved as (
    update public.affiliates a
       set pending_balance   = a.pending_balance   - t.total,
           available_balance = a.available_balance + t.total
      from totals t
     where a.id = t.affiliate_id
    returning t.n
  )
  select coalesce(sum(n), 0)::integer into released from moved;

  return released;
end;
$$;

create or replace function public.expire_stale_payments()
returns integer
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  expiry_minutes constant integer := 20;
  expired integer;
begin
  update public.payment_requests
     set status         = 'failed',
         paid           = false,
         failure_reason = format(
           'Payment attempt expired — no response after %s minutes.', expiry_minutes)
   where status = 'pending'
     and created_at < now() - (expiry_minutes || ' minutes')::interval;

  get diagnostics expired = row_count;
  return expired;
end;
$$;

-- ── Catalogue search ────────────────────────────────────────────────────────
-- searchDrugs() fetched every drug and filtered in JS. Same results, but the
-- filtering happens where the data is — and the paywall policy still applies,
-- because this is not security definer.

create or replace function public.search_drugs(q text)
returns setof public.drugs
language sql
stable
as $$
  select * from public.drugs
   where coalesce(trim(q), '') = ''
      or to_tsvector('english', name || ' ' || generic_name || ' ' || category || ' ' || uses)
         @@ plainto_tsquery('english', q)
      or name ilike '%' || q || '%'
   order by name;
$$;

-- ── Admin operations ────────────────────────────────────────────────────────
-- Callable by admins only; each re-checks is_admin() itself because security
-- definer bypasses the RLS that would otherwise do it.

create or replace function public.admin_update_user(
  p_user_id                 uuid,
  p_name                    text    default null,
  p_role                    user_role default null,
  p_is_subscribed           boolean default null,
  p_subscription_plan       subscription_plan default null,
  p_subscription_expires_at timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if not public.is_admin() then
    raise exception 'Admin privileges required' using errcode = '42501';
  end if;

  -- Only a super_admin may change a role, or any admin could promote
  -- themselves to super_admin — the same carve-out the users rule had.
  if p_role is not null and not public.is_super_admin() then
    raise exception 'Only a super admin may change roles' using errcode = '42501';
  end if;

  update public.users
     set name              = coalesce(p_name, name),
         role              = coalesce(p_role, role),
         is_subscribed     = coalesce(p_is_subscribed, is_subscribed),
         subscription_plan = coalesce(p_subscription_plan, subscription_plan),
         subscription_expires_at = coalesce(p_subscription_expires_at, subscription_expires_at)
   where id = p_user_id;
end;
$$;

-- Reconciling a payment manually must take the same path a real M-Pesa
-- confirmation does, so the referrer's commission is credited identically.
create or replace function public.admin_reconcile_payment(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  payment public.payment_requests;
begin
  if not public.is_admin() then
    raise exception 'Admin privileges required' using errcode = '42501';
  end if;

  select * into payment from public.payment_requests where id = p_payment_id for update;

  if payment is null then
    raise exception 'No such payment: %', p_payment_id;
  end if;
  if payment.paid then
    return;
  end if;
  if payment.plan is null then
    raise exception 'Payment % has no plan to activate', p_payment_id;
  end if;

  perform public.activate_subscription(
    payment.user_id, payment.plan, payment.amount, payment.id);
end;
$$;

create or replace function public.admin_reject_payment(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if not public.is_admin() then
    raise exception 'Admin privileges required' using errcode = '42501';
  end if;

  update public.payment_requests
     set status = 'failed', paid = false, paid_at = null
   where id = p_payment_id and not paid;
end;
$$;

create or replace function public.admin_resolve_payout(
  p_payout_id uuid,
  p_approve   boolean
)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  payout public.payout_requests;
begin
  if not public.is_admin() then
    raise exception 'Admin privileges required' using errcode = '42501';
  end if;

  select * into payout from public.payout_requests where id = p_payout_id for update;

  if payout is null then
    raise exception 'No such payout: %', p_payout_id;
  end if;
  if payout.status <> 'pending' then
    raise exception 'Payout % is already %', p_payout_id, payout.status;
  end if;

  update public.payout_requests
     set status = case when p_approve then 'paid' else 'rejected' end::payout_status
   where id = p_payout_id;

  -- Rejecting refunds the balance request_payout() deducted up front. The
  -- status guard above is what stops a double refund — the original
  -- rejectAffiliatePayout() could be called twice and credit twice.
  if not p_approve then
    update public.affiliates
       set available_balance = available_balance + payout.amount
     where id = payout.affiliate_id;
  end if;
end;
$$;

-- ── Edge function helpers ───────────────────────────────────────────────────

-- The chat function wrote four documents in sequence (chatLog, two
-- chatMessages, then an increment), any of which could fail independently and
-- leave chat_count disagreeing with the stored history. One call, one
-- transaction. Returns the new chat_count so the caller need not re-read.
create or replace function public.record_chat_exchange(
  p_user_id uuid,
  p_message text,
  p_reply   text
)
returns integer
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  new_count integer;
begin
  insert into public.chat_logs (user_id, message, reply)
  values (p_user_id, p_message, p_reply);

  insert into public.chat_messages (user_id, role, text)
  values (p_user_id, 'user', p_message),
         (p_user_id, 'ai',   p_reply);

  update public.users
     set chat_count = chat_count + 1
   where id = p_user_id
  returning chat_count into new_count;

  if new_count is null then
    raise exception 'No such user: %', p_user_id;
  end if;

  return new_count;
end;
$$;

-- Atomic check-and-increment for the symptom endpoints. The original read the
-- count, compared it, then wrote count+1 — two concurrent requests both read
-- the same value and both proceeded, so the limit could be overrun. The
-- INSERT ... ON CONFLICT DO UPDATE here settles that in one statement.
--
-- Returns true when the call is allowed (and has been counted), false when
-- the caller is over quota.
create or replace function public.consume_symptom_quota(
  p_subject_id text,
  p_kind       symptom_check_kind,
  p_limit      integer
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  new_count integer;
begin
  insert into public.symptom_check_quota (subject_id, kind, day, count)
  values (p_subject_id, p_kind, current_date, 1)
  on conflict (subject_id, kind, day) do update
    set count      = public.symptom_check_quota.count + 1,
        updated_at = now()
  returning count into new_count;

  return new_count <= p_limit;
end;
$$;

-- ── Grants ──────────────────────────────────────────────────────────────────
-- Default is EXECUTE to public on new functions, so revoke first and then
-- hand out only what each role legitimately calls.

revoke execute on all functions in schema public from public, anon;

grant execute on function
  public.enroll_affiliate(),
  public.request_payout(numeric, text),
  public.search_drugs(text),
  public.resolve_referral_code(text),
  public.plan_amount(subscription_plan),
  public.subscription_expiry(subscription_plan)
to authenticated;

grant execute on function
  public.admin_update_user(uuid, text, user_role, boolean, subscription_plan, timestamptz),
  public.admin_reconcile_payment(uuid),
  public.admin_reject_payment(uuid),
  public.admin_resolve_payout(uuid, boolean)
to authenticated;

-- Never client-callable: these are the money-moving paths, reached only by
-- edge functions holding the service role key.
grant execute on function
  public.activate_subscription(uuid, subscription_plan, numeric, uuid),
  public.credit_affiliate_commission(uuid, subscription_plan, numeric, uuid),
  public.release_affiliate_commissions(),
  public.expire_stale_payments(),
  public.record_chat_exchange(uuid, text, text),
  public.consume_symptom_quota(text, symptom_check_kind, integer)
to service_role;
