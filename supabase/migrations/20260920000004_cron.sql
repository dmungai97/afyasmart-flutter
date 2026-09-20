-- Replaces the two onSchedule() Cloud Functions in functions/index.js.
--
-- pg_cron runs inside the database, so these need no deployment, no billing
-- plan, and no auth hop — which was the whole reason the M-Pesa and chat
-- functions were pushed out to Supabase Edge Functions in the first place
-- (see the comment in src/services/mpesa.service.ts).

create extension if not exists pg_cron with schema extensions;

-- expireStalePayments: every 15 minutes.
select cron.schedule(
  'expire-stale-payments',
  '*/15 * * * *',
  $$select public.expire_stale_payments()$$
);

-- releaseAffiliateCommissions: daily. Pinned to 02:00 UTC rather than
-- "every 24 hours" from deploy time, so the run time is predictable.
select cron.schedule(
  'release-affiliate-commissions',
  '0 2 * * *',
  $$select public.release_affiliate_commissions()$$
);
