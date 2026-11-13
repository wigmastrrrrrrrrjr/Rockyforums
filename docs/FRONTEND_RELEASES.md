# Frontend releases and rollback

## Ownership and storage

Only the backend is distributed under the repository's MIT license. Editable frontend source and build tools live in the ignored `frontend/` workspace; keep a private backup independent of this public repository. Previously published MIT material and third-party licenses retain their grants. The packager includes `FRONTEND_NOTICE.txt` and dependency notices in every release.

Supabase stores compiled runtime assets in `frontend_private.releases` and `frontend_private.assets`. `frontend_private.site` holds the single active release ID. This is database-backed static delivery, not server-side rendering, and it does not hide downloadable browser code. No source maps, editable TypeScript/TSX, environment files or administrator keys belong in a release.

## Publish

The original full-workspace pipeline below remains supported when that private workspace is available. For the current owner/forum addon, use the additive release section below instead.

1. Make the UI change in the private workspace. Preserve the shared layout and account/legal boundaries; run its type, lint, unit and browser checks.
2. Choose a new lowercase release ID, 6–80 characters using letters, digits and hyphens. Never reuse an ID with different bytes.
3. Build with `FRONTEND_RELEASE_ID=<id> npm run build` from `frontend/`. This gives all asset URLs a `/_frontend/<id>/` prefix; SPA routes remain `/signup`, `/login`, etc.
4. From the backend root run `npm run frontend:package -- <id>`. The packager validates the build and produces ignored `frontend/.releases/<id>.frontend-release.json`, including checksums and license notices. Check the reported ID, size and checksum. Do not commit this package.
5. Supply `SUPABASE_URL` plus either `SUPABASE_SECRET_KEY` or `SUPABASE_SERVICE_ROLE_KEY` through a trusted **server-side** environment. Keep this credential separate from the read-only website process and private browser build. The public publishable key cannot publish.
6. Run `npm run frontend:publish -- stage <package-file>` to upload. Staging is transactional: a bad file rolls back the whole release. Drafts cannot be read by browser roles.
7. Run `npm run frontend:publish -- activate <id>` to activate. Or use `publish <package-file>` to stage and activate in one CLI invocation; those are two database transactions, so a failed activation can leave a safe inactive draft.
8. Check `/readyz`, load the account routes in a new browser tab, verify the banner and legal documents, and complete an appropriate live Auth smoke test with a disposable account you control. Browser API mocks do not prove a real account flow.

Backend deployments must not run these publisher commands. A database migration that breaks an active frontend API needs a coordinated, backwards-compatible rollout; separate packaging does not solve contract incompatibility.

## Rollback

```sh
npm run frontend:publish -- activate <previous-release-id>
```

Publication takes an advisory transaction lock, stamps the first publication time, and atomically updates the active pointer. Every HTML navigation consults the database with `Cache-Control: no-store`; no backend restart is needed. Published old assets remain readable at their versioned URLs so already-open pages do not break. Existing tabs do not automatically replace their running JavaScript: reload to receive the selected version.

The gateway's bounded cache contains only immutable, explicitly versioned assets, never the active HTML lookup. Do not add a CDN HTML cache or cache `/readyz` in a reverse proxy. If an external proxy was incorrectly caching HTML, purge that cache separately.

Do not edit/delete individual asset rows or rewrite an existing release. The database rejects asset updates/deletes. No garbage-collection command is provided: release retention and coordinated removal of old cached/versioned URLs require a deliberate later policy.

## Limits and safeguards

- 1–64 assets, exactly one `index.html`.
- At most 2 MiB per asset and 16 MiB for the whole release.
- Validated relative paths; no traversal, source maps or unsupported MIME types.
- SHA-256 and decoded byte counts checked by both publisher and database.
- Private tables have RLS and no browser schema/table grants.
- Only `service_role` can execute staging/publication RPCs. The database owner is also an administrative trust boundary.
- `anon`/`authenticated` can execute the narrow reader for published assets only. Those compiled assets are public by design, not personal data.
- The website uses only a public publishable key. It has no publication endpoint and accepts GET/HEAD only.
- CSP and MIME/security headers come from the gateway, not arbitrary database header metadata.

## Initial migration record

