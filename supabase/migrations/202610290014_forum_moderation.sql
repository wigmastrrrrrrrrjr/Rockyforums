-- this was created by an AI agent
-- Moderator controls remain exclusive to the owner and require fresh native TOTP.
alter table owner_private.audit_events drop constraint audit_events_action_check;
alter table owner_private.audit_events add constraint audit_events_action_check check(action in (
  'account_search','account_view','account_ban','account_unban','account_delete',
  'forum_thread_lock','forum_thread_delete','forum_reply_delete'
));
create function public.owner_set_thread_locked(target_id uuid, lock_state boolean, reason text, request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare replay jsonb; topic forum_private.threads; username text; inputs jsonb := jsonb_build_object('locked',lock_state,'reason',reason);
begin
  perform owner_private.assert_owner();
  replay := owner_private.operation_replay(request_id,'forum_thread_lock',target_id,inputs); if replay is not null then return replay; end if;
  if lock_state is null or reason is null or length(btrim(reason)) not between 1 and 1000 then raise exception 'A lock setting and reason are required' using errcode='22023'; end if;
  select * into topic from forum_private.threads t where t.id=target_id for update;
  if not found then raise exception 'Thread not found' using errcode='P0002'; end if;
  select p.username into username from public.profiles p where p.id=topic.author_id;
  update forum_private.threads t set locked=lock_state where t.id=target_id;
  return owner_private.finish_operation(request_id,'forum_thread_lock',target_id,username,inputs,
    jsonb_build_object('status','updated','thread_id',target_id,'locked',lock_state),
    jsonb_build_object('reason',btrim(reason),'locked',lock_state,'target_type','thread'));
end; $$;
create function public.owner_delete_forum_thread(target_id uuid, expected_title text, reason text, request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare replay jsonb; topic forum_private.threads; username text; replies_removed integer; inputs jsonb := jsonb_build_object('title',expected_title,'reason',reason);
begin
  perform owner_private.assert_owner();
  replay := owner_private.operation_replay(request_id,'forum_thread_delete',target_id,inputs); if replay is not null then return replay; end if;
  if reason is null or length(btrim(reason)) not between 1 and 1000 then raise exception 'A moderation reason is required' using errcode='22023'; end if;
  select * into topic from forum_private.threads t where t.id=target_id for update;
  if not found then raise exception 'Thread not found' using errcode='P0002'; end if;
  if topic.title is distinct from expected_title then raise exception 'Thread confirmation changed. Reload first.' using errcode='22023'; end if;
  select p.username into username from public.profiles p where p.id=topic.author_id;
  select count(*) into replies_removed from forum_private.replies r where r.thread_id=target_id;
  delete from forum_private.threads t where t.id=target_id;
  return owner_private.finish_operation(request_id,'forum_thread_delete',target_id,username,inputs,
    jsonb_build_object('status','deleted','thread_id',target_id,'category_slug',topic.category_slug),
    jsonb_build_object('reason',btrim(reason),'replies_removed',replies_removed,'target_type','thread'));
end; $$;
create function public.owner_delete_forum_reply(target_id uuid, reason text, request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare replay jsonb; post forum_private.replies; topic uuid; username text; inputs jsonb := jsonb_build_object('reason',reason);
begin
  perform owner_private.assert_owner();
  replay := owner_private.operation_replay(request_id,'forum_reply_delete',target_id,inputs); if replay is not null then return replay; end if;
  if reason is null or length(btrim(reason)) not between 1 and 1000 then raise exception 'A moderation reason is required' using errcode='22023'; end if;
  select r.thread_id into topic from forum_private.replies r where r.id=target_id;
  if topic is null then raise exception 'Reply not found' using errcode='P0002'; end if;
  perform 1 from forum_private.threads t where t.id=topic for update;
  select * into post from forum_private.replies r where r.id=target_id for update;
  if not found then raise exception 'Reply not found' using errcode='P0002'; end if;
  select p.username into username from public.profiles p where p.id=post.author_id;
  delete from forum_private.replies r where r.id=target_id;
  return owner_private.finish_operation(request_id,'forum_reply_delete',target_id,username,inputs,
    jsonb_build_object('status','deleted','thread_id',post.thread_id,'reply_id',target_id),
    jsonb_build_object('reason',btrim(reason),'thread_id',post.thread_id,'target_type','reply'));
end; $$;
revoke all on function public.owner_set_thread_locked(uuid,boolean,text,uuid),public.owner_delete_forum_thread(uuid,text,text,uuid),public.owner_delete_forum_reply(uuid,text,uuid) from public,anon;
grant execute on function public.owner_set_thread_locked(uuid,boolean,text,uuid),public.owner_delete_forum_thread(uuid,text,text,uuid),public.owner_delete_forum_reply(uuid,text,uuid) to authenticated;
