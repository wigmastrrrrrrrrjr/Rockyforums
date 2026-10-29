// this was created by an AI agent
// READ-ONLY live smoke. Auth writes and all non-reader RPCs are actively blocked.
import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import { chromium } from '@playwright/test';
const url = new URL(process.env.PAGES_URL ?? 'https://wigmastrrrrrrrrjr.github.io/Rockyforums/');
if (url.protocol !== 'https:' || !url.hostname.endsWith('.github.io'))
  throw new Error('Expected the HTTPS Pages URL');
if (!url.pathname.endsWith('/')) url.pathname += '/';
const browser = await chromium.launch({ headless: true });
const failures = [];
const readers = new Set([
  'read_frontend_asset',
  'forum_categories',
  'forum_list_threads',
  'forum_get_thread',
  'forum_viewer_status',
  'owner_access_status',
  'has_accepted_current_terms',
]);
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  page.on('pageerror', (error) => failures.push(error.message));
  await page.route('**/*.supabase.co/**', async (route) => {
    const request = route.request();
    const path = new URL(request.url()).pathname;
    const method = request.method();
    if (
      ['GET', 'HEAD', 'OPTIONS'].includes(method) ||
      (method === 'POST' && path.startsWith('/rest/v1/rpc/') && readers.has(path.split('/').at(-1)))
    ) {
      await route.continue();
      return;
    }
    failures.push(`Blocked non-reader request: ${method} ${path}`);
    await route.abort();
  });
  await page.goto(url.href, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.getByRole('heading', { name: 'Forums', exact: true }).waitFor({ timeout: 45000 });
  await page.getByRole('heading', { name: 'Forum categories', exact: true }).waitFor();
  const release = await page.locator('html').getAttribute('data-frontend-release');
  assert.match(release, /^ui-[a-z0-9-]+$/);
  assert.equal(
    await page.locator('meta[name="rockyforums-base-path"]').getAttribute('content'),
    url.pathname.replace(/\/$/, ''),
  );
  assert.ok(
    (await page.locator('body').innerText()).includes('email verification will be required soon!'),
  );
  await mkdir('test-results', { recursive: true });
  await page.screenshot({ path: 'test-results/pages-live-desktop.png', fullPage: true });
  await page.getByRole('link', { name: 'General discussion', exact: true }).first().click();
  await page
    .getByRole('heading', { name: 'General discussion', exact: true })
    .waitFor({ timeout: 45000 });
  await page.goto(new URL('signup', url).href, { waitUntil: 'domcontentloaded' });
  await page
    .getByRole('heading', { name: 'Create an account', exact: true })
    .waitFor({ timeout: 45000 });
  await page.getByLabel('Username', { exact: true }).waitFor();
  await page.getByRole('link', { name: 'Log in', exact: true }).first().click();
  await page.waitForURL(new URL('login', url).href);
  await page.getByLabel('Email address', { exact: true }).waitFor();
  await page.getByLabel('Password', { exact: true }).waitFor();
  for (const version of ['1.2', '1.4']) {
    await page.goto(new URL(`terms/${version}`, url).href, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(
      (value) => document.querySelector('article')?.textContent.includes(`Version ${value}`),
      version,
      { timeout: 45000 },
    );
  }
  await page.goto(new URL('owner', url).href, { waitUntil: 'domcontentloaded' });
  await page
    .getByRole('heading', { name: 'Sign in required', exact: true })
    .waitFor({ timeout: 45000 });
  assert.equal(await page.locator('.owner-setup-key').count(), 0);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(url.href, { waitUntil: 'domcontentloaded' });
  await page
    .getByRole('heading', { name: 'Forum categories', exact: true })
    .waitFor({ timeout: 45000 });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  await page.screenshot({ path: 'test-results/pages-live-mobile.png', fullPage: true });
  assert.deepEqual(failures, []);
  console.log(
    JSON.stringify({
      status: 'passed',
      url: url.href,
      release,
      checks: [
        'public forum categories',
        'category navigation',
        'exact verification banner',
        'project routing',
        'preserved signup/login',
        'historical and current legal versions',
        'guest owner lock',
        'mobile forum layout',
      ],
      accountWrites: 0,
      forumWrites: 0,
    }),
  );
} finally {
  await browser.close();
}
