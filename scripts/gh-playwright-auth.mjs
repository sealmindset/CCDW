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

  // If the session is stale, GitHub shows a bare login page -> can't proceed
  // headlessly. (Note: /login/device is NOT the login page — allow it through.)
  if (/\/login($|\?|#)/.test(page.url())) {
    console.error('ERROR: GitHub session expired — re-run the seeder to sign in again.');
    process.exit(3);
  }

  // The device grant is a MULTI-SCREEN flow that varies by account/session:
  //   1. "Verify Session" / select_account  -> a lone "Continue" button (no code
  //      field) when the session has saved accounts. Must click through it first.
  //   2. "Device Activation"                 -> 8 split boxes (#user-code-0..7);
  //      focusing the first and typing auto-advances. Then submit.
  //   3. Authorize grant                     -> "Authorize"/"Approve" button.
  //   4. Success                             -> "Congratulations" / "connected".
  // Old code assumed screen 2 was first and timed out on the Verify screen.
  // Drive it as a state machine: inspect the page each tick, act, repeat.
  let codeEntered = false, authorized = false;
  for (let i = 0; i < 20 && !authorized; i++) {          // ~20 ticks
    await page.waitForTimeout(1200);
    const url = page.url();
    const body = (await page.textContent('body').catch(() => '') || '');

    // Session went stale mid-flow.
    if (/\/login($|\?|#)/.test(url)) {
      console.error('ERROR: GitHub session expired — re-run the seeder.');
      process.exit(3);
    }

    // Corporate SAML SSO wall: after Authorize, org policy may bounce to the
    // identity provider (Microsoft/Okta/etc.) demanding an interactive login +
    // MFA. That cannot be completed headlessly — bail with a distinct code so
    // the caller can tell the user to sign in interactively.
    if (/login\.microsoftonline\.com|okta\.com|\/sso|saml/i.test(url)) {
      console.error('ERROR: sso_required — org enforces SAML SSO + MFA on the grant; cannot complete headlessly.');
      try { await browser.close(); } catch {}
      process.exit(4);
    }

    // Success screen — device connected. (Only THIS confirms success — a click
    // on Authorize is NOT proof the grant completed when SSO can intercept.)
    if (/congratulations|your device is now connected|device is now connected|now connected/i.test(body)) {
      authorized = true; break;
    }

    // Authorize / grant button present -> click it, then keep looping to verify
    // the outcome (success text or an SSO redirect) on subsequent ticks.
    const grant = page.getByRole('button', { name: /^(authorize|approve|grant)/i }).first();
    if (await grant.isVisible().catch(() => false)) {
      await grant.click({ timeout: 15000 }).catch(() => {});
      await page.waitForTimeout(2000);
      continue;
    }

    // Code-entry screen -> split boxes #user-code-0.. OR a single field.
    const firstBox = page.locator('#user-code-0');
    const anyText = page.locator('input[type="text"]:not([name="authenticity_token"]), input:not([type])');
    const hasCodeField =
      (await firstBox.isVisible().catch(() => false)) ||
      (await anyText.first().isVisible().catch(() => false));
    if (hasCodeField && !codeEntered) {
      const target = (await firstBox.isVisible().catch(() => false)) ? firstBox : anyText.first();
      await target.click({ timeout: 10000 }).catch(() => {});
      await page.keyboard.type(codeDigits, { delay: 60 });   // auto-advances split boxes
      codeEntered = true;
      // Submit the code (Continue / the form's submit).
      await page.getByRole('button', { name: /continue|verify|submit/i }).first()
        .click({ timeout: 8000 }).catch(() => {});
      continue;
    }

    // Interstitial (Verify Session / select_account): a Continue with no code field.
    const cont = page.getByRole('button', { name: /continue/i }).first();
    if (await cont.isVisible().catch(() => false)) {
      await cont.click({ timeout: 8000 }).catch(() => {});
      continue;
    }
  }

  if (!authorized) {
    console.error('ERROR: could not complete the grant (code entered: ' + codeEntered + ').');
    try { await browser.close(); } catch {}
    process.exit(1);
  }

  // Give GitHub a moment to record the grant, then persist refreshed cookies.
  await page.waitForTimeout(2500);
  await ctx.storageState({ path: statePath }).catch(() => {});

  console.log('authorized');
  await browser.close();
  process.exit(0);
} catch (e) {
  console.error('ERROR: automation failed — ' + (e && e.message ? e.message : e));
  try { await browser.close(); } catch {}
  process.exit(1);
}
