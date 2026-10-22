-- ── Notifications ───────────────────────────────────────────────────────────
-- Three pieces:
--
--   notifications            the in-app inbox, and the source of every push.
--                            Rows are created here in Postgres, next to the
--                            events they describe, never by the client.
--   notification_preferences what the settings screen toggles. Read by the
--                            push function; the inbox keeps everything.
--   device_tokens            FCM registration tokens, one row per install.
--
-- Delivery: an insert into notifications fires a pg_net call to the `push`
-- edge function, which sends through FCM (Android, and iOS via APNs). The
-- call needs two Vault secrets, created once per project:
--
--   select vault.create_secret('https://<ref>.supabase.co', 'project_url');
--   select vault.create_secret('<random string>', 'push_webhook_secret');
--
-- and the same random string set on the function as PUSH_WEBHOOK_SECRET.
-- Until both exist the trigger skips the call, so the inbox still works and
-- nothing errors — push simply stays off.

create extension if not exists pg_net with schema extensions;

create type notification_category as enum ('subscription', 'affiliate', 'symptom', 'wellness');

-- ── Tables ──────────────────────────────────────────────────────────────────

create table public.notifications (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null references public.users (id) on delete cascade,
  category    notification_category not null,
  title       text        not null,
  body        text        not null,
  -- Routing hints for the app (e.g. {"route": "/affiliate/earnings"}).
  data        jsonb       not null default '{}'::jsonb,
  -- Lets an event be announced at most once even if its trigger or cron job
  -- runs again (a repeated M-Pesa callback, a re-run of the daily job).
  dedupe_key  text,
  read_at     timestamptz,
  pushed_at   timestamptz,
  created_at  timestamptz not null default now()
);

create index notifications_user_created_idx on public.notifications (user_id, created_at desc);
create unique index notifications_dedupe_idx on public.notifications (user_id, dedupe_key)
  where dedupe_key is not null;

create table public.notification_preferences (
  user_id      uuid        primary key references public.users (id) on delete cascade,
  enabled      boolean     not null default true,
  symptom      boolean     not null default true,
  wellness     boolean     not null default true,
  subscription boolean     not null default true,
  affiliate    boolean     not null default true,
  updated_at   timestamptz not null default now()
);

create table public.device_tokens (
  token      text        primary key,
  user_id    uuid        not null references public.users (id) on delete cascade,
  platform   text        not null check (platform in ('android', 'ios')),
  updated_at timestamptz not null default now()
);

create index device_tokens_user_idx on public.device_tokens (user_id);

-- ── RLS ─────────────────────────────────────────────────────────────────────

alter table public.notifications            enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.device_tokens            enable row level security;

create policy notifications_select on public.notifications
  for select to authenticated using (user_id = auth.uid());
create policy notifications_update on public.notifications
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy notifications_delete on public.notifications
  for delete to authenticated using (user_id = auth.uid());

create policy notification_preferences_select on public.notification_preferences
  for select to authenticated using (user_id = auth.uid());
create policy notification_preferences_insert on public.notification_preferences
  for insert to authenticated with check (user_id = auth.uid());
create policy notification_preferences_update on public.notification_preferences
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy device_tokens_select on public.device_tokens
  for select to authenticated using (user_id = auth.uid());

revoke all on public.notifications, public.notification_preferences, public.device_tokens
  from anon, authenticated;

-- Only marking as read is client-writable; content is server-authored.
grant select, delete on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;
grant select, insert, update on public.notification_preferences to authenticated;
-- Token writes go through the RPCs below, since a token can move between
-- accounts on a shared phone and RLS would refuse to re-own another user's row.
grant select on public.device_tokens to authenticated;

grant all on public.notifications, public.notification_preferences, public.device_tokens
  to service_role;

-- ── Device token RPCs ───────────────────────────────────────────────────────

