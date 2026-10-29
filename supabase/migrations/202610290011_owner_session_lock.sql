-- this was created by an AI agent
-- An explicit UI lock must invalidate server privilege, not merely hide a panel.
-- Keep native Auth AMR records intact. A later successful native TOTP verification
-- advances its authoritative timestamp and releases this application-only lock.
create table owner_private.session_locks (
  session_id uuid primary key references auth.sessions(id) on delete cascade,
  invalidated_amr_at timestamptz not null
);
alter table owner_private.session_locks enable row level security;
revoke all on owner_private.session_locks from public,anon,authenticated;

create or replace function owner_private.totp_verified_at()
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
    and exists(select 1 from auth.users u where u.id=s.user_id and (u.banned_until is null or u.banned_until<=now()))
    and not exists(select 1 from owner_private.session_locks l where l.session_id=s.id
      and greatest(a.created_at,a.updated_at)<=l.invalidated_amr_at);
$$;
revoke all on function owner_private.totp_verified_at() from public,anon,authenticated;

-- A caller may lock only its own live owner session. This grants no inspection
-- or moderation capability, and intentionally does not need an existing unlock.
create function public.owner_lock_session()
returns void language plpgsql security definer set search_path = '' as $$
declare current_session uuid := owner_private.session_id(); proof_at timestamptz;
begin
  if not public.member_access_allowed() or not exists(
    select 1 from owner_private.owner_seat where singleton and user_id=auth.uid()
  ) then raise exception 'Owner access denied' using errcode='42501'; end if;
  select coalesce(max(greatest(a.created_at,a.updated_at)),'-infinity'::timestamptz)
    into proof_at from auth.mfa_amr_claims a
    where a.session_id=current_session and a.authentication_method='totp';
  insert into owner_private.session_locks(session_id,invalidated_amr_at)
    values(current_session,proof_at)
    on conflict(session_id) do update set invalidated_amr_at=greatest(
      owner_private.session_locks.invalidated_amr_at,excluded.invalidated_amr_at);
end;
$$;
revoke all on function public.owner_lock_session() from public,anon;
grant execute on function public.owner_lock_session() to authenticated;
