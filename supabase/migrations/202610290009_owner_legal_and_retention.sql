-- this was created by an AI agent
-- New legal versions; none of the published 1.0/1.1/1.2 text is edited.
do $$ begin
  if (select count(*) from public.legal_documents where is_current and version='1.2' and kind in ('terms','privacy'))<>2 then
    raise exception 'Review the current legal versions before applying the owner feature notice';
  end if;
end; $$;
update public.legal_documents set is_current=false where is_current and kind in ('terms','privacy');
insert into public.legal_documents(id,kind,version,title,effective_at,is_current,sections)
select kind||'-1.3',kind,'1.3',title,now(),true,
  jsonb_build_array(case when kind='terms' then
    jsonb_build_object('id','changes-in-1-3','title','Owner security and account moderation','paragraphs',jsonb_build_array(
      'This version adds a single-owner account-management interface. Its account inspection, temporary ban, early unban, and account deletion operations require a verified, recent authenticator challenge. Email verification remains temporarily paused.',
      'The owner may restrict or remove accounts for security, abuse prevention, violations of these rules, or necessary operation of this development service. A temporary ban has a reason and a finite expiry; the owner may lift it early. A ban blocks new sign-ins and protected account access, including existing sessions. You may need to sign in again after the restriction expires.',
      'Account deletion removes the live authentication account, profile, consent records and active sessions. It cannot be undone through the site. Minimal security audit records and provider logs/backups have separate retention as explained in the privacy notice.'
    )) else
    jsonb_build_object('id','changes-in-1-3','title','Protected owner access and audit records','paragraphs',jsonb_build_array(
      'A single owner can inspect account-management information after a recent time-based authenticator check. The interface returns username, email, account/confirmation timestamps, consent history, ban state, MFA status, and limited session security metadata such as client information and IP addresses processed by Supabase. It does not return password hashes, session/refresh tokens, OAuth credentials, or authenticator seeds.',
      'Successful account searches, inspections, bans, unbans and deletions generate restricted audit records. These contain the acting owner identifier, action/time, target identifier and username when relevant, and the moderation reason/expiry. Search text and email addresses are not copied into this audit trail. Minimal audit records can remain after account deletion for approximately 90 days, with daily cleanup; provider logs and backups follow their separate policies.',
      'Ban details are kept while a restriction is active and for approximately 90 days after expiry or early cancellation, with daily cleanup.',
      'Authenticator enrollment is performed in the signed-in account through Supabase. The setup key and QR code are shown during enrollment, not published in the repository or sent through a chat. Supabase processes the authenticator factor; this application does not log or archive setup keys or verification codes.'
    )) end)
  || coalesce((select jsonb_agg(case when s.value->>'id'='current-scope' and d.kind='terms' then
    s.value||jsonb_build_object('paragraphs',jsonb_build_array(
      'This release provides account creation, login, versioned legal acceptance and protected owner account-management/moderation tools. Email-code verification is implemented but temporarily paused. Public threads, replies, direct messages, uploads and paid services are not available.',
      'Material future changes will be described in a new version rather than silently rewriting published rules.'
    )) else s.value end order by s.ordinality)
    from jsonb_array_elements(d.sections) with ordinality s(value,ordinality)
    where s.value->>'id' not like 'changes-in-%'),'[]'::jsonb)
from public.legal_documents d where id in ('terms-1.2','privacy-1.2');

-- Application audits are append-only to all browser roles. Only this operator-owned
-- maintenance function may prune them; it is never exposed as an account-management RPC.
create function owner_private.prune_security_records()
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from owner_private.bans where coalesce(cancelled_at,expires_at)<clock_timestamp()-interval '90 days';
  delete from owner_private.audit_events where created_at<clock_timestamp()-interval '90 days';
  delete from owner_private.action_receipts where created_at<clock_timestamp()-interval '90 days';
  delete from owner_private.quotas where window_start<clock_timestamp()-interval '3 days';
end;
$$;
revoke all on function owner_private.prune_security_records() from public,anon,authenticated;
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('rockyforums-owner-security-retention','17 4 * * *','select owner_private.prune_security_records()');
