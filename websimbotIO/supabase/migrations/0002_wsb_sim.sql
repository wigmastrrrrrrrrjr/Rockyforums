-- websimbotIO :: authoritative simulation
-- Design note (see README): movement is client-side and streamed up at ~10 Hz.
-- Postgres is the referee: it re-derives every position, refuses impossible
-- input, and is the only thing allowed to score a kill. If the client's
-- predicted frame disagrees with the server, the server's position wins and
-- the client snaps back (see src/net.js reconciliation).

create or replace function wsb.cfg() returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'tick_ms',       100,
    'base_mass',     10,
    'base_radius',   17,
    'max_radius',    58,
    'hp_max',        100,
    'bullet_speed',  900,
    'bullet_life',   1.10,
    'fire_ticks',    6,
    'respawn_ms',    2500,
    'kills_to_win',  25,
    'grow_factor',   0.55,
    'max_players',   14
  )::jsonb
$$;

create or replace function wsb.radius_for(p_mass real) returns real
language sql immutable as $$
  select least((wsb.cfg()->>'max_radius')::real,
               (wsb.cfg()->>'base_radius')::real * sqrt(greatest(p_mass, 1) / 10.0))
$$;

-- fat players walk slower: ~234 px/s at spawn, ~150 px/s near max size
create or replace function wsb.speed_for(p_radius real) returns real
language sql immutable as $$
  select greatest(150, 270 - p_radius * 2.1)
$$;

create or replace function wsb.hue_for(p_text text) returns int
language sql immutable as $$
  select (abs(hashtext(coalesce(p_text, 'x'))) % 356)::int
$$;

create or replace function wsb.sanitize_call(p_call text) returns text
language sql immutable as $$
  select case
    when p_call is null or length(btrim(regexp_replace(p_call, '[^[:alnum:] _\-.]', '', 'g'))) < 2
      then 'sketchy' || (100 + (random() * 899)::int)
    else left(btrim(regexp_replace(p_call, '[^[:alnum:] _\-.]', '', 'g')), 14)
  end
$$;

-- squared distance from p to segment a-b
create or replace function wsb.seg_dist2(ax real, ay real, bx real, by real, px real, py real)
returns real language sql immutable as $$
  select (px - (ax + tt * (bx - ax))) ^ 2 + (py - (ay + tt * (by - ay))) ^ 2
    from (select case when (bx - ax) ^ 2 + (by - ay) ^ 2 = 0 then 0
                      else greatest(0, least(1,
                        ((px - ax) * (bx - ax) + (py - ay) * (by - ay)) /
                        ((bx - ax) ^ 2 + (by - ay) ^ 2))) end as tt) s
$$;

create or replace function wsb.spawn_point(p_match uuid, p_ax real default null, p_ay real default null)
returns point language plpgsql security definer set search_path = wsb, public as $$
declare
  m     wsb.matches%rowtype;
  tries int := 0;
  b_x   real;
  b_y   real;
begin
  select * into m from wsb.matches where id = p_match;
  if not found then return point(600, 600); end if;
  loop
    tries := tries + 1;
    b_x := 160 + random() * greatest(m.arena_w - 320, 100);
    b_y := 160 + random() * greatest(m.arena_h - 320, 100);
    if (p_ax is null or (p_ax - b_x) ^ 2 + (p_ay - b_y) ^ 2 > 260 * 260)
       and not exists (
         select 1 from wsb.players
          where match_id = m.id and alive
            and (x - b_x) ^ 2 + (y - b_y) ^ 2 < 250 * 250)
    then
      return point(b_x, b_y);
    end if;
    exit when tries >= 12;
  end loop;
  return point(b_x, b_y);
end $$;

-- --------------------------------------------------------------- matches ---
create or replace function wsb.open_match(p_room text) returns uuid
language plpgsql security definer set search_path = wsb, public as $$
declare mid uuid;
begin
  insert into wsb.matches (room) values (p_room) returning id into mid;
  return mid;
end $$;

