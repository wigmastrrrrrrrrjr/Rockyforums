// this was created by an AI agent

import { createServer } from 'node:http';
import { gzipSync } from 'node:zlib';
import { RELEASE_ID, validAssetPath } from './asset-store.mjs';

function acceptsGzip(header = '') {
  const encodings = new Map(
    String(header)
      .split(',')
      .map((part) => {
        const [name, ...parameters] = part.trim().split(';');
        const q = parameters.find((value) => value.trim().startsWith('q='));
        const quality = q ? Number(q.trim().slice(2)) : 1;
        return [
          name.trim().toLowerCase(),
          Number.isFinite(quality) && quality >= 0 && quality <= 1 ? quality : 0,
        ];
      }),
  );
  return (encodings.get('gzip') ?? encodings.get('*') ?? 0) > 0;
}

export function createWebsiteServer({
  store,
  supabaseUrl,
  allowPreviewEmbedding = false,
  logger = console,
}) {
  const csp = [
    "default-src 'self'",
    "script-src 'self'",
    "style-src 'self'",
    "font-src 'self'",
    "img-src 'self' data:",
    `connect-src 'self' ${supabaseUrl}`,
    "base-uri 'self'",
    "object-src 'none'",
    "form-action 'self'",
    ...(allowPreviewEmbedding ? [] : ["frame-ancestors 'none'"]),
  ].join('; ');

  return createServer(async (request, response) => {
    response.setHeader('X-Content-Type-Options', 'nosniff');
    response.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
    response.setHeader(
      'Permissions-Policy',
      'camera=(), microphone=(), geolocation=(), payment=()',
    );
    response.setHeader('Content-Security-Policy', csp);
    if (!allowPreviewEmbedding) response.setHeader('X-Frame-Options', 'DENY');

    function text(status, message) {
      response.writeHead(status, {
        'Content-Type': 'text/plain; charset=utf-8',
        'Cache-Control': 'no-store',
      });
      response.end(request.method === 'HEAD' ? undefined : message);
    }

    if (request.method !== 'GET' && request.method !== 'HEAD') {
      response.setHeader('Allow', 'GET, HEAD');
      return text(405, 'Method not allowed.');
    }

    try {
      const url = new URL(request.url, 'http://gateway.invalid');
      if (url.pathname === '/healthz') return text(200, 'ok');
      const versioned = url.pathname.startsWith('/_frontend/');
      let releaseId = null;
      let path = 'index.html';
      if (versioned) {
        const parts = url.pathname.slice('/_frontend/'.length).split('/');
        releaseId = parts.shift();
        path = parts.join('/');
        if (!RELEASE_ID.test(releaseId) || !validAssetPath(path) || path === 'index.html') {
          return text(404, 'Asset not found.');
        }
      } else if (
        /^\/(?:frontend|src|node_modules)(?:\/|$)/.test(url.pathname) ||
        url.pathname.startsWith('/.') ||
        (!String(request.headers.accept ?? '').includes('text/html') &&
          url.pathname !== '/' &&
          url.pathname !== '/readyz')
      ) {
        return text(404, 'Not found.');
      }

      const asset = await store.read(releaseId, path);
      if (!asset)
        return text(
          versioned ? 404 : 503,
          versioned ? 'Asset not found.' : 'No frontend release is published.',
        );
      if (url.pathname === '/readyz') return text(200, 'ready');

      const gzip = acceptsGzip(request.headers['accept-encoding']);
      const etag = `"${asset.sha256}${gzip ? '-gzip' : ''}"`;
      response.setHeader('Content-Type', asset.contentType);
      response.setHeader(
        'Cache-Control',
        versioned ? 'public, max-age=31536000, immutable' : 'no-store',
      );
      response.setHeader('ETag', etag);
      response.setHeader('Vary', 'Accept-Encoding');
      if (
        versioned &&
        request.headers['if-none-match']
          ?.split(',')
          .map((value) => value.trim())
          .includes(etag)
      ) {
        response.writeHead(304);
        return response.end();
      }
      const body = gzip ? gzipSync(asset.body) : asset.body;
      if (gzip) response.setHeader('Content-Encoding', 'gzip');
      response.setHeader('Content-Length', body.length);
      response.writeHead(200);
      response.end(request.method === 'HEAD' ? undefined : body);
    } catch (error) {
      // Do not expose database responses, asset bodies, keys, or stack traces to visitors.
      logger.error('Frontend delivery failed:', error.name);
      text(503, 'The site is temporarily unavailable. Please try again shortly.');
    }
  });
}
