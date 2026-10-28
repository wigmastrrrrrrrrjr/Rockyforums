-- Dedicated Rockyforums project only. No application roles can mutate these tables directly.
create table public.legal_documents (
  id text primary key,
  kind text not null check (kind in ('terms', 'privacy')),
  version text not null,
  title text not null,
  effective_at timestamptz not null,
  sections jsonb not null check (jsonb_typeof(sections) = 'array'),
  is_current boolean not null default false,
  unique (kind, version)
);
create unique index legal_documents_one_current_per_kind
  on public.legal_documents (kind) where is_current;

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique,
  created_at timestamptz not null default now(),
  constraint username_format check (username ~ '^[a-z0-9_]{3,24}$'),
  constraint username_not_reserved check (
    username not in ('admin', 'administrator', 'moderator', 'support', 'system', 'rockyforums')
  )
);

create table public.terms_acceptances (
  user_id uuid not null references public.profiles (id) on delete cascade,
  document_id text not null references public.legal_documents (id) on delete restrict,
  accepted_at timestamptz not null default now(),
  primary key (user_id, document_id)
);
create index terms_acceptances_document_id_idx on public.terms_acceptances (document_id);

alter table public.legal_documents enable row level security;
alter table public.profiles enable row level security;
alter table public.terms_acceptances enable row level security;
revoke all on public.legal_documents, public.profiles, public.terms_acceptances
  from anon, authenticated;
grant select on public.legal_documents to anon, authenticated;
grant select on public.profiles, public.terms_acceptances to authenticated;

-- Keep historical legal text available at its permanent version URL.
create policy "Published legal documents are readable" on public.legal_documents
  for select to anon, authenticated using (effective_at <= now());
create policy "Members read only their own profile" on public.profiles
  for select to authenticated using ((select auth.uid()) = id);
create policy "Members read only their own consent history" on public.terms_acceptances
  for select to authenticated using ((select auth.uid()) = user_id);

create function public.preserve_legal_document()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Published legal documents cannot be deleted';
  end if;
  if (new.id, new.kind, new.version, new.title, new.effective_at, new.sections)
     is distinct from
     (old.id, old.kind, old.version, old.title, old.effective_at, old.sections) then
    raise exception 'Publish a new legal version instead of editing history';
  end if;
  return new;
end;
$$;
revoke all on function public.preserve_legal_document() from public, anon, authenticated;
create trigger legal_document_history_is_immutable
  before update or delete on public.legal_documents
  for each row execute function public.preserve_legal_document();

-- Supabase Auth and the profile/consent inserts share one transaction.
-- An invalid username, a duplicate, missing consent, or stale terms aborts signup entirely.
create function public.handle_new_rockyforums_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  current_document_id text;
begin
  if new.raw_user_meta_data->>'accepted_terms' is distinct from 'true' then
    raise exception 'Explicit terms acceptance is required';
  end if;
  select id into current_document_id from public.legal_documents
    where kind = 'terms' and is_current and effective_at <= now()
      and version = new.raw_user_meta_data->>'terms_version'
    for share;
  if current_document_id is null then
    raise exception 'The current terms version must be accepted';
  end if;
  insert into public.profiles (id, username)
    values (new.id, lower(btrim(new.raw_user_meta_data->>'username')));
  insert into public.terms_acceptances (user_id, document_id)
    values (new.id, current_document_id);
  return new;
end;
$$;
revoke all on function public.handle_new_rockyforums_user() from public, anon, authenticated;
create trigger on_rockyforums_user_created after insert on auth.users
  for each row execute function public.handle_new_rockyforums_user();

create function public.accept_current_terms(document_version text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  member_id uuid := auth.uid();
  current_document_id text;
begin
  if member_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  select id into current_document_id from public.legal_documents
    where kind = 'terms' and is_current and effective_at <= now()
      and version = document_version
    for share;
  if current_document_id is null then
    raise exception 'The terms have changed. Read the current version before accepting.';
  end if;
  insert into public.terms_acceptances (user_id, document_id)
    values (member_id, current_document_id) on conflict do nothing;
end;
$$;
revoke all on function public.accept_current_terms(text) from public, anon, authenticated;
grant execute on function public.accept_current_terms(text) to authenticated;

-- Include this predicate in the RLS write policies of future forum features.
-- The UI gate is convenience; this is the database-enforceable authorization primitive.
create function public.has_accepted_current_terms()
returns boolean language sql stable security invoker set search_path = '' as $$
  select exists (
    select 1 from public.terms_acceptances a
    join public.legal_documents d on d.id = a.document_id
    where a.user_id = (select auth.uid()) and d.kind = 'terms'
      and d.is_current and d.effective_at <= now()
  );
$$;
revoke all on function public.has_accepted_current_terms() from public, anon, authenticated;
grant execute on function public.has_accepted_current_terms() to authenticated;
