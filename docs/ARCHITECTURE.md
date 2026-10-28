# Architecture and review guide

## Scope

An account-only starting point, not a simulated forum. Available routes:

- `/signup` (also the `/` default): email/password registration with a unique username and explicit terms acceptance.
- `/verify-email`: a paused-policy notice for now; the retained eight-digit confirmation/resend form is shown only when verification is enabled.
- `/login`: email/password authentication. No email-code or magic-link step while verification is paused.
- `/welcome`: authenticated account summary, logout, and a current-terms gate.
- `/terms` and `/privacy`: current published documents.
- `/terms/:version` and `/privacy/:version`: permanent historical documents.

Threads, replies, messaging, uploads, OAuth, password recovery, account editing, and self-service deletion are deliberately not implemented or advertised as working features.

## Layout

```text
server/                   Public read-only asset gateway; Node runtime only
scripts/                  Public packager/publisher and source-boundary checks
test/                     Public gateway/integrity/cache tests; generic fixtures
supabase/
  migrations/             Account/legal schema and private frontend release tables
  tests/                  Rollback-only database security tests
frontend/                 PRIVATE, ignored; not in the backend distribution
  src/
    app/                  Routing and layered, responsive global styles
    components/           Shared account layout, dialog and status feedback
    features/
      auth/               Forms, validation, Auth SDK calls and session context
      account/            Signed-in profile page and account queries
      legal/              Documents, consent gate, acceptance RPC and dialogs
    lib/                  Client configuration and data types
    test/                 Private unit-test setup and fixtures
  e2e/                    Private browser contract/accessibility tests
```

`frontend/src/features/auth/api.ts` handles credentials and sessions, `frontend/src/features/account/api.ts` reads account details, and `frontend/src/features/legal/api.ts` handles document reads and acceptance. Keep those calls out of shared layout components. The `/welcome` URL still opens the account page; the file move does not change existing links.

Prefer direct form handlers and ordinary conditionals over generic request/rendering frameworks. Keep comments for the reasons behind security checks, cancellation, consent resets, and duplicate-submit protection rather than narrating each line.

AI-created source files carry the comment `this was created by an AI agent`, using the file’s comment syntax. This records provenance, not a claim of human review. The original repository disclosure and already-applied migrations are unchanged.

The presentation layer never constructs SQL. Credentials go directly to Supabase Auth via the official SDK. Passwords are never placed in user metadata, profile rows, analytics, console output, or application-managed browser storage. Supabase handles credential hashing; the SDK persists session tokens in local storage.

## Independent frontend delivery

Only the backend is open source. The original MIT license and prior grants remain intact; new editable frontend material is proprietary. Keep the ignored frontend workspace privately backed up, not force-added to this repository. Compiled browser files are necessarily downloadable and are not a substitute for editable source.

`frontend_private.releases/assets/site` separate immutable releases from the active pointer. An owner builds with a version-prefixed Vite base, packages a checksummed manifest with license notices, stages through a service-role-only RPC, then explicitly publishes. No backend startup, build, CI job or deployment executes that publisher. See [FRONTEND_RELEASES.md](FRONTEND_RELEASES.md) for limits and recovery.

The Node gateway performs the narrow public read RPC using only a publishable key. Every SPA HTML request resolves the current database pointer; HTML is never cached. Versioned assets are validated and cached within bounded memory, with immutable HTTP caching and representation-specific ETags. Old published URLs remain available after rollback. A missing release or database failure returns a generic no-store error, never a stale bundled UI. Source maps and editable frontend files are not served.

Only the publisher has administrative credentials. Browser roles have no frontend schema/table access and cannot stage/publish, but can read explicitly published compiled assets. The gateway defines CSP/MIME/security headers itself. Production HTTPS is external to the Node process. API contract compatibility still matters when backend and frontend versions change independently.

The database release is active. GitHub Pages uses a static integrity-checking adapter plus a read-only Edge asset gateway; the Node gateway is an alternative host. See [GITHUB_PAGES.md](GITHUB_PAGES.md). The editable private workspace did not survive this resumed checkout; no development preview is being restarted. Local fixture checks, SQL checks, and the live public-site browser smoke test are distinct validation layers.

## Signup transaction

