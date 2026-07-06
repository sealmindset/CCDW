// =============================================================================
// gh-session-setup.mjs — one-time GitHub session seeder (runs on the HOST).
//
// Opens a VISIBLE browser to GitHub's login page. You sign in normally
// (username, password, 2FA). When you're in, it saves the session (cookies) so
// the container's headless auto-authorize (gh-playwright-auth.mjs) can enter
// device codes and click Authorize with no interaction. Local-only single-user.
//
// Run via scripts/gh-session-setup.command (which provisions Playwright+Chromium).
// State is written to ~/Documents/.ccdw/gh-session.json, which is mounted into
// the container at /home/coder/Documents/.ccdw/gh-session.json.
// =============================================================================
import fs from 'fs';
import os from 'os';
import path from 'path';
import { chromium } from 'playwright';

const statePath = process.env.CCDW_GH_STATE
  || path.join(os.homedir(), 'Documents', '.ccdw', 'gh-session.json');
fs.mkdirSync(path.dirname(statePath), { recursive: true });

// Prefer real Chrome (less bot-flagged than bundled Chromium) if present.
let browser;
try { browser = await chromium.launch({ headless: false, channel: 'chrome' }); }
catch { browser = await chromium.launch({ headless: false }); }

const ctx = await browser.newContext();
const page = await ctx.newPage();
await page.goto('https://github.com/login', { waitUntil: 'domcontentloaded' });
console.log('\n  A browser opened. Sign in to GitHub (username, password, 2FA).');
console.log('  Waiting for you to finish (up to 5 minutes)...\n');

let ok = false;
for (let i = 0; i < 150; i++) {          // ~5 min
  await page.waitForTimeout(2000);
  try {
    // Confirm a real session by loading a logged-in-only page.
    await page.goto('https://github.com/settings/profile', { waitUntil: 'domcontentloaded', timeout: 15000 });
    if (!/\/login/.test(page.url())) { ok = true; break; }
    await page.goto('https://github.com/login', { waitUntil: 'domcontentloaded' }).catch(() => {});
  } catch { /* still logging in */ }
}

if (ok) {
  await ctx.storageState({ path: statePath });
  console.log('  ✓ GitHub session saved to ' + statePath);
  console.log('  The dashboard GitHub card can now auto-authorize.\n');
} else {
  console.error('  ✗ Sign-in not detected in time. Re-run and complete the GitHub login.\n');
}
await browser.close();
process.exit(ok ? 0 : 1);
