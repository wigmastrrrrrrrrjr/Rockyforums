# Rockyforums backend

The open-source backend for Rockyforums: public discussions, real accounts and protected owner moderation. **The frontend is proprietary and is released separately into the database.** See [LICENSE_SCOPE.md](LICENSE_SCOPE.md); previously granted licenses are not revoked.

The compact gray-and-blue design is retained. Real accounts, profiles, legal documents and consent records use a dedicated Supabase project. Email verification remains temporarily paused, with the banner **“email verification will be required soon!”** Members can create threads and replies in General, Help and Site feedback, search titles, and edit/delete their own unlocked content. Public reading does not require an account. The UUID-bound `dougdev` owner has authenticator-protected account inspection, deletion, temporary bans and discussion moderation. No sample posts, simulated members/activity, messages, uploads or payments are provided.

## Two independent releases

```text
Private frontend workspace → build → explicit publish → Supabase release/assets tables
Public backend deployment → Node HTTP gateway → currently published database release
```

Deploying or restarting the backend **does not build, publish or replace the frontend**. HTML is resolved from the database on every navigation; versioned assets are immutable and cacheable. Publishing and rollback update one database pointer atomically. A backend deploy must still remain compatible with the active frontend's API contracts.

Editable frontend source is kept in the ignored `frontend/` workspace, not in this backend distribution. The database contains compiled HTML, CSS and JavaScript. New owner/forum source archives are stored **separately**, accessible only to a trusted operator—not to visitors or the signed-in site owner. Keep an independent secured backup too. These archives contain the new addon, not the original React source lost during workspace resume. Browser-delivered code is necessarily visible to visitors; proprietary does not mean hidden from developer tools.

## GitHub Pages

Public site: **https://wigmastrrrrrrrrjr.github.io/Rockyforums/**

Pages hosts a small delivery adapter, not the Node server or the application source. The adapter reads the active HTML from Supabase and loads its checked versioned assets through a read-only Edge Function. Publishing or rolling back a compatible database release therefore does not require another Pages deployment. Only `dist/pages/` is uploaded; never the entire repository. See [GitHub Pages deployment](docs/GITHUB_PAGES.md) for the workflow, project-path support, deep-link limitation and security boundaries.

## Run the alternative Node gateway

Node.js **22.12 or later** is required. There are no third-party runtime dependencies.

```sh
npm ci
cp .env.example .env.local
npm start
```

The gateway listens on `0.0.0.0:8080`. It needs only `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`, never an administrator key. The example identifies the dedicated project; these values are intentionally public. The serving machine must be able to reach that project's HTTPS REST endpoint. `/healthz` checks the process; `/readyz` also checks that the database has an active frontend.

Migrations `001`–`015` and the account, owner and main-forum frontend releases have been applied to the dedicated Rockyforums project. For a new, isolated project, apply `supabase/migrations/` in order and publish a frontend separately. An empty database returns an honest HTTP 503, not an old bundled UI. Do not share this account trigger with unrelated applications.

Use HTTPS in front of the gateway in production. The supplied Dockerfile copies only the backend; `.dockerignore` excludes the entire private frontend. `PORT` and `HOST` are configurable. `ALLOW_PREVIEW_EMBEDDING=true` is an explicit development-only opt-in for embedded previews; production defaults prevent framing. The public Pages adapter is the deployment target. No preview server is running. The new editable owner/forum workspace is private and backed up separately from public runtime assets; the original editable React source remains unavailable.

## Publish or roll back the UI

The owner needs the private frontend workspace and a **server-only** publisher credential supplied through a trusted environment/secret manager. Do not put secret/service-role keys in browser files, `VITE_` variables, public CI, shell history or Git.

```sh
# Current private owner/forum workspace:
cd frontend/owner
npm ci
npm test
FRONTEND_RELEASE_ID=ui-20261029-forum-2 npm run build
```

This build is an **additive** manifest, not a complete release package. A trusted operator must assemble it with the frozen base assets, validate it, and persist the separate private source archive as described in [the publishing runbook](docs/FRONTEND_RELEASES.md#additive-ownerforum-releases-and-private-source-recovery). Do not run the old full-workspace packager against an addon manifest.

For an already assembled full release package, use the existing server-only publisher from the backend root:

```sh
npm run frontend:publish -- stage frontend/.releases/<new-id>.frontend-release.json
npm run frontend:publish -- activate <new-id>
# Pause posting before reverting to an owner-only UI, then:
npm run frontend:publish -- activate ui-20261029-owner-1
```

Release IDs are unique and immutable. If staging succeeded but activation failed, activate the verified existing draft; do not upload different bytes under its ID. Frontend publication is independent of backend deployment. Keep prior compatible releases and source archives for recovery.

## Review and test

Public backend checks run without the private frontend or administrator credentials:

```sh
npm ci --ignore-scripts
npm run format:check
npm run lint
npm test
npm audit --audit-level=moderate
```

`lint` syntax-checks the JavaScript and checks the public-file boundary. Node tests exercise the gateway, integrity validation, caching, error handling and rollback visibility using controlled stores/HTTP responses. They do not assert live network connectivity.

Run `supabase/tests/{auth_security,frontend_security,owner_security,forum_security,forum_write_edges,security_retention}.sql` as the database owner in a dedicated development database. These use rollback-only fixtures; never strip their transaction boundaries. They test actual database permissions and constraints, not email delivery or Auth HTTP behavior.

The private owner/forum workspace has build and browser checks (37 passing scenarios); fixtures mock HTTP and never enroll the real owner or create production accounts. Browser contract tests intercept Auth/data responses and do not create production accounts. See [architecture](docs/ARCHITECTURE.md) and [SECURITY.md](SECURITY.md) for remaining launch prerequisites.

## Review map

- `server/` — read-only database asset store and HTTP gateway.
- `scripts/` — explicit release packaging/publishing and public-source checks.
- `test/` — public backend tests, with no proprietary UI fixtures.
- `supabase/migrations/` — account, consent, legal-history and frontend-release schema.
- `supabase/tests/` — real database permission and integrity checks.
- [Owner security and authenticator setup](docs/OWNER_SECURITY.md).
- [Forum API and operational controls](docs/FORUM.md).
- [Frontend publishing and rollback](docs/FRONTEND_RELEASES.md).
- [Email verification setup for later](docs/EMAIL_SETUP.md).
- [Updating versioned legal documents](docs/LEGAL_UPDATES.md).
- [AI disclosure](AI%20disclosure.md) — original disclosure preserved. AI-created code carries `this was created by an AI agent` comments.

**Before production use:** align Supabase's server-side minimum password length with the UI's 12-character requirement, publish a private support contact, review the legal text, and complete a live signup/login smoke test on the production domain. Email verification is intentionally still paused. See [SECURITY.md](SECURITY.md).