1. The legal provider reads the current published terms and privacy notice from Supabase.
2. Zod validates and normalizes the username and email; passwords are not transformed. The UI requires at least 12 characters and respects bcrypt's 72-byte UTF-8 input limit. Checkbox consent must be literally `true`.
3. `auth.signUp` sends email/password and the selected username, consent flag, and terms version.
4. The `auth.users` insert trigger validates the **current server-side** terms version and explicit acceptance, inserts the constrained profile, and creates the consent record using the database clock.
5. Any trigger failure rolls back the entire new account. Uniqueness is enforced in PostgreSQL, not by a racy availability check in the browser.
6. The current policy is `REQUIRE_EMAIL_VERIFICATION = false`, paired with Supabase `mailer_autoconfirm = true`. Signup must return a real session before navigating to `/welcome`; a missing session reports a configuration problem, never fake success.
7. The site-wide announcement states “email verification will be required soon!” Signup and login do not direct visitors to codes. Direct `/verify-email` visits show a paused-policy notice; the API boundary blocks both code verification and resend calls before contacting Supabase.
8. The future code flow remains implemented. When explicitly re-enabled with working email delivery and matching Supabase settings, pending signup goes to `/verify-email` with only email/send time in navigation state. `verifyOtp({ email, token, type: 'signup' })` must return a session; resend uses `type: 'signup'` and a cooldown. Passwords/codes never enter navigation state. An unexpected auto-confirmed session is rejected in that mode. See `EMAIL_SETUP.md` before changing the policy.

If the terms change during signup, the backend rejects the stale version. The form refreshes the legal documents; a version-keyed checkbox clears previous consent. Other entered form values remain intact. An account created by an interrupted response may still exist: a safe retry or login handles that uncertainty, rather than claiming the account could not possibly have been created.

## Security boundaries

- UI route guards are convenience only. Row-level security and explicit SQL grants are the authorization boundary.
- Public users can read published legal documents, including historical versions. They cannot read profiles or acceptance history.
- Authenticated members can read only their own profile and acceptance records. No browser role has direct table mutation privileges.
- The narrow `accept_current_terms` RPC derives the member ID from `auth.uid()`, validates the active version, generates its own timestamp, and is idempotent. It cannot accept on behalf of a supplied user ID.
- Security-definer functions have an empty search path, schema-qualified object names, and no default public execute grant.
- Raw user metadata is mutable by the user. It is read once by the signup trigger and is **not** subsequently trusted as profile data or proof of consent.
- Login failures do not distinguish an unknown email from a wrong password. An older unconfirmed-account response explains that email sending is paused and directs the member to the operator; no mass account confirmation is performed. Raw database messages are not displayed.
- Requests time out; database retries are explicit. Requests are aborted on component teardown, and stale responses do not update state.
- No `dangerouslySetInnerHTML`, external scripts, analytics, remotely loaded fonts, or fake OAuth buttons.

## Accessibility and design

A utilitarian forum layout: a compact wordmark, breadcrumb navigation, flat registration panels, left-aligned field labels on larger screens, and a small site-information sidebar. Neutral surfaces and a single blue action color replace the marketing hero, decorative illustrations, and feature cards. Typography uses the local Arial/Helvetica/system sans-serif stack, with no font downloads. `AccountLayout` shares the page structure across signup, login, verification, and account views; CSS cascade layers keep responsive overrides explicit. Mobile forms put labels above 16px inputs to avoid iOS focus zoom.

Forms have real labels, correct autocomplete values, associated inline errors, an initially unchecked consent box, and first-invalid-field focus. Native modal dialogs provide focus trapping and Escape support; cleanup explicitly restores the invoking element. Route navigation updates titles and moves keyboard context to the main landmark. Reduced-motion preferences are respected. Automated axe checks complement, but do not replace, manual assistive-technology review.

## Email delivery and legacy accounts

Email confirmation is intentionally disabled on the dedicated project for this release. Auto-confirmation enables signup but is not email ownership proof or bot protection. SMTP and the hosted numeric-code template remain unconfigured. The checked-in `supabase/templates/confirmation.html` is retained for future setup. Do not enable the frontend flag alone, or merely enable Supabase confirmation. Existing auto-confirmed accounts need a deliberate re-verification strategy; older pending accounts need individual operator handling, not silent bulk confirmation. Current terms/privacy 1.2 describe this pause; versions 1.0 and 1.1 remain immutable history.

## Validation and deployment limitations

See [SECURITY.md](../SECURITY.md) for operational prerequisites and the distinction between frontend password guidance and the provider's current password policy. See [LEGAL_UPDATES.md](LEGAL_UPDATES.md) before adding features. Supabase connection values prefixed `VITE_` are public; secret/service-role keys must never be added to them.
