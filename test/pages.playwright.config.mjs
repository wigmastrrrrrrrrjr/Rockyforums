// this was created by an AI agent
import { defineConfig } from '@playwright/test';
import { fileURLToPath } from 'node:url';
export default defineConfig({
  testDir: './pages-browser',
  workers: 1,
  forbidOnly: true,
  timeout: 30000,
  use: {
    baseURL: 'http://127.0.0.1:4177',
    headless: true,
    launchOptions: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH
      ? {
          executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH,
          args: ['--no-sandbox', '--disable-dev-shm-usage'],
        }
      : {},
  },
  webServer: {
    command: 'node scripts/serve-pages-test.mjs',
    cwd: fileURLToPath(new URL('../', import.meta.url)),
    url: 'http://127.0.0.1:4177/Rockyforums/',
    reuseExistingServer: false,
  },
});
