-- this was created by an AI agent
-- Optional operator-only source backups, separate from browser-readable compiled assets.
-- An owner-console session, even at AAL2, is NOT a source-backup or service-role credential.
create table frontend_private.source_archives (
  release_id text primary key references frontend_private.releases(id),
  format text not null check (format='rockyforums.private-source.gzip.v1'),
  body bytea not null check (octet_length(body) between 1 and 2097152),
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now()
);
alter table frontend_private.source_archives enable row level security;
revoke all on frontend_private.source_archives from public,anon,authenticated;
create trigger immutable_frontend_source_backups before update or delete on frontend_private.source_archives
for each row execute function frontend_private.prevent_asset_edits();
create function public.backup_frontend_source(release_id text, archive_base64 text, sha256 text)
returns void language plpgsql security definer set search_path = '' as $$
declare bytes bytea;
begin
  if archive_base64 is null or length(archive_base64)>2800000 then raise exception 'Invalid source archive size'; end if;
  bytes := decode(archive_base64,'base64');
  if octet_length(bytes) not between 1 and 2097152 or encode(sha256(bytes),'hex') is distinct from sha256 then
    raise exception 'Invalid source archive checksum';
  end if;
  insert into frontend_private.source_archives(release_id,format,body,sha256)
    values(release_id,'rockyforums.private-source.gzip.v1',bytes,sha256);
end;
$$;
create function public.read_frontend_source(release_id text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('release_id',a.release_id,'format',a.format,'sha256',a.sha256,'body_base64',encode(a.body,'base64'))
    from frontend_private.source_archives a where a.release_id=read_frontend_source.release_id;
$$;
revoke all on function public.backup_frontend_source(text,text,text),public.read_frontend_source(text) from public,anon,authenticated;
grant execute on function public.backup_frontend_source(text,text,text),public.read_frontend_source(text) to service_role;
