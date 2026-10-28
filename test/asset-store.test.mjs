// this was created by an AI agent

import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { test } from 'node:test';
import {
  contentType,
  DatabaseAssetStore,
  decodeAsset,
  validAssetPath,
} from '../server/asset-store.mjs';

const releaseId = 'ui-test-0001';
const config = {
  supabaseUrl: 'https://dedicated-project.supabase.co',
  publishableKey: 'sb_publishable_test',
};
function record(path = 'index.html', release = releaseId, body = 'compiled content') {
  return {
    release_id: release,
    path,
    content_type: contentType(path),
    body_base64: Buffer.from(body).toString('base64'),
    sha256: createHash('sha256').update(body).digest('hex'),
  };
}

test('only supported compiled asset paths are accepted', () => {
  for (const path of [
    'index.html',
    'assets/app-A1.js',
    'assets/app.css',
    'favicon.svg',
    'THIRD_PARTY_LICENSES.txt',
  ]) {
    assert.equal(validAssetPath(path), true, path);
  }
  for (const path of [
    '',
    '../index.html',
    'assets/../app.js',
    'assets//app.js',
    '/app.js',
    'src/app.tsx',
    '.env',
    'app.js.map',
    'assets/%2e%2e/app.js',
    'other.html',
    'a'.repeat(241) + '.js',
  ]) {
    assert.equal(validAssetPath(path), false, path);
  }
});

test('decodes database base64 with PostgreSQL line breaks and checks integrity', () => {
  const value = record();
  value.body_base64 = value.body_base64.replace(/.{8}/g, '$&\n');
  const result = decodeAsset(value, null, 'index.html');
  assert.equal(result.body.toString(), 'compiled content');
  assert.equal(result.releaseId, releaseId);
});

test('rejects wrong release, path, MIME, checksum, empty body and malformed base64', () => {
  const mutations = [
    { release_id: 'INVALID' },
    { release_id: 'ui-test-0002' },
    { path: 'different.js' },
    { content_type: 'application/octet-stream' },
    { sha256: '0'.repeat(64) },
    { body_base64: '' },
    { body_base64: '!!!!' },
    { body_base64: 'YWJj===' },
    { body_base64: 'Y'.repeat(2_800_004) },
  ];
  for (const change of mutations) {
    assert.throws(() => decodeAsset({ ...record(), ...change }, releaseId, 'index.html'));
  }
});

test('gateway configuration accepts only HTTPS Supabase and a public publishable key', () => {
  assert.throws(() => new DatabaseAssetStore({ ...config, supabaseUrl: 'http://localhost' }));
  assert.throws(
    () => new DatabaseAssetStore({ ...config, publishableKey: 'sb_secret_not-a-reader' }),
  );
  assert.throws(
    () => new DatabaseAssetStore({ ...config, supabaseUrl: 'https://project.supabase.co/evil' }),
  );
});

test('uses only the read RPC with a public API key; invalid input never makes a request', async () => {
  const calls = [];
  const store = new DatabaseAssetStore({
    ...config,
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return Response.json(record());
    },
  });
  assert.equal(await store.read('INVALID', 'index.html'), null);
  assert.equal(await store.read(null, '../index.html'), null);
  assert.equal(calls.length, 0);
  await store.read(null, 'index.html');
  assert.equal(calls[0].url, `${config.supabaseUrl}/rest/v1/rpc/read_frontend_asset`);
  assert.deepEqual(calls[0].options.headers, {
    apikey: config.publishableKey,
    'Content-Type': 'application/json',
  });
  assert.deepEqual(JSON.parse(calls[0].options.body), {
    release_id: null,
    asset_path: 'index.html',
  });
  assert.equal(calls[0].options.redirect, 'error');
  assert.ok(calls[0].options.signal instanceof AbortSignal);
});

test('caches immutable versioned assets, not missing assets', async () => {
  let calls = 0;
  const store = new DatabaseAssetStore({
    ...config,
    fetchImpl: async () => {
      calls++;
      return Response.json(calls === 1 ? null : record('assets/app.js'));
    },
  });
  assert.equal(await store.read(releaseId, 'assets/app.js'), null);
  const asset = await store.read(releaseId, 'assets/app.js');
  assert.equal(await store.read(releaseId, 'assets/app.js'), asset);
  assert.equal(calls, 2);
});

test('every active HTML read sees publish and rollback immediately', async () => {
  let active = releaseId;
  let calls = 0;
  const store = new DatabaseAssetStore({
    ...config,
    fetchImpl: async () => {
      calls++;
      return Response.json(record('index.html', active, active));
    },
  });
  assert.equal((await store.read(null, 'index.html')).releaseId, releaseId);
  active = 'ui-test-0002';
  assert.equal((await store.read(null, 'index.html')).releaseId, active);
  active = releaseId;
  assert.equal((await store.read(null, 'index.html')).releaseId, releaseId);
  assert.equal(calls, 3);
});

test('evicts old assets instead of growing beyond the entry limit', async () => {
  let calls = 0;
  const store = new DatabaseAssetStore({
    ...config,
    fetchImpl: async (_url, options) => {
      calls++;
      return Response.json(record(JSON.parse(options.body).asset_path));
    },
  });
  for (let index = 0; index < 129; index++) await store.read(releaseId, `assets/${index}.js`);
  await store.read(releaseId, 'assets/128.js');
  assert.equal(calls, 129);
  await store.read(releaseId, 'assets/0.js');
  assert.equal(calls, 130);
});

test('database failures, invalid JSON, bad digests and oversized responses fail closed', async () => {
  for (const response of [
    new Response('denied', { status: 403 }),
    new Response('not JSON'),
    Response.json({ ...record(), sha256: '0'.repeat(64) }),
    new Response(' '.repeat(3_000_001)),
  ]) {
    const store = new DatabaseAssetStore({ ...config, fetchImpl: async () => response });
    await assert.rejects(store.read(null, 'index.html'));
  }
});