create or replace function public.register_device_token(p_token text, p_platform text)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  insert into public.device_tokens (token, user_id, platform)
  values (p_token, auth.uid(), p_platform)
  on conflict (token) do update
    set user_id    = excluded.user_id,
        platform   = excluded.platform,
        updated_at = now();
end;
$$;

-- Called on sign-out, before the session ends, so the next person to use
-- the phone does not receive the previous account's notifications.
create or replace function public.unregister_device_token(p_token text)
returns void
language sql
security definer
set search_path = public, pg_catalog
as $$
  delete from public.device_tokens where token = p_token and user_id = auth.uid();
$$;

revoke execute on function public.register_device_token(text, text) from public, anon;
revoke execute on function public.unregister_device_token(text)      from public, anon;
grant  execute on function public.register_device_token(text, text) to authenticated;
grant  execute on function public.unregister_device_token(text)      to authenticated;

-- ── Creating notifications ──────────────────────────────────────────────────

create or replace function public.notify_user(
  p_user_id    uuid,
  p_category   notification_category,
  p_title      text,
  p_body       text,
  p_data       jsonb default '{}'::jsonb,
  p_dedupe_key text  default null
)
returns void
language sql
security definer
set search_path = public, pg_catalog
as $$
  insert into public.notifications (user_id, category, title, body, data, dedupe_key)
  values (p_user_id, p_category, p_title, p_body, coalesce(p_data, '{}'::jsonb), p_dedupe_key)
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
$$;

revoke execute on function public.notify_user(uuid, notification_category, text, text, jsonb, text)
  from public, anon, authenticated;
grant execute on function public.notify_user(uuid, notification_category, text, text, jsonb, text)
  to service_role;

-- "150.00" -> "150", "150.50" -> "150.5"
create or replace function public.format_kes(amount numeric)
returns text
language sql
stable
as $$
  select 'KES ' || rtrim(rtrim(to_char(amount, 'FM999999990.00'), '0'), '.');
$$;

create or replace function public.format_nairobi_date(ts timestamptz)
returns text
language sql
stable
as $$
  select to_char(ts at time zone 'Africa/Nairobi', 'FMDD Mon YYYY');
$$;

-- ── Event triggers ──────────────────────────────────────────────────────────
-- Triggers rather than edits to activate_subscription() and friends: the
-- money-moving functions stay exactly as reviewed, and any path that changes
-- these rows (callback, poll, admin reconcile, admin edit) is covered.

create or replace function public.notify_on_subscription_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if new.is_subscribed
     and new.subscription_expires_at is not null
     and new.subscription_expires_at > now()
     and new.subscription_expires_at is distinct from old.subscription_expires_at then
    perform public.notify_user(
      new.id,
      'subscription',
      'Subscription active',
      'Your ' || new.subscription_plan || ' plan is active until '
        || public.format_nairobi_date(new.subscription_expires_at) || '.',
      jsonb_build_object('route', '/home'),
      'sub-active-' || extract(epoch from new.subscription_expires_at)::bigint
    );
  end if;
  return new;
end;
$$;

create trigger users_notify_subscription
  after update of is_subscribed, subscription_expires_at on public.users
  for each row execute function public.notify_on_subscription_change();

create or replace function public.notify_on_commission()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if tg_op = 'INSERT' then
    perform public.notify_user(
      new.affiliate_id,
      'affiliate',
      'You earned ' || public.format_kes(new.commission_amount),
      'A referral subscribed to the ' || new.plan || ' plan. Your commission '
        || 'can be withdrawn from ' || public.format_nairobi_date(new.available_at) || '.',
      jsonb_build_object('route', '/affiliate/earnings'),
      'commission-' || new.id
    );
  elsif old.status = 'pending' and new.status = 'available' then
    perform public.notify_user(
      new.affiliate_id,
      'affiliate',
      'Commission ready to withdraw',
      public.format_kes(new.commission_amount) || ' has moved to your available balance.',
      jsonb_build_object('route', '/affiliate/withdraw'),
      'commission-available-' || new.id
    );
  end if;
  return new;
