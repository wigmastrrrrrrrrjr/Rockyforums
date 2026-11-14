-- websimbotIO :: core schema
-- A fan-made .io shooter. All gameplay state lives in this schema, prefixed wsb_.

create extension if not exists pgcrypto;

create schema if not exists wsb;
grant usage on schema wsb to anon, authenticated;

-- ---------------------------------------------------------------- matches ---
create table wsb.matches (
  id                  uuid primary key default gen_random_uuid(),
  room                text not null,
  arena_w             real not null default 2000,
  arena_h             real not null default 1500,
  state               text not null default 'live' check (state in ('live','over')),
  tick                bigint not null default 0,
  tick_ms             int not null default 100,
  started_at          timestamptz not null default now(),
  ended_at            timestamptz,
  winner_call         text,
  last_server_tick    timestamptz not null default now(),
  player_count        int not null default 0
);
create index on wsb.matches (room, state);

-- ---------------------------------------------------------------- players ---
create table wsb.players (
  id                uuid primary key default gen_random_uuid(),
  match_id          uuid not null references wsb.matches(id) on delete cascade,
  client_id         text not null,
  call              text not null,
  hue               int not null default 0,
  is_bot            boolean not null default false,

  -- authoritative state (written only by wsb.simulate / wsb.shoot)
  x                 real not null,
  y                 real not null,
  vx                real not null default 0,
  vy                real not null default 0,
  aim               real not null default 0,
  mass              real not null default 10,
  radius            real not null default 13,
  hp                real not null default 100,
  alive             boolean not null default true,
  respawn_at        timestamptz,
  streak            int not null default 0,
  last_fire_tick    bigint not null default -1000,

  -- lifetime score, survives death (feeds the leaderboard)
  kills             int not null default 0,
  deaths            int not null default 0,

  -- last client packet, mirrored here so the sim is pure-sql
  in_seq            bigint not null default 0,
  in_fx             real not null default 0,
  in_fy             real not null default 0,
  in_aim            real not null default 0,
  in_shoot          boolean not null default false,
  in_last_tick      bigint not null default 0,

  -- latest client-predicted snapshot, used to guide the sim + respawn point
  auth_x            real not null default 0,
  auth_y            real not null default 0,

  joined_at         timestamptz not null default now(),
  last_seen         timestamptz not null default now(),
  unique (match_id, client_id)
);
create index on wsb.players (match_id, alive);
create index on wsb.players (last_seen);

-- ---------------------------------------------------------------- bullets ---
create table wsb.bullets (
  id            bigserial primary key,
  match_id      uuid not null references wsb.matches(id) on delete cascade,
  owner_id      uuid not null references wsb.players(id) on delete cascade,
  x             real not null,
  y             real not null,
  vx            real not null,
  vy            real not null,
  life          real not null default 1.15,
  born_tick     bigint not null default 0
);
create index on wsb.bullets (match_id);

-- ----------------------------------------------------------------- events ---
-- Short-lived FX/score feed. Clients poll this and play sounds / popups.
create table wsb.events (
  id          bigserial primary key,
  match_id    uuid not null references wsb.matches(id) on delete cascade,
  tick        bigint not null,
  kind        text not null,          -- hit | kill | fire | join | leave | streak
  actor_name  text,
  target_name text,
  x           real,
  y           real,
  amount      real,
  created_at  timestamptz not null default now()
);
create index on wsb.events (match_id, tick);

-- -------------------------------------------------------------- integrity ---
-- RLS: everything is read-only for clients. All writes go through the
-- SECURITY DEFINER functions below, which validate before committing.
alter table wsb.matches enable row level security;
alter table wsb.players enable row level security;
alter table wsb.bullets enable row level security;
alter table wsb.events  enable row level security;

create policy wsb_matches_read on wsb.matches for select to anon, authenticated using (true);
create policy wsb_players_read on wsb.players for select to anon, authenticated using (true);
create policy wsb_bullets_read on wsb.bullets for select to anon, authenticated using (true);
create policy wsb_events_read  on wsb.events  for select to anon, authenticated using (true);

-- Clients never read tables directly: wsb.snapshot()/wsb.pump() are the only
-- read paths, so other players' client ids can never leak (which would let a
-- cheater forge input on someone else's behalf). Only the match row is
-- readable, and only so realtime can push a "tick changed" ping.
revoke all on all tables in schema wsb from anon, authenticated;
grant select (id, room, tick, state, winner_call, player_count) on wsb.matches to anon, authenticated;
revoke all on all sequences in schema wsb from anon, authenticated;

-- realtime: clients subscribe to wsb.matches as a cheap "please poll now" kick
do $$
begin
  alter publication supabase_realtime add table wsb.matches;
exception when duplicate_object then null;
end $$;
