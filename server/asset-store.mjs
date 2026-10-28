// this was created by an AI agent

import { createHash } from 'node:crypto';

export const RELEASE_ID = /^[a-z0-9][a-z0-9-]{5,79}$/;
export const ASSET_TYPES = new Map([
  ['.js', 'text/javascript; charset=utf-8'],
  ['.css', 'text/css; charset=utf-8'],
  ['.svg', 'image/svg+xml'],
  ['.png', 'image/png'],
  ['.jpg', 'image/jpeg'],
  ['.jpeg', 'image/jpeg'],
  ['.webp', 'image/webp'],
  ['.ico', 'image/x-icon'],
  ['.woff2', 'font/woff2'],
  ['.woff', 'font/woff'],
  ['.txt', 'text/plain; charset=utf-8'],
]);

export function contentType(path) {
  if (path === 'index.html') return 'text/html; charset=utf-8';
  return ASSET_TYPES.get(path.slice(path.lastIndexOf('.')));
}

export function validAssetPath(path) {
  return (
    typeof path === 'string' &&
    path.length <= 240 &&
    /^[A-Za-z0-9][A-Za-z0-9_./-]*$/.test(path) &&
    !path.split('/').some((part) => part === '.' || part === '..' || !part) &&
    Boolean(contentType(path))
  );
}

export function decodeAsset(value, releaseId, path) {
  if (
    !value ||
    !validAssetPath(path) ||
    typeof value.release_id !== 'string' ||
    !RELEASE_ID.test(value.release_id) ||
    value.path !== path ||
    (releaseId !== null && value.release_id !== releaseId) ||
    value.content_type !== contentType(path) ||
    !/^[a-f0-9]{64}$/.test(value.sha256) ||
    typeof value.body_base64 !== 'string'
  ) {
    throw new Error('Invalid frontend asset response');
  }
  const encoded = value.body_base64.replace(/\s/g, '');
  if (
    encoded.length > 2_800_000 ||
    encoded.length % 4 !== 0 ||
    !/^[A-Za-z0-9+/]*={0,2}$/.test(encoded)
  ) {
    throw new Error('Invalid frontend asset encoding');
  }
  const body = Buffer.from(encoded, 'base64');
  if (
    body.length === 0 ||
    body.length > 2_097_152 ||
    createHash('sha256').update(body).digest('hex') !== value.sha256
  ) {
    throw new Error('Frontend asset checksum mismatch');
  }
  return {
    releaseId: value.release_id,
    path,
    contentType: value.content_type,
    sha256: value.sha256,
    body,
  };
}

async function readBoundedJson(response) {
  const chunks = [];
  let size = 0;
  for await (const chunk of response.body) {
    size += chunk.length;
    if (size > 3_000_000) throw new Error('Frontend asset response is too large');
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

export class DatabaseAssetStore {
  #cache = new Map();
  #cacheBytes = 0;

  constructor({ supabaseUrl, publishableKey, fetchImpl = fetch }) {
    if (
      !/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(supabaseUrl) ||
      !publishableKey?.startsWith('sb_publishable_')
    ) {
      throw new Error('Configure the dedicated Supabase URL and public publishable key.');
    }
    this.endpoint = `${supabaseUrl}/rest/v1/rpc/read_frontend_asset`;
    this.publishableKey = publishableKey;
    this.fetch = fetchImpl;
  }

  async read(releaseId, path) {
    if ((releaseId !== null && !RELEASE_ID.test(releaseId)) || !validAssetPath(path)) return null;
    const key = releaseId === null ? null : `${releaseId}/${path}`;
    if (key && this.#cache.has(key)) return this.#cache.get(key);

    const response = await this.fetch(this.endpoint, {
      method: 'POST',
      headers: { apikey: this.publishableKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({ release_id: releaseId, asset_path: path }),
      signal: AbortSignal.timeout(15_000),
      redirect: 'error',
    });
    if (!response.ok) throw new Error(`Frontend database request failed (${response.status})`);
    const value = await readBoundedJson(response);
    if (value === null) return null;
    const asset = decodeAsset(value, releaseId, path);

    // Immutable version URLs can be cached. Never cache the active-document lookup:
    // a publish or rollback must be visible on the next page load, without a deploy.
    if (key) {
      while (this.#cache.size >= 128 || this.#cacheBytes + asset.body.length > 32_000_000) {
        const oldest = this.#cache.keys().next().value;
        this.#cacheBytes -= this.#cache.get(oldest).body.length;
        this.#cache.delete(oldest);
      }
      this.#cache.set(key, asset);
      this.#cacheBytes += asset.body.length;
    }
    return asset;
  }
}