-- 1 Hz heartbeat, scheduled with pg_cron so matches run with nobody watching
create or replace function wsb.tick_once(p_match uuid, p_jobname text)
returns void language plpgsql security definer set search_path = wsb, public as $$
declare m wsb.matches%rowtype; live int; stop boolean := false;
begin
  select * into m from wsb.matches where id = p_match;
  if not found then stop := true;
  elsif m.state <> 'live' then stop := true;
  else
    perform wsb.simulate(p_match, 10);
    select count(*) into live from wsb.players
     where match_id = p_match and last_seen > now() - interval '25 seconds';
    if live = 0 then
      update wsb.matches set state = 'over', ended_at = now() where id = p_match;
      stop := true;
    end if;
  end if;
  if stop then
    begin
      perform cron.unschedule(p_jobname);
    exception when others then null;
    end;
  end if;
end $$;

-- Called by every client frame. Serialises the room, catches the sim up to
-- wall-clock time, makes sure a heartbeat exists, returns the match id.
create or replace function wsb.enqueue(p_room text) returns uuid
language plpgsql security definer set search_path = wsb, public as $$
declare
  m      wsb.matches%rowtype;
  behind int;
  jname  text;
begin
  perform pg_advisory_xact_lock(hashtext('wsb-room-' || coalesce(p_room, 'main')));

  select * into m from wsb.matches
   where room = p_room and state = 'live' order by started_at desc limit 1;

  if not found then
    insert into wsb.matches (room) values (p_room)
      on conflict do nothing returning * into m;
    if not found then
      select * into m from wsb.matches where room = p_room and state = 'live'
       order by started_at desc limit 1;
    end if;
  end if;

  behind := floor(extract(epoch from (now() - m.last_server_tick)) / 0.1)::int;
  if behind > 0 then
    perform wsb.simulate(m.id, least(behind, 30));
    update wsb.matches set last_server_tick = now() where id = m.id;
  end if;

  jname := 'wsb:' || m.id::text;
  if not exists (select 1 from cron.job where jobname = jname) then
    perform cron.schedule(jname, '1 second',
      format('select wsb.tick_once(%L::uuid, %L)', m.id, jname));
  end if;

  return m.id;
end $$;

-- -------------------------------------------------------------- join/leave --
create or replace function wsb.join(p_room text, p_client text, p_call text, p_hue int)
returns jsonb language plpgsql security definer set search_path = wsb, public as $$
declare
  mid    uuid;
  sp     point;
  p      wsb.players%rowtype;
  people int;
  gone   boolean := false;
begin
  if p_client is null or length(p_client) < 6 then
    return jsonb_build_object('ok', false, 'error', 'bad_client');
  end if;
  if p_room is null or length(p_room) > 24 then
    return jsonb_build_object('ok', false, 'error', 'bad_room');
  end if;

  mid := wsb.enqueue(p_room);

  select count(*) into people from wsb.players
   where match_id = mid and not is_bot
     and last_seen > now() - interval '20 seconds' and client_id <> p_client;
  if people >= (wsb.cfg()->>'max_players')::int then
    return jsonb_build_object('ok', false, 'error', 'full');
  end if;

  select * into p from wsb.players where match_id = mid and client_id = p_client;

  if not found then
    sp := wsb.spawn_point(mid);
    insert into wsb.players (match_id, client_id, call, hue, x, y, auth_x, auth_y,
                             radius, hp, mass)
    values (mid, p_client, wsb.sanitize_call(p_call), wsb.hue_for(p_client),
            sp[0], sp[1], sp[0], sp[1],
            wsb.radius_for((wsb.cfg()->>'base_mass')::real),
            (wsb.cfg()->>'hp_max')::real,
            (wsb.cfg()->>'base_mass')::real)
    returning * into p;
  else
    -- returning after a reload: revive at a fresh spot, keep your score
    gone := p.last_seen < now() - interval '15 seconds';
    if gone then sp := wsb.spawn_point(mid, p.x, p.y); end if;

    update wsb.players s set
      last_seen  = now(),
      call       = wsb.sanitize_call(p_call),
      hue        = wsb.hue_for(p_client),
      alive      = case when gone then true else s.alive end,
      respawn_at = case when gone then null else s.respawn_at end,
      hp         = case when gone then (wsb.cfg()->>'hp_max')::real else s.hp end,
      mass       = case when gone then (wsb.cfg()->>'base_mass')::real else s.mass end,
      radius     = case when gone then wsb.radius_for((wsb.cfg()->>'base_mass')::real)
                        else s.radius end,
      x          = case when gone then sp[0] else s.x end,
      y          = case when gone then sp[1] else s.y end,
      vx         = case when gone then 0 else s.vx end,
      vy         = case when gone then 0 else s.vy end,
      auth_x     = case when gone then sp[0] else s.auth_x end,
      auth_y     = case when gone then sp[1] else s.auth_y end
     where s.id = p.id
     returning * into p;
  end if;

  insert into wsb.events (match_id, tick, kind, actor_name, x, y)
  select mid, coalesce(max(tick), 0), 'join', p.call, p.x, p.y from wsb.matches where id = mid;

  perform wsb.ensure_bots(mid, 5);

  return jsonb_build_object('ok', true, 'player_id', p.id, 'match_id', mid,
                            'hue', p.hue, 'call', p.call, 'x', p.x, 'y', p.y);
