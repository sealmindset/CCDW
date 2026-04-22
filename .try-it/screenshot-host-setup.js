const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });

  await page.goto('http://127.0.0.1:9222');
  await page.waitForTimeout(1500);
  await page.screenshot({ path: '.try-it/screenshots/host-setup-main.png', fullPage: true });
  console.log('Screenshot: host-setup-main.png');

  // Click Azure Foundry (active)
  await page.locator('[data-provider="azure-foundry"]').click();
  await page.waitForTimeout(1000);
  await page.screenshot({ path: '.try-it/screenshots/host-setup-azure.png' });
  console.log('Screenshot: host-setup-azure.png');

  // Click Next to see credentials
  const next = page.locator('[data-action="next"]');
  if (await next.isVisible()) {
    await next.click();
    await page.waitForTimeout(800);
    await page.screenshot({ path: '.try-it/screenshots/host-setup-azure-creds.png' });
    console.log('Screenshot: host-setup-azure-creds.png');
  }

  // Close
  await page.locator('#btnCloseConfig').click();
  await page.waitForTimeout(500);

  // Click Anthropic
  await page.locator('[data-provider="anthropic"]').click();
  await page.waitForTimeout(1000);
  // Click Next to see API key field
  if (await page.locator('[data-action="next"]').isVisible()) {
    await page.locator('[data-action="next"]').click();
    await page.waitForTimeout(800);
  }
  await page.screenshot({ path: '.try-it/screenshots/host-setup-anthropic-creds.png' });
  console.log('Screenshot: host-setup-anthropic-creds.png');

  await page.locator('#btnCloseConfig').click();
  await page.waitForTimeout(300);

  await browser.close();
  console.log('Done!');
})();
