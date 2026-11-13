-- this was created by an AI agent
-- Ownership is provisioned separately by the operator against an existing Auth UUID.
-- A username, email, user_metadata claim, or client-side flag can never grant ownership.
create schema owner_private;
revoke all on schema owner_private from public, anon, authenticated;

create table owner_private.owner_seat (
  singleton boolean primary key default true check (singleton),
  user_id uuid not null unique references auth.users(id) on delete restrict,
  bound_at timestamptz not null default now()
);
create table owner_private.bans (
  user_id uuid primary key references auth.users(id) on delete cascade,
  expires_at timestamptz not null check (isfinite(expires_at)),
  reason text not null check (length(reason) between 1 and 1000),
  issued_at timestamptz not null default now(),
  issued_by uuid not null,
  cancelled_at timestamptz
);
create table owner_private.audit_events (
  id bigint generated always as identity primary key,
  actor_id uuid not null,
  action text not null check (action in ('account_search','account_view','account_ban','account_unban','account_delete')),
  target_id uuid,
  target_username text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp()
);
create index owner_audit_recent_idx on owner_private.audit_events(created_at desc);
create table owner_private.action_receipts (
  request_id uuid primary key,
  actor_id uuid not null,
  action text not null,
  target_id uuid not null,
  input_hash text not null,
  result jsonb not null,
  created_at timestamptz not null default clock_timestamp()
);
create table owner_private.quotas (
  actor_id uuid not null,
  window_start timestamptz not null,
  reads integer not null default 0,
  writes integer not null default 0,
  primary key (actor_id, window_start)
);
alter table owner_private.owner_seat enable row level security;
alter table owner_private.bans enable row level security;
alter table owner_private.audit_events enable row level security;
alter table owner_private.action_receipts enable row level security;
alter table owner_private.quotas enable row level security;
revoke all on all tables in schema owner_private from public, anon, authenticated;
revoke all on all sequences in schema owner_private from public, anon, authenticated;

create function owner_private.session_id()
returns uuid language plpgsql stable set search_path = '' as $$
declare value text := auth.jwt()->>'session_id';
begin
  if value ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    return value::uuid;
  end if;
  return null;
end;
$$;

-- Also check the live Auth session: a JWT remains cryptographically valid after logout/ban.
create function public.member_access_allowed()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from auth.users u join auth.sessions s on s.user_id=u.id
    where u.id=(select auth.uid()) and s.id=owner_private.session_id()
      and (s.not_after is null or s.not_after > now())
      and (u.banned_until is null or u.banned_until <= now())
  );
$$;
revoke all on function public.member_access_allowed() from public, anon;
grant execute on function public.member_access_allowed() to authenticated;

drop policy "Members read only their own profile" on public.profiles;
create policy "Active members read only their own profile" on public.profiles
  for select to authenticated using ((select auth.uid())=id and (select public.member_access_allowed()));
drop policy "Members read only their own consent history" on public.terms_acceptances;
create policy "Active members read only their own consent history" on public.terms_acceptances
  for select to authenticated using ((select auth.uid())=user_id and (select public.member_access_allowed()));

create or replace function public.accept_current_terms(document_version text)
returns void language plpgsql security definer set search_path = '' as $$
declare member_id uuid := auth.uid(); current_document_id text;
begin
  if member_id is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if not public.member_access_allowed() then raise exception 'An active, unrestricted account session is required' using errcode='42501'; end if;
  select id into current_document_id from public.legal_documents
    where kind='terms' and is_current and effective_at<=now() and version=document_version for share;
  if current_document_id is null then raise exception 'The terms have changed. Read the current version before accepting.'; end if;
  insert into public.terms_acceptances(user_id,document_id) values(member_id,current_document_id)
    on conflict do nothing;
end;
$$;
create or replace function public.has_accepted_current_terms()
returns boolean language sql stable security invoker set search_path = '' as $$
  select public.member_access_allowed() and exists (
    select 1 from public.terms_acceptances a join public.legal_documents d on d.id=a.document_id
    where a.user_id=(select auth.uid()) and d.kind='terms' and d.is_current and d.effective_at<=now()
  );
$$;

create function owner_private.totp_verified_at()
returns timestamptz language sql stable security definer set search_path = '' as $$
  select max(greatest(a.created_at,a.updated_at))
  from auth.sessions s
  join auth.mfa_factors f on f.id=s.factor_id and f.user_id=s.user_id
  join auth.mfa_amr_claims a on a.session_id=s.id
  where s.id=owner_private.session_id() and s.user_id=(select auth.uid())
    and s.aal::text='aal2' and auth.jwt()->>'aal'='aal2'
    and f.factor_type::text='totp' and f.status::text='verified'
    and a.authentication_method='totp'
    and (s.not_after is null or s.not_after>now())
    and exists(select 1 from auth.users u where u.id=s.user_id and (u.banned_until is null or u.banned_until<=now()));
