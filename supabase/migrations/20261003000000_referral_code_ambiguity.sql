-- ── Fix ambiguous `code` references in the referral functions ───────────────
-- All three functions named a variable or parameter `code`, the same as the
-- affiliates.code column, and then wrote `upper(code)` unqualified:
--   * handle_new_user() and claim_referral() are plpgsql, where that is a
--     hard "column reference is ambiguous" error. In the trigger it aborted
--     the auth.users insert, so every sign-up carrying a referral code failed
--     with "Database error saving new user".
--   * resolve_referral_code() is plain SQL, where the column silently wins:
--     it compared each code to itself and returned an arbitrary affiliate.
-- Parameter names are part of the RPC interface, so those are qualified
-- rather than renamed.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  referrer_id uuid;
  ref_code    text;
begin
  ref_code := nullif(trim(new.raw_user_meta_data ->> 'referral_code'), '');

  if ref_code is not null then
    select id into referrer_id from public.affiliates where affiliates.code = upper(ref_code);
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

create or replace function public.claim_referral(code text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  caller      uuid := auth.uid();
  referrer_id uuid;
  ref_code    text;
  claimed     integer;
begin
  if caller is null then
    raise exception 'not authenticated';
  end if;

  ref_code := nullif(trim(claim_referral.code), '');
  if ref_code is null then
    return false;
  end if;

  select id into referrer_id from public.affiliates where affiliates.code = upper(ref_code);
  if referrer_id is null or referrer_id = caller then
    return false;
  end if;

  update public.users
     set referred_by_uid = referrer_id
   where id = caller
     and referred_by_uid is null
     and not has_subscribed
     and created_at > now() - interval '1 hour';
  get diagnostics claimed = row_count;

  if claimed = 0 then
    return false;
  end if;

  update public.affiliates
     set referrals_count = referrals_count + 1
   where id = referrer_id;

  return true;
end;
$$;

create or replace function public.resolve_referral_code(code text)
returns uuid
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select id from public.affiliates where affiliates.code = upper(trim(resolve_referral_code.code));
$$;
