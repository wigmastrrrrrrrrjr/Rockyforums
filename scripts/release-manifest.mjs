// this was created by an AI agent

import { decodeAsset, RELEASE_ID, validAssetPath } from '../server/asset-store.mjs';

// Shared by the local packager and publisher; this module never makes network requests.
export function parseReleasePackage(source) {
  if (!Buffer.isBuffer(source) || source.length > 24_000_000) {
    throw new Error('Release package is too large or is not a byte buffer.');
  }
  const bundle = JSON.parse(source.toString('utf8'));
  if (
    !bundle ||
    bundle.format !== 'rockyforums.frontend.release.v1' ||
    typeof bundle.release_id !== 'string' ||
    !RELEASE_ID.test(bundle.release_id) ||
    !Array.isArray(bundle.assets) ||
    !bundle.assets.length ||
    bundle.assets.length > 64
  ) {
    throw new Error('Invalid release package.');
  }
  const paths = new Set();
  let total = 0;
  for (const asset of bundle.assets) {
    if (!asset || !validAssetPath(asset.path) || paths.has(asset.path)) {
      throw new Error('Invalid or duplicate asset path.');
    }
    paths.add(asset.path);
    total += decodeAsset({ ...asset, release_id: bundle.release_id }, bundle.release_id, asset.path)
      .body.length;
  }
  if (!paths.has('index.html') || total > 16_777_216) {
    throw new Error('Invalid frontend release size or index.');
  }
  return bundle;
}
