// this was created by an AI agent
// READ-ONLY live smoke check. Never signs up, logs in, publishes, or changes accounts.
import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import { chromium } from '@playwright/test';
const url = new URL(process.env.PAGES_URL ?? 'https://wigmastrrrrrrrrjr.github.io/Rockyforums/');
if (url.protocol !== 'https:' || !url.hostname.endsWith('.github.io'))
  throw new Error('Expected the HTTPS Pages URL');
if (!url.pathname.endsWith('/')) url.pathname += '/';
const browser = await chromium.launch({ headless: true });
const failures = [];
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  page.on('pageerror', (error) => failures.push(error.message));
  await page.goto(url.href, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page
    .getByRole('heading', { name: 'Create an account', exact: true })
    .waitFor({ timeout: 45000 });
  await page.getByLabel('Username', { exact: true }).waitFor();
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
  await page.getByRole('link', { name: 'Log in', exact: true }).first().click();
  await page.waitForURL(new URL('login', url).href);
  await page.getByLabel('Email address', { exact: true }).waitFor();
  await page.getByLabel('Password', { exact: true }).waitFor();
  await page.goto(new URL('terms/1.2', url).href, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(
    () => document.querySelector('article')?.textContent.includes('Version 1.2'),
    undefined,
    { timeout: 45000 },
  );
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(new URL('signup', url).href, { waitUntil: 'domcontentloaded' });
  await page.getByLabel('Username', { exact: true }).waitFor({ timeout: 45000 });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  await page.screenshot({ path: 'test-results/pages-live-mobile.png', fullPage: true });
  assert.deepEqual(failures, []);
  console.log(
    JSON.stringify({
      status: 'passed',
      url: url.href,
      release,
      checks: [
        'desktop signup',
        'exact verification banner',
        'project routing',
        'login navigation',
        'fresh historical legal deep link',
        'mobile layout',
      ],
      accountWrites: 0,
    }),
  );
} finally {
  await browser.close();
}
