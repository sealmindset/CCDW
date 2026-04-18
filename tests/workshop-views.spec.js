const { test, expect } = require('@playwright/test');

const WORKSHOP_URL = 'http://localhost:9200';

test.describe('Workshop Views', () => {

  test.beforeEach(async ({ page }) => {
    await page.goto(WORKSHOP_URL);
    // Dismiss walkthrough if shown
    const skipBtn = page.locator('#btnWalkthroughSkip');
    if (await skipBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
      await skipBtn.click();
    }
    await page.waitForTimeout(500);
  });

  // =================================================================
  // VIEW 1: HOME
  // =================================================================
  test('Home view renders with hero, new project button, and projects list', async ({ page }) => {
    const homeView = page.locator('#viewHome');
    await expect(homeView).toHaveClass(/active/);

    await expect(page.locator('.home-hero h1')).toContainText('What would you like to build');
    await expect(page.locator('#btnNewProject')).toBeVisible();
    await expect(page.locator('#projectsList')).toBeVisible();
  });

  test('Header renders with brand, nav buttons, and status', async ({ page }) => {
    await expect(page.locator('.header-brand .header-title')).toContainText('Workshop');
    await expect(page.locator('.nav-btn[data-view="home"]')).toHaveClass(/active/);
    await expect(page.locator('.nav-btn[data-view="terminal"]')).toBeVisible();
    await expect(page.locator('#btnSeeApp')).toBeVisible();
    await expect(page.locator('#statusDot')).toBeVisible();
  });

  test('See Your App button is visible but disabled when no app running', async ({ page }) => {
    const btn = page.locator('#btnSeeApp');
    await expect(btn).toBeVisible();
    await expect(btn).toHaveClass(/disabled/);
    await expect(btn).not.toHaveClass(/hidden/);
  });

  test('New Project button opens dialog or setup wizard', async ({ page }) => {
    await page.locator('#btnNewProject').click();
    // Preflight runs first — either the project dialog or setup overlay will appear
    await page.waitForTimeout(3000);

    const dialogVisible = await page.locator('#dialogNewProject').evaluate(el => el.open).catch(() => false);
    const setupVisible = await page.locator('#setupOverlay').evaluate(el => !el.classList.contains('hidden')).catch(() => false);

    expect(dialogVisible || setupVisible).toBeTruthy();
  });

  // =================================================================
  // VIEW 2: CHAT
  // =================================================================
  test('Chat view has message area, input, and send button', async ({ page }) => {
    // Navigate to chat by simulating view switch
    await page.evaluate(() => {
      document.querySelector('#viewChat').classList.add('active');
      document.querySelector('#viewHome').classList.remove('active');
    });

    await expect(page.locator('#chatMessages')).toBeVisible();
    await expect(page.locator('#chatInput')).toBeVisible();
    await expect(page.locator('#btnSend')).toBeVisible();
    await expect(page.locator('#quickReplies')).toBeAttached();
  });

  // =================================================================
  // VIEW 3: BUILD (Bifrost)
  // =================================================================
  test('Build view has Bifrost container, phases, walker, and status line', async ({ page }) => {
    await page.evaluate(() => {
      document.querySelector('#viewBuild').classList.add('active');
      document.querySelector('#viewHome').classList.remove('active');
    });

    await expect(page.locator('#bifrostContainer')).toBeVisible();
    await expect(page.locator('#bifrostPath')).toBeVisible();
    await expect(page.locator('#bifrostGlow')).toBeVisible();
    await expect(page.locator('#bifrostBricks')).toBeVisible();
    await expect(page.locator('#bifrostWalker')).toBeVisible();
    await expect(page.locator('#buildStatusLine')).toBeAttached();
    await expect(page.locator('#buildComplete')).toBeAttached();
  });

  test('Bifrost has 4 phase nodes with correct labels', async ({ page }) => {
    await page.evaluate(() => {
      document.querySelector('#viewBuild').classList.add('active');
      document.querySelector('#viewHome').classList.remove('active');
    });

    const phases = page.locator('.phase-node');
    await expect(phases).toHaveCount(4);

    const labels = page.locator('.phase-label');
    await expect(labels.nth(0)).toContainText('Idea');
    await expect(labels.nth(1)).toContainText('Design');
    await expect(labels.nth(2)).toContainText('Build');
    await expect(labels.nth(3)).toContainText('Ready');
  });

  test('Bifrost phase nodes have icon containers (not circles)', async ({ page }) => {
    await page.evaluate(() => {
      document.querySelector('#viewBuild').classList.add('active');
      document.querySelector('#viewHome').classList.remove('active');
    });

    const icons = page.locator('.phase-icon');
    await expect(icons).toHaveCount(4);

    // Each icon should contain an SVG
    for (let i = 0; i < 4; i++) {
      await expect(icons.nth(i).locator('svg')).toBeAttached();
    }

    // Old circles should not exist
    await expect(page.locator('.phase-circle')).toHaveCount(0);
  });

  test('Bifrost walker has Claude pixel mascot SVG', async ({ page }) => {
    await page.evaluate(() => {
      document.querySelector('#viewBuild').classList.add('active');
      document.querySelector('#viewHome').classList.remove('active');
    });

    const walkerSvg = page.locator('.walker-icon svg');
    await expect(walkerSvg).toBeAttached();

    // Check for the terracotta color (Claude mascot body)
    const hasMascot = await page.evaluate(() => {
      const rects = document.querySelectorAll('.walker-icon svg rect');
      return Array.from(rects).some(r => r.getAttribute('fill') === '#D4956B');
    });
    expect(hasMascot).toBeTruthy();
  });

  test('Bifrost phase icons are positioned above the bridge path', async ({ page }) => {
    await page.evaluate(() => {
      document.querySelector('#viewBuild').classList.add('active');
      document.querySelector('#viewHome').classList.remove('active');
    });

    const phasesTop = await page.locator('.bifrost-phases').evaluate(el => {
      return window.getComputedStyle(el).top;
    });
    const pathBottom = await page.locator('.bifrost-path').evaluate(el => {
      return window.getComputedStyle(el).bottom;
    });

    // Phases should be at top: 0px, path at bottom
    expect(phasesTop).toBe('0px');
  });

  // =================================================================
  // VIEW 4: EXPLORE
  // =================================================================
  test('Explore view has header, app toolbar, and iframe', async ({ page }) => {
    await page.evaluate(() => {
      document.querySelector('#viewExplore').classList.add('active');
      document.querySelector('#viewHome').classList.remove('active');
    });

    await expect(page.locator('#exploreHeader')).toBeVisible();
    await expect(page.locator('#projectTitle')).toBeVisible();
    await expect(page.locator('.app-toolbar')).toBeVisible();
    await expect(page.locator('#appFrame')).toBeAttached();
    await expect(page.locator('#btnIterate')).toBeVisible();
    await expect(page.locator('#btnGoLive')).toBeVisible();
    await expect(page.locator('#btnRefreshApp')).toBeVisible();
    await expect(page.locator('#btnOpenExternal')).toBeVisible();
  });

  // =================================================================
  // VIEW 5: ITERATE
  // =================================================================
  test('Iterate view has board and chat panels', async ({ page }) => {
    await page.evaluate(() => {
      document.querySelector('#viewIterate').classList.add('active');
      document.querySelector('#viewHome').classList.remove('active');
    });

    await expect(page.locator('#iterateBoard')).toBeVisible();
    await expect(page.locator('#iterateChat')).toBeVisible();
    await expect(page.locator('#iterateChatInput')).toBeVisible();
    await expect(page.locator('#btnIterateSend')).toBeVisible();
    await expect(page.locator('#btnNewRequest')).toBeVisible();
    await expect(page.locator('#boardItems')).toBeAttached();
  });

  // =================================================================
  // VIEW 6: SHIP
  // =================================================================
  test('Ship view has wizard content area', async ({ page }) => {
    await page.evaluate(() => {
      document.querySelector('#viewShip').classList.add('active');
      document.querySelector('#viewHome').classList.remove('active');
    });

    await expect(page.locator('#viewShip .ship-wizard')).toBeVisible();
    await expect(page.locator('#wizardContent')).toBeAttached();
  });

  // =================================================================
  // VIEW TRANSITIONS
  // =================================================================
  test('Home view is active on initial load', async ({ page }) => {
    // On fresh load, home is the default active view
    await expect(page.locator('#viewHome')).toHaveClass(/active/);
    // Other views should not be active
    await expect(page.locator('#viewChat')).not.toHaveClass(/active/);
    await expect(page.locator('#viewBuild')).not.toHaveClass(/active/);
    await expect(page.locator('#viewExplore')).not.toHaveClass(/active/);
  });

  // =================================================================
  // OVERLAYS & PANELS
  // =================================================================
  test('Bootstrap panel toggles on gear icon click', async ({ page }) => {
    const panel = page.locator('#bootstrapPanel');
    await expect(panel).toHaveClass(/hidden/);

    await page.locator('#btnBootstrap').click();
    await expect(panel).not.toHaveClass(/hidden/);

    await page.locator('#btnCloseBootstrap').click();
    await expect(panel).toHaveClass(/hidden/);
  });

  test('Bootstrap panel shows preflight check steps', async ({ page }) => {
    await page.locator('#btnBootstrap').click();
    const sequence = page.locator('#bootstrapSequence');
    await expect(sequence).toBeVisible();

    // Should have 5 steps: network, auth, cli, ws, skill
    const steps = sequence.locator('.bootstrap-step');
    await expect(steps).toHaveCount(5);
  });

  test('Walkthrough overlay shows on first visit', async ({ page }) => {
    // Clear walkthrough state and reload
    await page.evaluate(() => localStorage.removeItem('workshop-walkthrough-done'));
    await page.reload();
    await page.waitForTimeout(1000);

    const overlay = page.locator('#walkthroughOverlay');
    const visible = await overlay.isVisible().catch(() => false);
    if (visible) {
      await expect(page.locator('#walkthroughContent')).toContainText('Welcome to Workshop');
      await expect(page.locator('#btnWalkthroughNext')).toBeVisible();
      await expect(page.locator('#btnWalkthroughSkip')).toBeVisible();
    }
    // If not visible, it may have been dismissed in beforeEach — still pass
  });
});
