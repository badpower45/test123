import { test, expect, Browser, Page } from '@playwright/test';

type Credentials = {
  id: string;
  pin: string;
};

type SessionState = {
  isLoggedIn: boolean;
  role: string | null;
  employeeId: string | null;
  branch: string | null;
  fullName: string | null;
};

type CandidateLoginResult = {
  credentials: Credentials;
  session: SessionState;
};

const APP_ENTRY = '/?flutter_semantics_enabled=true';
const EMPLOYEE_FIELD = { x: 720, y: 460 };
const EMPLOYEE_HINT = 'معرف الموظف';
const PIN_HINT = 'الرقم السري';

const APP_BOOT_DELAY_MS = 5000;
const LOGIN_SETTLE_DELAY_MS = 8000;

const OWNER_CREDENTIALS: Credentials = { id: 'OWNER001', pin: '1234' };
const MANAGER_CANDIDATES: Credentials[] = [
  { id: 'MGR001', pin: '1111' },
  { id: 'MGR_MAADI', pin: '8888' },
  { id: 'EMP004', pin: '9999' },
];
const STAFF_CANDIDATES: Credentials[] = [
  { id: 'EMP001', pin: '2222' },
  { id: 'EMP001', pin: '1234' },
  { id: 'EMP_MAADI', pin: '5555' },
  { id: 'EMP005', pin: '5555' },
  { id: 'EMP002', pin: '3333' },
  { id: 'EMP003', pin: '4444' },
];

async function openApp(page: Page): Promise<void> {
  await page.goto(APP_ENTRY);
  await page.locator('flt-glass-pane').first().waitFor({ state: 'attached', timeout: 45000 });
  await page.waitForTimeout(APP_BOOT_DELAY_MS);
}

async function focusEmployeeField(page: Page): Promise<void> {
  const started = Date.now();
  let fieldState: { placeholder: string | null; activeTag: string | null } | null = null;

  while (Date.now() - started < 25000) {
    await page.mouse.click(EMPLOYEE_FIELD.x, EMPLOYEE_FIELD.y);
    await page.waitForTimeout(260);

    fieldState = await page.evaluate(() => {
      const input = document.querySelector('input.flt-text-editing') as HTMLInputElement | null;
      if (!input) {
        return null;
      }

      return {
        placeholder: input.getAttribute('placeholder'),
        activeTag: document.activeElement?.tagName ?? null,
      };
    });

    if (fieldState?.placeholder === PIN_HINT) {
      await page.keyboard.down('Shift');
      await page.keyboard.press('Tab');
      await page.keyboard.up('Shift');
      await page.waitForTimeout(180);

      fieldState = await page.evaluate(() => {
        const input = document.querySelector('input.flt-text-editing') as HTMLInputElement | null;
        if (!input) {
          return null;
        }

        return {
          placeholder: input.getAttribute('placeholder'),
          activeTag: document.activeElement?.tagName ?? null,
        };
      });
    }

    if (fieldState?.placeholder === EMPLOYEE_HINT) {
      break;
    }

    await page.waitForTimeout(250);
  }

  expect(fieldState).not.toBeNull();
  expect(fieldState?.placeholder).toBe(EMPLOYEE_HINT);
  expect(fieldState?.activeTag).toBe('INPUT');
}

async function loginWithKeyboard(page: Page, credentials: Credentials): Promise<SessionState> {
  await focusEmployeeField(page);
  await page.keyboard.type(credentials.id, { delay: 20 });
  await page.keyboard.press('Tab');
  await page.waitForTimeout(120);
  await page.keyboard.type(credentials.pin, { delay: 20 });
  await page.keyboard.press('Enter');

  await page.waitForTimeout(LOGIN_SETTLE_DELAY_MS);
  return readSessionState(page);
}

async function readSessionState(page: Page): Promise<SessionState> {
  return page.evaluate(() => {
    const decode = (value: string | null): string | null => {
      if (value == null) return null;
      try {
        return JSON.parse(value) as string;
      } catch {
        return value;
      }
    };

    return {
      isLoggedIn: localStorage.getItem('flutter.is_logged_in') === 'true',
      role: decode(localStorage.getItem('flutter.role')),
      employeeId: decode(localStorage.getItem('flutter.employee_id')),
      branch: decode(localStorage.getItem('flutter.branch')),
      fullName: decode(localStorage.getItem('flutter.full_name')),
    };
  });
}

