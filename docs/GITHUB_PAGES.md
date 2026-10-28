# GitHub Pages deployment

Public URL: **https://wigmastrrrrrrrrjr.github.io/Rockyforums/**

## What is hosted where

GitHub Pages cannot execute the Node server. It hosts only a small, open-source **delivery adapter** from `server/pages/`: a loading document, integrity-checked document reader, module loader and status styles. The Pages artifact contains no application bundle, editable frontend source, private environment or administrator key. The root `index.html` is the user's retained placeholder and is not deployed.

The actual application HTML, CSS, JavaScript and notices stay in the dedicated database:

1. On each full page load, the browser calls the narrow public `read_frontend_asset` RPC for the active `index.html`, explicitly without caching that lookup.
2. The adapter validates the response and SHA-256, adds the `/Rockyforums` router base, and resolves versioned resources through the public `frontend-assets` Edge Function.
3. That function uses **only the runtime anonymous key**, not a service-role key. It validates published asset metadata, MIME, decoded size and SHA-256 before serving bytes with CORS, `nosniff`, ETags and immutable caching.
4. The application uses the existing Supabase Auth, profile, consent and legal APIs. There are no account mocks in the deployed site.

The application frontend remains proprietary; generic delivery infrastructure is part of the MIT backend. Browser-delivered compiled code is necessarily downloadable. Existing MIT grants and third-party licenses remain intact.

## Deployment workflow

`.github/workflows/static.yml` builds and uploads **only `dist/pages/`**, never the entire repository. It runs backend checks and generic browser delivery tests before deployment, then performs a read-only live browser smoke check. The `github-pages` environment remains restricted to `main`. Work is committed/pushed to the fixed session branch and reviewed through a pull request before the normal main-branch deployment.

Only delivery-adapter/configuration changes trigger automatic Pages deployment. Changes to unrelated backend handlers or database application assets do not build or replace the frontend. A manual workflow dispatch can redeploy the delivery layer. No administrator credential is stored in this workflow.

To build the adapter locally:

```sh
npm ci --ignore-scripts
npm run pages:build
```

`PAGES_BASE_PATH` defaults to `/Rockyforums/`; root custom-domain deployments can set `/`. Only the public project URL and publishable key are read from the environment/example. Invalid paths or a secret key are rejected.

## Application updates and rollback

Publish a new compatible application release to the database using the existing publisher. Pages does not need another deployment: a new page load resolves the active pointer. Already-open tabs keep their current code until reloaded. Old published resources remain available at versioned URLs.

**First Pages-compatible release:** `ui-20261028-pages-1`. It preserves the prior UI and adds only a native `BrowserRouter` base-path option and a `rockyforums-routing=base-path-v1` document marker. The original `ui-20261028-1` is retained for the root-mounted Node gateway, but predates project-path support; do not select that Node-only release as a Pages rollback target. Subsequent Pages rollbacks must select a Pages-compatible release.

The original editable workspace is absent from this resumed checkout. The existing compiled release was checksum-verified and adapted without changing its forms, legal/auth behavior or styling; this does **not** recreate the editable TypeScript source. Keep/restore a separately secured private source backup before future application development. Future private builds must:

- Keep the router base configurable from `meta[name="rockyforums-base-path"]`, defaulting to `/`.
- Include `<meta name="rockyforums-routing" content="base-path-v1" />`.
- Use external module scripts and the versioned asset namespace.
- Use relative module imports. If CSS/JS contains absolute runtime asset URLs, build those URLs against `https://rccshonvlrgskzvrpqhy.supabase.co/functions/v1/frontend-assets/_frontend/<release-id>/` rather than a GitHub-origin `/_frontend/` path.

The Node gateway remains available as an alternative host. A future release using absolute Edge asset URLs also needs an appropriately configured Node CSP if served through that alternative.

## Hosting limitations and security

- Pages provides the `404.html` loading adapter for fresh deep links such as `/Rockyforums/terms/1.2`. The application loads and the URL is preserved, but GitHub's initial HTTP response is still 404. This is a static-host limitation, not an authentication failure.
- Pages does not let this repository set custom response headers. The adapter supplies a restrictive CSP/referrer policy through metadata, refuses to load account UI in a frame, and permits scripts/styles only from itself and the exact asset-function path. A reverse proxy/custom host is needed for response-header controls such as `frame-ancestors`, HSTS management and custom HTTP status routing. The Node host has stronger header controls.
- A public project Pages site shares an origin with that owner's other Pages projects. Use a dedicated custom domain before relying on origin isolation from other applications.
- The Edge Function deliberately does not serve HTML. Default Supabase function domains are not being used to bypass their HTML-hosting restrictions.
- Email verification stays paused and the exact announcement remains. Server-side password-policy alignment, operator contact, legal review and a real signup/login test with an inbox/account you control remain production prerequisites in `SECURITY.md`.

## Validation

```sh
npm test
npm run pages:build
npx playwright install --with-deps chromium
npm run test:pages
```

These tests use generic delivery fixtures, not proprietary UI source. The post-deploy `scripts/check-pages-live.mjs` check uses a real browser against the public site: signup screen, exact announcement, login navigation, a fresh historical legal link and mobile overflow. It creates no accounts, signs in as nobody, and does not claim a completed real authentication smoke test.
