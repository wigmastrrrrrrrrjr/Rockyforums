-- this was created by an AI agent
-- Run as postgres in a dedicated development database. Never remove BEGIN/ROLLBACK.
-- Fixtures and the active release pointer are rolled back; existing accounts are untouched.
begin;

select set_config('rockytests.frontend_a', 'test-ui-a-' || gen_random_uuid()::text, true);
select set_config('rockytests.frontend_b', 'test-ui-b-' || gen_random_uuid()::text, true);
select set_config('rockytests.frontend_bad', 'test-ui-bad-' || gen_random_uuid()::text, true);
select set_config('rockytests.frontend_fixture', jsonb_build_array(
  jsonb_build_object(
    'path', 'index.html', 'content_type', 'text/html; charset=utf-8',
    'body_base64', encode(convert_to('<!doctype html><title>Fixture</title>', 'UTF8'), 'base64'),
    'sha256', encode(sha256(convert_to('<!doctype html><title>Fixture</title>', 'UTF8')), 'hex')
  ),
  jsonb_build_object(
    'path', 'assets/app.js', 'content_type', 'text/javascript; charset=utf-8',
    'body_base64', encode(convert_to('export const fixture = true;', 'UTF8'), 'base64'),
    'sha256', encode(sha256(convert_to('export const fixture = true;', 'UTF8')), 'hex')
  )
)::text, true);

-- Failed staging must not leave a partial release or asset rows.
do $$
declare
  rejected boolean := false;
  invalid_assets jsonb := jsonb_set(
    current_setting('rockytests.frontend_fixture')::jsonb,
    '{1,sha256}', to_jsonb(repeat('0', 64))
  );
begin
  begin
    perform public.stage_frontend_release(current_setting('rockytests.frontend_bad'), invalid_assets);
  exception when raise_exception then rejected := true;
  end;
  if not rejected then raise exception 'Bad checksum was accepted'; end if;
  if exists (select 1 from frontend_private.releases where id = current_setting('rockytests.frontend_bad'))
    or exists (select 1 from frontend_private.assets where release_id = current_setting('rockytests.frontend_bad')) then
    raise exception 'Failed staging left partial data';
  end if;
end;
$$;

-- Validate IDs, index presence, traversal, unsupported source maps, MIME and duplicates.
do $$
declare
  item jsonb;
  rejected boolean;
  fixture jsonb := current_setting('rockytests.frontend_fixture')::jsonb;
begin
  for item in select value from jsonb_array_elements(jsonb_build_array(
    '[]'::jsonb,
    jsonb_build_array(fixture->1),
    jsonb_set(fixture, '{1,path}', '"../app.js"'),
    jsonb_set(fixture, '{1,path}', '"assets/app.js.map"'),
    jsonb_set(fixture, '{1,content_type}', '"text/html; charset=utf-8"'),
    jsonb_build_array(fixture->0, fixture->1, fixture->1)
  )) loop
    rejected := false;
    begin
      perform public.stage_frontend_release(current_setting('rockytests.frontend_bad'), item);
    exception when raise_exception or unique_violation then rejected := true;
    end;
    if not rejected then raise exception 'Invalid release assets were accepted'; end if;
  end loop;
  rejected := false;
  begin
    perform public.stage_frontend_release('../invalid', fixture);
  exception when raise_exception then rejected := true;
  end;
  if not rejected then raise exception 'Invalid release ID was accepted'; end if;
  if exists (select 1 from frontend_private.releases where id = current_setting('rockytests.frontend_bad')) then
    raise exception 'Invalid release persisted';
  end if;
end;
$$;

select public.stage_frontend_release(
  current_setting('rockytests.frontend_a'), current_setting('rockytests.frontend_fixture')::jsonb
);
select public.stage_frontend_release(
  current_setting('rockytests.frontend_b'), current_setting('rockytests.frontend_fixture')::jsonb
);

-- Drafts are hidden even through the SECURITY DEFINER reader.
do $$ begin
  if public.read_frontend_asset(current_setting('rockytests.frontend_a'), 'index.html') is not null then
    raise exception 'Draft release was exposed';
  end if;
  if exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'frontend_private' and c.relname in ('releases','assets','site') and not c.relrowsecurity
  ) then raise exception 'A frontend table is missing RLS'; end if;
