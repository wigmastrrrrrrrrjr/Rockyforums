# Exclusive owner tools

The single owner seat is bound to the established `dougdev` Auth UUID, not a username match, editable metadata, signup order or a frontend flag. There is no browser API for assigning another owner. Migrations `007`–`011` implement the owner boundary; `014` adds forum moderation.

## Private authenticator setup

1. Sign in as the existing owner at the [live owner page](https://wigmastrrrrrrrrjr.github.io/Rockyforums/owner).
2. Read/accept the current terms if prompted, then start private authenticator setup.
3. Scan the native QR in an authenticator app, or enter the displayed private setup key. The type is **time-based (TOTP)**: **six digits, 30-second period**.
4. Enter a current code in that signed-in page. Account tools remain unavailable until native verification succeeds.

Setup is user-operated. Never send passwords, setup keys, QR images, recovery material or codes in chat, issues, logs or source. The application does not invent a key for the owner. An existing verified factor is challenged without revealing its seed. Abandoned unverified factors created by this setup may be reset; verified factors cannot be removed by these tools.

## Every protected request

PostgreSQL independently checks:

- The caller matches the singleton UUID owner seat and a live, unrestricted Auth user/session.
- Both the JWT and native session have AAL2.
- That session references a matching, verified native **TOTP** factor.
- A native `mfa_amr_claims` TOTP proof was updated within five minutes. A claimed client time, generic AAL2, arbitrary AMR claim or factor challenge time is insufficient.
- The current terms have been accepted.
- A manual session lock has not invalidated the proof; a later successful native TOTP verification is required to unlock.

The guard uses native AMR `greatest(created_at, updated_at)` because repeated successful verification refreshes `updated_at`. Native Auth schema/behavior is an external dependency: review and rerun the SQL suite after provider changes. Forum writes additionally lock native user/session rows against concurrent bans and logout. Client expiry hides data and ignores late responses, but is not the authorization boundary.

## Capabilities and safeguards

- Bounded account search and allowlisted profile, email, consent, identity-provider/factor-status and session metadata. No password hashes, tokens, OAuth credentials, seeds or unrestricted Auth rows.
- Temporary native bans from one minute to 365 days, using a duration or explicit expiry. Bans revoke sessions/refresh tokens; unban does not resurrect them. Automatic expiry still requires a new sign-in after revocation.
- Permanent account removal with typed username, reason and irreversible confirmation. The sole owner cannot delete or ban itself.
- Fresh-TOTP discussion lock/unlock and thread/reply removal with recorded reasons.
- Account-bound input-fingerprinted receipts make identical retries idempotent and reject altered-input reuse. Limits: 60 protected reads and 10 mutations per minute.
- Minimal private audits and receipts are pruned after approximately 90 days; minute quotas after approximately three days. The daily `rockyforums-owner-security-retention` job runs at 04:17 UTC. Provider logs/backups are separate.

Deleting an Auth account removes its profile, consent history, identities, factors, sessions, authored threads and replies. Removing a thread also removes **all** its replies, including other authors' replies. The UI and legal 1.4 disclose this cascade. Audits survive account removal until their retention cutoff.

Site-owner MFA is **not** a database/service-role/publisher credential. It cannot access source archives, change the owner seat, deploy arbitrary code or bypass sole-owner protection. Source recovery and native factor recovery require a separately trusted operator and appropriate identity verification; no recovery backdoor is supplied by the owner console.

## Validation and limitations

`supabase/tests/owner_security.sql` uses isolated rollback-only users/sessions/native factor fixtures and actual `anon`/`authenticated` roles. It covers identity forgery, native proof freshness/locks, current terms, bans, session revocation, confirmation, self-protection, idempotency, audit and quotas. The private browser suite checks enrollment/verification UI, data clearing, late responses, retries, bans/deletion and mobile layout using mocked HTTP. These tests do not enroll the real owner or prove a live Auth HTTP enrollment.

Shared Pages-origin local storage, a compromised device, stolen fully authenticated sessions, operator credentials and provider availability remain trust boundaries. See [SECURITY.md](../SECURITY.md) for password-policy, contact and launch prerequisites.
