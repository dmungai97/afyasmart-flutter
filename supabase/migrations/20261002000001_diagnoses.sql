-- ── Diagnosis history ──────────────────────────────────────────────────────
-- Symptom-check results used to live only in the device's SharedPreferences,
-- one at a time, so the Medical History screen could show at most the latest
-- result and lost even that on logout, reinstall or a new phone.
--
-- Rows are written by the client straight after a signed-in symptom check.
-- That is safe to leave client-writable: a row only ever describes the
-- caller's own history, nothing reads it to make a decision, and the paid
-- analysis itself still goes through the symptoms edge function's quota.
-- conditions and medications keep the exact JSON shape the app already
-- persists locally, so one model serves both.

create table public.diagnoses (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null references public.users (id) on delete cascade,
  symptoms    text        not null default '',
  summary     text        not null default '',
  urgency     text        not null default 'Low',
  conditions  jsonb       not null default '[]'::jsonb check (jsonb_typeof(conditions) = 'array'),
  medications jsonb       not null default '[]'::jsonb check (jsonb_typeof(medications) = 'array'),
  created_at  timestamptz not null default now()
);

create index diagnoses_user_created_idx on public.diagnoses (user_id, created_at desc);

alter table public.diagnoses enable row level security;

create policy diagnoses_select on public.diagnoses
  for select to authenticated
  using (user_id = auth.uid());

create policy diagnoses_insert on public.diagnoses
  for insert to authenticated
  with check (user_id = auth.uid());

create policy diagnoses_delete on public.diagnoses
  for delete to authenticated
  using (user_id = auth.uid());

revoke all on public.diagnoses from anon, authenticated;
grant select, insert, delete on public.diagnoses to authenticated;
grant all on public.diagnoses to service_role;
