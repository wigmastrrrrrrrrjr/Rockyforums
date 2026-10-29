-- this was created by an AI agent
-- Operator-only source storage and bounded security retention, with rollback fixtures.
begin;
select set_config('retention.actor',gen_random_uuid()::text,true);
select set_config('retention.release','ui-source-fixture-'||gen_random_uuid()::text,true);
insert into auth.users(id,email,raw_user_meta_data) values(current_setting('retention.actor')::uuid,current_setting('retention.actor')||'@example.invalid',jsonb_build_object('username','ret_'||left(replace(current_setting('retention.actor'),'-',''),12),'accepted_terms',true,'terms_version',(select version from public.legal_documents where kind='terms' and is_current)));
select public.stage_frontend_release(current_setting('retention.release'),jsonb_build_array(jsonb_build_object('path','index.html','content_type','text/html; charset=utf-8','sha256',encode(sha256(convert_to('<!doctype html><title>Fixture</title>','UTF8')),'hex'),'body_base64',encode(convert_to('<!doctype html><title>Fixture</title>','UTF8'),'base64'))));
-- A small fixture archive checks the storage contract; actual gzip recovery is
-- separately verified against the real retained addon archive during publication.
select public.backup_frontend_source(current_setting('retention.release'),encode(convert_to('operator-only fixture','UTF8'),'base64'),encode(sha256(convert_to('operator-only fixture','UTF8')),'hex'));
set local role service_role;
do $$declare archive jsonb;begin
 archive:=public.read_frontend_source(current_setting('retention.release'));
 if archive->>'format'<>'rockyforums.private-source.gzip.v1' or archive->>'sha256'<>encode(sha256(decode(archive->>'body_base64','base64')),'hex') then raise exception 'FAIL: archive readback/checksum';end if;
end;$$;
reset role;
set local role anon;
do $$begin if has_function_privilege(current_user,'public.read_frontend_source(text)','EXECUTE') or has_function_privilege(current_user,'public.backup_frontend_source(text,text,text)','EXECUTE') then raise exception 'FAIL: anonymous source access';end if;end;$$;
reset role;
set local role authenticated;
do $$begin if has_function_privilege(current_user,'public.read_frontend_source(text)','EXECUTE') or has_function_privilege(current_user,'public.backup_frontend_source(text,text,text)','EXECUTE') then raise exception 'FAIL: member source access';end if;end;$$;
reset role;
create function pg_temp.archive_immutable(statement text) returns void language plpgsql as $$begin
 begin execute statement;exception when raise_exception then if sqlerrm='Create a new frontend release instead of editing existing assets' then return;else raise;end if;end;
 raise exception 'FAIL: archive was mutable';
end;$$;
select pg_temp.archive_immutable(format('update frontend_private.source_archives set body=body where release_id=%L',current_setting('retention.release')));
select pg_temp.archive_immutable(format('delete from frontend_private.source_archives where release_id=%L',current_setting('retention.release')));
insert into owner_private.audit_events(actor_id,action,created_at) values(current_setting('retention.actor')::uuid,'account_search',clock_timestamp()-interval '100 days'),(current_setting('retention.actor')::uuid,'account_search',clock_timestamp());
insert into owner_private.action_receipts(request_id,actor_id,action,target_id,input_hash,result,created_at) values(gen_random_uuid(),current_setting('retention.actor')::uuid,'account_ban',current_setting('retention.actor')::uuid,repeat('0',64),'{}',clock_timestamp()-interval '100 days');
insert into owner_private.bans(user_id,expires_at,reason,issued_by) values(current_setting('retention.actor')::uuid,clock_timestamp()-interval '100 days','Retention fixture',current_setting('retention.actor')::uuid);
insert into owner_private.quotas(actor_id,window_start) values(current_setting('retention.actor')::uuid,clock_timestamp()-interval '4 days');
insert into forum_private.receipts(request_id,actor_id,operation,input_hash,result,created_at) values(gen_random_uuid(),current_setting('retention.actor')::uuid,'create_thread',repeat('0',64),'{}',clock_timestamp()-interval '100 days');
insert into forum_private.quotas(actor_id,window_start,threads,writes) values(current_setting('retention.actor')::uuid,clock_timestamp()-interval '4 days',0,1);
select owner_private.prune_security_records();
do $$begin
 if(select count(*) from owner_private.audit_events where actor_id=current_setting('retention.actor')::uuid)<>1 or exists(select 1 from owner_private.action_receipts where actor_id=current_setting('retention.actor')::uuid) or exists(select 1 from owner_private.bans where user_id=current_setting('retention.actor')::uuid) or exists(select 1 from owner_private.quotas where actor_id=current_setting('retention.actor')::uuid) or exists(select 1 from forum_private.receipts where actor_id=current_setting('retention.actor')::uuid) or exists(select 1 from forum_private.quotas where actor_id=current_setting('retention.actor')::uuid) then raise exception 'FAIL: security retention cutoff';end if;
 if not exists(select 1 from frontend_private.source_archives where release_id=current_setting('retention.release')) then raise exception 'FAIL: source archive pruned as a security receipt';end if;
end;$$;
rollback;
select 'Source archive readback/checksum/ACL/immutability and owner/forum security retention passed; fixtures rolled back.' as result;