end $$;

-- ------------------------------------------------------------- input push --
-- Every field is validated here. Impossible packets are refused and the
-- client is handed the server's real coordinates so it can snap back.
create or replace function wsb.push_input(p_player uuid, p_seq bigint, p_fx real, p_fy real,
                                          p_aim real, p_shoot boolean, p_x real, p_y real)
returns jsonb language plpgsql security definer set search_path = wsb, public as $$
declare
  p       wsb.players%rowtype;
  fx      real;
  fy      real;
  len     real;
  allowed real;
  d       real;
begin
  select * into p from wsb.players where id = p_player for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'gone'); end if;

  if p_seq is not null and p_seq <= p.in_seq then
    return jsonb_build_object('ok', false, 'error', 'stale');
  end if;

  fx := coalesce(p_fx, 0);
  fy := coalesce(p_fy, 0);
  if fx <> fx or fy <> fy or coalesce(p_aim, 0) <> coalesce(p_aim, 0) then
    return jsonb_build_object('ok', false, 'error', 'nan');
  end if;

  len := sqrt(fx * fx + fy * fy);
  if len > 1.0001 then fx := fx / len; fy := fy / len; end if;

  -- speedhack check: distance is budgeted from elapsed wall time, not from
  -- anything the client says about itself.
  if p_x is not null and p_y is not null then
    allowed := wsb.speed_for(p.radius)
               * (extract(epoch from (now() - p.last_seen)) + 0.30) * 2.0 + 60;
    d := sqrt((p_x - p.auth_x) ^ 2 + (p_y - p.auth_y) ^ 2);
    if d > allowed then
      update wsb.players set last_seen = now() where id = p.id;
      return jsonb_build_object('ok', false, 'error', 'teleport', 'x', p.x, 'y', p.y);
    end if;
  end if;

  update wsb.players set
    in_seq    = coalesce(p_seq, p.in_seq),
    in_fx     = fx,
    in_fy     = fy,
    in_aim    = coalesce(p_aim, p.in_aim),
    in_shoot  = coalesce(p_shoot, false),
    auth_x    = coalesce(p_x, p.auth_x),
    auth_y    = coalesce(p_y, p.auth_y)
   where id = p.id;

  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------- respawn --
