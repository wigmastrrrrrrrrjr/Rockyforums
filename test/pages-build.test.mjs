// this was created by an AI agent
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  existsSync,
  mkdtempSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
const script = fileURLToPath(new URL('../scripts/build-pages.mjs', import.meta.url));
function workspace(t) {
  const directory = mkdtempSync(join(tmpdir(), 'rocky-pages-build-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  return directory;
}
function build(directory, extra = {}) {
  return spawnSync(process.execPath, [script], {
    cwd: directory,
    encoding: 'utf8',
    env: {
      ...process.env,
      SUPABASE_URL: 'https://dedicated-project.supabase.co',
      SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_fixture',
      PAGES_BASE_PATH: '/Rockyforums/',
      SUPABASE_SECRET_KEY: 'TOP_SECRET_SHOULD_NOT_BE_COPIED',
      ...extra,
    },
  });
}
test('Pages build removes stale files and copies only the public delivery adapter', (t) => {
  const directory = workspace(t);
  const output = join(directory, 'dist/pages');
  mkdirSync(output, { recursive: true });
  writeFileSync(join(output, 'stale-application.js'), 'must not be uploaded');
  const result = build(directory);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(readdirSync(output).sort(), [
    '.nojekyll',
    '404.html',
    'delivery.css',
    'index.html',
    'loader.mjs',
    'read-document.mjs',
    'site-config.mjs',
  ]);
  const config = readFileSync(join(output, 'site-config.mjs'), 'utf8');
  assert.match(config, /sb_publishable_fixture/);
  assert.doesNotMatch(config, /TOP_SECRET|SUPABASE_SECRET_KEY/);
  const html = readFileSync(join(output, 'index.html'), 'utf8');
  assert.match(html, /\/Rockyforums\/loader.mjs/);
  assert.doesNotMatch(html, /__BASE_PATH__|__DELIVERY_CSP__/);
});
test('Pages build refuses secret credentials before producing an artifact', (t) => {
  const directory = workspace(t);
  const result = build(directory, { SUPABASE_PUBLISHABLE_KEY: 'sb_secret_fixture' });
  assert.notEqual(result.status, 0);
  assert.equal(existsSync(join(directory, 'dist/pages')), false);
});
