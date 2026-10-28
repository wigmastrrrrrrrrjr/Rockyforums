// this was created by an AI agent

const releasePattern = /^[a-z0-9][a-z0-9-]{5,79}$/;

export function validateSiteConfig(config) {
  if (
    !/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(config.supabaseUrl ?? '') ||
    !config.publishableKey?.startsWith('sb_publishable_') ||
    !/^\/(?:[A-Za-z0-9_-]+\/)*$/.test(config.basePath ?? '')
  ) {
    throw new Error('Invalid public delivery configuration');
  }
  return config;
}

export async function decodeDocument(value) {
  if (
    !value ||
    typeof value.release_id !== 'string' ||
    !releasePattern.test(value.release_id) ||
    value.path !== 'index.html' ||
    value.content_type !== 'text/html; charset=utf-8' ||
    !/^[a-f0-9]{64}$/.test(value.sha256) ||
    typeof value.body_base64 !== 'string'
  )
    throw new Error('Invalid published document');
  const encoded = value.body_base64.replace(/\s/g, '');
  if (encoded.length > 2_800_000 || encoded.length % 4 || !/^[A-Za-z0-9+/]*={0,2}$/.test(encoded)) {
    throw new Error('Invalid published document encoding');
  }
  const bytes = Uint8Array.from(atob(encoded), (character) => character.charCodeAt(0));
  if (!bytes.length || bytes.length > 2_097_152) throw new Error('Invalid published document size');
  const hash = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
  if (hash !== value.sha256) throw new Error('Published document checksum mismatch');
  return {
    releaseId: value.release_id,
    html: new TextDecoder('utf-8', { fatal: true }).decode(bytes),
  };
}

export async function readPublishedDocument(config, fetchImpl = fetch) {
  validateSiteConfig(config);
  const response = await fetchImpl(`${config.supabaseUrl}/rest/v1/rpc/read_frontend_asset`, {
    method: 'POST',
    headers: { apikey: config.publishableKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ release_id: null, asset_path: 'index.html' }),
    cache: 'no-store',
    redirect: 'error',
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) throw new Error('Published document unavailable');
  const reader = response.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 3_000_000) throw new Error('Published document response too large');
      chunks.push(value);
    }
  } finally {
    await reader.cancel();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return decodeDocument(JSON.parse(new TextDecoder().decode(bytes)));
}

export function deliveryPolicy(config) {
  validateSiteConfig(config);
  const source = `${config.supabaseUrl}/functions/v1/frontend-assets/`;
  return [
    "default-src 'self'",
    `script-src 'self' ${source}`,
    `style-src 'self' ${source}`,
    `img-src 'self' data: ${source}`,
    `font-src 'self' ${source}`,
    `connect-src 'self' ${config.supabaseUrl}`,
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-src 'none'",
  ].join('; ');
}
