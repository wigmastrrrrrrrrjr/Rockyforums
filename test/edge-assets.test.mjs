// this was created by an AI agent
import assert from 'node:assert/strict';
import { createHash, webcrypto } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { runInNewContext } from 'node:vm';
const source = readFileSync(
  new URL('../supabase/functions/frontend-assets/index.js', import.meta.url),
  'utf8',
);
const path =
  'https://dedicated-project.supabase.co/functions/v1/frontend-assets/_frontend/ui-test-0001/assets/app.js';
function gateway({ corrupt = false, unavailable = false } = {}) {
  let handler;
  const calls = [];
  const body = 'export const fixture = true;';
  runInNewContext(source, {
    Deno: {
      env: {
        get: (key) =>
          key === 'SUPABASE_URL' ? 'https://dedicated-project.supabase.co' : 'anon-key-fixture',
      },
      serve: (value) => {
        handler = value;
      },
    },
    URL,
    Response,
    Uint8Array,
    TextDecoder,
    AbortSignal,
    atob,
    crypto: webcrypto,
    console: { error() {} },
    fetch: async (url, options) => {
      calls.push({ url, options });
      if (unavailable) return new Response('private provider detail', { status: 500 });
      return Response.json({
        release_id: 'ui-test-0001',
        path: 'assets/app.js',
        content_type: 'text/javascript; charset=utf-8',
        body_base64: Buffer.from(body).toString('base64'),
        sha256: corrupt ? '0'.repeat(64) : createHash('sha256').update(body).digest('hex'),
      });
    },
  });
  return { request: (url = path, options) => handler(new Request(url, options)), calls, body };
}
test('Edge gateway serves checked public JavaScript with CORS, MIME, immutable cache and no admin credential', async () => {
  const site = gateway();
  const result = await site.request();
  assert.equal(result.status, 200);
  assert.equal(await result.text(), site.body);
  assert.equal(result.headers.get('access-control-allow-origin'), '*');
  assert.equal(result.headers.get('content-type'), 'application/javascript; charset=utf-8');
  assert.match(result.headers.get('cache-control'), /immutable/);
  assert.equal(site.calls[0].options.headers.apikey, 'anon-key-fixture');
  assert.deepEqual(JSON.parse(site.calls[0].options.body), {
    release_id: 'ui-test-0001',
    asset_path: 'assets/app.js',
  });
});
test('checked versioned assets are cached; HEAD and conditional GET preserve the representation', async () => {
  const site = gateway();
  const first = await site.request();
  const head = await site.request(path, { method: 'HEAD' });
  assert.equal(head.status, 200);
  assert.equal(await head.text(), '');
  const conditional = await site.request(path, {
    headers: { 'If-None-Match': first.headers.get('etag') },
  });
  assert.equal(conditional.status, 304);
  assert.equal(site.calls.length, 1);
});
test('Edge gateway rejects HTML/source/invalid paths and all visitor writes', async () => {
  const site = gateway();
  for (const suffix of ['index.html', 'app.js.map', '../secret', '.env']) {
    assert.equal((await site.request(path.replace('assets/app.js', suffix))).status, 404);
  }
  assert.equal((await site.request(path, { method: 'POST' })).status, 405);
  assert.equal(site.calls.length, 0);
});
test('Edge errors never expose response bodies or damaged assets', async () => {
  for (const options of [{ corrupt: true }, { unavailable: true }]) {
    const response = await gateway(options).request();
    assert.equal(response.status, 503);
    assert.doesNotMatch(await response.text(), /private provider|fixture|sha256/);
  }
});
