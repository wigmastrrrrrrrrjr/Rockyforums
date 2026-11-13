-- this was created by an AI agent
-- Published legal text is immutable: the public forum is a new 1.4 feature notice.
do $$ begin
  if (select count(*) from public.legal_documents where is_current and version='1.3' and kind in ('terms','privacy'))<>2 then raise exception 'Review current legal versions before publishing the forum notice'; end if;
end; $$;
update public.legal_documents set is_current=false where is_current and kind in ('terms','privacy');
insert into public.legal_documents(id,kind,version,title,effective_at,is_current,sections)
select kind||'-1.4',kind,'1.4',title,now(),true,
  jsonb_build_array(case when kind='terms' then
    jsonb_build_object('id','changes-in-1-4','title','Public forum discussions','paragraphs',jsonb_build_array(
      'The main forum now supports public categories, threads and replies. An active, unrestricted account with current terms acceptance is required to post. Authors can edit or delete their own unlocked content. Posting limits apply; uploads, direct messages and paid services remain unavailable.',
      'Post titles, text, usernames and timestamps are public and readable without an account. Do not post passwords, verification codes, authenticator keys, private contact details or other information you do not want made public. Other people and search engines may copy public material.',
      'The single owner may lock or unlock discussions and remove threads or replies for security, abuse prevention, rule violations or necessary operation. Owner moderation requires a recent authenticator check and a recorded reason. A locked discussion does not accept new replies or author edits/deletions until it is unlocked.',
      'Deleting a thread also deletes all its replies, including replies by other people. Permanent account deletion removes that account''s authored threads and replies; replies within removed threads also disappear. These live-data deletions cannot be undone through the site and do not remove outside copies or separate provider logs/backups. Minimal security audits have separate retention.'
    )) else
    jsonb_build_object('id','changes-in-1-4','title','Public posts and their retention','paragraphs',jsonb_build_array(
      'Forum titles, post text, author usernames, creation/edit times, reply counts and discussion lock state are public. The public forum reader does not return email addresses, Auth account identifiers, session metadata, authenticator seeds, credentials or private moderation reasons.',
      'Posts remain while their account and thread exist, unless deleted by the author or owner. Account deletion removes authored threads and replies, and removing a thread removes all replies within it. People or search engines may retain copies made while content was public. Supabase logs/backups follow separate policies; deletion is not a guarantee that every outside or backup copy disappears immediately.',
      'Posting uses account-bound rate counters and duplicate-request receipts. These are private operational records: receipts contain identifiers and an input fingerprint, not a separate copy of the post body. Receipts are pruned after approximately 90 days and minute-rate buckets after approximately three days, with daily cleanup.',
      'Owner discussion locks and content removals produce restricted audits containing action/time, owner and target identifiers, target username when relevant, reason, and limited action metadata. Post bodies are not copied into the audit trail. Audit retention remains approximately 90 days with daily cleanup.'
    )) end)
  || coalesce((select jsonb_agg(case when s.value->>'id'='current-scope' and d.kind='terms' then
    s.value||jsonb_build_object('paragraphs',jsonb_build_array(
      'This release provides accounts, login, versioned legal acceptance, public forum categories/threads/replies, author editing/deletion, and protected owner account-management/moderation tools. Email-code verification remains temporarily paused. Direct messages, uploads and paid services are not available.',
      'Material future changes will be described in a new legal version rather than silently rewriting published rules.'
    )) else s.value end order by s.ordinality)
    from jsonb_array_elements(d.sections) with ordinality s(value,ordinality)),'[]'::jsonb)
from public.legal_documents d where id in ('terms-1.3','privacy-1.3');

create or replace function owner_private.prune_security_records()
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from forum_private.receipts where created_at<clock_timestamp()-interval '90 days';
  delete from forum_private.quotas where window_start<clock_timestamp()-interval '3 days';
  delete from owner_private.bans where coalesce(cancelled_at,expires_at)<clock_timestamp()-interval '90 days';
  delete from owner_private.audit_events where created_at<clock_timestamp()-interval '90 days';
  delete from owner_private.action_receipts where created_at<clock_timestamp()-interval '90 days';
  delete from owner_private.quotas where window_start<clock_timestamp()-interval '3 days';
end; $$;
revoke all on function owner_private.prune_security_records() from public,anon,authenticated;
