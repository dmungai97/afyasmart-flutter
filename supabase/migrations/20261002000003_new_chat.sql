-- ── "New chat" ──────────────────────────────────────────────────────────────
-- Each user has one running conversation, and the chat function feeds the
-- last 20 messages of it to the model. Once old topics fill that window they
-- colour answers to unrelated new questions, so the app offers "New chat".
--
-- chat_messages is the conversation as shown and as sent to the model;
-- chat_logs is the permanent record of every exchange. Starting a new chat
-- clears only the former, so nothing is lost for support or review, and
-- chat_count is untouched: a new chat is not a way to reset the free limit.
--
-- A function rather than a delete policy, keeping chat_messages
-- select-only for clients as the RLS migration intends.

create or replace function public.start_new_chat()
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  delete from public.chat_messages where user_id = auth.uid();
end;
$$;

revoke execute on function public.start_new_chat() from public, anon;
grant execute on function public.start_new_chat() to authenticated;
