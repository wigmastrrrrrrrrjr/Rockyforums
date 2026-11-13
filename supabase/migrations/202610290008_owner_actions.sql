-- this was created by an AI agent
-- Narrow, server-authorized RPCs. No service key, password hash, session token or MFA seed is returned.
create function public.owner_search_accounts(search_text text default '')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid; needle text := lower(btrim(coalesce(search_text,''))); results jsonb;
begin
  actor := owner_private.assert_owner();
  perform owner_private.take_quota(false);
  if length(needle)>100 then raise exception 'Search is too long' using errcode='22023'; end if;
  select coalesce(jsonb_agg(row_to_json(rows)),'[]'::jsonb) into results from (
    select p.id,p.username,u.email,p.created_at,u.last_sign_in_at,
      case when u.banned_until>now() then u.banned_until else null end as banned_until,
      exists(select 1 from owner_private.owner_seat o where o.user_id=p.id) as is_owner
    from public.profiles p join auth.users u on u.id=p.id
    where needle='' or starts_with(p.username,needle) or lower(u.email)=needle or u.id::text=needle
    order by p.created_at desc,p.id limit 25
  ) rows;
  insert into owner_private.audit_events(actor_id,action,details)
    values(actor,'account_search',jsonb_build_object('result_count',jsonb_array_length(results)));
  return results;
