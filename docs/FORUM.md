# Main forum API and operations

Migrations `012`–`015` add real public discussions without placeholder users/posts. General discussion, Help & questions and Site feedback are category configuration, not simulated activity. Email verification remains paused with the exact existing banner. Uploads, messages and payments are unavailable.

## Data boundary

`forum_private` contains the maintenance switch, categories, threads, replies, duplicate-write receipts and minute quotas. Tables have RLS and no browser schema/table grants. Public security-definer functions use an empty search path and explicit output fields.

Public readers expose usernames, post IDs/content/timestamps, categories, counts and lock state—not Auth account IDs, emails, session information or private moderation reasons. `forum_viewer_status()` returns only the caller's own session/consent/ban/owner status. Banned members can still read public discussions.

| RPC                                                                          | Contract                                                                                    |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `forum_categories()`                                                         | Configured categories with actual counts/activity.                                          |
| `forum_list_threads(category_slug, page_number, search_text)`                | Latest-activity order; optional category and literal case-insensitive title substring.      |
| `forum_get_thread(target_id, page_number)`                                   | Opening post and oldest-first replies; ownership flag only for an active consenting caller. |
| `forum_viewer_status()`                                                      | Own status and active terms version; no account enumeration.                                |
| `forum_create_thread(category_slug, title, body, request_id)`                | Native-session, ban, current-terms and maintenance checks; existing category.               |
| `forum_create_reply(target_id, body, request_id)`                            | Same member checks; parent must exist and be unlocked.                                      |
| `forum_edit_thread(target_id, title, body, expected_updated_at, request_id)` | Own unlocked thread; exact optimistic timestamp.                                            |
| `forum_edit_reply(target_id, body, expected_updated_at, request_id)`         | Own reply in an unlocked thread; exact optimistic timestamp.                                |
| `forum_delete_thread(target_id, expected_title, request_id)`                 | Own unlocked thread; exact title confirmation; cascades all replies.                        |
| `forum_delete_reply(target_id, request_id)`                                  | Own reply in an unlocked thread.                                                            |
| `owner_set_thread_locked(target_id, lock_state, reason, request_id)`         | Fresh native TOTP owner proof; private audit.                                               |
| `owner_delete_forum_thread(target_id, expected_title, reason, request_id)`   | Fresh native TOTP, exact title, reason and private audit.                                   |
| `owner_delete_forum_reply(target_id, reason, request_id)`                    | Fresh native TOTP, reason and private audit.                                                |

Pages contain 25 records, bounded to 1–1000; search is at most 100 characters. Titles are 1–160 characters and bodies 1–20,000 after trimming. Content is **plain text**, not HTML/Markdown; the UI uses text nodes. There are no fake online counters, seeded conversations or generated posting identities.

## Write authorization and retries

Every member mutation checks the native user/session and ban state rather than trusting an unexpired JWT alone. Row locks serialize against native bans/logout. Current legal acceptance is checked on the server for every write, including replay. Thread locks are acquired before reply locks consistently. Own editing/deletion does not grant moderation rights over other authors.

Use a fresh UUID request ID for a new operation; retain it when retrying the exact same uncertain request. Receipts bind actor, operation and a canonical input fingerprint. Changed inputs or another account cannot reuse the key. Limits are three new threads and 20 member mutations per minute. Owner moderation has the separate protected-owner quota. UI checks are not authorization.

Editing uses the server's exact returned `updated_at`, not a client-generated timestamp. A stale edit is rejected rather than overwriting another edit. Reply creation returns the page containing the new reply.

## Maintenance and rollout

Posting starts disabled in migration `012`. Only a trusted database operator may enable it after legal/UI deployment and tests; no browser RPC can flip this flag.

```sql
-- Read-only status:
select enabled from forum_private.site where singleton;
-- Trusted operator only; public reading is unaffected:
update forum_private.site set enabled = false where singleton;
-- Re-enable only after the release has been validated:
update forum_private.site set enabled = true where singleton;
```

The validated forum release is `ui-20261029-forum-1`, built additively from immutable `ui-20261028-pages-1` assets. Owner-only `ui-20261029-owner-1` is retained for rollback. Pause posting before rolling back to a UI without forum controls; do not rewrite legal history, remove posted data or attempt to reuse an immutable release ID.

## Deletion and retention

Account deletion cascades authored threads/replies. Thread removal also deletes every descendant reply, including other authors' replies. Public copies/search indexes and provider backups/logs are outside live database deletion. Legal 1.4 preserves 1.3 owner disclosures and adds these public-content rules without changing older documents or acceptance timestamps. Returning members must explicitly accept 1.4 before posting.

The existing daily security cleanup prunes forum receipts after approximately 90 days and minute quotas after approximately three days, alongside owner security records. Receipts store identifiers/fingerprints/results, not a second post body. Content moderation audits store limited identifiers/action/reason/metadata, not post text.

## Checks

Run `supabase/tests/forum_security.sql`, `forum_write_edges.sql` and `security_retention.sql` as the database owner in an isolated development database, keeping its transaction/rollback intact. It tests actual anonymous/member privileges, publication gate, native sessions, consent, idempotency, ownership, optimistic edits, locks, bans, owner moderation and content cascades. Fixtures are never committed as real activity. Native Auth HTTP and mail delivery are separate tests.

The private browser suite covers empty categories, search/routing, guest access, creation/replies, own edits/removal, plaintext/XSS handling, ban/consent gates, moderation, uncertain-response retries and small screens. Its HTTP responses are mocked. `scripts/check-pages-live.mjs` is a separate real read-only Pages smoke: it blocks all Auth writes/non-reader RPCs and verifies forum/category navigation, existing auth forms, legal history, guest owner access and mobile layout.
