-- this was created by an AI agent
-- Dedicated-database rollback fixtures. No visible discussions/users are left behind.
begin;
select set_config('forumtests.a',gen_random_uuid()::text,true);
select set_config('forumtests.b',gen_random_uuid()::text,true);
select set_config('forumtests.owner',gen_random_uuid()::text,true);
select set_config('forumtests.sa',gen_random_uuid()::text,true);
select set_config('forumtests.sb',gen_random_uuid()::text,true);
select set_config('forumtests.so',gen_random_uuid()::text,true);
select set_config('forumtests.factor',gen_random_uuid()::text,true);
select set_config('forumtests.request',gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data)
select current_setting('forumtests.'||label)::uuid,label||'-'||current_setting('forumtests.'||label)||'@example.invalid',jsonb_build_object('username','forum_'||label||'_'||left(current_setting('forumtests.'||label),8),'accepted_terms',true,'terms_version',(select version from public.legal_documents where kind='terms' and is_current)) from(values('a'),('b'),('owner'))v(label);
insert into auth.sessions(id,user_id,aal,created_at,updated_at)
values(current_setting('forumtests.sa')::uuid,current_setting('forumtests.a')::uuid,'aal1',now(),now()),(current_setting('forumtests.sb')::uuid,current_setting('forumtests.b')::uuid,'aal1',now(),now()),(current_setting('forumtests.so')::uuid,current_setting('forumtests.owner')::uuid,'aal2',now(),now());
insert into auth.mfa_factors(id,user_id,factor_type,status,secret,created_at,updated_at) values(current_setting('forumtests.factor')::uuid,current_setting('forumtests.owner')::uuid,'totp','verified','NOT_A_REAL_SEED',now(),now());
update auth.sessions set factor_id=current_setting('forumtests.factor')::uuid where id=current_setting('forumtests.so')::uuid;
insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values(gen_random_uuid(),current_setting('forumtests.so')::uuid,'totp',now(),now());
insert into owner_private.owner_seat(singleton,user_id) values(true,current_setting('forumtests.owner')::uuid) on conflict(singleton) do update set user_id=excluded.user_id;
create function pg_temp.as_member(actor uuid,session_id uuid,aal text default 'aal1') returns void language plpgsql as $$ begin
  perform set_config('request.jwt.claim.sub',actor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',session_id,'role','authenticated','aal',aal)::text,true);
end; $$;
create function pg_temp.expect_error(statement text,expected_code text) returns void language plpgsql as $$ begin
  begin execute statement; exception when others then if sqlstate=expected_code then return;else raise;end if;end;
  raise exception 'FAIL: operation unexpectedly succeeded: %',statement;
end; $$;
set local role anon;
do $$ begin
  if jsonb_array_length(public.forum_categories())<>3 then raise exception 'FAIL: category configuration';end if;
  if has_schema_privilege(current_user,'forum_private','USAGE') or has_function_privilege(current_user,'public.forum_create_thread(text,text,text,uuid)','EXECUTE') then raise exception 'FAIL: anonymous write/private schema grants';end if;
end; $$;
reset role;
select pg_temp.as_member(current_setting('forumtests.a')::uuid,current_setting('forumtests.sa')::uuid);
-- Rollout/maintenance switch blocks even an otherwise valid member.
update forum_private.site set enabled=false;
set local role authenticated;
select pg_temp.expect_error('select public.forum_create_thread(''general'',''paused'',''paused'',gen_random_uuid())','42501');
reset role;
update forum_private.site set enabled=true;
set local role authenticated;
select set_config('forumtests.thread',(public.forum_create_thread('general','Rollback fixture thread','Public fixture body <script>not executable</script>',current_setting('forumtests.request')::uuid)->>'thread_id'),true);
select public.forum_create_thread('general','Rollback fixture thread','Public fixture body <script>not executable</script>',current_setting('forumtests.request')::uuid);
select pg_temp.expect_error(format('select public.forum_create_thread(''general'',''different input'',''body'',%L::uuid)',current_setting('forumtests.request')),'22023');
select pg_temp.expect_error('select public.forum_create_thread(''general'',''empty body'','''',gen_random_uuid())','22023');
reset role;
do $$ declare data jsonb;begin
  if(select count(*) from forum_private.threads where id=current_setting('forumtests.thread')::uuid)<>1 then raise exception 'FAIL: duplicate thread';end if;
  data:=public.forum_get_thread(current_setting('forumtests.thread')::uuid);
  if data::text like '%@example.invalid%' or data::text like '%'||current_setting('forumtests.a')||'%' or data::text ~ '(author_id|encrypted_password|refresh_token)' then raise exception 'FAIL: public reader leaked account information';end if;
end; $$;
select pg_temp.as_member(current_setting('forumtests.b')::uuid,current_setting('forumtests.sb')::uuid);
set local role authenticated;
select set_config('forumtests.reply',(public.forum_create_reply(current_setting('forumtests.thread')::uuid,'Reply from a second account',gen_random_uuid())->>'reply_id'),true);
select pg_temp.expect_error(format('select public.forum_delete_thread(%L::uuid,''Rollback fixture thread'',gen_random_uuid())',current_setting('forumtests.thread')),'42501');
select pg_temp.expect_error(format('select public.forum_edit_thread(%L::uuid,''stolen'',''stolen'',now(),gen_random_uuid())',current_setting('forumtests.thread')),'42501');
select pg_temp.expect_error(format('select public.owner_set_thread_locked(%L::uuid,true,''forged owner'',gen_random_uuid())',current_setting('forumtests.thread')),'42501');
reset role;
select pg_temp.as_member(current_setting('forumtests.a')::uuid,current_setting('forumtests.sa')::uuid);
select set_config('forumtests.updated',(select updated_at::text from forum_private.threads where id=current_setting('forumtests.thread')::uuid),true);
set local role authenticated;
select public.forum_edit_thread(current_setting('forumtests.thread')::uuid,'Edited fixture thread','Edited body',current_setting('forumtests.updated')::timestamptz,gen_random_uuid());
select pg_temp.expect_error(format('select public.forum_edit_thread(%L::uuid,''stale edit'',''body'',%L::timestamptz,gen_random_uuid())',current_setting('forumtests.thread'),current_setting('forumtests.updated')),'22023');
select pg_temp.expect_error(format('select public.forum_delete_reply(%L::uuid,gen_random_uuid())',current_setting('forumtests.reply')),'42501');
reset role;
select pg_temp.as_member(current_setting('forumtests.owner')::uuid,current_setting('forumtests.so')::uuid,'aal2');
set local role authenticated;
select public.owner_set_thread_locked(current_setting('forumtests.thread')::uuid,true,'Rollback fixture lock',gen_random_uuid());
reset role;
select pg_temp.as_member(current_setting('forumtests.b')::uuid,current_setting('forumtests.sb')::uuid);
set local role authenticated;
select pg_temp.expect_error(format('select public.forum_create_reply(%L::uuid,''locked reply'',gen_random_uuid())',current_setting('forumtests.thread')),'22023');
reset role;
select pg_temp.as_member(current_setting('forumtests.owner')::uuid,current_setting('forumtests.so')::uuid,'aal2');
set local role authenticated;
select public.owner_set_thread_locked(current_setting('forumtests.thread')::uuid,false,'Rollback fixture unlock',gen_random_uuid());
select public.owner_delete_forum_reply(current_setting('forumtests.reply')::uuid,'Rollback fixture removal',gen_random_uuid());
reset role;
-- Already-signed-in banned users cannot create, reply, edit, delete or replay writes.
update auth.users set banned_until=now()+interval '1 hour' where id=current_setting('forumtests.a')::uuid;
select pg_temp.as_member(current_setting('forumtests.a')::uuid,current_setting('forumtests.sa')::uuid);
set local role authenticated;
select pg_temp.expect_error('select public.forum_create_thread(''general'',''banned'',''body'',gen_random_uuid())','42501');
select pg_temp.expect_error(format('select public.forum_create_reply(%L::uuid,''banned reply'',gen_random_uuid())',current_setting('forumtests.thread')),'42501');
select pg_temp.expect_error(format('select public.forum_delete_thread(%L::uuid,''Edited fixture thread'',gen_random_uuid())',current_setting('forumtests.thread')),'42501');
reset role;
update auth.users set banned_until=now()-interval '1 second' where id=current_setting('forumtests.a')::uuid;
select pg_temp.as_member(current_setting('forumtests.b')::uuid,current_setting('forumtests.sb')::uuid);
set local role authenticated;
select public.forum_create_reply(current_setting('forumtests.thread')::uuid,'Reply removed by parent account wipe',gen_random_uuid());
reset role;
-- A real account wipe cascades through authored threads and their replies.
delete from auth.users where id=current_setting('forumtests.a')::uuid;
do $$ begin
  if exists(select 1 from forum_private.threads where id=current_setting('forumtests.thread')::uuid) or exists(select 1 from forum_private.replies where thread_id=current_setting('forumtests.thread')::uuid) or exists(select 1 from forum_private.receipts where actor_id=current_setting('forumtests.a')::uuid) then raise exception 'FAIL: account/forum erasure incomplete';end if;
  if not exists(select 1 from owner_private.audit_events where action='forum_reply_delete' and target_id=current_setting('forumtests.reply')::uuid) then raise exception 'FAIL: content moderation audit missing';end if;
end; $$;
-- Revoke the session and confirm an otherwise unbanned member is still denied.
delete from auth.sessions where id=current_setting('forumtests.sb')::uuid;
set local role authenticated;
select pg_temp.expect_error('select public.forum_create_thread(''general'',''revoked'',''body'',gen_random_uuid())','42501');
reset role;
rollback;
select 'Forum reads, private ACLs, membership, idempotency, author isolation, stale edits, locks, owner MFA moderation, bans and account/content cascades passed; fixtures rolled back.' as result;
