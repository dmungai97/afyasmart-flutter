-- ── Admin Catalogue Write Policies ──────────────────────────────────────────
-- Allows authenticated admins to INSERT, UPDATE, and DELETE facilities/catalogue
-- rows (doctors, pharmacies, drugs) directly from the Admin Facilities screen.

create policy doctors_admin_manage on public.doctors
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy pharmacies_admin_manage on public.pharmacies
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy drugs_admin_manage on public.drugs
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

grant insert, update, delete on public.doctors, public.pharmacies, public.drugs to authenticated;