$$;
create function owner_private.assert_owner()
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); verified_at timestamptz;
begin
  perform 1 from owner_private.owner_seat where singleton and user_id=actor for share;
  if not found or not public.member_access_allowed() then
    raise exception 'Owner access denied' using errcode='42501';
  end if;
  verified_at := owner_private.totp_verified_at();
  if verified_at is null or verified_at<clock_timestamp()-interval '5 minutes' or verified_at>clock_timestamp()+interval '30 seconds' then
    raise exception 'Verify your owner authenticator again' using errcode='42501', detail='owner_mfa_required';
  end if;
  if not public.has_accepted_current_terms() then
    raise exception 'Accept the current terms before using owner tools' using errcode='42501', detail='current_terms_required';
  end if;
  return actor;
end;
$$;

-- The status endpoint exposes only the caller's own setup/access state, not account data.
create function public.owner_access_status()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actor uuid := auth.uid(); is_owner boolean; verified_at timestamptz; banned_until timestamptz; ban_reason text;
begin
  if actor is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if not exists(select 1 from auth.users where id=actor) then raise exception 'Account no longer exists' using errcode='42501'; end if;
  select u.banned_until into banned_until from auth.users u where u.id=actor;
  if banned_until>now() then
    select b.reason into ban_reason from owner_private.bans b where b.user_id=actor and b.cancelled_at is null and b.expires_at>now();
    return jsonb_build_object('is_owner',false,'account_active',false,'banned_until',banned_until,'ban_reason',ban_reason);
  end if;
  is_owner := exists(select 1 from owner_private.owner_seat where singleton and user_id=actor);
  if not is_owner then return jsonb_build_object('is_owner',false,'account_active',public.member_access_allowed()); end if;
  verified_at := owner_private.totp_verified_at();
  return jsonb_build_object(
    'is_owner',true,'account_active',public.member_access_allowed(),
    'totp_enrolled',exists(select 1 from auth.mfa_factors where user_id=actor and factor_type::text='totp' and status::text='verified'),
    'mfa_recent',coalesce(verified_at>=now()-interval '5 minutes' and verified_at<=now()+interval '30 seconds',false),
    'verified_until',case when verified_at is not null then verified_at+interval '5 minutes' else null end,
    'terms_accepted',public.has_accepted_current_terms(),
    'terms_version',(select version from public.legal_documents where kind='terms' and is_current and effective_at<=now())
  );
end;
$$;
revoke all on function public.owner_access_status() from public, anon;
grant execute on function public.owner_access_status() to authenticated;

create function owner_private.take_quota(is_write boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare bucket timestamptz := date_trunc('minute',clock_timestamp()); n integer;
begin
  insert into owner_private.quotas(actor_id,window_start,reads,writes)
    values(auth.uid(),bucket,case when is_write then 0 else 1 end,case when is_write then 1 else 0 end)
    on conflict(actor_id,window_start) do update set
      reads=owner_private.quotas.reads+case when is_write then 0 else 1 end,
      writes=owner_private.quotas.writes+case when is_write then 1 else 0 end
    returning case when is_write then writes else reads end into n;
  if n>(case when is_write then 10 else 60 end) then raise exception 'Owner action rate limit reached' using errcode='P0001', detail='rate_limited'; end if;
end;
$$;
create function owner_private.operation_replay(request_id uuid, operation text, target_id uuid, inputs jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare receipt owner_private.action_receipts; fingerprint text;
begin
  if request_id is null or target_id is null then raise exception 'A target and request ID are required' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(request_id::text,19734));
  perform owner_private.assert_owner();
  fingerprint := encode(sha256(convert_to(inputs::text,'UTF8')),'hex');
  select * into receipt from owner_private.action_receipts r where r.request_id=operation_replay.request_id;
  if found then
    if receipt.actor_id<>auth.uid() or receipt.action<>operation or receipt.target_id<>operation_replay.target_id or receipt.input_hash<>fingerprint then
      raise exception 'Request ID was already used for a different action' using errcode='22023';
    end if;
    return receipt.result;
  end if;
  perform owner_private.take_quota(true);
  return null;
end;
$$;
create function owner_private.finish_operation(request_id uuid, operation text, target_id uuid, username text, inputs jsonb, result jsonb, details jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  insert into owner_private.audit_events(actor_id,action,target_id,target_username,details)
    values(auth.uid(),operation,target_id,username,details);
  insert into owner_private.action_receipts(request_id,actor_id,action,target_id,input_hash,result)
    values(request_id,auth.uid(),operation,target_id,encode(sha256(convert_to(inputs::text,'UTF8')),'hex'),result);
  return result;
end;
$$;
revoke all on all functions in schema owner_private from public, anon, authenticated;
