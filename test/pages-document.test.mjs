// this was created by an AI agent
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { test } from 'node:test';
import {
  decodeDocument,
  readPublishedDocument,
  validateSiteConfig,
} from '../server/pages/read-document.mjs';
const config = {
  supabaseUrl: 'https://dedicated-project.supabase.co',
  publishableKey: 'sb_publishable_fixture',
  basePath: '/Rockyforums/',
};
function record(body = '<!doctype html><title>Fixture</title>') {
  return {
    release_id: 'ui-test-0001',
    path: 'index.html',
    content_type: 'text/html; charset=utf-8',
    body_base64: Buffer.from(body).toString('base64'),
    sha256: createHash('sha256').update(body).digest('hex'),
  };
}
test('Pages configuration accepts public HTTPS identity and safe project/root mount paths', () => {
  assert.equal(validateSiteConfig(config), config);
  validateSiteConfig({ ...config, basePath: '/' });
  for (const change of [
    { publishableKey: 'sb_secret_no' },
    { supabaseUrl: 'https://evil.example' },
    { basePath: '/../../' },
    { basePath: '/Rockyforums/"' },
  ])
    assert.throws(() => validateSiteConfig({ ...config, ...change }));
});
test('document reader verifies published bytes and rejects changed metadata/encoding/digests', async () => {
  assert.equal((await decodeDocument(record())).releaseId, 'ui-test-0001');
  for (const change of [
    { sha256: '0'.repeat(64) },
    { release_id: 123456 },
    { path: 'other.html' },
    { content_type: 'text/plain' },
    { body_base64: '!!!!' },
  ])
    await assert.rejects(decodeDocument({ ...record(), ...change }));
});
test('active HTML is fetched with only the public key and explicitly without a cache', async () => {
  const calls = [];
  await readPublishedDocument(config, async (url, options) => {
    calls.push({ url, options });
    return Response.json(record());
  });
  assert.equal(calls[0].options.headers.apikey, config.publishableKey);
  assert.equal(calls[0].options.headers.Authorization, undefined);
  assert.equal(calls[0].options.cache, 'no-store');
  assert.equal(calls[0].options.redirect, 'error');
  assert.deepEqual(JSON.parse(calls[0].options.body), {
    release_id: null,
    asset_path: 'index.html',
  });
});
test('errors and oversized document responses fail closed', async () => {
  for (const response of [
    new Response('private provider message', { status: 403 }),
    new Response(' '.repeat(3000001)),
    Response.json(null),
  ]) {
    await assert.rejects(readPublishedDocument(config, async () => response));
  }
});
