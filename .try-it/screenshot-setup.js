const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });

  // 1. Setup page - main view with provider cards
  await page.goto('http://localhost:9200/setup.html');
  await page.waitForTimeout(1500);
  await page.screenshot({ path: '.try-it/screenshots/setup-main.png', fullPage: true });
  console.log('Screenshot: setup-main.png');

  // Helper: close config panel using X button
  async function closeConfig() {
    const closeBtn = page.locator('#btnCloseConfig');
    if (await closeBtn.isVisible()) {
      await closeBtn.click();
      await page.waitForTimeout(500);
    }
  }

  // 2. Click on Azure AI Foundry card (the active provider) to open config panel
  await page.locator('[data-provider="azure-foundry"]').click();
  await page.waitForTimeout(1000);
  await page.screenshot({ path: '.try-it/screenshots/setup-azure-foundry-prereqs.png' });
  console.log('Screenshot: setup-azure-foundry-prereqs.png');

  // Click Next to see credentials step
  const nextBtn = page.locator('[data-action="next"]');
  if (await nextBtn.isVisible()) {
    await nextBtn.click();
    await page.waitForTimeout(800);
    await page.screenshot({ path: '.try-it/screenshots/setup-azure-foundry-creds.png' });
    console.log('Screenshot: setup-azure-foundry-creds.png');
  }

  await closeConfig();

  // 3. Click on Anthropic card
  await page.locator('[data-provider="anthropic"]').click();
  await page.waitForTimeout(1000);
  await page.screenshot({ path: '.try-it/screenshots/setup-anthropic-panel.png' });
  console.log('Screenshot: setup-anthropic-panel.png');
  await closeConfig();

  // 4. Click on AWS Bedrock card
  await page.locator('[data-provider="bedrock"]').click();
  await page.waitForTimeout(1000);
  await page.screenshot({ path: '.try-it/screenshots/setup-bedrock-panel.png' });
  console.log('Screenshot: setup-bedrock-panel.png');
  await closeConfig();

  // 5. Click on OpenAI card (App Development)
  await page.locator('[data-provider="openai"]').click();
  await page.waitForTimeout(1000);
  await page.screenshot({ path: '.try-it/screenshots/setup-openai-panel.png' });
  console.log('Screenshot: setup-openai-panel.png');
  await closeConfig();

  // 6. Click on Azure OpenAI card
  await page.locator('[data-provider="azure-openai"]').click();
  await page.waitForTimeout(1000);
  await page.screenshot({ path: '.try-it/screenshots/setup-azure-openai-panel.png' });
  console.log('Screenshot: setup-azure-openai-panel.png');
  await closeConfig();

  // 7. Workshop main page
  await page.goto('http://localhost:9200/');
  await page.waitForTimeout(2000);
  await page.screenshot({ path: '.try-it/screenshots/workshop-main.png' });
  console.log('Screenshot: workshop-main.png');

  // 8. Look for setup link in auth banner
  const setupLink = page.locator('#authSetupLink');
  if (await setupLink.isVisible({ timeout: 3000 }).catch(() => false)) {
    await setupLink.click();
    await page.waitForTimeout(1500);
    await page.screenshot({ path: '.try-it/screenshots/workshop-setup-overlay.png' });
    console.log('Screenshot: workshop-setup-overlay.png');
  } else {
    console.log('No auth setup link visible (auth may already be configured)');
  }

  await browser.close();
  console.log('All done!');
})();
