-- this was created by an AI agent
-- Trusted SQL fixtures simulate Auth's protected rows. They do NOT enroll real users.
-- All users, factors, sessions, owner-seat changes, bans and audits roll back together.
begin;
select set_config('ownertests.owner',gen_random_uuid()::text,true);
select set_config('ownertests.member',gen_random_uuid()::text,true);
select set_config('ownertests.other',gen_random_uuid()::text,true);
select set_config('ownertests.session',gen_random_uuid()::text,true);
select set_config('ownertests.member_session',gen_random_uuid()::text,true);
select set_config('ownertests.factor',gen_random_uuid()::text,true);
select set_config('ownertests.request',gen_random_uuid()::text,true);
insert into auth.users(id,email,encrypted_password,raw_user_meta_data)
select current_setting('ownertests.'||label)::uuid,label||'-'||current_setting('ownertests.'||label)||'@example.invalid','NOT_A_REAL_PASSWORD_HASH',
  jsonb_build_object('username','sec_'||label||'_'||left(current_setting('ownertests.'||label),8),'accepted_terms',true,
    'terms_version',(select version from public.legal_documents where kind='terms' and is_current),'role','owner','is_owner',true)
from (values('owner'),('member'),('other')) v(label);
insert into auth.mfa_factors(id,user_id,factor_type,status,secret,friendly_name,created_at,updated_at)
values(current_setting('ownertests.factor')::uuid,current_setting('ownertests.owner')::uuid,'totp','verified','NOT_A_REAL_AUTHENTICATOR_SEED','rollback-only fixture',now(),now());
insert into auth.sessions(id,user_id,aal,factor_id,created_at,updated_at)
values(current_setting('ownertests.session')::uuid,current_setting('ownertests.owner')::uuid,'aal2',current_setting('ownertests.factor')::uuid,now(),now()),
 (current_setting('ownertests.member_session')::uuid,current_setting('ownertests.member')::uuid,'aal1',null,now(),now());
insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at)
values(gen_random_uuid(),current_setting('ownertests.session')::uuid,'totp',now(),now());
insert into owner_private.owner_seat(singleton,user_id) values(true,current_setting('ownertests.owner')::uuid)
  on conflict(singleton) do update set user_id=excluded.user_id;

