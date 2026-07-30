// End-to-end check that Chat drives real Claude Code: a message must produce
// streamed prose plus at least one tool activity chip that resolves, and the
// folder picker must be able to rebind the conversation.
const { test, expect } = require('@playwright/test');

const CHAT = process.env.CHAT_URL || 'http://localhost:3002';

test.describe('Claude Chat agent', () => {
  test('loads clean with a folder chip and a model list', async ({ page }) => {
    const errors = [];
    page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
    page.on('pageerror', e => errors.push(e.message));

    await page.goto(CHAT);
    await expect(page.locator('#workdir-chip')).toContainText('Documents');

    const options = page.locator('#model-selector option');
    expect(await options.count()).toBeGreaterThan(0);

    expect(errors, `console errors: ${errors.join(' | ')}`).toEqual([]);
  });

  test('folder picker browses the mounted tree', async ({ page }) => {
    await page.goto(CHAT);
    await page.click('#workdir-chip');
    await expect(page.locator('#workdir-dialog')).toBeVisible();
    await expect(page.locator('#workdir-crumb')).toContainText('/home/coder/Documents');

    // Descending must update the crumb and offer a way back up.
    await page.locator('.wd-row', { hasText: 'CCDW' }).first().click();
    await expect(page.locator('#workdir-crumb')).toContainText('CCDW');
    await expect(page.locator('.wd-up')).toBeVisible();

    await page.click('#btn-workdir-use');
    await expect(page.locator('#workdir-chip')).toContainText('CCDW');
  });

  test('a message runs tools and streams a reply', async ({ page }) => {
    test.setTimeout(180000);
    await page.goto(CHAT);

    // Bind to a folder with known contents.
    await page.click('#workdir-chip');
    await page.locator('.wd-row', { hasText: 'CCDW' }).first().click();
    await expect(page.locator('#btn-workdir-use')).toBeEnabled();
    await page.click('#btn-workdir-use');
    await expect(page.locator('#workdir-chip')).toContainText('CCDW');

    await page.fill('#message-input', 'Run ls on the chat/ directory and tell me what you see.');
    await page.click('#btn-send');

    const chip = page.locator('.tool-chip').first();
    await expect(chip).toBeVisible({ timeout: 120000 });
    await expect(chip).toHaveClass(/tool-done|tool-error/, { timeout: 120000 });
    await expect(chip).toContainText('Ran');

    // Chips stay collapsed until asked -- the reply is the point, not the log.
    await expect(chip.locator('.tool-chip-body')).toBeHidden();
    await chip.locator('.tool-chip-head').click();
    await expect(chip.locator('.tool-chip-body')).toBeVisible();

    await expect(page.locator('.message-assistant .message-bubble').last())
      .toContainText(/server\.js|providers\.js|conversations\.js/, { timeout: 120000 });

    // Input comes back and the thread gets a real name.
    await expect(page.locator('#message-input')).toBeEnabled({ timeout: 120000 });
    await expect(page.locator('.sidebar-list')).not.toContainText('New conversation');
  });
});
