-- ── Referral attribution for Google sign-ups ───────────────────────────────
-- handle_new_user() reads the referral code from raw_user_meta_data, which
-- only an email signUp() can set. signInWithIdToken() (Google) creates the
-- auth.users row with Google's metadata, so a referred user who chose Google
-- was never attributed and the affiliate never earned the commission.
--
-- claim_referral() lets the client attach the code right after that first
-- sign-in. It is deliberately narrow so it cannot be used to re-point an
-- existing referral or to attach one long after the fact:
--   * only the caller's own row,
--   * only while referred_by_uid is still null,
--   * only within an hour of the account being created,
--   * only before the account has ever subscribed (commission is credited at
--     activation, so a later claim could never pay out anyway).
-- Like handle_new_user(), an unknown code or a self-referral is a quiet no-op
-- rather than an error: a bad link must never break sign-in.

create or replace function public.claim_referral(code text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  caller      uuid := auth.uid();
  referrer_id uuid;
  claimed     integer;
begin
  if caller is null then
    raise exception 'not authenticated';
  end if;

  code := nullif(trim(code), '');
  if code is null then
    return false;
  end if;

  select id into referrer_id from public.affiliates where affiliates.code = upper(code);
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

revoke execute on function public.claim_referral(text) from public, anon;
grant execute on function public.claim_referral(text) to authenticated;
