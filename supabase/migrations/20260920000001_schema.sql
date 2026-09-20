-- AfyaSmart: Firestore -> Postgres schema.
--
-- Field names are kept identical to the Firestore documents (already
-- snake_case) so the existing client models map 1:1 without a translation
-- layer.
--
-- Firestore document ids were opaque strings. Two id strategies replace them:
--   * user-owned rows key off auth.users(id) (uuid).
--   * catalogue rows (doctors/drugs/pharmacies) use identity bigints, because
--     the client already coerces their ids to numbers (see numericId() in
--     src/services/doctor.service.ts).

create extension if not exists "pgcrypto";

-- ── Enums ───────────────────────────────────────────────────────────────────

create type user_role         as enum ('user', 'admin', 'super_admin');
create type subscription_plan as enum ('free', 'daily', 'weekly', 'monthly');
-- 'cancelled' is M-Pesa ResultCode 1032 (user dismissed the STK prompt). It
-- is distinct from 'failed' because it is the user's own choice, not an
-- error, and the UI words the two differently.
create type payment_status    as enum ('pending', 'paid', 'failed', 'cancelled');
create type commission_status as enum ('pending', 'available', 'paid');
create type payout_status     as enum ('pending', 'paid', 'rejected');
create type chat_role         as enum ('user', 'ai');

-- ── users ───────────────────────────────────────────────────────────────────
-- Mirrors the Firestore users/{uid} document. The row is created by the
-- on_auth_user_created trigger (see the functions migration) rather than by
-- the client, so the "safe create" constraints that isSafeUserCreate()
-- enforced in firestore.rules are now structural defaults instead of rules.

create table public.users (
  id                       uuid primary key references auth.users (id) on delete cascade,
  name                     text        not null default 'AfyaSmart User',
  email                    text        not null,
  phone                    text        not null default '',
  role                     user_role   not null default 'user',
  is_subscribed            boolean     not null default false,
  has_subscribed           boolean     not null default false,
  onboarding_completed     boolean     not null default false,
  subscription_plan        subscription_plan not null default 'free',
  chat_count               integer     not null default 0 check (chat_count >= 0),
  subscription_expires_at  timestamptz,
  referred_by_uid          uuid        references public.users (id) on delete set null,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),

  -- Self-referral was silently ignored by creditAffiliateCommission();
  -- make it unrepresentable instead.
  constraint users_no_self_referral check (referred_by_uid is distinct from id)
);

create index users_created_at_idx     on public.users (created_at desc);
create index users_referred_by_idx    on public.users (referred_by_uid) where referred_by_uid is not null;
create index users_is_subscribed_idx  on public.users (is_subscribed) where is_subscribed;
create index users_has_subscribed_idx on public.users (has_subscribed) where has_subscribed;

-- ── Catalogue: doctors / drugs / pharmacies ─────────────────────────────────
-- Read-gated behind an active subscription (the paywall), admin-writable.

