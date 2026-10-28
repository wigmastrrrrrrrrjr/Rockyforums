// this was created by an AI agent

import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { once } from 'node:events';
import { request as httpRequest } from 'node:http';
import { test } from 'node:test';
import { gunzipSync } from 'node:zlib';
import { createWebsiteServer } from '../server/http.mjs';

const releaseId = 'ui-test-0001';
const assetPath = `/_frontend/${releaseId}/assets/app.js`;
function asset(body = '<!doctype html><title>Current UI</title>') {
  return {
    releaseId,
    path: 'index.html',
    contentType: 'text/html; charset=utf-8',
    body: Buffer.from(body),
    sha256: createHash('sha256').update(body).digest('hex'),
  };
}
async function website(t, options = {}) {
  const calls = [];
  const errors = [];
  const store = options.store ?? {
    async read(release, path) {
      calls.push([release, path]);
      return path === 'index.html'
        ? asset()
        : {
            ...asset('export const compiled = true;'),
            contentType: 'text/javascript; charset=utf-8',
          };
    },
  };
  const server = createWebsiteServer({
    store,
    supabaseUrl: 'https://dedicated-project.supabase.co',
    logger: { error: (...args) => errors.push(args) },
    ...options,
  });
  server.listen(0, '0.0.0.0');
  await once(server, 'listening');
  t.after(() => new Promise((resolve) => server.close(resolve)));
  function request(path, method = 'GET', headers = {}) {
    return new Promise((resolve, reject) => {
      const req = httpRequest(
        { hostname: '127.0.0.1', port: server.address().port, path, method, headers, agent: false },
        (res) => {
          const parts = [];
          res.on('data', (chunk) => parts.push(chunk));
          res.on('end', () =>
            resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(parts) }),
          );
          res.on('error', reject);
        },
      );
      req.on('error', reject);
      req.end();
    });
  }
  return { request, calls, errors };
}

test('serves active database HTML for root and SPA navigation, always without caching', async (t) => {
  const { request, calls } = await website(t);
  for (const path of ['/', '/signup', '/login', '/terms/1.2']) {
    const result = await request(path, 'GET', { Accept: 'text/html', 'If-None-Match': 'anything' });
    assert.equal(result.status, 200);
    assert.equal(result.headers['cache-control'], 'no-store');
    assert.equal(result.headers['content-type'], 'text/html; charset=utf-8');
    assert.match(result.body.toString(), /Current UI/);
  }
  assert.deepEqual(calls, Array(4).fill([null, 'index.html']));
});

test('versioned assets use immutable caching, MIME and representation-specific ETags', async (t) => {
  const { request } = await website(t);
  const raw = await request(assetPath);
  assert.equal(raw.status, 200);
  assert.match(raw.headers['cache-control'], /31536000, immutable/);
  assert.equal(raw.headers['content-type'], 'text/javascript; charset=utf-8');
  const gzipped = await request(assetPath, 'GET', { 'Accept-Encoding': 'gzip' });
  assert.equal(gzipped.headers['content-encoding'], 'gzip');
  assert.equal(gzipped.headers.vary, 'Accept-Encoding');
  assert.deepEqual(gunzipSync(gzipped.body), raw.body);
  assert.notEqual(gzipped.headers.etag, raw.headers.etag);
  const notModified = await request(assetPath, 'GET', { 'If-None-Match': raw.headers.etag });
  assert.equal(notModified.status, 304);
  assert.equal(notModified.body.length, 0);
});

test('HEAD has the same headers and content length but no body', async (t) => {
  const { request } = await website(t);
  const get = await request(assetPath);
  const head = await request(assetPath, 'HEAD');
  assert.equal(head.status, 200);
  assert.equal(head.headers['content-length'], get.headers['content-length']);
  assert.equal(head.headers.etag, get.headers.etag);
  assert.equal(head.body.length, 0);
});

