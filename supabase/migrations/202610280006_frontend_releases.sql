-- this was created by an AI agent
-- Store compiled runtime assets, never frontend source or administrator credentials.
create schema frontend_private;
revoke all on schema frontend_private from public, anon, authenticated;

create table frontend_private.releases (
  id text primary key check (id ~ '^[a-z0-9][a-z0-9-]{5,79}$'),
  created_at timestamptz not null default now(),
  published_at timestamptz,
  asset_count integer not null check (asset_count between 1 and 64),
  total_bytes integer not null check (total_bytes between 1 and 16777216)
);
create table frontend_private.assets (
  release_id text not null references frontend_private.releases(id),
  path text not null check (length(path) between 1 and 240),
  content_type text not null,
  body bytea not null check (octet_length(body) between 1 and 2097152),
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
  primary key (release_id, path)
);
create table frontend_private.site (
  singleton boolean primary key default true check (singleton),
  active_release text not null references frontend_private.releases(id)
);
alter table frontend_private.releases enable row level security;
alter table frontend_private.assets enable row level security;
alter table frontend_private.site enable row level security;
revoke all on all tables in schema frontend_private from public, anon, authenticated;

create function frontend_private.prevent_asset_edits()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'Create a new frontend release instead of editing existing assets';
end;
$$;
revoke all on function frontend_private.prevent_asset_edits() from public;
create trigger immutable_frontend_assets before update or delete on frontend_private.assets
for each row execute function frontend_private.prevent_asset_edits();

create function public.stage_frontend_release(release_id text, assets jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  item jsonb;
  asset_body bytea;
  expected_type text;
  asset_path text;
  size_sum integer := 0;
  count_assets integer;
begin
  if release_id is null or release_id !~ '^[a-z0-9][a-z0-9-]{5,79}$' then
    raise exception 'Invalid frontend release ID';
  end if;
  if jsonb_typeof(assets) is distinct from 'array' then
    raise exception 'Frontend assets must be an array';
  end if;
  count_assets := jsonb_array_length(assets);
  if count_assets not between 1 and 64 then raise exception 'Invalid frontend asset count'; end if;
  if (select count(*) from jsonb_array_elements(assets) a where a->>'path' = 'index.html') <> 1 then
    raise exception 'A frontend release needs exactly one index.html';
  end if;

  -- Every row is installed in the same transaction. A failed asset leaves no partial release.
  insert into frontend_private.releases(id, asset_count, total_bytes)
    values (release_id, count_assets, 1);
  for item in select value from jsonb_array_elements(assets) loop
    if jsonb_typeof(item) is distinct from 'object'
      or jsonb_typeof(item->'path') is distinct from 'string'
      or jsonb_typeof(item->'content_type') is distinct from 'string'
      or jsonb_typeof(item->'sha256') is distinct from 'string'
      or jsonb_typeof(item->'body_base64') is distinct from 'string' then
      raise exception 'Invalid frontend asset metadata';
    end if;
    asset_path := item->>'path';
    if asset_path !~ '^[A-Za-z0-9][A-Za-z0-9_./-]*$'
      or asset_path ~ '(^|/)\.\.?(/|$)' or asset_path like '%//%'
      or length(asset_path) > 240 then raise exception 'Invalid frontend asset path'; end if;
    expected_type := case
      when asset_path = 'index.html' then 'text/html; charset=utf-8'
      when asset_path ~ '\.js$' then 'text/javascript; charset=utf-8'
      when asset_path ~ '\.css$' then 'text/css; charset=utf-8'
      when asset_path ~ '\.svg$' then 'image/svg+xml'
      when asset_path ~ '\.png$' then 'image/png'
      when asset_path ~ '\.jpe?g$' then 'image/jpeg'
      when asset_path ~ '\.webp$' then 'image/webp'
      when asset_path ~ '\.ico$' then 'image/x-icon'
      when asset_path ~ '\.woff2$' then 'font/woff2'
      when asset_path ~ '\.woff$' then 'font/woff'
      when asset_path ~ '\.txt$' then 'text/plain; charset=utf-8'
      else null end;
    if expected_type is null or (item->>'content_type') <> expected_type then
      raise exception 'Unsupported frontend asset type';
    end if;
    asset_body := decode(item->>'body_base64', 'base64');
    if octet_length(asset_body) not between 1 and 2097152
      or (item->>'sha256') is distinct from encode(sha256(asset_body), 'hex') then
      raise exception 'Frontend asset size or checksum mismatch';
    end if;
    size_sum := size_sum + octet_length(asset_body);
    if size_sum > 16777216 then raise exception 'Frontend release is too large'; end if;
    insert into frontend_private.assets(release_id, path, content_type, body, sha256)
      values (release_id, asset_path, expected_type, asset_body, item->>'sha256');
  end loop;
  update frontend_private.releases r set total_bytes = size_sum where r.id = release_id;
end;
$$;
revoke all on function public.stage_frontend_release(text, jsonb) from public, anon, authenticated;
grant execute on function public.stage_frontend_release(text, jsonb) to service_role;

create function public.publish_frontend_release(release_id text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(761028006);
  if not exists (select 1 from frontend_private.releases r where r.id = release_id) then
    raise exception 'Frontend release does not exist';
  end if;
  update frontend_private.releases r set published_at = coalesce(r.published_at, now())
    where r.id = release_id;
  insert into frontend_private.site(singleton, active_release) values (true, release_id)
    on conflict (singleton) do update set active_release = excluded.active_release;
end;
$$;
revoke all on function public.publish_frontend_release(text) from public, anon, authenticated;
grant execute on function public.publish_frontend_release(text) to service_role;

-- Public reads expose only compiled assets from explicitly published releases.
-- Drafts, source files, and all writes remain inaccessible to browser roles.
create function public.read_frontend_asset(release_id text, asset_path text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'release_id', r.id, 'path', a.path, 'content_type', a.content_type,
    'sha256', a.sha256, 'body_base64', encode(a.body, 'base64')
  )
  from frontend_private.releases r
  join frontend_private.assets a on a.release_id = r.id
  where r.id = coalesce($1, (select active_release from frontend_private.site where singleton))
    and r.published_at is not null and a.path = $2;
$$;
revoke all on function public.read_frontend_asset(text, text) from public;
grant execute on function public.read_frontend_asset(text, text) to anon, authenticated, service_role;
