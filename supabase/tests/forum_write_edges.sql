-- this was created by an AI agent
-- Additional native-role write/consent/quota cases; every fixture is rolled back.
begin;
select set_config('forumedge.a',gen_random_uuid()::text,true);
select set_config('forumedge.b',gen_random_uuid()::text,true);
select set_config('forumedge.sa',gen_random_uuid()::text,true);
select set_config('forumedge.sb',gen_random_uuid()::text,true);
select set_config('forumedge.request',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select current_setting('forumedge.'||label)::uuid,current_setting('forumedge.'||label)||'@example.invalid',jsonb_build_object('username','edge_'||label||'_'||left(current_setting('forumedge.'||label),8),'accepted_terms',true,'terms_version',(select version from public.legal_documents where kind='terms' and is_current)) from(values('a'),('b'))v(label);
insert into auth.sessions(id,user_id,aal,created_at,updated_at) values(current_setting('forumedge.sa')::uuid,current_setting('forumedge.a')::uuid,'aal1',now(),now()),(current_setting('forumedge.sb')::uuid,current_setting('forumedge.b')::uuid,'aal1',now(),now());
update forum_private.site set enabled=true;
create function pg_temp.edge_actor(label text) returns void language plpgsql as $$begin
  perform set_config('request.jwt.claim.sub',current_setting('forumedge.'||label),true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('forumedge.'||label),'session_id',current_setting('forumedge.s'||label),'role','authenticated','aal','aal1')::text,true);
end;$$;
create function pg_temp.edge_error(statement text,code text,detail text default null) returns void language plpgsql as $$declare actual_detail text;begin
  begin execute statement;exception when others then get stacked diagnostics actual_detail=pg_exception_detail;
    if sqlstate=code and (detail is null or detail=actual_detail) then return;else raise;end if;end;
  raise exception 'FAIL: unexpectedly allowed: %',statement;
end;$$;
select pg_temp.edge_actor('a');
set local role authenticated;
select set_config('forumedge.thread',public.forum_create_thread('general','Edge fixture thread','Edge fixture body',current_setting('forumedge.request')::uuid)->>'thread_id',true);
reset role;
select pg_temp.edge_actor('b');
set local role authenticated;
-- A receipt cannot be replayed under another account, even with identical inputs.
select pg_temp.edge_error(format('select public.forum_create_thread(''general'',''Edge fixture thread'',''Edge fixture body'',%L::uuid)',current_setting('forumedge.request')),'22023');
select set_config('forumedge.reply',public.forum_create_reply(current_setting('forumedge.thread')::uuid,'Editable fixture reply',gen_random_uuid())->>'reply_id',true);
select set_config('forumedge.updated',public.forum_get_thread(current_setting('forumedge.thread')::uuid)->'replies'->0->>'updated_at',true);
select public.forum_edit_reply(current_setting('forumedge.reply')::uuid,'Edited reply',current_setting('forumedge.updated')::timestamptz,gen_random_uuid());
select pg_temp.edge_error(format('select public.forum_edit_reply(%L::uuid,''stale'',%L::timestamptz,gen_random_uuid())',current_setting('forumedge.reply'),current_setting('forumedge.updated')),'22023');
select public.forum_delete_reply(current_setting('forumedge.reply')::uuid,gen_random_uuid());
select set_config('forumedge.scratch',public.forum_create_thread('help','Delete this fixture','Fixture body',gen_random_uuid())->>'thread_id',true);
select pg_temp.edge_error(format('select public.forum_delete_thread(%L::uuid,''wrong title'',gen_random_uuid())',current_setting('forumedge.scratch')),'22023');
select public.forum_delete_thread(current_setting('forumedge.scratch')::uuid,'Delete this fixture',gen_random_uuid());
reset role;
do $$begin if exists(select 1 from forum_private.threads where id=current_setting('forumedge.scratch')::uuid) or exists(select 1 from forum_private.replies where id=current_setting('forumedge.reply')::uuid) then raise exception 'FAIL: own removal';end if;end;$$;
-- A real UUID owner seat without native TOTP proof does not authorize moderation.
insert into owner_private.owner_seat(singleton,user_id) values(true,current_setting('forumedge.a')::uuid) on conflict(singleton) do update set user_id=excluded.user_id;
select pg_temp.edge_actor('a');
set local role authenticated;
select pg_temp.edge_error(format('select public.owner_set_thread_locked(%L::uuid,true,''missing native proof'',gen_random_uuid())',current_setting('forumedge.thread')),'42501','owner_mfa_required');
reset role;
-- Rotating terms never upgrades old acceptance implicitly.
select set_config('forumedge.terms',(select id from public.legal_documents where kind='terms' and is_current),true);
update public.legal_documents set is_current=false where id=current_setting('forumedge.terms');
insert into public.legal_documents(id,kind,version,title,effective_at,is_current,sections) select 'terms-forum-edge-fixture','terms','forum-edge-fixture',title,now(),true,sections from public.legal_documents where id=current_setting('forumedge.terms');
set local role authenticated;
select pg_temp.edge_error(format('select public.forum_create_reply(%L::uuid,''stale consent'',gen_random_uuid())',current_setting('forumedge.thread')),'42501','current_terms_required');
select public.accept_current_terms('forum-edge-fixture');
select public.forum_create_reply(current_setting('forumedge.thread')::uuid,'Explicit current consent',gen_random_uuid());
reset role;
-- Fill current and next buckets so a minute tick cannot make this flaky.
insert into forum_private.quotas(actor_id,window_start,threads,writes) select current_setting('forumedge.a')::uuid,bucket,0,20 from generate_series(date_trunc('minute',clock_timestamp()),date_trunc('minute',clock_timestamp())+interval '1 minute',interval '1 minute') bucket on conflict(actor_id,window_start) do update set threads=0,writes=20;
set local role authenticated;
select pg_temp.edge_error(format('select public.forum_create_reply(%L::uuid,''over write limit'',gen_random_uuid())',current_setting('forumedge.thread')),'P0001','rate_limited');
reset role;
update forum_private.quotas set threads=3,writes=0 where actor_id=current_setting('forumedge.a')::uuid;
set local role authenticated;
select pg_temp.edge_error('select public.forum_create_thread(''general'',''over thread limit'',''body'',gen_random_uuid())','P0001','rate_limited');
reset role;
rollback;
select 'Own reply edits/removal, own thread removal, cross-account receipts, missing native TOTP, current-terms rotation and both posting quotas passed; fixtures rolled back.' as result;
