// this was created by an AI agent

import { readFile } from 'node:fs/promises';
import { RELEASE_ID } from '../server/asset-store.mjs';
import { parseReleasePackage } from './release-manifest.mjs';

const [command, input] = process.argv.slice(2);
if (!['stage', 'publish', 'activate'].includes(command) || !input) {
  throw new Error(
    'Usage: npm run frontend:publish -- <stage|publish> <package-file> OR activate <release-id>',
  );
}
const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;
if (
  !/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(url ?? '') ||
  !key ||
  key.startsWith('sb_publishable_')
) {
  throw new Error(
    'Publishing needs SUPABASE_URL and a server-only SUPABASE_SECRET_KEY or SUPABASE_SERVICE_ROLE_KEY. Never put that key in a frontend environment file.',
  );
}
async function rpc(name, values) {
  const headers = { apikey: key, 'Content-Type': 'application/json' };
  if (!key.startsWith('sb_secret_')) headers.Authorization = `Bearer ${key}`;
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(values),
    signal: AbortSignal.timeout(30_000),
    redirect: 'error',
  });
  if (!response.ok)
    throw new Error(
      `${name} failed (${response.status}). Check the release ID, database migrations, asset limits, and publisher permissions.`,
    );
}
let releaseId = input;
if (command !== 'activate') {
  const bundle = parseReleasePackage(await readFile(input));
  releaseId = bundle.release_id;
  await rpc('stage_frontend_release', { release_id: releaseId, assets: bundle.assets });
  console.log(`Staged ${releaseId}.`);
}
if (!RELEASE_ID.test(releaseId)) throw new Error('Invalid release ID.');
if (command !== 'stage') {
  await rpc('publish_frontend_release', { release_id: releaseId });
  console.log(`Active frontend: ${releaseId}. No backend redeployment is needed.`);
}