test('encoding negotiation honors explicit gzip refusal and invalid qualities', async (t) => {
  const { request } = await website(t);
  for (const encoding of ['gzip;q=0', 'gzip;q=0, *;q=1', 'gzip;q=garbage', 'br']) {
    const result = await request(assetPath, 'GET', { 'Accept-Encoding': encoding });
    assert.equal(result.headers['content-encoding'], undefined, encoding);
  }
  const result = await request(assetPath, 'GET', { 'Accept-Encoding': 'br, gzip;q=0.5' });
  assert.equal(result.headers['content-encoding'], 'gzip');
});

test('rejects writes, malformed asset URLs, source requests and non-HTML unknown paths', async (t) => {
  const { request, calls } = await website(t);
  for (const method of ['POST', 'PUT', 'DELETE', 'OPTIONS']) {
    const result = await request('/', method);
    assert.equal(result.status, 405);
    assert.equal(result.headers.allow, 'GET, HEAD');
  }
  for (const path of [
    '/_frontend/INVALID/app.js',
    '/_frontend/ui-test-0001/index.html',
    '/_frontend/ui-test-0001/app.js.map',
    '/_frontend/ui-test-0001/assets//app.js',
    '/src/app.js',
    '/frontend/src/main.tsx',
    '/node_modules/react',
    '/.git/config',
    '/.env',
    '/unknown.js',
  ]) {
    const result = await request(path);
    assert.equal(result.status, 404, path);
  }
  for (const path of ['/frontend/src/main.tsx', '/src/app.js', '/.env.local', '/.git/config']) {
    assert.equal((await request(path, 'GET', { Accept: 'text/html' })).status, 404, path);
  }
  assert.equal(calls.length, 0);
});

test('health is independent of the database, readiness is not', async (t) => {
  const { request, calls } = await website(t);
  assert.equal((await request('/healthz')).status, 200);
  assert.equal(calls.length, 0);
  const result = await request('/readyz');
  assert.equal(result.status, 200);
  assert.equal(result.body.toString(), 'ready');
  assert.equal(calls.length, 1);
});

test('missing releases/assets return no-store errors, without a bundled fallback', async (t) => {
  const { request } = await website(t, {
    store: {
      async read() {
        return null;
      },
    },
  });
  assert.equal((await request('/')).status, 503);
  const missing = await request(assetPath);
  assert.equal(missing.status, 404);
  assert.equal(missing.headers['cache-control'], 'no-store');
  assert.equal((await request('/readyz')).status, 503);
});

test('database errors never expose stack traces, keys, responses or asset bodies', async (t) => {
  const { request, errors } = await website(t, {
    store: {
      async read() {
        throw new Error('private-database-response-and-key');
      },
    },
  });
  const result = await request('/');
  assert.equal(result.status, 503);
  assert.doesNotMatch(result.body.toString(), /private-database|Error|stack/);
  assert.deepEqual(errors, [['Frontend delivery failed:', 'Error']]);
});

test('security headers forbid embedding by default; preview embedding is an explicit opt-in', async (t) => {
  const normal = await website(t);
  const response = await normal.request('/');
  assert.equal(response.headers['x-content-type-options'], 'nosniff');
  assert.equal(response.headers['x-frame-options'], 'DENY');
  assert.equal(response.headers['referrer-policy'], 'strict-origin-when-cross-origin');
  assert.match(response.headers['content-security-policy'], /frame-ancestors 'none'/);
  assert.match(response.headers['content-security-policy'], /object-src 'none'/);
  assert.match(
    response.headers['content-security-policy'],
    /connect-src 'self' https:\/\/dedicated-project.supabase.co/,
  );
  assert.doesNotMatch(response.headers['content-security-policy'], /unsafe-inline|unsafe-eval/);
  const preview = await website(t, { allowPreviewEmbedding: true });
  assert.doesNotMatch(
    (await preview.request('/')).headers['content-security-policy'],
    /frame-ancestors/,
  );
});