create or replace function wsb.respawn(p_player uuid)
returns jsonb language plpgsql security definer set search_path = wsb, public as $$
declare p wsb.players%rowtype; sp point;
begin
  select * into p from wsb.players where id = p_player for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'gone'); end if;
  if p.alive then return jsonb_build_object('ok', false, 'error', 'alive'); end if;
  if p.respawn_at is not null and p.respawn_at > now() then
    return jsonb_build_object('ok', false, 'error', 'wait',
      'in_ms', (extract(epoch from (p.respawn_at - now())) * 1000)::int);
  end if;

  sp := wsb.spawn_point(p.match_id, p.auth_x, p.auth_y);
  update wsb.players x set
    x = sp[0], y = sp[1], vx = 0, vy = 0,
    auth_x = sp[0], auth_y = sp[1],
    hp = (wsb.cfg()->>'hp_max')::real,
    mass = (wsb.cfg()->>'base_mass')::real,
    radius = wsb.radius_for((wsb.cfg()->>'base_mass')::real),
    alive = true, respawn_at = null, last_seen = now()
   where x.id = p.id;

  return jsonb_build_object('ok', true, 'x', sp[0], 'y', sp[1]);
end $$;

-- ------------------------------------------------------------- bot brains --
create or replace function wsb.bot_names() returns text[]
language sql immutable as $$
  select array['nib','scriber','blot','smudge','hatch','skribble','lineweight','eraser',
               'sharpener','ruler','inkwell','pencil','charcoal','bristle','shade',
               'crayon','stipple','vellum','gouache','squiggle','gutter','margin'];
$$;

create or replace function wsb.ensure_bots(p_match uuid, p_desired int default 5)
returns void language plpgsql security definer set search_path = wsb, public as $$
declare
  humans int;
  bots   int;
  need   int;
  i      int;
  nm     text;
  sp     point;
  names  text[] := wsb.bot_names();
begin
  select count(*) into humans from wsb.players
   where match_id = p_match and not is_bot and last_seen > now() - interval '25 seconds';
  select count(*) into bots from wsb.players
   where match_id = p_match and is_bot and alive;

  need := least(9, greatest(0, p_desired - humans)) - bots;
  if need <= 0 then return; end if;

  for i in 1 .. need loop
    nm := names[1 + (random() * (array_length(names, 1) - 1))::int];
    sp := wsb.spawn_point(p_match);
    insert into wsb.players (match_id, client_id, call, hue, is_bot, x, y, auth_x, auth_y,
                             radius, hp, mass)
    values (p_match, 'bot-' || gen_random_uuid()::text,
            nm || case when random() < 0.35 then (1 + (random() * 9)::int)::text else '' end,
            wsb.hue_for(nm || random()::text), true, sp[0], sp[1], sp[0], sp[1],
            wsb.radius_for((wsb.cfg()->>'base_mass')::real),
            (wsb.cfg()->>'hp_max')::real,
            (wsb.cfg()->>'base_mass')::real);
  end loop;
end $$;

-- ------------------------------------------------------------------ fire ---
create or replace function wsb.spawn_bullets(p_match uuid, p_tick bigint)
returns int language plpgsql security definer set search_path = wsb, public as $$
declare n int;
begin
  -- cooldown lives on the server; holding the trigger down cannot skip it
  update wsb.players p set last_fire_tick = p_tick
   where p.match_id = p_match and p.alive and p.in_shoot
     and p.in_last_tick >= p_tick - 8
     and p.last_fire_tick <= p_tick - (wsb.cfg()->>'fire_ticks')::int;

  insert into wsb.bullets (match_id, owner_id, x, y, vx, vy, life, born_tick)
  select p.match_id, p.id,
         p.x + cos(p.in_aim) * (p.radius + 6),
         p.y + sin(p.in_aim) * (p.radius + 6),
         cos(p.in_aim + jitter) * (wsb.cfg()->>'bullet_speed')::real,
         sin(p.in_aim + jitter) * (wsb.cfg()->>'bullet_speed')::real,
         (wsb.cfg()->>'bullet_life')::real, p_tick
    from (select q.*, case when q.is_bot then (random() - 0.5) * 0.085
                           else (random() - 0.5) * 0.028 end as jitter
            from wsb.players q
           where q.match_id = p_match and q.alive and q.last_fire_tick = p_tick) p;

  get diagnostics n = row_count;
  return n;
end $$;

