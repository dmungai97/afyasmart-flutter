-- Gives back a symptom check that was counted but never delivered. The
-- analyze endpoint used to answer an OpenAI failure with a canned result, so
-- every counted call returned something. It now returns an honest error, and
-- a user who retries after one should not lose a free check to our outage.
create or replace function public.release_symptom_quota(
  p_subject_id text,
  p_kind       symptom_check_kind
)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  update public.symptom_check_quota
     set count      = greatest(count - 1, 0),
         updated_at = now()
   where subject_id = p_subject_id
     and kind       = p_kind
     and day        = current_date;
end;
$$;

revoke execute on function public.release_symptom_quota(text, symptom_check_kind)
  from public, anon, authenticated;
grant execute on function public.release_symptom_quota(text, symptom_check_kind)
  to service_role;
