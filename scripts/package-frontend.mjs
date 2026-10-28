// this was created by an AI agent

import { createHash } from 'node:crypto';
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { contentType, RELEASE_ID, validAssetPath } from '../server/asset-store.mjs';
import { parseReleasePackage } from './release-manifest.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const [
  releaseId,
  input = 'frontend/dist',
  output = `frontend/.releases/${releaseId}.frontend-release.json`,
] = process.argv.slice(2);
if (!RELEASE_ID.test(releaseId ?? ''))
  throw new Error(
    'Usage: npm run frontend:package -- <release-id> [build-directory] [output-file]',
  );
const buildDirectory = resolve(input);
const outputPath = resolve(output);
const insideRepository = !relative(root, outputPath).startsWith('..');
if (insideRepository && !relative(root, outputPath).startsWith('frontend/')) {
  throw new Error(
    'Private release packages must stay in the ignored frontend workspace or outside the repository.',
  );
}
const index = await readFile(join(buildDirectory, 'index.html'), 'utf8');
if (!index.includes(`/_frontend/${releaseId}/`)) {
  throw new Error('Rebuild the frontend with FRONTEND_RELEASE_ID matching this release ID.');
}

// Preserve runtime dependency notices without adding private source to the public repository.
const workspace = resolve(root, 'frontend');
const lock = JSON.parse(await readFile(join(workspace, 'package-lock.json'), 'utf8'));
const notices = [];
for (const [packagePath, metadata] of Object.entries(lock.packages)) {
  if (!packagePath.startsWith('node_modules/') || metadata.dev) continue;
  const directory = join(workspace, packagePath);
  let names;
  try {
    names = await readdir(directory);
  } catch {
    continue;
  }
  const licenseNames = names.filter((name) => /^(?:licen[cs]e|copying)(?:[._-].*)?$/i.test(name));
  for (const name of licenseNames) {
    try {
      const license = await readFile(join(directory, name), 'utf8');
      notices.push(`${packagePath.replace(/^node_modules\//, '')} ${metadata.version}\n${license}`);
    } catch {
      /* Some packages use a LICENSE directory rather than a text file. */
    }
  }
}
if (!notices.length) throw new Error('No dependency license notices were found.');
await writeFile(
  join(buildDirectory, 'THIRD_PARTY_LICENSES.txt'),
  notices.join('\n\n--------------------\n\n'),
);
await writeFile(
  join(buildDirectory, 'FRONTEND_NOTICE.txt'),
  await readFile(join(workspace, 'LICENSE')),
);

const assets = [];
async function collect(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isSymbolicLink()) throw new Error('Release builds must not contain symbolic links.');
    if (entry.isDirectory()) {
      await collect(path);
      continue;
    }
    if (!entry.isFile()) throw new Error('Release builds must contain regular files only.');
    const assetPath = relative(buildDirectory, path).split('\\').join('/');
    if (['_headers', '_redirects'].includes(assetPath)) continue;
    if (!validAssetPath(assetPath)) throw new Error(`Unsupported build artifact: ${assetPath}`);
    const body = await readFile(path);
    if (!body.length || body.length > 2_097_152)
      throw new Error(`Invalid asset size: ${assetPath}`);
    assets.push({
      path: assetPath,
      content_type: contentType(assetPath),
      sha256: createHash('sha256').update(body).digest('hex'),
      body_base64: body.toString('base64'),
    });
  }
}
await collect(buildDirectory);
if (
  assets.length > 64 ||
  assets.reduce((total, item) => total + Buffer.from(item.body_base64, 'base64').length, 0) >
    16_777_216
) {
  throw new Error('Release exceeds the database size limits.');
}
assets.sort((a, b) => a.path.localeCompare(b.path));
const body = JSON.stringify({
  format: 'rockyforums.frontend.release.v1',
  release_id: releaseId,
  assets,
});
parseReleasePackage(Buffer.from(body));
await mkdir(dirname(outputPath), { recursive: true });
await writeFile(outputPath, body, { mode: 0o600 });
console.log(
  JSON.stringify(
    {
      releaseId,
      assetCount: assets.length,
      packageBytes: Buffer.byteLength(body),
      packageSha256: createHash('sha256').update(body).digest('hex'),
      output: outputPath,
    },
    null,
    2,
  ),
);
