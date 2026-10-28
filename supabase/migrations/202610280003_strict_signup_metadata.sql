-- Treat signup metadata as untrusted JSON, including its scalar types.
create or replace function public.handle_new_rockyforums_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  current_document_id text;
begin
  if new.raw_user_meta_data->'accepted_terms' is distinct from 'true'::jsonb then
    raise exception 'Explicit terms acceptance is required';
  end if;
  if jsonb_typeof(new.raw_user_meta_data->'username') is distinct from 'string' then
    raise exception 'A text username is required';
  end if;
  if jsonb_typeof(new.raw_user_meta_data->'terms_version') is distinct from 'string' then
    raise exception 'The current terms version must be accepted';
  end if;
  select id into current_document_id from public.legal_documents
    where kind = 'terms' and is_current and effective_at <= now()
      and version = new.raw_user_meta_data->>'terms_version'
    for share;
  if current_document_id is null then
    raise exception 'The current terms version must be accepted';
  end if;
  insert into public.profiles (id, username)
    values (new.id, lower(btrim(new.raw_user_meta_data->>'username')));
  insert into public.terms_acceptances (user_id, document_id)
    values (new.id, current_document_id);
  return new;
end;
$$;
revoke all on function public.handle_new_rockyforums_user() from public, anon, authenticated;