-- --------------------------------------------------------------- simulate --
-- The whole game, 100 ms at a time. Called by enqueue() (whenever wall-clock
-- time is ahead of the sim) and by the 1 Hz pg_cron heartbeat.
create or replace function wsb.simulate(p_match uuid, p_ticks int default 1)
returns jsonb language plpgsql security definer set search_path = wsb, public as $$
declare
  m           wsb.matches%rowtype;
  dt          real := (wsb.cfg()->>'tick_ms')::real / 1000.0;
  n           int  := greatest(1, least(30, coalesce(p_ticks, 1)));
  i           int;
  r           record;
  h           record;
  dmg         real;
  killer      wsb.players%rowtype;
  victim      wsb.players%rowtype;
  cur_tick    bigint;
  dist        real;
  ang         real;
  want        real;
begin
  select * into m from wsb.matches where id = p_match for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'no_match'); end if;
  if m.state <> 'live' then
    return jsonb_build_object('ok', true, 'state', m.state, 'tick', m.tick);
  end if;

  -- housekeeping ----------------------------------------------------------
  update wsb.players p set alive = false, respawn_at = null, deaths = deaths + 1,
                           streak = 0, hp = 0
   where p.match_id = p_match and p.alive
     and not p.is_bot and p.last_seen < now() - interval '40 seconds';

  delete from wsb.players p
   where p.match_id = p_match and not p.is_bot and p.last_seen < now() - interval '5 minutes';

  delete from wsb.players p
   where p.match_id = p_match and p.is_bot
     and not exists (select 1 from wsb.players h
                      where h.match_id = p_match and not h.is_bot
                        and h.last_seen > now() - interval '40 seconds');

  for i in 1 .. n loop
    cur_tick := m.tick + 1;

    -- 1. respawns ---------------------------------------------------------
    for r in select id from wsb.players
              where match_id = p_match and not alive
                and respawn_at is not null and respawn_at <= now()
    loop
      perform wsb.respawn(r.id);
    end loop;

    -- 2. bot brains -------------------------------------------------------
    for r in select * from wsb.players
              where match_id = p_match and is_bot and alive
    loop
      select * into h from wsb.players
       where match_id = p_match and alive and id <> r.id
       order by is_bot::int, (x - r.x) ^ 2 + (y - r.y) ^ 2
       limit 1;
      if found then
        dist := sqrt((h.x - r.x) ^ 2 + (h.y - r.y) ^ 2);
        -- aim where the target will be, with a bit of lead
        ang  := atan2(h.y + h.vy * 0.10 * least(dist / 500.0, 1.0) - r.y,
                      h.x + h.vx * 0.10 * least(dist / 500.0, 1.0) - r.x);
        want := case when dist > 200 then ang
                     else ang + (case when r.kills % 2 = 0 then 1.45 else -1.45 end) end;
        update wsb.players p set
          in_aim  = ang,
          in_fx   = cos(want),
          in_fy   = sin(want),
          in_shoot = dist < 720 and random() < 0.75,
          in_last_tick = cur_tick
         where p.id = r.id;
      else
        update wsb.players p set
          in_aim = p.aim,
          in_fx  = cos(cur_tick::real * 0.3 + p.hue),
          in_fy  = sin(cur_tick::real * 0.3 + p.hue),
          in_shoot = false, in_last_tick = cur_tick
         where p.id = r.id;
      end if;
    end loop;

    -- 3. movement: the server re-derives every position --------------------
    update wsb.players p set
      vx = wsb.speed_for(p.radius) * case when p.is_bot or p.in_last_tick >= cur_tick - 10
                                          then p.in_fx else 0 end,
      vy = wsb.speed_for(p.radius) * case when p.is_bot or p.in_last_tick >= cur_tick - 10
                                          then p.in_fy else 0 end
     where p.match_id = p_match and p.alive;

    update wsb.players p set
      x   = least(greatest(p.x + p.vx * dt, p.radius), m.arena_w - p.radius),
      y   = least(greatest(p.y + p.vy * dt, p.radius), m.arena_h - p.radius),
      aim = p.in_aim
     where p.match_id = p_match and p.alive;

    -- 4. firing -----------------------------------------------------------
    perform wsb.spawn_bullets(p_match, cur_tick);

    -- 5. sweep the bullets, then advance survivors -------------------------
    for r in
      select b.id as bid, b.owner_id, b.x as bx, b.y as by, b.vx as bvx, b.vy as bvy,
             t.id as tid, t.radius as trad, t.x as tx, t.y as ty, t.call as tcall
        from wsb.bullets b
        join wsb.players t
          on t.match_id = b.match_id and t.alive and t.id <> b.owner_id
       where b.match_id = p_match
         and wsb.seg_dist2(b.x, b.y, b.x + b.vx * dt, b.y + b.vy * dt, t.x, t.y)
             <= (t.radius + 3) ^ 2
         and ((t.x - b.x) * b.vx + (t.y - b.y) * b.vy) >= 0
    loop
      delete from wsb.bullets where id = r.bid;

      select * into victim from wsb.players where id = r.tid and alive;
      if not found then continue; end if;
      select * into killer from wsb.players where id = r.owner_id;
      if not found then continue; end if;

      -- bigger shooters hit harder, with heavy diminishing returns
      dmg := 22 * (1 + 0.22 * ln(greatest(killer.mass, 10) / 10.0));

      if victim.hp - dmg > 0 then
        update wsb.players set hp = greatest(0, hp - dmg) where id = victim.id;
        insert into wsb.events (match_id, tick, kind, actor_name, target_name, x, y, amount)
        values (p_match, cur_tick, 'hit', killer.call, victim.call, victim.x, victim.y, dmg);
      else
        update wsb.players set
          alive = false, hp = 0, vx = 0, vy = 0,
          deaths = deaths + 1, streak = 0,
          respawn_at = now() + ((wsb.cfg()->>'respawn_ms')::int || ' milliseconds')::interval
         where id = victim.id;

        -- the bigger you kill, the bigger you get
        update wsb.players p set
          kills  = p.kills + 1,
          streak = p.streak + 1,
          mass   = p.mass + greatest(4.0, victim.mass * (wsb.cfg()->>'grow_factor')::real),
          hp     = least((wsb.cfg()->>'hp_max')::real, p.hp + 18)
         where p.id = killer.id;

        update wsb.players p set radius = wsb.radius_for(p.mass) where p.id = killer.id;

        insert into wsb.events (match_id, tick, kind, actor_name, target_name, x, y)
        values (p_match, cur_tick, 'kill', killer.call, victim.call, victim.x, victim.y);

        if (select coalesce(sum(kills), 0) from wsb.players where id = killer.id)
             >= (wsb.cfg()->>'kills_to_win')::int then
          update wsb.matches set state = 'over', ended_at = now(),
                                 winner_call = killer.call
           where id = p_match and state = 'live';
          m.state := 'over';
        end if;
      end if;
    end loop;

    if m.state = 'over' then
      update wsb.matches set tick = cur_tick where id = p_match;
      return jsonb_build_object('ok', true, 'state', 'over', 'tick', cur_tick);
    end if;

    update wsb.bullets set
      x = x + vx * dt, y = y + vy * dt, life = life - dt
     where match_id = p_match;

    delete from wsb.bullets
     where match_id = p_match
       and (life <= 0 or x < -24 or y < -24 or x > m.arena_w + 24 or y > m.arena_h + 24);

    -- cost guard: a long match can never bloat the table
    delete from wsb.bullets where id in (
      select id from wsb.bullets where match_id = p_match order by id desc offset 500);

    m.tick := cur_tick;
  end loop;

  update wsb.matches set tick = m.tick, player_count = (
      select count(*) from wsb.players where match_id = p_match and alive)
   where id = p_match;

  -- the event feed is only ever read for the last second of play
  delete from wsb.events where match_id = p_match and tick < m.tick - 60;

  return jsonb_build_object('ok', true, 'tick', m.tick, 'state', m.state);
