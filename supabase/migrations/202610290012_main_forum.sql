-- this was created by an AI agent
-- Real public discussions. Categories are configuration, never fabricated activity.
create schema forum_private;
revoke all on schema forum_private from public,anon,authenticated;
create table forum_private.site (singleton boolean primary key default true check(singleton),enabled boolean not null default false);
insert into forum_private.site(singleton,enabled) values(true,false);
alter table forum_private.site enable row level security;
create table forum_private.categories (
  slug text primary key check (slug ~ '^[a-z][a-z0-9-]{0,39}$'),
  title text not null, description text not null, sort_order integer not null
);
create table forum_private.threads (
  id uuid primary key default gen_random_uuid(),
  category_slug text not null references forum_private.categories(slug),
  author_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (length(btrim(title)) between 1 and 160),
  body text not null check (length(btrim(body)) between 1 and 20000),
  locked boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table forum_private.replies (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references forum_private.threads(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (length(btrim(body)) between 1 and 20000),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index forum_threads_category_idx on forum_private.threads(category_slug,created_at desc,id);
create index forum_threads_author_idx on forum_private.threads(author_id);
create index forum_replies_thread_idx on forum_private.replies(thread_id,created_at,id);
create index forum_replies_author_idx on forum_private.replies(author_id);
create table forum_private.receipts (
  request_id uuid primary key, actor_id uuid not null references public.profiles(id) on delete cascade,
  operation text not null, input_hash text not null, result jsonb not null,
  created_at timestamptz not null default clock_timestamp()
);
create table forum_private.quotas (
  actor_id uuid not null references public.profiles(id) on delete cascade,
  window_start timestamptz not null, threads integer not null default 0, writes integer not null default 0,
  primary key(actor_id,window_start)
);
alter table forum_private.categories enable row level security;
alter table forum_private.threads enable row level security;
alter table forum_private.replies enable row level security;
alter table forum_private.receipts enable row level security;
alter table forum_private.quotas enable row level security;
revoke all on all tables in schema forum_private from public,anon,authenticated;
insert into forum_private.categories(slug,title,description,sort_order) values
  ('general','General discussion','Talk about what is on your mind.',1),
  ('help','Help & questions','Ask questions and help each other.',2),
  ('feedback','Site feedback','Report problems and suggest improvements to Rockyforums.',3);

create function forum_private.assert_member() returns uuid
language plpgsql security definer set search_path = '' as $$
begin
  if not exists(select 1 from forum_private.site where singleton and enabled) then raise exception 'Forum posting is temporarily unavailable' using errcode='42501',detail='forum_disabled'; end if;
  -- Serialize each write against native bans/logout: never rely on an old JWT alone.
  perform 1 from auth.users u where u.id=auth.uid() for share;
  perform 1 from auth.sessions s where s.id=owner_private.session_id() and s.user_id=auth.uid() for share;
  if not found or not public.member_access_allowed() then
    raise exception 'An active, unrestricted account session is required' using errcode='42501';
  end if;
  if not public.has_accepted_current_terms() then
    raise exception 'Accept the current terms before posting' using errcode='42501',detail='current_terms_required';
  end if;
  return auth.uid();
end; $$;

-- Request receipts prevent duplicate posts on retries. Native session/ban/terms
-- checks run again after the advisory lock, including on receipt replay.
create function forum_private.begin_write(request_id uuid, operation text, inputs jsonb, new_thread boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid; receipt forum_private.receipts; fingerprint text; t integer; w integer;
begin
  actor := forum_private.assert_member();
  if request_id is null then raise exception 'A request ID is required' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(request_id::text,728194));
  perform forum_private.assert_member();
  fingerprint := encode(sha256(convert_to(inputs::text,'UTF8')),'hex');
  select * into receipt from forum_private.receipts r where r.request_id=begin_write.request_id;
  if found then
    if receipt.actor_id<>actor or receipt.operation<>operation or receipt.input_hash<>fingerprint then
      raise exception 'Request ID was already used for a different action' using errcode='22023';
    end if;
    return receipt.result;
  end if;
  insert into forum_private.quotas(actor_id,window_start,threads,writes)
    values(actor,date_trunc('minute',clock_timestamp()),case when new_thread then 1 else 0 end,1)
    on conflict(actor_id,window_start) do update set
      threads=forum_private.quotas.threads+case when new_thread then 1 else 0 end,
      writes=forum_private.quotas.writes+1 returning threads,writes into t,w;
  if t>3 or w>20 then raise exception 'Posting limit reached. Wait a minute and retry.' using errcode='P0001',detail='rate_limited'; end if;
  return null;
end; $$;
create function forum_private.finish_write(request_id uuid, operation text, inputs jsonb, result jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  insert into forum_private.receipts(request_id,actor_id,operation,input_hash,result)
  values(request_id,auth.uid(),operation,encode(sha256(convert_to(inputs::text,'UTF8')),'hex'),result);
  return result;
end; $$;
revoke all on all functions in schema forum_private from public,anon,authenticated;

-- Readers return only public post fields and usernames, not profiles, email,
-- Auth identifiers, session information or moderation reasons.
create function public.forum_categories() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(row_to_json(c) order by c.sort_order),'[]'::jsonb) from (
    select c.slug,c.title,c.description,c.sort_order,
      (select count(*) from forum_private.threads t where t.category_slug=c.slug) as thread_count,
      (select count(*) from forum_private.replies r join forum_private.threads t on t.id=r.thread_id where t.category_slug=c.slug) as reply_count,
      (select max(activity) from (
        select t.created_at as activity from forum_private.threads t where t.category_slug=c.slug
        union all select r.created_at from forum_private.replies r join forum_private.threads t on t.id=r.thread_id where t.category_slug=c.slug
      ) a) as last_activity_at
    from forum_private.categories c
  ) c;
$$;
create function public.forum_list_threads(category_slug text default null, page_number integer default 1, search_text text default '')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare items jsonb; category jsonb; needle text := lower(btrim(coalesce(search_text,'')));
begin
  if page_number is null or page_number not between 1 and 1000 or length(needle)>100 then raise exception 'Invalid page or search' using errcode='22023'; end if;
  if category_slug is not null then
    select jsonb_build_object('slug',c.slug,'title',c.title,'description',c.description) into category from forum_private.categories c where c.slug=category_slug;
    if category is null then raise exception 'Category not found' using errcode='P0002'; end if;
  end if;
  select coalesce(jsonb_agg(row_to_json(records)),'[]'::jsonb) into items from (
    select t.id,t.title,t.category_slug,c.title as category_title,p.username as author,t.created_at,t.updated_at,t.locked,
      (select count(*) from forum_private.replies r where r.thread_id=t.id) as reply_count,
      greatest(t.created_at,(select max(r.created_at) from forum_private.replies r where r.thread_id=t.id)) as last_activity_at
    from forum_private.threads t join public.profiles p on p.id=t.author_id join forum_private.categories c on c.slug=t.category_slug
    where (forum_list_threads.category_slug is null or t.category_slug=forum_list_threads.category_slug)
      and (needle='' or position(needle in lower(t.title))>0)
    order by last_activity_at desc,t.id desc limit 26 offset (page_number-1)*25
  ) records;
  return jsonb_build_object('category',category,'page',page_number,'has_more',jsonb_array_length(items)>25,
    'threads',(select coalesce(jsonb_agg(value),'[]'::jsonb) from jsonb_array_elements(items) with ordinality x(value,n) where n<=25));
end; $$;
create function public.forum_get_thread(target_id uuid, page_number integer default 1)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare topic jsonb; items jsonb; active boolean := public.member_access_allowed() and public.has_accepted_current_terms();
begin
  if page_number is null or page_number not between 1 and 1000 then raise exception 'Invalid page' using errcode='22023'; end if;
  select jsonb_build_object('id',t.id,'title',t.title,'body',t.body,'author',p.username,'category_slug',c.slug,'category_title',c.title,
    'created_at',t.created_at,'updated_at',t.updated_at,'locked',t.locked,'is_own',active and t.author_id=auth.uid(),
    'reply_count',(select count(*) from forum_private.replies r where r.thread_id=t.id)) into topic
    from forum_private.threads t join public.profiles p on p.id=t.author_id join forum_private.categories c on c.slug=t.category_slug where t.id=target_id;
  if topic is null then raise exception 'Thread not found' using errcode='P0002'; end if;
  select coalesce(jsonb_agg(row_to_json(posts)),'[]'::jsonb) into items from (
    select r.id,r.body,p.username as author,r.created_at,r.updated_at,active and r.author_id=auth.uid() as is_own
    from forum_private.replies r join public.profiles p on p.id=r.author_id where r.thread_id=target_id
    order by r.created_at,r.id limit 26 offset (page_number-1)*25
  ) posts;
  return jsonb_build_object('thread',topic,'page',page_number,'has_more',jsonb_array_length(items)>25,
    'replies',(select coalesce(jsonb_agg(value),'[]'::jsonb) from jsonb_array_elements(items) with ordinality x(value,n) where n<=25));
end; $$;
revoke all on function public.forum_categories(),public.forum_list_threads(text,integer,text),public.forum_get_thread(uuid,integer) from public;
grant execute on function public.forum_categories(),public.forum_list_threads(text,integer,text),public.forum_get_thread(uuid,integer) to anon,authenticated;

-- Caller-only session/consent state for the forum header and posting forms.
create function public.forum_viewer_status() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare status jsonb; version text;
begin
  select d.version into version from public.legal_documents d where d.kind='terms' and d.is_current and d.effective_at<=now();
  if auth.uid() is null then return jsonb_build_object('signed_in',false,'account_active',false,'terms_version',version,'forum_enabled',(select enabled from forum_private.site where singleton)); end if;
  if not exists(select 1 from auth.users u where u.id=auth.uid()) then return jsonb_build_object('signed_in',true,'account_active',false,'terms_version',version); end if;
  status := public.owner_access_status();
  return status||jsonb_build_object('signed_in',true,'terms_version',version,'terms_accepted',public.has_accepted_current_terms(),
    'forum_enabled',(select enabled from forum_private.site where singleton),'username',(select p.username from public.profiles p where p.id=auth.uid() and public.member_access_allowed()));
end; $$;
revoke all on function public.forum_viewer_status() from public;
grant execute on function public.forum_viewer_status() to anon,authenticated;
