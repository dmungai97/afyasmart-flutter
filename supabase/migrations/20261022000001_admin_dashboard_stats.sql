-- Every figure on the admin dashboard, computed in the database.
--
-- The client used to download every paid payment and add them up itself.
-- PostgREST returns at most 1000 rows per request, so past that the revenue
-- would have quietly undercounted, and the download grew with every payment.
-- This returns only the totals.
--
-- Customers only: accounts with role 'user'. Admin accounts were counted as
-- users and subscribers (and their test payments as revenue), so one admin
-- on a granted plan read as "12.5% conversion".
--
-- "This week" starts Monday 00:00 Nairobi time, whatever the device's clock.
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