end;
$$;
create function public.owner_account_details(target_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid; account jsonb; username text;
begin
  actor := owner_private.assert_owner();
  perform owner_private.take_quota(false);
  select p.username,jsonb_build_object(
    'id',p.id,'username',p.username,'email',u.email,'created_at',p.created_at,
    'email_confirmed_at',u.email_confirmed_at,'last_sign_in_at',u.last_sign_in_at,
    'is_owner',exists(select 1 from owner_private.owner_seat o where o.user_id=p.id),
    'banned_until',case when u.banned_until>now() then u.banned_until else null end,
    'ban', (select jsonb_build_object('expires_at',b.expires_at,'reason',b.reason,'issued_at',b.issued_at)
      from owner_private.bans b where b.user_id=p.id and b.cancelled_at is null and b.expires_at>now()),
    'consents',coalesce((select jsonb_agg(jsonb_build_object('document_id',a.document_id,'accepted_at',a.accepted_at) order by a.accepted_at)
      from public.terms_acceptances a where a.user_id=p.id),'[]'::jsonb),
    'sessions',coalesce((select jsonb_agg(row_to_json(safe_sessions)) from (
      select s.created_at,s.refreshed_at,s.not_after,s.aal,s.ip::text as ip,s.user_agent
      from auth.sessions s where s.user_id=p.id order by s.created_at desc limit 20
    ) safe_sessions),'[]'::jsonb),
    'mfa',coalesce((select jsonb_agg(jsonb_build_object('type',f.factor_type,'status',f.status))
      from auth.mfa_factors f where f.user_id=p.id),'[]'::jsonb)
  ) into username,account from public.profiles p join auth.users u on u.id=p.id where p.id=target_id;
  if account is null then raise exception 'Account not found' using errcode='P0002'; end if;
  insert into owner_private.audit_events(actor_id,action,target_id,target_username)
    values(actor,'account_view',target_id,username);
  return account;
end;
$$;
create function public.owner_ban_account(target_id uuid, expected_username text, reason text, request_id uuid,
  duration_seconds integer default null, until_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid; expires_at timestamptz; username text; replay jsonb; result jsonb;
  inputs jsonb := jsonb_build_object('username',expected_username,'reason',reason,'seconds',duration_seconds,'until',until_at);
begin
  actor := owner_private.assert_owner();
  replay := owner_private.operation_replay(request_id,'account_ban',target_id,inputs);
  if replay is not null then return replay; end if;
  if (duration_seconds is null)=(until_at is null) then raise exception 'Choose exactly one duration or expiry' using errcode='22023'; end if;
  if duration_seconds is not null and duration_seconds not between 60 and 31536000 then
    raise exception 'Ban duration must be between one minute and 365 days' using errcode='22023';
  end if;
  expires_at := coalesce(until_at,clock_timestamp()+make_interval(secs=>duration_seconds));
  if not isfinite(expires_at) or expires_at<clock_timestamp()+interval '59 seconds' or expires_at>clock_timestamp()+interval '365 days' then
    raise exception 'Choose an expiry between one minute and 365 days from now' using errcode='22023';
  end if;
  if reason is null or length(btrim(reason)) not between 1 and 1000 then raise exception 'A reason of 1 to 1000 characters is required' using errcode='22023'; end if;
  if exists(select 1 from owner_private.owner_seat where user_id=target_id) then raise exception 'The sole owner cannot be banned' using errcode='22023'; end if;
  perform 1 from auth.users u where u.id=target_id for update;
  select p.username into username from public.profiles p where p.id=target_id for update;
  if username is null then raise exception 'Account not found' using errcode='P0002'; end if;
  if username is distinct from expected_username then raise exception 'Account confirmation does not match' using errcode='22023'; end if;
  update auth.users u set banned_until=expires_at,updated_at=clock_timestamp() where u.id=target_id;
  insert into owner_private.bans(user_id,expires_at,reason,issued_by,cancelled_at)
    values(target_id,expires_at,btrim(reason),actor,null)
    on conflict(user_id) do update set expires_at=excluded.expires_at,reason=excluded.reason,
      issued_at=clock_timestamp(),issued_by=excluded.issued_by,cancelled_at=null;
  delete from auth.refresh_tokens r where r.user_id=target_id::text;
  delete from auth.sessions s where s.user_id=target_id;
  result := jsonb_build_object('status','banned','id',target_id,'username',username,'expires_at',expires_at);
  return owner_private.finish_operation(request_id,'account_ban',target_id,username,inputs,result,
    jsonb_build_object('reason',btrim(reason),'expires_at',expires_at));
end;
$$;
create function public.owner_unban_account(target_id uuid, expected_username text, reason text, request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid; username text; replay jsonb; result jsonb;
  inputs jsonb := jsonb_build_object('username',expected_username,'reason',reason);
begin
  actor := owner_private.assert_owner();
  replay := owner_private.operation_replay(request_id,'account_unban',target_id,inputs);
  if replay is not null then return replay; end if;
  if reason is null or length(btrim(reason)) not between 1 and 1000 then raise exception 'An unban reason is required' using errcode='22023'; end if;
  if exists(select 1 from owner_private.owner_seat where user_id=target_id) then raise exception 'The sole owner cannot be a moderation target' using errcode='22023'; end if;
  perform 1 from auth.users u where u.id=target_id for update;
  select p.username into username from public.profiles p where p.id=target_id for update;
  if username is null then raise exception 'Account not found' using errcode='P0002'; end if;
  if username is distinct from expected_username then raise exception 'Account confirmation does not match' using errcode='22023'; end if;
  update auth.users u set banned_until=null,updated_at=clock_timestamp() where u.id=target_id;
  update owner_private.bans b set cancelled_at=clock_timestamp() where b.user_id=target_id and b.cancelled_at is null;
  result := jsonb_build_object('status','unbanned','id',target_id,'username',username);
  return owner_private.finish_operation(request_id,'account_unban',target_id,username,inputs,result,jsonb_build_object('reason',btrim(reason)));
end;
$$;
create function public.owner_delete_account(target_id uuid, expected_username text, reason text, request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid; username text; replay jsonb; result jsonb;
  inputs jsonb := jsonb_build_object('username',expected_username,'reason',reason);
begin
  actor := owner_private.assert_owner();
  replay := owner_private.operation_replay(request_id,'account_delete',target_id,inputs);
  if replay is not null then return replay; end if;
  if reason is null or length(btrim(reason)) not between 1 and 1000 then raise exception 'A deletion reason is required' using errcode='22023'; end if;
  if exists(select 1 from owner_private.owner_seat where user_id=target_id) then raise exception 'The sole owner cannot be deleted' using errcode='22023'; end if;
  perform 1 from auth.users u where u.id=target_id for update;
  select p.username into username from public.profiles p where p.id=target_id for update;
  if username is null then raise exception 'Account not found' using errcode='P0002'; end if;
  if username is distinct from expected_username then raise exception 'Type the exact username to confirm deletion' using errcode='22023'; end if;
  delete from auth.refresh_tokens r where r.user_id=target_id::text;
  delete from auth.sessions s where s.user_id=target_id;
  delete from auth.flow_state f where f.user_id=target_id;
  delete from auth.users u where u.id=target_id;
  result := jsonb_build_object('status','deleted','id',target_id,'username',username);
  return owner_private.finish_operation(request_id,'account_delete',target_id,username,inputs,result,
    jsonb_build_object('reason',btrim(reason),'retention','Minimal audit entry retained; provider logs/backups are separate'));
end;
$$;
create function public.owner_recent_audit()
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform owner_private.assert_owner();
  perform owner_private.take_quota(false);
  return (select coalesce(jsonb_agg(row_to_json(events)),'[]'::jsonb) from (
    select id,action,target_id,target_username,details,created_at from owner_private.audit_events
      where created_at>=now()-interval '90 days' order by created_at desc,id desc limit 100
  ) events);
end;
$$;
revoke all on function public.owner_search_accounts(text),public.owner_account_details(uuid),
  public.owner_ban_account(uuid,text,text,uuid,integer,timestamptz),public.owner_unban_account(uuid,text,text,uuid),
  public.owner_delete_account(uuid,text,text,uuid),public.owner_recent_audit() from public,anon;
grant execute on function public.owner_search_accounts(text),public.owner_account_details(uuid),
  public.owner_ban_account(uuid,text,text,uuid,integer,timestamptz),public.owner_unban_account(uuid,text,text,uuid),
  public.owner_delete_account(uuid,text,text,uuid),public.owner_recent_audit() to authenticated;
