import { defineConfig } from '@playwright/test';

const PORT = 4173;

export default defineConfig({
  testDir: './e2e',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: `http://127.0.0.1:${PORT}`,
    headless: true,
    trace: 'off',
    screenshot: 'only-on-failure',
    video: 'off',
    viewport: { width: 1440, height: 900 },
    actionTimeout: 15000,
    navigationTimeout: 60000,
  },
  webServer: {
    command: `python3 -m http.server ${PORT} --directory build/web`,
    url: `http://127.0.0.1:${PORT}`,
    timeout: 120000,
    reuseExistingServer: true,
  },
  timeout: 120000,
});