end $$;

-- -------------------------------------------------------------- snapshot ----
create or replace function wsb.snapshot(p_match uuid, p_since bigint default 0)
returns jsonb language plpgsql security definer set search_path = wsb, public as $$
declare
  m       wsb.matches%rowtype;
  players jsonb;
  bullets jsonb;
  events  jsonb;
begin
  select * into m from wsb.matches where id = p_match;
  if not found then return jsonb_build_object('ok', false, 'error', 'no_match'); end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', id, 'call', call, 'hue', hue, 'bot', is_bot,
           'x', round(x::numeric, 1), 'y', round(y::numeric, 1),
           'vx', round(vx::numeric, 1), 'vy', round(vy::numeric, 1),
           'aim', round(aim::numeric, 3),
           'mass', round(mass::numeric, 1), 'radius', round(radius::numeric, 1),
           'hp', round(hp::numeric, 1), 'alive', alive, 'streak', streak,
           'kills', kills, 'deaths', deaths,
           'respawn_ms', case when respawn_at is null then null
                              else greatest(0, (extract(epoch from (respawn_at - now())) * 1000)::int) end
         ) order by kills desc), '[]'::jsonb)
    into players
    from wsb.players
   where match_id = p_match
     and ((is_bot and alive) or last_seen > now() - interval '40 seconds');

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', id, 'x', round(x::numeric, 1), 'y', round(y::numeric, 1),
           'vx', round(vx::numeric, 0), 'vy', round(vy::numeric, 0),
           'owner', owner_id, 'life', round(life::numeric, 2)
         )), '[]'::jsonb)
    into bullets
    from wsb.bullets where match_id = p_match;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', id, 'kind', kind, 'actor', actor_name, 'target', target_name,
           'x', x, 'y', y, 'amount', round(amount::numeric, 1)
         ) order by id), '[]'::jsonb)
    into events
    from wsb.events where match_id = p_match and id > coalesce(p_since, 0);

  return jsonb_build_object(
    'ok', true, 'match_id', m.id, 'state', m.state, 'tick', m.tick,
    'winner', m.winner_call,
    'server_ms', (extract(epoch from now()) * 1000)::bigint,
    'world', jsonb_build_object('w', m.arena_w, 'h', m.arena_h),
    'tuning', wsb.cfg(),
    'players', players, 'bullets', bullets, 'events', events
  );
