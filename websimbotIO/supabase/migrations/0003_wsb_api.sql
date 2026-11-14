-- websimbotIO :: public API surface
-- PostgREST only exposes `public`, so these thin SECURITY DEFINER wrappers are
-- the only functions a client can call. They pass straight through to wsb.*,
-- which does all of the validation.

create or replace function public.wsb_join(p_room text, p_client text, p_call text, p_hue int)
returns jsonb language sql security definer set search_path = wsb, public as $$
  select wsb.join(p_room, p_client, p_call, coalesce(p_hue, 0))
$$;

create or replace function public.wsb_pump(
  p_room text, p_player uuid,
  p_seq bigint default null, p_fx real default 0, p_fy real default 0,
  p_aim real default null, p_shoot boolean default false,
  p_x real default null, p_y real default null,
  p_since bigint default 0
) returns jsonb language sql security definer set search_path = wsb, public as $$
  select wsb.pump(p_room, p_player, p_seq, p_fx, p_fy, p_aim, p_shoot, p_x, p_y, p_since)
$$;

create or replace function public.wsb_respawn(p_player uuid)
returns jsonb language sql security definer set search_path = wsb, public as $$
  select wsb.respawn(p_player)
$$;

create or replace function public.wsb_leave(p_player uuid)
returns void language sql security definer set search_path = wsb, public as $$
  select wsb.leave(p_player)
$$;

-- Lobby: how busy is a room right now. Read-only, no player data.
create or replace function public.wsb_room(p_room text)
returns jsonb language sql security definer set search_path = wsb, public as $$
  select coalesce((
    select jsonb_build_object(
      'room', m.room, 'match_id', m.id, 'state', m.state,
      'tick', m.tick, 'players', m.player_count,
      'winner', m.winner_call,
      'started_ms', (extract(epoch from m.started_at) * 1000)::bigint
    )
    from wsb.matches m
    where m.room = p_room
    order by m.started_at desc limit 1
  ), jsonb_build_object('room', p_room, 'state', 'empty', 'players', 0))
$$;

revoke all on function public.wsb_join(text, text, text, int) from public;
revoke all on function public.wsb_pump(text, uuid, bigint, real, real, real, boolean, real, real, bigint) from public;
revoke all on function public.wsb_respawn(uuid) from public;
revoke all on function public.wsb_leave(uuid) from public;
revoke all on function public.wsb_room(text) from public;

grant execute on function public.wsb_join(text, text, text, int) to anon, authenticated;
grant execute on function public.wsb_pump(text, uuid, bigint, real, real, real, boolean, real, real, bigint) to anon, authenticated;
grant execute on function public.wsb_respawn(uuid) to anon, authenticated;
grant execute on function public.wsb_leave(uuid) to anon, authenticated;
grant execute on function public.wsb_room(text) to anon, authenticated;
