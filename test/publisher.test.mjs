// this was created by an AI agent

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

function fixture() {
  const body = '<!doctype html><title>Fixture</title>';
  return {
    format: 'rockyforums.frontend.release.v1',
    release_id: 'ui-test-0001',
    assets: [
      {
        path: 'index.html',
        content_type: 'text/html; charset=utf-8',
        body_base64: Buffer.from(body).toString('base64'),
        sha256: createHash('sha256').update(body).digest('hex'),
      },
    ],
  };
}
function run(t, command, { bundle = fixture(), input, env = {} } = {}) {
  const directory = mkdtempSync(join(tmpdir(), 'rocky-publisher-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const packagePath = join(directory, 'fixture.json');
  const callsPath = join(directory, 'calls.jsonl');
  writeFileSync(packagePath, JSON.stringify(bundle));
  // Intercept fetch in the child process: these tests never contact a live project.
  const preload = `import { appendFileSync } from 'node:fs';
    globalThis.fetch = async (url, options) => {
      appendFileSync(process.env.TEST_CALLS, JSON.stringify({ url, method: options.method, headers: options.headers, values: JSON.parse(options.body), redirect: options.redirect }) + '\\n');
      return new Response(process.env.TEST_STATUS ? 'private provider error detail' : null, { status: Number(process.env.TEST_STATUS || 204) });
    };`;
  const result = spawnSync(
    process.execPath,
    [
      '--import',
      `data:text/javascript,${encodeURIComponent(preload)}`,
      fileURLToPath(new URL('../scripts/publish-frontend.mjs', import.meta.url)),
      command,
      input ?? (command === 'activate' ? 'ui-test-0001' : packagePath),
    ],
    {
      encoding: 'utf8',
      env: {
        ...process.env,
        SUPABASE_URL: 'https://dedicated-project.supabase.co',
        SUPABASE_SECRET_KEY: 'sb_secret_fixture',
        SUPABASE_SERVICE_ROLE_KEY: '',
        TEST_CALLS: callsPath,
        TEST_STATUS: '',
        ...env,
      },
    },
  );
  assert.equal(result.error, undefined);
  const calls = existsSync(callsPath)
    ? readFileSync(callsPath, 'utf8')
        .trim()
        .split('\n')
        .map((line) => JSON.parse(line))
    : [];
  return { ...result, calls };
}

test('publish validates and stages before activation with secret-key API headers', (t) => {
  const result = run(t, 'publish');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.calls.length, 2);
  assert.match(result.calls[0].url, /\/rpc\/stage_frontend_release$/);
  assert.match(result.calls[1].url, /\/rpc\/publish_frontend_release$/);
  assert.equal(result.calls[0].headers.apikey, 'sb_secret_fixture');
  assert.equal(result.calls[0].headers.Authorization, undefined);
  assert.equal(result.calls[0].method, 'POST');
  assert.equal(result.calls[0].redirect, 'error');
  assert.deepEqual(result.calls[1].values, { release_id: 'ui-test-0001' });
});

test('stage uploads without changing the active pointer', (t) => {
  const result = run(t, 'stage');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.calls.length, 1);
  assert.match(result.calls[0].url, /stage_frontend_release$/);
});

test('activate/rollback changes only the pointer and supports legacy service-role headers', (t) => {
  const result = run(t, 'activate', {
    input: 'ui-previous-0001',
    env: { SUPABASE_SECRET_KEY: '', SUPABASE_SERVICE_ROLE_KEY: 'legacy-service-role-fixture' },
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.calls.length, 1);
  assert.match(result.calls[0].url, /publish_frontend_release$/);
  assert.deepEqual(result.calls[0].values, { release_id: 'ui-previous-0001' });
  assert.equal(result.calls[0].headers.Authorization, 'Bearer legacy-service-role-fixture');
});

test('public credentials, invalid release IDs and corrupt packages cannot make network requests', (t) => {
  const corrupt = fixture();
  corrupt.assets[0].sha256 = '0'.repeat(64);
  for (const result of [
    run(t, 'publish', { env: { SUPABASE_SECRET_KEY: 'sb_publishable_fixture' } }),
    run(t, 'activate', { input: '../invalid' }),
    run(t, 'publish', { bundle: corrupt }),
  ]) {
    assert.notEqual(result.status, 0);
    assert.equal(result.calls.length, 0);
  }
});

test('a failed stage never activates and provider response bodies are not exposed', (t) => {
  const result = run(t, 'publish', { env: { TEST_STATUS: '403' } });
  assert.notEqual(result.status, 0);
  assert.equal(result.calls.length, 1);
  assert.doesNotMatch(result.stderr, /private provider error detail|sb_secret_fixture/);
});
