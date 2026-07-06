// =============================================================================
// gh-playwright-auth.mjs — headless GitHub device-flow auto-authorize.
//
// Runs INSIDE the container. Uses a pre-seeded GitHub session (storageState,
// created once by scripts/gh-session-setup.command on the host) so it can enter
// the device user_code and click "Authorize" with NO human interaction.
//
// Usage: node gh-playwright-auth.mjs <USER_CODE> [VERIFICATION_URI] [STATE_PATH]
//   USER_CODE         e.g. "ABCD-1234" (from `gh auth login` device flow)
//   VERIFICATION_URI  default https://github.com/login/device
//   STATE_PATH        default /home/coder/Documents/.ccdw/gh-session.json
//
// Exit codes: 0 authorized · 2 bad args · 3 no seeded session · 1 automation failed.
//
// NOTE: GitHub's device page DOM changes over time and GitHub may flag automated
// browsers. Selectors are best-effort with fallbacks; local-only single-user use.
// =============================================================================
import fs from 'fs';

// Find the Chromium baked into the image if the env var isn't already set.
if (!process.env.PLAYWRIGHT_BROWSERS_PATH) {
  process.env.PLAYWRIGHT_BROWSERS_PATH = '/opt/claude-code-docker/pw-browsers';
}

const code = process.argv[2];
const uri = process.argv[3] || 'https://github.com/login/device';
const statePath = process.argv[4] || '/home/coder/Documents/.ccdw/gh-session.json';

if (!code) { console.error('ERROR: no user_code'); process.exit(2); }
if (!fs.existsSync(statePath)) {
  console.error('ERROR: no GitHub session at ' + statePath + ' — run the one-time seeder (gh-session-setup.command) first.');
  process.exit(3);
}

let chromium;
try { ({ chromium } = await import('playwright')); }
catch { ({ chromium } = await import('playwright-core')); }

const codeDigits = code.replace(/-/g, '');
// Alpine can't run Playwright's bundled Chromium (musl vs glibc) — use the
// system Chromium (apk). On other OSes, fall back to Playwright's bundled one.
const chromeExe = process.env.PLAYWRIGHT_CHROMIUM_PATH
  || (fs.existsSync('/usr/bin/chromium-browser') ? '/usr/bin/chromium-browser'
      : fs.existsSync('/usr/bin/chromium') ? '/usr/bin/chromium' : undefined);
const browser = await chromium.launch({
  headless: true,
  executablePath: chromeExe,
  args: ['--no-sandbox', '--disable-dev-shm-usage'],
});
try {
  const ctx = await browser.newContext({ storageState: statePath });
  const page = await ctx.newPage();
  await page.goto(uri, { waitUntil: 'domcontentloaded', timeout: 30000 });

  // If the session is stale, GitHub shows a login page -> we can't proceed headlessly.
  if (/\/login($|\?)/.test(page.url())) {
    console.error('ERROR: GitHub session expired — re-run the seeder to sign in again.');
    process.exit(3);
  }

  // Enter the code. GitHub's device page uses either one field or split boxes;
  // clicking the first input and typing the 8 chars fills either layout.
  await page.locator('input[type="text"], input:not([type])').first().click({ timeout: 15000 });
  await page.keyboard.type(codeDigits, { delay: 40 });

  // Continue (advances to the grant screen). Ignore if the page auto-advances.
  await page.getByRole('button', { name: /continue|verify/i }).first()
    .click({ timeout: 10000 }).catch(() => {});
  await page.waitForTimeout(1500);

  // Authorize the grant.
  await page.getByRole('button', { name: /authorize|grant|approve/i }).first()
    .click({ timeout: 20000 });

  // Give GitHub a moment to record the grant, then persist refreshed cookies.
  await page.waitForTimeout(3000);
  await ctx.storageState({ path: statePath });

  console.log('authorized');
  await browser.close();
  process.exit(0);
} catch (e) {
  console.error('ERROR: automation failed — ' + (e && e.message ? e.message : e));
  try { await browser.close(); } catch {}
  process.exit(1);
}