end; $$;

select public.publish_frontend_release(current_setting('rockytests.frontend_a'));

set local role anon;
do $$ begin
  if public.read_frontend_asset(null, 'index.html')->>'release_id' is distinct from current_setting('rockytests.frontend_a') then
    raise exception 'Anonymous published read failed';
  end if;
  if public.read_frontend_asset(current_setting('rockytests.frontend_b'), 'index.html') is not null then
    raise exception 'Anonymous draft read leaked';
  end if;
  if has_schema_privilege(current_user, 'frontend_private', 'USAGE')
    or has_function_privilege(current_user, 'public.stage_frontend_release(text,jsonb)', 'EXECUTE')
    or has_function_privilege(current_user, 'public.publish_frontend_release(text)', 'EXECUTE') then
    raise exception 'Anonymous role has administrative frontend access';
  end if;
  begin
    perform public.publish_frontend_release(current_setting('rockytests.frontend_b'));
    raise exception 'Anonymous publication succeeded';
  exception when insufficient_privilege then null;
  end;
end; $$;
reset role;

set local role authenticated;
do $$ begin
  if public.read_frontend_asset(null, 'index.html')->>'release_id' is distinct from current_setting('rockytests.frontend_a') then
    raise exception 'Authenticated published read failed';
  end if;
  if public.read_frontend_asset(current_setting('rockytests.frontend_b'), 'index.html') is not null then
    raise exception 'Authenticated draft read leaked';
  end if;
  if has_schema_privilege(current_user, 'frontend_private', 'USAGE')
    or has_function_privilege(current_user, 'public.stage_frontend_release(text,jsonb)', 'EXECUTE')
    or has_function_privilege(current_user, 'public.publish_frontend_release(text)', 'EXECUTE') then
    raise exception 'Authenticated role has administrative frontend access';
  end if;
  begin
    perform public.stage_frontend_release(current_setting('rockytests.frontend_bad'), '[]'::jsonb);
    raise exception 'Authenticated staging succeeded';
  exception when insufficient_privilege then null;
  end;
end; $$;
reset role;

-- Service publishers can use the two narrow mutation functions.
set local role service_role;
select public.publish_frontend_release(current_setting('rockytests.frontend_b'));
reset role;

do $$ begin
  if public.read_frontend_asset(null, 'index.html')->>'release_id' is distinct from current_setting('rockytests.frontend_b') then
    raise exception 'Publication did not change active HTML';
  end if;
  if public.read_frontend_asset(current_setting('rockytests.frontend_a'), 'assets/app.js') is null then
    raise exception 'Publication broke older version URLs';
  end if;
  begin
    update frontend_private.assets set body = convert_to('tamper', 'UTF8')
      where release_id = current_setting('rockytests.frontend_a');
    raise exception 'Asset update succeeded';
  exception when raise_exception then
    if sqlerrm = 'Asset update succeeded' then raise; end if;
  end;
  begin
    delete from frontend_private.assets where release_id = current_setting('rockytests.frontend_a');
    raise exception 'Asset deletion succeeded';
  exception when raise_exception then
    if sqlerrm = 'Asset deletion succeeded' then raise; end if;
  end;
end; $$;

select public.publish_frontend_release(current_setting('rockytests.frontend_a'));
do $$ begin
  if public.read_frontend_asset(null, 'index.html')->>'release_id' is distinct from current_setting('rockytests.frontend_a') then
    raise exception 'Rollback did not restore the earlier release';
  end if;
  if public.read_frontend_asset(current_setting('rockytests.frontend_b'), 'assets/app.js') is null then
    raise exception 'Rollback broke the newer version URLs';
  end if;
  if public.read_frontend_asset(null, '../secret') is not null then
    raise exception 'Unknown path was readable';
  end if;
end; $$;

rollback;
select 'Frontend grants, validation, draft isolation, immutability, publication and rollback passed; fixtures rolled back.' as result;
