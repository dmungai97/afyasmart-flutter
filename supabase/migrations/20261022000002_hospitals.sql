-- Hospitals, as their own table.
--
-- The map used to make hospital pins up from the bundled seed doctors'
-- "hospital" field. Those doctors were invented, so the pins went with them.
-- Hospitals are real, public places, so they get a table of their own that
-- the map reads and Admin Facilities manages.
--
-- verified: rows start unverified and patients do not see them until an
-- admin has checked the location (and phone) and marked them verified. The
-- rows below are a starting list of well-known hospitals; their coordinates
-- are approximate and they have no phone numbers yet, so every one needs
-- checking before it goes live.
--
-- Visible to every signed-in user once verified, unlike doctors and
-- pharmacies, which are a subscriber feature: knowing where the nearest
-- hospital is should never be behind a paywall.

create table public.hospitals (
  id          bigint generated always as identity primary key,
  name        text    not null,
  location    text    not null default '',
  address     text    not null default '',
  phone       text    not null default '',
  latitude    double precision,
  longitude   double precision,
  open_24hrs  boolean not null default true,
  verified    boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create trigger hospitals_touch_updated_at before update on public.hospitals
  for each row execute function public.touch_updated_at();

alter table public.hospitals enable row level security;

create policy hospitals_select on public.hospitals
  for select to authenticated
  using (verified or public.is_admin());

create policy hospitals_admin_manage on public.hospitals
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

revoke all on public.hospitals from anon, authenticated;
grant select, insert, update, delete on public.hospitals to authenticated;

-- Deduplicated: "Thika District Hospital" is Thika Level 5 under its old
-- name, and "Rift Valley Provincial Hospital" is Nakuru Level 5.
insert into public.hospitals (name, location, latitude, longitude) values
  ('Kenyatta National Hospital',                      'Upper Hill, Nairobi', -1.3009, 36.8070),
  ('The Nairobi Hospital',                            'Upper Hill, Nairobi', -1.2960, 36.8045),
  ('Aga Khan University Hospital',                    'Parklands, Nairobi',  -1.2612, 36.8227),
  ('MP Shah Hospital',                                'Parklands, Nairobi',  -1.2638, 36.8155),
  ('The Karen Hospital',                              'Karen, Nairobi',      -1.3372, 36.7300),
  ('Gertrude''s Children''s Hospital',                'Muthaiga, Nairobi',   -1.2490, 36.8330),
  ('Nakuru Level 5 Hospital',                         'Nakuru',              -0.2870, 36.0750),
  ('Nakuru War Memorial Hospital',                    'Nakuru',              -0.2970, 36.0770),
  ('Coast General Teaching and Referral Hospital',    'Mombasa',             -4.0567, 39.6730),
  ('Pandya Memorial Hospital',                        'Mombasa',             -4.0470, 39.6660),
  ('Aga Khan Hospital Mombasa',                       'Mombasa',             -4.0575, 39.6745),
  ('The Mombasa Hospital',                            'Mombasa',             -4.0640, 39.6780),
  ('Jaramogi Oginga Odinga Teaching and Referral Hospital', 'Kisumu',        -0.0930, 34.7710),
  ('Kisumu County Referral Hospital',                 'Kisumu',              -0.1000, 34.7560),
  ('Aga Khan Hospital Kisumu',                        'Kisumu',              -0.0960, 34.7650),
  ('Moi Teaching and Referral Hospital',              'Eldoret',              0.5150, 35.2780),
  ('Eldoret Hospital',                                'Eldoret',              0.5170, 35.2850),
  ('Thika Level 5 Hospital',                          'Thika',               -1.0400, 37.0750);

-- The dashboard's facility count now includes hospitals.
create or replace function public.admin_dashboard_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  week_start timestamptz :=
    date_trunc('week', now() at time zone 'Africa/Nairobi') at time zone 'Africa/Nairobi';
  result jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admin privileges required' using errcode = '42501';
  end if;

  with customers as (
    select id, subscription_plan, is_subscribed, subscription_expires_at
    from public.users
    where role = 'user'
  ),
  active as (
    select subscription_plan
    from customers
    where is_subscribed
      and (subscription_expires_at is null or subscription_expires_at > now())
  ),
  -- A missing or zero amount falls back to the plan's list price, as the
  -- client's paymentAmount() did, so legacy rows are not counted as Ksh 0.
  customer_payments as (
    select p.status,
           p.paid_at,
           coalesce(nullif(p.amount, 0), public.plan_amount(p.plan), 0) as amount
    from public.payment_requests p
    join customers c on c.id = p.user_id
    where p.status in ('paid', 'pending')
  ),
  paid as (
    select paid_at, amount from customer_payments where status = 'paid'
  ),
  pending as (
    select amount from customer_payments where status = 'pending'
  ),
  this_week as (
    select extract(isodow from paid_at at time zone 'Africa/Nairobi')::int - 1 as day,
           sum(amount) as revenue,
           count(*) as payments
    from paid
    where paid_at >= week_start
    group by 1
  ),
  payouts as (
    select amount from public.payout_requests where status = 'pending'
  )
  select jsonb_build_object(
    'total_users',              (select count(*) from customers),
    'active_subscribers',       (select count(*) from active),
    'daily',                    (select count(*) from active where subscription_plan = 'daily'),
    'weekly',                   (select count(*) from active where subscription_plan = 'weekly'),
    'monthly',                  (select count(*) from active where subscription_plan = 'monthly'),
    'revenue',                  (select coalesce(sum(amount), 0) from paid),
    'paid_payments',            (select count(*) from paid),
    'pending_payments',         (select count(*) from pending),
    'pending_value',            (select coalesce(sum(amount), 0) from pending),
    'payouts_to_approve',       (select count(*) from payouts),
    'payouts_to_approve_value', (select coalesce(sum(amount), 0) from payouts),
    'doctors',                  (select count(*) from public.doctors),
    'pharmacies',               (select count(*) from public.pharmacies),
    'hospitals',                (select count(*) from public.hospitals),
    'hospitals_unverified',     (select count(*) from public.hospitals where not verified),
    'drugs',                    (select count(*) from public.drugs),
    'week', coalesce(
      (select jsonb_agg(jsonb_build_object(
         'day', day, 'revenue', revenue, 'payments', payments))
       from this_week),
      '[]'::jsonb)
  ) into result;

  return result;
end;
$$;

revoke execute on function public.admin_dashboard_stats() from public, anon;
grant  execute on function public.admin_dashboard_stats() to authenticated;