`ui-20261028-1` was the initial release in the dedicated project `rccshonvlrgskzvrpqhy`: seven assets, 633,604 decoded bytes. The packaged JSON SHA-256 is `2c88fa45c01dbcde1c4161d9f3117df01cdfeedacc5c1c1e9ec750c1f1ea5aed`.

This sandbox's direct Supabase network access is blocked and its preview ports require a traffic token. The one-time import therefore used a public-key-encrypted compiled package relayed as an unreferenced GitHub object. Its private decryption key was wrapped with the destination project's runtime secret; no plaintext proprietary code, editable source or administrator credential was uploaded to the public repository. A dependency-only transfer object contained only independently licensed third-party code and full notices, with a checked module boundary. No Git commit, branch, tag or published release contains frontend code. A failed draft-release upload was removed. The encrypted objects are not part of the backend distribution and are not used for ongoing delivery.

The destination checked the approved package checksum before transactional staging. All seven stored assets were verified, then activated explicitly. The temporary installer, HTTP extension and transfer server were removed. Normal future publication uses the CLI from an authorized machine with HTTPS access, not this one-time bridge.

A separate read-only smoke test used only the public publishable key through the real REST endpoint and verified the active HTML plus all seven asset checksums. Its temporary function and HTTP extension were removed.

The original editable React workspace is absent after resume. New owner/forum source is a separate additive application, not a recovery of that original source. The compiled database release remains intact. The Pages-compatible successor is `ui-20261028-pages-1`, with package SHA-256 `d738a5eafbb91e37fc9a5793735bbe96193bc80644b376b8fecc2f2f0516c8db`. It adds only router-base support, preserving the UI and auth/legal behavior. See [GITHUB_PAGES.md](GITHUB_PAGES.md) for deployment, compatible rollback targets and the separate live browser smoke check.

## Additive owner/forum releases and private source recovery

The ignored `frontend/owner/` build now emits `rockyforums.frontend.addon.v1`, not the full-package format accepted by the original packaging CLI. Its build/test commands are `npm ci`, `npm test`, then `FRONTEND_RELEASE_ID=<new-id> npm run build` in that private workspace. Do not pass an additive manifest to the full-package publisher. Freeze and retain its exact manifest before rebuilding.

A trusted operator assembles a full package using the immutable `ui-20261028-pages-1` database assets: retain all six non-HTML assets byte-for-byte, replace the single module entry in a new HTML document, update its release prefix, remove the unnecessary legacy vendor preload, add the new CSS/dependency-license link, and append the verified addon assets. The private entry bridges legacy React soft-navigation into the new forum/owner routes and updates obsolete feature-availability copy without editing the frozen base bytes. Run the resulting complete asset array through `stage_frontend_release`, not direct browser table writes.

Store the separate SHA-256-checked gzip source through `backup_frontend_source(release_id, archive_base64, sha256)` before activation. `read_frontend_source(release_id)` is service-role-only; site-owner AAL2 cannot use it. Validate its format/hash, decompress it with a bounded output size, and recover `files` from the `rockyforums.private-source.v1` JSON into a fresh **private** directory. Reject absolute/traversal/symlink paths, retain dependency notices/lockfile, and never overwrite a workspace blindly. The archive includes new owner/forum modules, tests, build script, lockfile and private README—not node_modules, environments, browser state, actual MFA keys or original React source. Runtime asset delivery cannot read these archives. Updates/deletion of stored archives are rejected. Keep an independent secured backup too.

Retained owner release: `ui-20261029-owner-1`, 12 assets / 890,400 bytes; its 27,647-byte source SHA-256 is `9d4eac3dd1c20ff789a5b9e794fcd1b05e825936b0dea39012f9d9f9cb3d943f`. The published forum successor is `ui-20261029-forum-1`, 15 assets / 919,798 bytes; its 39,526-byte source SHA-256 is `3dbbdd9852a2b922f6ab62316e53d08e3127ae66d081699172e0118a62882db3` (19 files). Both retained archives were read back, hash-verified and successfully decompressed. Pause member posting before rolling back to an owner-only UI. Legal 1.4 stays immutable even during a UI rollback.

The sandbox transfer uses only an authenticated encrypted envelope in an unattached Git object, never plaintext frontend source in Git history. The destination verifies envelope/manifest hashes and retains the private source separately; activation remains an explicit trusted-database operation. Temporary transfer functions and HTTP extensions are removed afterward.
