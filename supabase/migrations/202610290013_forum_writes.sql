-- this was created by an AI agent
-- Ordinary authors can manage their own public content, never another account.
create function forum_private.check_body(body text) returns void language plpgsql set search_path = '' as $$
begin
  if body is null or length(btrim(body)) not between 1 and 20000 then raise exception 'Write between 1 and 20000 characters' using errcode='22023'; end if;
end; $$;
create function forum_private.check_title(title text) returns void language plpgsql set search_path = '' as $$
begin
  if title is null or length(btrim(title)) not between 1 and 160 then raise exception 'A title of 1 to 160 characters is required' using errcode='22023'; end if;
end; $$;
create function public.forum_create_thread(category_slug text, title text, body text, request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare replay jsonb; topic uuid; posted_at timestamptz; inputs jsonb := jsonb_build_object('category',category_slug,'title',title,'body',body);
begin
  replay := forum_private.begin_write(request_id,'create_thread',inputs,true); if replay is not null then return replay; end if;
  perform forum_private.check_title(title); perform forum_private.check_body(body);
  if not exists(select 1 from forum_private.categories c where c.slug=category_slug) then raise exception 'Category not found' using errcode='P0002'; end if;
  posted_at := clock_timestamp();
  insert into forum_private.threads(category_slug,author_id,title,body,created_at,updated_at) values(category_slug,auth.uid(),btrim(title),btrim(body),posted_at,posted_at) returning id into topic;
  return forum_private.finish_write(request_id,'create_thread',inputs,jsonb_build_object('status','created','thread_id',topic));
end; $$;
create function public.forum_create_reply(target_id uuid, body text, request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare replay jsonb; topic forum_private.threads; post uuid; posted_at timestamptz; reply_page integer; inputs jsonb := jsonb_build_object('thread',target_id,'body',body);
begin
  replay := forum_private.begin_write(request_id,'create_reply',inputs); if replay is not null then return replay; end if;
  perform forum_private.check_body(body);
  select * into topic from forum_private.threads t where t.id=target_id for update;
  if not found then raise exception 'Thread not found' using errcode='P0002'; end if;
  if topic.locked then raise exception 'This thread is locked' using errcode='22023'; end if;
  posted_at := clock_timestamp();
  insert into forum_private.replies(thread_id,author_id,body,created_at,updated_at) values(target_id,auth.uid(),btrim(body),posted_at,posted_at) returning id into post;
  select ((count(*)-1)/25+1)::integer into reply_page from forum_private.replies r where r.thread_id=target_id;
  return forum_private.finish_write(request_id,'create_reply',inputs,jsonb_build_object('status','created','thread_id',target_id,'reply_id',post,'reply_page',reply_page));
end; $$;
create function public.forum_edit_thread(target_id uuid, title text, body text, expected_updated_at timestamptz, request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare replay jsonb; topic forum_private.threads; inputs jsonb := jsonb_build_object('thread',target_id,'title',title,'body',body,'updated',expected_updated_at);
begin
  replay := forum_private.begin_write(request_id,'edit_thread',inputs); if replay is not null then return replay; end if;
  perform forum_private.check_title(title); perform forum_private.check_body(body);
  select * into topic from forum_private.threads t where t.id=target_id for update;
  if not found then raise exception 'Thread not found' using errcode='P0002'; end if;
  if topic.author_id<>auth.uid() then raise exception 'Only the author may edit this thread' using errcode='42501'; end if;
  if topic.locked then raise exception 'This thread is locked' using errcode='22023'; end if;
  if topic.updated_at is distinct from expected_updated_at then raise exception 'This post changed. Reload before editing.' using errcode='22023'; end if;
  update forum_private.threads t set title=btrim(forum_edit_thread.title),body=btrim(forum_edit_thread.body),updated_at=clock_timestamp() where t.id=target_id;
  return forum_private.finish_write(request_id,'edit_thread',inputs,jsonb_build_object('status','edited','thread_id',target_id));
end; $$;
create function public.forum_edit_reply(target_id uuid, body text, expected_updated_at timestamptz, request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare replay jsonb; post forum_private.replies; locked boolean; topic uuid; inputs jsonb := jsonb_build_object('reply',target_id,'body',body,'updated',expected_updated_at);
begin
  replay := forum_private.begin_write(request_id,'edit_reply',inputs); if replay is not null then return replay; end if;
  perform forum_private.check_body(body);
  select r.thread_id into topic from forum_private.replies r where r.id=target_id;
  if topic is null then raise exception 'Reply not found' using errcode='P0002'; end if;
  perform 1 from forum_private.threads t where t.id=topic for update;
  select * into post from forum_private.replies r where r.id=target_id for update;
  if not found then raise exception 'Reply not found' using errcode='P0002'; end if;
  if post.author_id<>auth.uid() then raise exception 'Only the author may edit this reply' using errcode='42501'; end if;
  select t.locked into locked from forum_private.threads t where t.id=post.thread_id for share;
  if locked then raise exception 'This thread is locked' using errcode='22023'; end if;
  if post.updated_at is distinct from expected_updated_at then raise exception 'This post changed. Reload before editing.' using errcode='22023'; end if;
  update forum_private.replies r set body=btrim(forum_edit_reply.body),updated_at=clock_timestamp() where r.id=target_id;
  return forum_private.finish_write(request_id,'edit_reply',inputs,jsonb_build_object('status','edited','thread_id',post.thread_id,'reply_id',target_id));
end; $$;
create function public.forum_delete_thread(target_id uuid, expected_title text, request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare replay jsonb; topic forum_private.threads; inputs jsonb := jsonb_build_object('thread',target_id,'title',expected_title);
begin
  replay := forum_private.begin_write(request_id,'delete_thread',inputs); if replay is not null then return replay; end if;
  select * into topic from forum_private.threads t where t.id=target_id for update;
  if not found then raise exception 'Thread not found' using errcode='P0002'; end if;
  if topic.author_id<>auth.uid() then raise exception 'Only the author may delete this thread' using errcode='42501'; end if;
  if topic.locked then raise exception 'This thread is locked' using errcode='22023'; end if;
  if topic.title is distinct from expected_title then raise exception 'Thread confirmation changed. Reload first.' using errcode='22023'; end if;
  delete from forum_private.threads t where t.id=target_id;
  return forum_private.finish_write(request_id,'delete_thread',inputs,jsonb_build_object('status','deleted','thread_id',target_id,'category_slug',topic.category_slug));
end; $$;
create function public.forum_delete_reply(target_id uuid, request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare replay jsonb; post forum_private.replies; locked boolean; topic uuid; inputs jsonb := jsonb_build_object('reply',target_id);
begin
  replay := forum_private.begin_write(request_id,'delete_reply',inputs); if replay is not null then return replay; end if;
  select r.thread_id into topic from forum_private.replies r where r.id=target_id;
  if topic is null then raise exception 'Reply not found' using errcode='P0002'; end if;
  perform 1 from forum_private.threads t where t.id=topic for update;
  select * into post from forum_private.replies r where r.id=target_id for update;
  if not found then raise exception 'Reply not found' using errcode='P0002'; end if;
  if post.author_id<>auth.uid() then raise exception 'Only the author may delete this reply' using errcode='42501'; end if;
  select t.locked into locked from forum_private.threads t where t.id=post.thread_id for share;
  if locked then raise exception 'This thread is locked' using errcode='22023'; end if;
  delete from forum_private.replies r where r.id=target_id;
  return forum_private.finish_write(request_id,'delete_reply',inputs,jsonb_build_object('status','deleted','thread_id',post.thread_id,'reply_id',target_id));
end; $$;
revoke all on all functions in schema forum_private from public,anon,authenticated;
revoke all on function public.forum_create_thread(text,text,text,uuid),public.forum_create_reply(uuid,text,uuid),public.forum_edit_thread(uuid,text,text,timestamptz,uuid),public.forum_edit_reply(uuid,text,timestamptz,uuid),public.forum_delete_thread(uuid,text,uuid),public.forum_delete_reply(uuid,uuid) from public,anon;
grant execute on function public.forum_create_thread(text,text,text,uuid),public.forum_create_reply(uuid,text,uuid),public.forum_edit_thread(uuid,text,text,timestamptz,uuid),public.forum_edit_reply(uuid,text,timestamptz,uuid),public.forum_delete_thread(uuid,text,uuid),public.forum_delete_reply(uuid,uuid) to authenticated;
