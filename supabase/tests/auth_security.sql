-- this was created by an AI agent

-- Run against a dedicated development Supabase database as postgres.
-- Every fixture and the simulated policy update are rolled back. No test users remain.
begin;
select set_config('rockytests.user_one', gen_random_uuid()::text, true);
select set_config('rockytests.user_two', gen_random_uuid()::text, true);

insert into auth.users (id, email, raw_user_meta_data)
values
  (current_setting('rockytests.user_one')::uuid, 'one-' || current_setting('rockytests.user_one') || '@example.invalid',
   jsonb_build_object('username', 'Case_' || left(current_setting('rockytests.user_one'), 8), 'accepted_terms', true, 'terms_version', '1.2')),
  (current_setting('rockytests.user_two')::uuid, 'two-' || current_setting('rockytests.user_two') || '@example.invalid',
   jsonb_build_object('username', 'other_' || left(current_setting('rockytests.user_two'), 8), 'accepted_terms', true, 'terms_version', '1.2'));

do $$
declare
  fixture_id uuid := current_setting('rockytests.user_one')::uuid;
  fixture_username text;
begin
  select username into fixture_username from public.profiles where id = fixture_id;
  if fixture_username is null or fixture_username <> lower(fixture_username) then
    raise exception 'FAIL: profile missing or username not normalized';
  end if;
  if not exists (select 1 from public.terms_acceptances where user_id = fixture_id and document_id = 'terms-1.2' and accepted_at = now()) then
    raise exception 'FAIL: atomic, server-timestamped consent missing';
  end if;
  if exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname in ('profiles', 'terms_acceptances', 'legal_documents') and not c.relrowsecurity
  ) then raise exception 'FAIL: RLS not enabled'; end if;

  begin
    insert into auth.users (id, raw_user_meta_data) values (gen_random_uuid(), jsonb_build_object('username', fixture_username, 'accepted_terms', true, 'terms_version', '1.2'));
    raise exception 'FAIL: duplicate username accepted';
  exception when unique_violation then null;
  end;
  begin
    insert into auth.users (id, raw_user_meta_data) values (gen_random_uuid(), '{"username":"missing_consent"}'::jsonb);
    raise exception 'FAIL: missing consent accepted';
  exception when raise_exception then
    if sqlerrm <> 'Explicit terms acceptance is required' then raise; end if;
  end;
  begin
    insert into auth.users (id, raw_user_meta_data) values (gen_random_uuid(), '{"username":"string_consent","accepted_terms":"true","terms_version":"1.2"}'::jsonb);
    raise exception 'FAIL: string consent treated as a boolean';
  exception when raise_exception then
    if sqlerrm <> 'Explicit terms acceptance is required' then raise; end if;
  end;
  begin
    insert into auth.users (id, raw_user_meta_data) values (gen_random_uuid(), '{"username":123,"accepted_terms":true,"terms_version":"1.2"}'::jsonb);
    raise exception 'FAIL: non-string username accepted';
  exception when raise_exception then
    if sqlerrm <> 'A text username is required' then raise; end if;
  end;
  begin
    insert into auth.users (id, raw_user_meta_data) values (gen_random_uuid(), '{"username":"stale_terms","accepted_terms":true,"terms_version":"0.0"}'::jsonb);
    raise exception 'FAIL: stale terms accepted';
  exception when raise_exception then
    if sqlerrm <> 'The current terms version must be accepted' then raise; end if;
  end;
  begin
    insert into auth.users (id, raw_user_meta_data) values (gen_random_uuid(), '{"username":"admin","accepted_terms":true,"terms_version":"1.2"}'::jsonb);
    raise exception 'FAIL: reserved username accepted';
  exception when check_violation then null;
  end;
  begin
    insert into auth.users (id, raw_user_meta_data) values (gen_random_uuid(), '{"username":"bad name","accepted_terms":true,"terms_version":"1.2"}'::jsonb);
    raise exception 'FAIL: malformed username accepted';
  exception when check_violation then null;
  end;
  begin
    update public.legal_documents set title = 'Changed history' where id = 'terms-1.2';
    raise exception 'FAIL: legal history was editable';
  exception when raise_exception then
    if sqlerrm <> 'Publish a new legal version instead of editing history' then raise; end if;
  end;
