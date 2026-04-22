const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });

  // Workshop main page - click gear icon to open setup overlay
  await page.goto('http://localhost:9200/');
  await page.waitForTimeout(2000);

  // Find and click the gear icon
  const gearIcon = page.locator('.gear-icon, [title*="Setup"], [title*="Settings"], .nav-icon-settings').first();
  if (await gearIcon.isVisible({ timeout: 3000 }).catch(() => false)) {
    await gearIcon.click();
    await page.waitForTimeout(1500);
    await page.screenshot({ path: '.try-it/screenshots/workshop-gear-overlay.png' });
    console.log('Screenshot: workshop-gear-overlay.png');
  } else {
    // Try clicking any gear/settings element in top-right area
    const topRight = page.locator('nav >> svg, .topbar >> svg, header >> svg').last();
    if (await topRight.isVisible({ timeout: 2000 }).catch(() => false)) {
      await topRight.click();
      await page.waitForTimeout(1500);
      await page.screenshot({ path: '.try-it/screenshots/workshop-gear-overlay.png' });
      console.log('Screenshot: workshop-gear-overlay.png (via svg)');
    } else {
      console.log('Could not find gear icon to click');
      // Try to find it by examining what's there
      const html = await page.locator('nav, .topbar, header').first().innerHTML();
      console.log('Nav area HTML:', html.substring(0, 500));
    }
  }

  await browser.close();
})();