create table public.doctors (
  id                bigint generated always as identity primary key,
  name              text    not null,
  specialization    text    not null default '',
  hospital          text    not null default '',
  location          text    not null default '',
  region            text,
  phone             text    not null default '',
  email             text    not null default '',
  latitude          double precision,
  longitude         double precision,
  experience_years  integer not null default 0,
  rating            numeric(2,1) not null default 0 check (rating between 0 and 5),
  availability      text    not null default '',
  available         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index doctors_region_idx         on public.doctors (region);
create index doctors_specialization_idx on public.doctors (specialization);

create table public.drugs (
  id                    bigint generated always as identity primary key,
  name                  text    not null,
  generic_name          text    not null default '',
  category              text    not null default 'Other',
  uses                  text    not null default '',
  dosage                text    not null default '',
  side_effects          text    not null default '',
  pregnancy_safe        boolean not null default false,
  alcohol_safe          boolean not null default false,
  lactation_safe        boolean not null default false,
  prescription_required text    not null default 'Yes',
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

-- searchDrugs() in src/services/drug.service.ts pulled every drug and
-- filtered client-side. This index lets the same search run server-side.
create index drugs_search_idx on public.drugs
  using gin (to_tsvector('english',
    name || ' ' || generic_name || ' ' || category || ' ' || uses));

create table public.pharmacies (
  id            bigint generated always as identity primary key,
  name          text    not null,
  location      text    not null default '',
  address       text    not null default '',
  phone         text    not null default '',
  email         text    not null default '',
  latitude      double precision,
  longitude     double precision,
  opening_hours text    not null default '',
  open_24hrs    boolean not null default false,
  open          boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ── Chat ────────────────────────────────────────────────────────────────────
-- Firestore had these as users/{uid} subcollections; ownership is now a FK.

create table public.chat_messages (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid      not null references public.users (id) on delete cascade,
  role       chat_role not null,
  text       text      not null,
  created_at timestamptz not null default now()
);

create index chat_messages_user_created_idx on public.chat_messages (user_id, created_at);

create table public.chat_logs (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.users (id) on delete cascade,
  message    text not null,
  reply      text not null,
  created_at timestamptz not null default now()
);

create index chat_logs_user_created_idx on public.chat_logs (user_id, created_at desc);

-- ── symptom_check_quota ─────────────────────────────────────────────────────
-- Was the symptomChecks/{uid}_{date} and symptomClarifyChecks/{uid}_{date}
-- document pair. The symptom endpoints are deliberately unauthenticated —
-- onboarding lets a guest check symptoms before an account exists — so the
-- subject is a plain text id (a user uuid once signed in, a client-generated
-- guest id before that) and NOT a FK. That is also why the quota exists at
-- all: without it, anyone could call the endpoint with an arbitrary id and
-- run up unbounded OpenAI cost.

create type symptom_check_kind as enum ('analyze', 'clarify');

create table public.symptom_check_quota (
  subject_id text               not null,
  kind       symptom_check_kind not null,
  day        date               not null,
  count      integer            not null default 0 check (count >= 0),
  updated_at timestamptz        not null default now(),

  primary key (subject_id, kind, day)
);

-- ── payment_requests ────────────────────────────────────────────────────────
-- Firestore keyed these by CheckoutRequestID, but failed initiations were
-- written with addDoc() and had no checkout id at all — hence a surrogate
-- primary key with checkout_request_id as a nullable unique key.

create table public.payment_requests (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references public.users (id) on delete cascade,
  phone               text,
  plan                subscription_plan,
  amount              numeric(10,2),
  status              payment_status not null default 'pending',
  paid                boolean not null default false,
  provider            text not null default 'mpesa',
  checkout_request_id text unique,
  merchant_request_id text,
  failure_reason      text,
  -- The raw Daraja stkQuery response, kept verbatim for dispute resolution:
  -- it is the only record of what Safaricom actually said.
  result              jsonb,
  paid_at             timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  -- paid and status could drift apart across the callback/poll/reconcile
  -- paths in functions/index.js; make the two impossible to disagree.
  constraint payment_paid_matches_status check (paid = (status = 'paid')),
  constraint payment_paid_at_present     check ((status = 'paid') = (paid_at is not null))
);

create index payment_requests_created_idx on public.payment_requests (created_at desc);
create index payment_requests_user_idx    on public.payment_requests (user_id, created_at desc);
create index payment_requests_status_idx  on public.payment_requests (status, created_at);

-- ── Affiliate program ───────────────────────────────────────────────────────
-- The affiliateCodes collection existed only to map a code -> uid for
-- lookup at registration. That is now just a unique column here, exposed
-- through the resolve_referral_code() function in the functions migration.

create table public.affiliates (
  id                uuid primary key references public.users (id) on delete cascade,
  code              text unique not null,
  available_balance numeric(10,2) not null default 0 check (available_balance >= 0),
  pending_balance   numeric(10,2) not null default 0 check (pending_balance   >= 0),
  total_earned      numeric(10,2) not null default 0 check (total_earned      >= 0),
  referrals_count   integer not null default 0 check (referrals_count >= 0),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create table public.commissions (
  id                uuid primary key default gen_random_uuid(),
  affiliate_id      uuid not null references public.affiliates (id) on delete cascade,
  referred_id       uuid not null references public.users (id) on delete cascade,
  payment_id        uuid references public.payment_requests (id) on delete set null,
  plan              subscription_plan not null,
  amount            numeric(10,2) not null,
  commission_amount numeric(10,2) not null,
  status            commission_status not null default 'pending',
  available_at      timestamptz not null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index commissions_affiliate_idx on public.commissions (affiliate_id, created_at desc);
create index commissions_release_idx   on public.commissions (status, available_at)
  where status = 'pending';

-- One commission per payment: without this, a retried M-Pesa callback and a
-- status poll resolving the same STK push could each credit the referrer.
create unique index commissions_one_per_payment_idx on public.commissions (payment_id)
  where payment_id is not null;

create table public.payout_requests (
  id           uuid primary key default gen_random_uuid(),
  affiliate_id uuid not null references public.affiliates (id) on delete cascade,
  amount       numeric(10,2) not null check (amount >= 100),
  phone        text not null,
  status       payout_status not null default 'pending',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index payout_requests_created_idx   on public.payout_requests (created_at desc);
create index payout_requests_affiliate_idx on public.payout_requests (affiliate_id, created_at desc);

-- ── updated_at maintenance ──────────────────────────────────────────────────
-- Replaces the scattered serverTimestamp() writes; no caller can forget it.

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $fn$
begin
  new.updated_at := now();
  return new;
end;
$fn$;

do $do$
declare t text;
begin
  foreach t in array array[
    'users', 'doctors', 'drugs', 'pharmacies', 'payment_requests',
    'affiliates', 'commissions', 'payout_requests'
  ] loop
    execute format(
      'create trigger %I_touch_updated_at before update on public.%I
         for each row execute function public.touch_updated_at()', t, t);
  end loop;
end;
$do$;