async function expectLoggedOut(page: Page): Promise<void> {
  const session = await readSessionState(page);
  expect(session.isLoggedIn).toBe(false);
  expect(session.role).toBeNull();
  expect(session.employeeId).toBeNull();
}

async function tryRoleCandidates(
  browser: Browser,
  candidates: Credentials[],
  expectedRole: string,
): Promise<CandidateLoginResult | null> {
  for (const credentials of candidates) {
    const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
    const page = await context.newPage();

    try {
      await openApp(page);
      const session = await loginWithKeyboard(page, credentials);

      if (session.isLoggedIn && session.role === expectedRole) {
        return { credentials, session };
      }
    } catch {
      // Continue trying next candidate; some environments do not have full seed data.
    } finally {
      await context.close();
    }
  }

  return null;
}

test.describe('Flutter Web - Playwright smoke suite', () => {
  test('app loads login form and exposes keyboard input bridge', async ({ page }) => {
    await openApp(page);
    await focusEmployeeField(page);
  });

  test('login requires employee id and pin', async ({ page }) => {
    await openApp(page);
    await focusEmployeeField(page);

    await page.keyboard.type('OWNER001', { delay: 20 });
    await page.keyboard.press('Tab');
    await page.waitForTimeout(120);
    await page.keyboard.press('Enter');
    await page.waitForTimeout(2000);

    await expectLoggedOut(page);
  });

  test('invalid credentials do not create a logged-in session', async ({ page }) => {
    await openApp(page);

    await loginWithKeyboard(page, { id: 'INVALID_USER', pin: '0000' });
    await expectLoggedOut(page);
  });

  test('owner login succeeds and stores session data', async ({ page }) => {
    test.slow();

    await openApp(page);
    const session = await loginWithKeyboard(page, OWNER_CREDENTIALS);

    expect(session.isLoggedIn).toBe(true);
    expect(session.role).toBe('owner');
    expect(session.employeeId).toBe(OWNER_CREDENTIALS.id);
    expect(session.fullName).not.toBeNull();
  });

  test('owner session persists across page reload', async ({ page }) => {
    test.slow();

    await openApp(page);
    const beforeReload = await loginWithKeyboard(page, OWNER_CREDENTIALS);
    expect(beforeReload.isLoggedIn).toBe(true);
    expect(beforeReload.role).toBe('owner');

    await page.reload();
    await page.waitForTimeout(APP_BOOT_DELAY_MS + 1500);

    const afterReload = await readSessionState(page);
    expect(afterReload.isLoggedIn).toBe(true);
    expect(afterReload.role).toBe('owner');
    expect(afterReload.employeeId).toBe(OWNER_CREDENTIALS.id);
  });

  test('manager login smoke (runs when manager seed exists)', async ({ browser }) => {
    test.slow();

    const result = await tryRoleCandidates(browser, MANAGER_CANDIDATES, 'manager');

    if (!result) {
      test.skip(true, 'No manager credential from candidate seed list is active in this environment.');
      return;
    }

    expect(result.session.isLoggedIn).toBe(true);
    expect(result.session.role).toBe('manager');
    test.info().annotations.push({
      type: 'manager-credentials',
      description: `${result.credentials.id}/${result.credentials.pin}`,
    });
  });

  test('staff login smoke (runs when staff seed exists)', async ({ browser }) => {
    test.slow();

    const result = await tryRoleCandidates(browser, STAFF_CANDIDATES, 'staff');

    if (!result) {
      test.skip(true, 'No staff credential from candidate seed list is active in this environment.');
      return;
    }

    expect(result.session.isLoggedIn).toBe(true);
    expect(result.session.role).toBe('staff');
    test.info().annotations.push({
      type: 'staff-credentials',
      description: `${result.credentials.id}/${result.credentials.pin}`,
    });
  });
});
