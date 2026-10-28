// this was created by an AI agent

import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { test } from 'node:test';
import { parseReleasePackage } from '../scripts/release-manifest.mjs';

function manifest() {
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
const parse = (bundle) => parseReleasePackage(Buffer.from(JSON.stringify(bundle)));

test('validates a complete immutable release without changing it', () => {
  const fixture = manifest();
  assert.deepEqual(parse(fixture), fixture);
});

test('rejects unsupported manifest shape, format, release ID and missing index', () => {
  const fixture = manifest();
  for (const value of [
    null,
    [],
    {},
    { ...fixture, format: 'unknown' },
    { ...fixture, release_id: 123456 },
    { ...fixture, release_id: '../bad' },
    { ...fixture, assets: [] },
    { ...fixture, assets: [null] },
    { ...fixture, assets: [{ ...fixture.assets[0], path: 'other.html' }] },
  ]) {
    assert.throws(() => parse(value));
  }
});

test('rejects duplicates, too many assets, traversal, source maps and wrong digests', () => {
  const fixture = manifest();
  const entry = fixture.assets[0];
  for (const assets of [
    [entry, entry],
    Array(65).fill(entry),
    [{ ...entry, path: '../index.html' }],
    [{ ...entry, path: 'app.js.map' }],
    [{ ...entry, sha256: '0'.repeat(64) }],
  ]) {
    assert.throws(() => parse({ ...fixture, assets }));
  }
});

test('bounds the encoded package before parsing JSON', () => {
  assert.throws(() => parseReleasePackage(Buffer.alloc(24_000_001)));
  assert.throws(() => parseReleasePackage('not a buffer'));
  assert.throws(() => parseReleasePackage(Buffer.from('not JSON')));
});
