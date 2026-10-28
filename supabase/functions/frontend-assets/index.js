// this was created by an AI agent
// Public, read-only compiled-asset delivery. Never use an administrator key here.
const project = Deno.env.get('SUPABASE_URL');
const apiKey = Deno.env.get('SUPABASE_ANON_KEY');
const releasePattern = /^[a-z0-9][a-z0-9-]{5,79}$/;
const types = new Map([
  ['js', 'text/javascript; charset=utf-8'],
  ['css', 'text/css; charset=utf-8'],
  ['svg', 'image/svg+xml'],
  ['png', 'image/png'],
  ['jpg', 'image/jpeg'],
  ['jpeg', 'image/jpeg'],
  ['webp', 'image/webp'],
  ['ico', 'image/x-icon'],
  ['woff2', 'font/woff2'],
  ['woff', 'font/woff'],
  ['txt', 'text/plain; charset=utf-8'],
]);
const cache = new Map();
let cacheBytes = 0;
const commonHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
  'Access-Control-Allow-Headers': 'if-none-match',
  'Access-Control-Expose-Headers': 'ETag, X-Frontend-Release',
  'Cross-Origin-Resource-Policy': 'cross-origin',
  'X-Content-Type-Options': 'nosniff',
  'Content-Security-Policy': "default-src 'none'; sandbox",
};
function message(status, text, method) {
  return new Response(method === 'HEAD' ? null : text, {
    status,
    headers: {
      ...commonHeaders,
      'Content-Type': 'text/plain; charset=utf-8',
      'Cache-Control': 'no-store',
    },
  });
}
async function readAsset(releaseId, path, expectedType) {
  const key = `${releaseId}/${path}`;
  if (cache.has(key)) return cache.get(key);
  const response = await fetch(`${project}/rest/v1/rpc/read_frontend_asset`, {
    method: 'POST',
    headers: {
      apikey: apiKey,
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ release_id: releaseId, asset_path: path }),
    signal: AbortSignal.timeout(15000),
    redirect: 'error',
  });
  if (!response.ok) throw new Error('Asset reader unavailable');
  let size = 0;
  const chunks = [];
  for await (const chunk of response.body) {
    size += chunk.length;
    if (size > 3000000) throw new Error('Asset reader response too large');
    chunks.push(chunk);
  }
  const json = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    json.set(chunk, offset);
    offset += chunk.length;
  }
  const value = JSON.parse(new TextDecoder().decode(json));
  if (value === null) return null;
  if (
    value.release_id !== releaseId ||
    value.path !== path ||
    value.content_type !== expectedType ||
    !/^[a-f0-9]{64}$/.test(value.sha256) ||
    typeof value.body_base64 !== 'string'
  )
    throw new Error('Invalid asset metadata');
  const encoded = value.body_base64.replace(/\s/g, '');
  if (encoded.length > 2800000 || encoded.length % 4 || !/^[A-Za-z0-9+/]*={0,2}$/.test(encoded))
    throw new Error('Invalid asset encoding');
  const body = Uint8Array.from(atob(encoded), (char) => char.charCodeAt(0));
  if (!body.length || body.length > 2097152) throw new Error('Invalid asset size');
  const hash = [...new Uint8Array(await crypto.subtle.digest('SHA-256', body))]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
  if (hash !== value.sha256) throw new Error('Asset checksum mismatch');
  const asset = { body, sha256: hash };
  while (cache.size >= 128 || cacheBytes + body.length > 32000000) {
    const oldest = cache.keys().next().value;
    cacheBytes -= cache.get(oldest).body.length;
    cache.delete(oldest);
  }
  cache.set(key, asset);
  cacheBytes += body.length;
  return asset;
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS')
    return new Response(null, { status: 204, headers: commonHeaders });
  if (!['GET', 'HEAD'].includes(request.method)) {
    const response = message(405, 'Method not allowed.', request.method);
    response.headers.set('Allow', 'GET, HEAD, OPTIONS');
    return response;
  }
  try {
    const url = new URL(request.url);
    const marker = '/_frontend/';
    const position = url.pathname.indexOf(marker);
    if (position < 0) return message(404, 'Asset not found.', request.method);
    const parts = url.pathname.slice(position + marker.length).split('/');
    const releaseId = parts.shift();
    const path = parts.join('/');
    const expectedType = types.get(path.slice(path.lastIndexOf('.') + 1));
    if (
      !releasePattern.test(releaseId) ||
      !expectedType ||
      path.length > 240 ||
      !/^[A-Za-z0-9][A-Za-z0-9_./-]*$/.test(path) ||
      path.split('/').some((part) => !part || part === '.' || part === '..')
    ) {
      return message(404, 'Asset not found.', request.method);
    }
    const asset = await readAsset(releaseId, path, expectedType);
    if (!asset) return message(404, 'Asset not found.', request.method);
    const headers = {
      ...commonHeaders,
      'Content-Type': expectedType.startsWith('text/javascript')
        ? 'application/javascript; charset=utf-8'
        : expectedType,
      'Cache-Control': 'public, max-age=31536000, immutable',
      ETag: `"${asset.sha256}"`,
      'X-Frontend-Release': releaseId,
    };
    if (
      request.headers
        .get('if-none-match')
        ?.split(',')
        .map((tag) => tag.trim())
        .includes(headers.ETag)
    ) {
      return new Response(null, { status: 304, headers });
    }
    headers['Content-Length'] = String(asset.body.length);
    return new Response(request.method === 'HEAD' ? null : asset.body, { status: 200, headers });
  } catch (error) {
    console.error('Published asset delivery failed:', error.name);
    return message(503, 'The site is temporarily unavailable.', request.method);
  }
});
