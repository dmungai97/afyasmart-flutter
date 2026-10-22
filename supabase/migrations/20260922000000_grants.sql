-- ── Ensure service_role grants ───────────────────────────────────────────────
-- Service role bypasses RLS policies, but Postgres still requires table-level
-- SELECT, INSERT, UPDATE, DELETE grants for the service_role database role.

grant usage on schema public to service_role;

grant all privileges on all tables in schema public to service_role;
grant all privileges on all sequences in schema public to service_role;
grant all privileges on all functions in schema public to service_role;

alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant all on sequences to service_role;
alter default privileges in schema public grant all on functions to service_role;