end;
$$;

create trigger commissions_notify
  after insert or update of status on public.commissions
  for each row execute function public.notify_on_commission();

create or replace function public.notify_on_payout()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if old.status = 'pending' and new.status <> 'pending' then
    perform public.notify_user(
      new.affiliate_id,
      'affiliate',
      case new.status when 'paid' then 'Payout sent' else 'Payout declined' end,
      case new.status
        when 'paid' then public.format_kes(new.amount) || ' has been sent to ' || new.phone || '.'
        else 'Your ' || public.format_kes(new.amount)
          || ' withdrawal was declined and the amount returned to your balance.'
      end,
      jsonb_build_object('route', '/affiliate/earnings'),
      'payout-' || new.id || '-' || new.status
    );
  end if;
  return new;
end;
$$;

create trigger payout_requests_notify
  after update of status on public.payout_requests
  for each row execute function public.notify_on_payout();

-- ── Daily subscription reminders ────────────────────────────────────────────

create or replace function public.notify_subscription_expiry()
returns integer
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  u    record;
  sent integer := 0;
begin
  -- Expiring within the next 48 hours. Daily and weekly plans are short
  -- enough that this is most of a daily plan's life, so only monthly and
  -- weekly plans get the advance warning.
  for u in
    select id, subscription_plan, subscription_expires_at
      from public.users
     where is_subscribed
       and subscription_plan in ('weekly', 'monthly')
       and subscription_expires_at between now() and now() + interval '48 hours'
  loop
    perform public.notify_user(
      u.id,
      'subscription',
      'Your subscription ends soon',
      'Your ' || u.subscription_plan || ' plan ends on '
        || public.format_nairobi_date(u.subscription_expires_at)
        || '. Renew to keep access to doctors, pharmacies and symptom checks.',
      jsonb_build_object('route', '/subscription'),
      'sub-expiring-' || extract(epoch from u.subscription_expires_at)::bigint
    );
    sent := sent + 1;
  end loop;

  -- Lapsed in the last day.
  for u in
    select id, subscription_plan, subscription_expires_at
      from public.users
     where subscription_expires_at between now() - interval '1 day' and now()
  loop
    perform public.notify_user(
      u.id,
      'subscription',
      'Your subscription has ended',
      'Renew any time to pick up where you left off.',
      jsonb_build_object('route', '/subscription'),
      'sub-expired-' || extract(epoch from u.subscription_expires_at)::bigint
    );
    sent := sent + 1;
  end loop;

  return sent;
end;
$$;

revoke execute on function public.notify_subscription_expiry() from public, anon, authenticated;
grant  execute on function public.notify_subscription_expiry() to service_role;

-- 06:00 UTC is 09:00 in Nairobi.
select cron.schedule(
  'notify-subscription-expiry',
  '0 6 * * *',
  $$select public.notify_subscription_expiry()$$
);

-- ── Push dispatch ───────────────────────────────────────────────────────────

create or replace function public.dispatch_push()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  project_url text;
  secret      text;
begin
  select decrypted_secret into project_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into secret      from vault.decrypted_secrets where name = 'push_webhook_secret';

  if project_url is null or secret is null then
    return new;
  end if;

  -- pg_net is asynchronous: the request is queued and sent after commit, so
  -- a slow or failing push never holds up or rolls back the event itself.
  perform net.http_post(
    url     := rtrim(project_url, '/') || '/functions/v1/push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', secret
    ),
    body    := jsonb_build_object('notification_id', new.id)
  );
  return new;
end;
$$;

create trigger notifications_dispatch_push
  after insert on public.notifications
  for each row execute function public.dispatch_push();

-- Trigger functions never need direct EXECUTE.
revoke execute on function
  public.notify_on_subscription_change(),
  public.notify_on_commission(),
  public.notify_on_payout(),
  public.dispatch_push()
from public, anon, authenticated;

-- Realtime, so an open app's inbox and bell badge update live.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end;
$$;