create function pg_temp.claims(actor uuid, session_id uuid, assurance text default 'aal2')
returns void language plpgsql as $$ begin
  perform set_config('request.jwt.claim.sub',actor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated','session_id',session_id,'aal',assurance)::text,true);
end; $$;
create function pg_temp.denied(statement text)
returns void language plpgsql as $$ begin
  begin execute statement; exception when insufficient_privilege then return; end;
  raise exception 'FAIL: unauthorized operation succeeded: %',statement;
end; $$;
create function pg_temp.invalid(statement text)
returns void language plpgsql as $$ begin
  begin execute statement; exception when invalid_parameter_value then return; end;
  raise exception 'FAIL: invalid operation succeeded: %',statement;
end; $$;

set local role anon;
do $$ begin
  if has_function_privilege(current_user,'public.owner_access_status()','EXECUTE')
    or has_function_privilege(current_user,'public.owner_search_accounts(text)','EXECUTE') then raise exception 'FAIL: anonymous owner RPC grant'; end if;
end; $$;
reset role;
select pg_temp.claims(current_setting('ownertests.member')::uuid,current_setting('ownertests.member_session')::uuid);
set local role authenticated;
select pg_temp.denied('select public.owner_search_accounts()');
select pg_temp.denied(format('select public.owner_account_details(%L::uuid)',current_setting('ownertests.owner')));
do $$ begin
  if (public.owner_access_status()->>'is_owner')::boolean then raise exception 'FAIL: user_metadata granted ownership'; end if;
end; $$;
reset role;

-- Real ownership alone is insufficient: both signed JWT AAL and live Auth evidence are required.
select pg_temp.claims(current_setting('ownertests.owner')::uuid,current_setting('ownertests.session')::uuid,'aal1');
set local role authenticated;
select pg_temp.denied('select public.owner_search_accounts()');
reset role;
select pg_temp.claims(current_setting('ownertests.owner')::uuid,current_setting('ownertests.session')::uuid);
update auth.sessions set aal='aal1' where id=current_setting('ownertests.session')::uuid;
set local role authenticated;
select pg_temp.denied('select public.owner_search_accounts()');
reset role;
update auth.sessions set aal='aal2' where id=current_setting('ownertests.session')::uuid;
update auth.mfa_factors set status='unverified' where id=current_setting('ownertests.factor')::uuid;
set local role authenticated;
select pg_temp.denied('select public.owner_search_accounts()');
reset role;
update auth.mfa_factors set status='verified' where id=current_setting('ownertests.factor')::uuid;
update auth.mfa_factors set factor_type='phone' where id=current_setting('ownertests.factor')::uuid;
set local role authenticated;
select pg_temp.denied('select public.owner_search_accounts()');
reset role;
update auth.mfa_factors set factor_type='totp' where id=current_setting('ownertests.factor')::uuid;
update auth.mfa_amr_claims set authentication_method='mfa/phone' where session_id=current_setting('ownertests.session')::uuid;
set local role authenticated;
select pg_temp.denied('select public.owner_search_accounts()');
reset role;
update auth.mfa_amr_claims set authentication_method='totp' where session_id=current_setting('ownertests.session')::uuid;
update auth.mfa_amr_claims set created_at=now()-interval '6 minutes',updated_at=now()-interval '6 minutes' where session_id=current_setting('ownertests.session')::uuid;
set local role authenticated;
select pg_temp.denied('select public.owner_search_accounts()');
reset role;
update auth.mfa_amr_claims set created_at=now(),updated_at=now() where session_id=current_setting('ownertests.session')::uuid;
update auth.sessions set not_after=now()-interval '1 second' where id=current_setting('ownertests.session')::uuid;
set local role authenticated;
select pg_temp.denied('select public.owner_search_accounts()');
reset role;
update auth.sessions set not_after=null where id=current_setting('ownertests.session')::uuid;
select pg_temp.claims(current_setting('ownertests.owner')::uuid,current_setting('ownertests.member_session')::uuid);
set local role authenticated;
select pg_temp.denied('select public.owner_search_accounts()');
reset role;
select pg_temp.claims(current_setting('ownertests.owner')::uuid,current_setting('ownertests.session')::uuid);
update auth.users set banned_until=now()+interval '1 hour' where id=current_setting('ownertests.owner')::uuid;
set local role authenticated;
select pg_temp.denied('select public.owner_search_accounts()');
reset role;
update auth.users set banned_until=null where id=current_setting('ownertests.owner')::uuid;

set local role authenticated;
do $$ declare account jsonb; begin
  if has_schema_privilege(current_user,'owner_private','USAGE') then raise exception 'FAIL: browser can access private owner tables'; end if;
  if has_function_privilege(current_user,'public.read_frontend_source(text)','EXECUTE') or has_function_privilege(current_user,'public.backup_frontend_source(text,text,text)','EXECUTE') then raise exception 'FAIL: account owner has source/publishing privileges'; end if;
  if not (public.owner_access_status()->>'mfa_recent')::boolean then raise exception 'FAIL: verified owner not recognized'; end if;
  account := public.owner_account_details(current_setting('ownertests.member')::uuid);
  if account::text ~ '(NOT_A_REAL|encrypted_password|refresh_token|access_token|"secret")' then raise exception 'FAIL: credential leaked'; end if;
  if jsonb_array_length(public.owner_search_accounts('sec_'))<3 then raise exception 'FAIL: account search'; end if;
end; $$;
select pg_temp.invalid(format('select public.owner_delete_account(%L::uuid,%L,%L,gen_random_uuid())',current_setting('ownertests.owner'),'anything','self wipe'));
select pg_temp.invalid(format('select public.owner_ban_account(%L::uuid,%L,%L,gen_random_uuid(),60)',current_setting('ownertests.owner'),'anything','self ban'));
select pg_temp.invalid(format('select public.owner_ban_account(%L::uuid,%L,%L,gen_random_uuid(),0)',current_setting('ownertests.member'),'wrong','invalid duration'));
select pg_temp.invalid(format('select public.owner_ban_account(%L::uuid,%L,%L,gen_random_uuid(),31536001)',current_setting('ownertests.member'),'wrong','invalid duration'));
select pg_temp.invalid(format('select public.owner_ban_account(%L::uuid,%L,%L,gen_random_uuid(),null,%L::timestamptz)',current_setting('ownertests.member'),'wrong','invalid expiry','infinity'));
select public.owner_lock_session();
select pg_temp.denied('select public.owner_search_accounts()');
reset role;
update auth.mfa_amr_claims set updated_at=clock_timestamp() where session_id=current_setting('ownertests.session')::uuid;
set local role authenticated;
do $$ begin if not (public.owner_access_status()->>'mfa_recent')::boolean then raise exception 'FAIL: later native verification did not release session lock'; end if; end; $$;
select pg_temp.invalid(format('select public.owner_delete_account(%L::uuid,%L,%L,gen_random_uuid())',current_setting('ownertests.member'),'wrong','incorrect confirmation'));
reset role;
select set_config('ownertests.member_name',(select username from public.profiles where id=current_setting('ownertests.member')::uuid),true);
select set_config('ownertests.owner_name',(select username from public.profiles where id=current_setting('ownertests.owner')::uuid),true);
set local role authenticated;
select public.owner_ban_account(current_setting('ownertests.member')::uuid,current_setting('ownertests.member_name'),'rollback fixture ban',current_setting('ownertests.request')::uuid,3600);
select public.owner_ban_account(current_setting('ownertests.member')::uuid,current_setting('ownertests.member_name'),'rollback fixture ban',current_setting('ownertests.request')::uuid,3600);
select pg_temp.invalid(format('select public.owner_ban_account(%L::uuid,%L,%L,%L::uuid,3600)',current_setting('ownertests.member'),current_setting('ownertests.member_name'),'changed input',current_setting('ownertests.request')));
reset role;
do $$ begin
  if (select count(*) from owner_private.audit_events where action='account_ban' and target_id=current_setting('ownertests.member')::uuid)<>1 then raise exception 'FAIL: duplicate action was not idempotent'; end if;
  if exists(select 1 from auth.sessions where user_id=current_setting('ownertests.member')::uuid) then raise exception 'FAIL: ban retained sessions'; end if;
  if not exists(select 1 from auth.users where id=current_setting('ownertests.member')::uuid and banned_until>now()) then raise exception 'FAIL: native Auth ban missing'; end if;
end; $$;
select pg_temp.claims(current_setting('ownertests.member')::uuid,current_setting('ownertests.member_session')::uuid,'aal1');
set local role authenticated;
do $$ begin
  if public.member_access_allowed() or (select count(*) from public.profiles)>0 or public.has_accepted_current_terms() then raise exception 'FAIL: stale banned JWT retained protected access'; end if;
end; $$;
select pg_temp.denied(format('select public.accept_current_terms(%L)',(select version from public.legal_documents where kind='terms' and is_current)));
reset role;
select pg_temp.claims(current_setting('ownertests.owner')::uuid,current_setting('ownertests.session')::uuid);
set local role authenticated;
select public.owner_unban_account(current_setting('ownertests.member')::uuid,current_setting('ownertests.member_name'),'rollback fixture early unban',gen_random_uuid());
reset role;
do $$ begin
  if exists(select 1 from auth.users where id=current_setting('ownertests.member')::uuid and banned_until>now()) then raise exception 'FAIL: unban retained native restriction'; end if;
end; $$;
-- Expiry uses server time, not a client clock or a cleanup job.
update auth.users set banned_until=now()-interval '1 second' where id=current_setting('ownertests.member')::uuid;
insert into auth.sessions(id,user_id,aal,created_at,updated_at)
values(current_setting('ownertests.member_session')::uuid,current_setting('ownertests.member')::uuid,'aal1',now(),now());
select pg_temp.claims(current_setting('ownertests.member')::uuid,current_setting('ownertests.member_session')::uuid,'aal1');
set local role authenticated;
do $$ begin if not public.member_access_allowed() or (select count(*) from public.profiles)<>1 then raise exception 'FAIL: expired ban did not restore normal account access after sign-in'; end if; end; $$;
reset role;
select pg_temp.claims(current_setting('ownertests.owner')::uuid,current_setting('ownertests.session')::uuid);
set local role authenticated;
select public.owner_delete_account(current_setting('ownertests.member')::uuid,current_setting('ownertests.member_name'),'rollback fixture delete',gen_random_uuid());
reset role;
do $$ begin
  if exists(select 1 from auth.users where id=current_setting('ownertests.member')::uuid)
    or exists(select 1 from public.profiles where id=current_setting('ownertests.member')::uuid)
    or exists(select 1 from public.terms_acceptances where user_id=current_setting('ownertests.member')::uuid)
    or exists(select 1 from auth.sessions where user_id=current_setting('ownertests.member')::uuid) then raise exception 'FAIL: account deletion incomplete'; end if;
  if not exists(select 1 from owner_private.audit_events where action='account_delete' and target_id=current_setting('ownertests.member')::uuid) then raise exception 'FAIL: deletion audit missing'; end if;
  if not exists(select 1 from auth.users where id=current_setting('ownertests.other')::uuid) then raise exception 'FAIL: unrelated account removed'; end if;
end; $$;
-- Rotating legal versions invalidates owner privilege until explicit new consent.
select set_config('ownertests.terms',(select id from public.legal_documents where kind='terms' and is_current),true);
update public.legal_documents set is_current=false where id=current_setting('ownertests.terms');
insert into public.legal_documents(id,kind,version,title,effective_at,is_current,sections)
select 'terms-owner-fixture','terms','owner-fixture',title,now(),true,sections from public.legal_documents where id=current_setting('ownertests.terms');
set local role authenticated;
select pg_temp.denied('select public.owner_search_accounts()');
select public.accept_current_terms('owner-fixture');
select public.owner_search_accounts('no-match-fixture');
reset role;
-- Both quota buckets are filled to make the boundary check deterministic across a minute tick.
insert into owner_private.quotas(actor_id,window_start,reads,writes)
select current_setting('ownertests.owner')::uuid,bucket,60,10
from generate_series(date_trunc('minute',clock_timestamp()),date_trunc('minute',clock_timestamp())+interval '1 minute',interval '1 minute') bucket
on conflict(actor_id,window_start) do update set reads=60,writes=10;
set local role authenticated;
do $$ declare detail text; begin
  begin perform public.owner_search_accounts(); raise exception 'FAIL: read limit not enforced';
  exception when raise_exception then get stacked diagnostics detail=pg_exception_detail;
    if detail is distinct from 'rate_limited' then raise; end if; end;
  begin perform public.owner_unban_account(current_setting('ownertests.other')::uuid,'anything','quota fixture',gen_random_uuid()); raise exception 'FAIL: write limit not enforced';
  exception when raise_exception then get stacked diagnostics detail=pg_exception_detail;
    if detail is distinct from 'rate_limited' then raise; end if; end;
end; $$;
reset role;
-- A revoked owner's JWT cannot retain privileged access.
delete from auth.sessions where id=current_setting('ownertests.session')::uuid;
set local role authenticated;
select pg_temp.denied('select public.owner_search_accounts()');
reset role;
rollback;
select 'Owner identity/MFA/ACL, protected account reads, typed deletion, bans, expiry, session revocation, idempotency and audit checks passed; fixtures rolled back.' as result;
