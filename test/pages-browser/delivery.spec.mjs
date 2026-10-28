// this was created by an AI agent
// Generic delivery fixtures only: no proprietary application source or production accounts.
import { test, expect } from '@playwright/test';
import { createHash } from 'node:crypto';
const releaseId = 'ui-test-pages-1';
const project = 'https://rccshonvlrgskzvrpqhy.supabase.co';
const prefix = `/_frontend/${releaseId}/`;
const html = `<!doctype html><html lang="en"><head><title>Published fixture</title><meta name="rockyforums-routing" content="base-path-v1"><link rel="stylesheet" href="${prefix}fixture.css"><link rel="modulepreload" href="${prefix}vendor.js"><script type="module" src="${prefix}entry.js"></script></head><body><main id="root"></main></body></html>`;
const value = {
  release_id: releaseId,
  path: 'index.html',
  content_type: 'text/html; charset=utf-8',
  body_base64: Buffer.from(html).toString('base64'),
  sha256: createHash('sha256').update(html).digest('hex'),
};
async function routes(page, { corrupt = false, missingScript = false } = {}) {
  const reads = [];
  await page.route(`${project}/rest/v1/rpc/read_frontend_asset`, async (route) => {
    reads.push(route.request().postDataJSON());
    await route.fulfill({
      contentType: 'application/json',
      headers: { 'Access-Control-Allow-Origin': '*' },
      body: JSON.stringify({ ...value, ...(corrupt ? { sha256: '0'.repeat(64) } : {}) }),
    });
  });
  await page.route(`${project}/functions/v1/frontend-assets/**`, async (route) => {
    const path = new URL(route.request().url()).pathname.split('/').at(-1);
    const source = {
      'vendor.js': 'export const label = "Published database fixture";',
      'entry.js':
        'import {label} from "./vendor.js";const root=document.getElementById("root");const title=document.createElement("h1");title.textContent=label;root.append(title);root.dataset.base=document.querySelector("meta[name=rockyforums-base-path]").content;root.dataset.path=location.pathname;',
      'fixture.css': '#root { color: rgb(35, 79, 119); }',
    }[path];
    await route.fulfill({
      status: !source || (missingScript && path === 'entry.js') ? 404 : 200,
      contentType: path.endsWith('.css') ? 'text/css' : 'application/javascript',
      headers: { 'Access-Control-Allow-Origin': '*' },
      body: source ?? '',
    });
  });
  return reads;
}

test('loads the current document and relative ESM graph from the database, with the project base', async ({
  page,
}) => {
  const reads = await routes(page);
  await page.goto('/Rockyforums/');
  await expect(page.getByRole('heading', { name: 'Published database fixture' })).toBeVisible();
  await expect(page.locator('#root')).toHaveAttribute('data-base', '/Rockyforums');
  await expect(page.locator('#root')).toHaveCSS('color', 'rgb(35, 79, 119)');
  await expect(page.locator('html')).toHaveAttribute('data-frontend-release', releaseId);
  expect(reads).toEqual([{ release_id: null, asset_path: 'index.html' }]);
});

test('a fresh deep link works through the Pages 404 shell without changing the URL', async ({
  page,
}) => {
  await routes(page);
  const response = await page.goto('/Rockyforums/terms/1.2');
  expect(response.status()).toBe(404);
  await expect(page.getByRole('heading', { name: 'Published database fixture' })).toBeVisible();
  await expect(page.locator('#root')).toHaveAttribute('data-path', '/Rockyforums/terms/1.2');
});

test('reload re-reads the active document; no stale bundled application is used', async ({
  page,
}) => {
  const reads = await routes(page);
  await page.goto('/Rockyforums/');
  await expect(page.getByRole('heading', { name: 'Published database fixture' })).toBeVisible();
  await page.reload();
  await expect(page.getByRole('heading', { name: 'Published database fixture' })).toBeVisible();
  expect(reads).toHaveLength(2);
});

test('invalid checksums fail closed with a usable retry rather than executing the application', async ({
  page,
}) => {
  await routes(page, { corrupt: true });
  await page.goto('/Rockyforums/');
  await expect(page.getByRole('heading', { name: 'Rockyforums could not load' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Try again' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Published database fixture' })).toHaveCount(0);
});

test('a missing module produces an honest error', async ({ page }) => {
  await routes(page, { missingScript: true });
  await page.goto('/Rockyforums/');
  await expect(page.getByRole('heading', { name: 'Rockyforums could not load' })).toBeVisible();
});
