-- ── Self-service account deletion ────────────────────────────────────────────
-- The account edge function deletes the auth.users row, and every table
-- hanging off public.users cascades with it. One of those cascades was wrong:
--
-- commissions.referred_id cascaded, so when a referred user deleted their
-- account the referrer's commission row vanished. The money was real (the
-- referred user paid), and for a still-pending commission it was worse:
-- pending_balance had already been credited, release_affiliate_commissions()
-- would never find the row to move it to available_balance, and the amount
-- would sit in pending_balance forever.
--
-- The commission is the affiliate's record, not the deleted user's, so it now
-- survives with the referred user detached.

alter table public.commissions
  alter column referred_id drop not null;

alter table public.commissions
  drop constraint commissions_referred_id_fkey,
  add constraint commissions_referred_id_fkey
    foreign key (referred_id) references public.users (id) on delete set null;
