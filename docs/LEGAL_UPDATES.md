# Updating the ground rules

Published documents live in Supabase, not hardcoded UI fallbacks. Their text, identity, version, kind, and effective time are immutable. Only the current-version marker can change. Do not edit an already-applied migration or rewrite published history.

The current terms and privacy notice are a practical starting point for a **development release with public discussions and owner moderation**, not lawyer-reviewed production documents. Before inviting the public, identify the operator, publish a real private support/privacy contact, review local age/consumer/privacy requirements, and publish a replacement version. Never direct people to post private account information in a GitHub issue.

Version 1.1 added required email-code verification without rewriting 1.0. Version **1.2** temporarily paused that requirement and discloses unverified signup while retaining both older versions. See `202610280005_pause_email_verification.sql`. Version **1.3** added exclusive authenticator-protected owner tools and limited security retention. Current **1.4** adds public posts, author/owner removal, thread/account cascades, operational receipts and their retention. Earlier versions remain readable. When verification returns, publish another version; do not edit history.

## A feature release that changes the rules

1. Describe the exact new feature and associated moderation, privacy, ownership, retention, and abuse-handling rules. Do not imply unavailable functionality already exists.
2. Write a **new** timestamped migration with a new document ID and version. Include a human-readable change summary as a document section.
3. In one transaction, mark the old document non-current and insert the new current version. Its effective timestamp must not be in the future when activated. The unique partial index permits only one current version per kind.
4. Keep the old document. Its `/terms/:version` or `/privacy/:version` URL continues to work. Use an expanded version string only containing URL-safe characters.
5. For material privacy/feature changes, publish a new terms version too, so existing members must explicitly accept before participating. A privacy-notice-only update does **not** create a new consent requirement automatically; separate legally required purpose-specific consents must be designed separately.
6. Add `public.has_accepted_current_terms()` to **every new feature's database write policy**, alongside row ownership and any moderation checks. The UI gate alone is not authorization. Add tests that old consent cannot authorize the new operation.
7. Test direct API access, concurrent/stale signup, returning-member acceptance, rejection of old versions, unchanged old timestamps, and anonymous access to legal text.
8. Deploy the migration and the feature in a controlled release. Provide advance notice when required by law or your published terms. Update these documents if future rules need scheduled activation.

Example migration shape (replace the example content; do not apply verbatim):

```sql
begin;
update public.legal_documents
  set is_current = false
  where kind = 'terms' and is_current;

insert into public.legal_documents
  (id, kind, version, title, effective_at, is_current, sections)
values (
  'terms-<new-version>', 'terms', '<new-version>', 'Terms of Service', now(), true,
  '[{"id":"changes","title":"What changed","paragraphs":["Explain the new feature and its rules here."]}]'::jsonb
);
commit;
```

The returning-member RPC accepts **only** the active version. It appends an acceptance record using the database time and never overwrites the earlier version's record. The member page fetches that database predicate when loaded; an old open tab is not continuously polled. New feature authorization must always rely on its database policies, not on what a tab happens to display.

## Retention

Deleting an Auth account cascades to its profile and consent history in the live database. Published legal text remains. Provider logs and backups have independent retention. If future legal requirements call for retaining identifiable consent after account deletion, design and disclose a lawful, time-limited retention mechanism before changing this behavior.

Public forum content is retained while its account/thread exists unless removed. Deleting a thread removes all replies, including other authors’ replies; deleting an account removes its authored threads/replies and their descendant replies. Owner/security audits and duplicate-operation receipts are pruned after approximately 90 days, minute-rate buckets after approximately three days, by a daily job. Provider logs/backups and outside copies are separate. Source/runtime release archives are immutable deployment records, not copies of user posts.