end $$;

-- One call per client frame: push input, keep the sim on wall-clock time,
-- return the world. This is the only function the client needs while playing.
create or replace function wsb.pump(
  p_room text, p_player uuid,
  p_seq bigint default null, p_fx real default 0, p_fy real default 0,
  p_aim real default null, p_shoot boolean default false,
  p_x real default null, p_y real default null,
  p_since bigint default 0
) returns jsonb language plpgsql security definer set search_path = wsb, public as $$
declare
  res     jsonb;
  mid     uuid;
  m       wsb.matches%rowtype;
  behind  int;
begin
  if p_player is not null then
    res := wsb.push_input(p_player, p_seq, p_fx, p_fy, p_aim, p_shoot, p_x, p_y);
    update wsb.players set last_seen = now() where id = p_player;
    select match_id into mid from wsb.players where id = p_player;
  end if;

  if mid is null then
    mid := wsb.enqueue(p_room);
  else
    select * into m from wsb.matches where id = mid;
    if found and m.state = 'live' then
      behind := floor(extract(epoch from (now() - m.last_server_tick)) / 0.1)::int;
      if behind > 0 then
        perform wsb.simulate(mid, least(behind, 12));
        update wsb.matches set last_server_tick = now() where id = mid;
      end if;
    end if;
  end if;

  return wsb.snapshot(mid, p_since) || jsonb_build_object('input', res);
end $$;

create or replace function wsb.leave(p_player uuid)
returns void language sql security definer set search_path = wsb, public as $$
  update wsb.players set last_seen = now() - interval '5 minutes' where id = p_player;
$$;

grant execute on all functions in schema wsb to anon, authenticated;