end;
$$;

set local role anon;
do $$
begin
  if (select count(*) from public.legal_documents where is_current) <> 2 then
    raise exception 'FAIL: published legal documents not readable anonymously';
  end if;
  if has_table_privilege(current_user, 'public.profiles', 'SELECT') or has_table_privilege(current_user, 'public.terms_acceptances', 'SELECT') then
    raise exception 'FAIL: anonymous account access';
  end if;
  if has_function_privilege(current_user, 'public.accept_current_terms(text)', 'EXECUTE') then
    raise exception 'FAIL: anonymous acceptance RPC access';
  end if;
end;
$$;
reset role;

select set_config('request.jwt.claim.sub', current_setting('rockytests.user_one'), true);
set local role authenticated;
do $$
begin
  if (select count(*) from public.profiles) <> 1 then raise exception 'FAIL: cross-account profile read'; end if;
  if (select count(*) from public.terms_acceptances) <> 1 then raise exception 'FAIL: cross-account consent read'; end if;
  if not public.has_accepted_current_terms() then raise exception 'FAIL: valid current acceptance not recognized'; end if;
  perform public.accept_current_terms('1.2');
  if (select count(*) from public.terms_acceptances) <> 1 then raise exception 'FAIL: acceptance is not idempotent'; end if;
  if has_table_privilege(current_user, 'public.profiles', 'UPDATE')
    or has_table_privilege(current_user, 'public.terms_acceptances', 'INSERT')
    or has_table_privilege(current_user, 'public.terms_acceptances', 'DELETE')
    or has_table_privilege(current_user, 'public.legal_documents', 'UPDATE') then
    raise exception 'FAIL: client has direct mutation privileges';
  end if;
end;
$$;
reset role;

-- A future feature release rotates the current version, never edits existing legal text.
update public.legal_documents set is_current = false where id = 'terms-1.2';
insert into public.legal_documents (id, kind, version, title, effective_at, sections, is_current)
select 'terms-test-next', kind, 'test-next', title, effective_at, sections, true
  from public.legal_documents where id = 'terms-1.2';
set local role authenticated;
do $$
begin
  if public.has_accepted_current_terms() then raise exception 'FAIL: old consent authorized new terms'; end if;
  begin
    perform public.accept_current_terms('1.2');
    raise exception 'FAIL: stale acceptance RPC succeeded';
  exception when raise_exception then
    if sqlerrm <> 'The terms have changed. Read the current version before accepting.' then raise; end if;
  end;
  perform public.accept_current_terms('test-next');
  perform public.accept_current_terms('test-next');
  if not public.has_accepted_current_terms() then raise exception 'FAIL: new acceptance did not unlock access'; end if;
  if (select count(*) from public.terms_acceptances) <> 2 then raise exception 'FAIL: consent history lost or duplicated'; end if;
  if exists (select 1 from public.terms_acceptances where user_id <> current_setting('rockytests.user_one')::uuid) then
    raise exception 'FAIL: another account consent became visible';
  end if;
end;
$$;
reset role;
select set_config('request.jwt.claim.sub', current_setting('rockytests.user_two'), true);
set local role authenticated;
do $$
begin
  if public.has_accepted_current_terms() then raise exception 'FAIL: another user acceptance granted access'; end if;
  if (select count(*) from public.terms_acceptances) <> 1 then raise exception 'FAIL: second member sees first member history'; end if;
end;
$$;
reset role;
rollback;
select 'Account, RLS, immutable legal history, and terms rotation checks passed; all fixtures rolled back.' as result;
