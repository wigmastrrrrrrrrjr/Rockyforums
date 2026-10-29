# Security and production-readiness notes

## Current state

- Dedicated free Supabase project **Rockyforums**, `rccshonvlrgskzvrpqhy`, `us-east-2`. The older shared application is not used or modified.
- Email/password signups enabled. **Email verification remains paused** (`mailer_autoconfirm = true`), matching the private frontend's policy. New accounts require a real returned session, but their address is not proven.
- Refresh-token rotation enabled; one-hour access-token lifetime.
- Account RLS, constrained profiles, atomic signup/consent, immutable legal history and current-version acceptance RPCs are applied.
- Versioned compiled frontend assets are in private-schema tables with RLS and no browser table grants. The published read RPC is public by design; stage/publish are service-role-only. Drafts are hidden and assets cannot be edited in place.
- The website gateway holds **only a public publishable key**, checks asset hashes, bounds memory/response sizes, and never caches active HTML. Publisher credentials are a separate administrative trust boundary.
- Frontend source is proprietary and ignored by the public backend repository. Root MIT grants and earlier published grants are preserved. Downloadable browser code is not a secret.

## Owner and forum controls

See [owner security](docs/OWNER_SECURITY.md) and [forum operations](docs/FORUM.md). Browser route guards are not authorization. Privileged actions require the singleton UUID owner seat, live unbanned native session, matching verified native TOTP factor, native/JWT AAL2, an authoritative TOTP AMR check within five minutes, and current terms. Native session revocation and bans block old JWTs. Manual lock requires a later native proof. Real authenticator setup remains a private user-operated flow; never send seeds or codes in chat.

Forum tables have RLS and no browser table grants. Public readers expose post fields/usernames only; mutations check live sessions, bans, consent, authorship/locks, bounded input and account-bound idempotency/quotas on the server. Removing an account/thread has disclosed content cascades. Source backups are immutable operator-only records; site-owner MFA cannot read/publish them.

## Required before public launch

1. **Set Supabase Auth's minimum password length to 12 in its dashboard.** The connector could not change the last-observed provider minimum of **6**. The UI's 12-character validation is bypassable and is not a server-enforced policy. Enable leaked-password protection if available on the plan.
2. Review Auth rate limits and provider-supported CAPTCHA. Username uniqueness and email auto-confirmation are not bot protection. No claim of email ownership or legal identity is made.
3. Set the final HTTPS site URL in Auth settings. No broad redirect wildcards are needed: there is no OAuth or email-link flow.
4. Publish the actual operator and a working **private** security/privacy/support contact. Review the starting-point legal text and publish new versions where needed. Do not solicit private account data in public issues.
5. Use the **database-backed Pages adapter** or deploy the alternative **backend gateway** behind HTTPS; never publish private frontend source. For the Node option, set the dedicated URL/public key in its environment; do not give it publisher credentials. Its serving host must be able to reach Supabase. Check `/readyz`, SPA routing, CSP, MIME handling and the published version. Production must not opt into preview embedding. A backend build must not republish the UI.
6. Test signup → immediate real session → refresh → logout → login on the deployed domain with a disposable account you control. Unit/browser API mocks and SQL checks do not prove live Auth connectivity. This sandbox blocks direct Supabase HTTP access. The GitHub Pages adapter uses the real database from the browser; its read-only live check is not a completed authentication smoke test. See `docs/GITHUB_PAGES.md` for Pages header, deep-link and shared-origin limitations.
7. Document provider log/backup retention, operator access, deletion and incident response. Self-service deletion and password recovery are not implemented. Keep an independent private source backup; the operator-only archive covers the new owner/forum application, not the original React source.
8. Keep publisher/service-role keys in a trusted server-side secret manager. Never put them in `VITE_` variables, database frontend assets, Git, logs, public CI or chat. The publication CLI is an administrative tool, not a visitor-facing API. Preserve old version URLs during rollback.

## Email verification stays paused

The exact site-wide banner is **“email verification will be required soon!”** The current UI hides code/resend controls and guards their API functions. Do not change provider settings or the frontend flag alone. When verification is explicitly re-enabled, coordinate SMTP, the numeric-code template, frontend release, provider enforcement, legal disclosures and existing-account handling using [docs/EMAIL_SETUP.md](docs/EMAIL_SETUP.md).

Email-code verification proves mailbox access at a point in time, not identity, trustworthiness or humanity. It is not MFA. Pending accounts reserve usernames and require a deliberate retention/abuse policy. Auto-confirmed accounts need deliberate re-verification later. Existing users have not been bulk-confirmed, deleted or migrated as part of frontend release work.

## Browser and database trust boundaries

The frontend remains a SPA. SDK session tokens persist in browser local storage; XSS could expose them. Inputs are rendered as text, production headers restrict scripts/styles/connections, and there are no external scripts, analytics or remote font loads. Moving to HttpOnly server cookies would require a deliberate session/CSRF design. Logout is local to this browser.

The gateway serves only published database assets and never reads frontend files from disk. It supplies MIME/security headers rather than trusting arbitrary header metadata. GET/HEAD are the only accepted methods. CSP blocks framing by default, objects and external scripts; failures return generic no-store errors rather than database details. HTTPS termination and denial-of-service protections remain deployment responsibilities.

Frontend guards are not authorization. Profiles and acceptance history remain owner-only under RLS; anonymous access is limited to published legal text, public forum content and compiled site assets. Signup triggers reject missing/stale consent metadata atomically. User-editable Auth metadata is not ongoing authorization. Future feature writes must enforce current terms in database policies, not just the UI.

## Review checks

```sh
npm ci --ignore-scripts
npm run format:check
npm run lint
npm test
npm audit --audit-level=moderate
```

`supabase/tests/{auth_security,frontend_security,owner_security,forum_security,forum_write_edges,security_retention}.sql` exercise real permissions, integrity and rollback in owner-run transactions. Run only in a dedicated development database; preserve their rollback boundaries. They do not call Auth HTTP or test email delivery. Private UI build/browser checks are run from the separately secured frontend workspace.

No public production-readiness claim is made until the operational items above and the real deployed-domain smoke test are complete. Do not include credentials, tokens or personal information in public vulnerability reports.
