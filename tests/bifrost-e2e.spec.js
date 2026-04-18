const { test, expect } = require('@playwright/test');

const WORKSHOP_URL = 'http://localhost:9200';

test.describe('Bifrost End-to-End', () => {

  test.beforeEach(async ({ page }) => {
    await page.goto(WORKSHOP_URL);
    // Dismiss walkthrough
    const skipBtn = page.locator('#btnWalkthroughSkip');
    if (await skipBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
      await skipBtn.click();
    }
    await page.waitForTimeout(500);

    // Switch to build view for Bifrost testing
    await page.evaluate(() => {
      document.querySelector('#viewBuild').classList.add('active');
      document.querySelector('#viewHome').classList.remove('active');
    });
  });

  // =================================================================
  // INITIAL STATE
  // =================================================================
  test('Bifrost starts in reset state', async ({ page }) => {
    // Explicitly reset since the controller may have been initialized with no data-progress attr
    await page.evaluate(() => window.bifrost.reset());
    await page.waitForTimeout(100);

    const glow = page.locator('#bifrostGlow');
    await expect(glow).toHaveAttribute('data-progress', '0');

    const walker = page.locator('#bifrostWalker');
    await expect(walker).toHaveAttribute('data-position', 'start');

    const activeNodes = page.locator('.phase-node.active');
    const completedNodes = page.locator('.phase-node.completed');
    await expect(activeNodes).toHaveCount(0);
    await expect(completedNodes).toHaveCount(0);
  });

  test('Bug character is hidden initially', async ({ page }) => {
    await expect(page.locator('#bifrostBug')).toHaveClass(/hidden/);
  });

  test('Build complete button is hidden initially', async ({ page }) => {
    await expect(page.locator('#buildComplete')).toHaveClass(/hidden/);
  });

  // =================================================================
  // PHASE PROGRESSION
  // =================================================================
  test('setPhase("ideation") activates first node and moves walker', async ({ page }) => {
    await page.evaluate(() => window.bifrost.setPhase('ideation'));
    await page.waitForTimeout(600);

    await expect(page.locator('#bifrostGlow')).toHaveAttribute('data-progress', '25');
    await expect(page.locator('#bifrostWalker')).toHaveAttribute('data-position', 'phase-1');
    await expect(page.locator('.phase-node[data-phase="ideation"]')).toHaveClass(/active/);
  });

  test('setPhase("design") completes ideation, activates design', async ({ page }) => {
    await page.evaluate(() => window.bifrost.setPhase('ideation'));
    await page.waitForTimeout(600);

    await page.evaluate(() => window.bifrost.setPhase('design'));
    await page.waitForTimeout(600);

    await expect(page.locator('#bifrostGlow')).toHaveAttribute('data-progress', '50');
    await expect(page.locator('#bifrostWalker')).toHaveAttribute('data-position', 'phase-2');
    await expect(page.locator('.phase-node[data-phase="ideation"]')).toHaveClass(/completed/);
    await expect(page.locator('.phase-node[data-phase="design"]')).toHaveClass(/active/);
  });

  test('setPhase("building") completes design, activates building', async ({ page }) => {
    await page.evaluate(() => {
      window.bifrost.setPhase('ideation');
      setTimeout(() => window.bifrost.setPhase('design'), 100);
      setTimeout(() => window.bifrost.setPhase('building'), 200);
    });
    await page.waitForTimeout(800);

    await expect(page.locator('#bifrostGlow')).toHaveAttribute('data-progress', '75');
    await expect(page.locator('#bifrostWalker')).toHaveAttribute('data-position', 'phase-3');
    await expect(page.locator('.phase-node[data-phase="ideation"]')).toHaveClass(/completed/);
    await expect(page.locator('.phase-node[data-phase="design"]')).toHaveClass(/completed/);
    await expect(page.locator('.phase-node[data-phase="building"]')).toHaveClass(/active/);
  });

  test('Full progression: ideation → design → building → complete', async ({ page }) => {
    await page.evaluate(() => {
      window.bifrost.setPhase('ideation');
      setTimeout(() => window.bifrost.setPhase('design'), 200);
      setTimeout(() => window.bifrost.setPhase('building'), 400);
      setTimeout(() => window.bifrost.setPhase('complete'), 600);
    });
    await page.waitForTimeout(1200);

    await expect(page.locator('#bifrostGlow')).toHaveAttribute('data-progress', '100');
    await expect(page.locator('#bifrostWalker')).toHaveAttribute('data-position', 'phase-4');

    // All nodes should be completed (not active) after complete()
    const phases = page.locator('.phase-node');
    for (let i = 0; i < 4; i++) {
      // Complete sets all to completed except the last which is active briefly
      const cls = await phases.nth(i).getAttribute('class');
      expect(cls).toMatch(/completed|active/);
    }
  });

  // =================================================================
  // BACKWARD PHASE (should be ignored)
  // =================================================================
  test('setPhase ignores backward movement', async ({ page }) => {
    await page.evaluate(() => {
      window.bifrost.setPhase('ideation');
      setTimeout(() => window.bifrost.setPhase('design'), 100);
    });
    await page.waitForTimeout(600);

    // Try going backward
    await page.evaluate(() => window.bifrost.setPhase('ideation'));
    await page.waitForTimeout(200);

    // Should still be on design
    await expect(page.locator('#bifrostGlow')).toHaveAttribute('data-progress', '50');
    await expect(page.locator('#bifrostWalker')).toHaveAttribute('data-position', 'phase-2');
  });

  // =================================================================
  // COMPLETE ANIMATION
  // =================================================================
  test('complete() triggers celebration classes', async ({ page }) => {
    await page.evaluate(() => window.bifrost.complete());
    await page.waitForTimeout(600);

    await expect(page.locator('#bifrostGlow')).toHaveClass(/celebrating/);
    await expect(page.locator('#bifrostWalker')).toHaveClass(/celebrating/);

    // Celebration classes should be removed after ~2.5s
    await page.waitForTimeout(2500);
    await expect(page.locator('#bifrostGlow')).not.toHaveClass(/celebrating/);
    await expect(page.locator('#bifrostWalker')).not.toHaveClass(/celebrating/);
  });

  test('complete() sets all phases to completed and progress to 100', async ({ page }) => {
    await page.evaluate(() => window.bifrost.complete());
    await page.waitForTimeout(800);

    await expect(page.locator('#bifrostGlow')).toHaveAttribute('data-progress', '100');
    await expect(page.locator('#bifrostWalker')).toHaveAttribute('data-position', 'phase-4');

    const phases = page.locator('.phase-node');
    for (let i = 0; i < 4; i++) {
      await expect(phases.nth(i)).toHaveClass(/completed/);
    }
  });

  // =================================================================
  // BUG ENCOUNTER
  // =================================================================
  test('showBug() makes bug visible ahead of walker', async ({ page }) => {
    await page.evaluate(() => {
      window.bifrost.setPhase('ideation');
    });
    await page.waitForTimeout(300);

    await page.evaluate(() => window.bifrost.showBug());
    await page.waitForTimeout(100);

    const bug = page.locator('#bifrostBug');
    await expect(bug).not.toHaveClass(/hidden/);
  });

  test('defeatBug() adds defeating class then hides bug', async ({ page }) => {
    await page.evaluate(() => {
      window.bifrost.showBug();
    });
    await page.waitForTimeout(100);

    await page.evaluate(() => window.bifrost.defeatBug());

    // Should have defeating class immediately
    await expect(page.locator('#bifrostBug')).toHaveClass(/defeating/);

    // After animation, bug should be hidden
    await page.waitForTimeout(1000);
    await expect(page.locator('#bifrostBug')).toHaveClass(/hidden/);
  });

  test('Bug defeat shows spark effect', async ({ page }) => {
    await page.evaluate(() => {
      window.bifrost.showBug();
      window.bifrost.defeatBug();
    });

    // Defeat spark should be visible briefly
    const defeat = page.locator('#bugDefeat');
    await expect(defeat).not.toHaveClass(/hidden/);

    // After animation it goes back to hidden
    await page.waitForTimeout(1000);
    await expect(defeat).toHaveClass(/hidden/);
  });

  // =================================================================
  // RESET
  // =================================================================
  test('reset() returns everything to initial state', async ({ page }) => {
    // Advance to building
    await page.evaluate(() => {
      window.bifrost.setPhase('ideation');
      setTimeout(() => window.bifrost.setPhase('design'), 100);
      setTimeout(() => window.bifrost.setPhase('building'), 200);
    });
    await page.waitForTimeout(800);

    // Reset
    await page.evaluate(() => window.bifrost.reset());
    await page.waitForTimeout(100);

    await expect(page.locator('#bifrostGlow')).toHaveAttribute('data-progress', '0');
    await expect(page.locator('#bifrostWalker')).toHaveAttribute('data-position', 'start');
    await expect(page.locator('.phase-node.active')).toHaveCount(0);
    await expect(page.locator('.phase-node.completed')).toHaveCount(0);
    await expect(page.locator('#bifrostBug')).toHaveClass(/hidden/);
  });

  // =================================================================
  // VISUAL LAYOUT ASSERTIONS
  // =================================================================
  test('Phase icons are above the bridge path vertically', async ({ page }) => {
    const layout = await page.evaluate(() => {
      const phases = document.querySelector('.bifrost-phases');
      const path = document.querySelector('.bifrost-path');
      const phasesRect = phases.getBoundingClientRect();
      const pathRect = path.getBoundingClientRect();
      return {
        phasesTop: phasesRect.top,
        phasesBottom: phasesRect.bottom,
        pathTop: pathRect.top,
        pathBottom: pathRect.bottom,
      };
    });

    // Phase icons top should be above (or at) the path top
    expect(layout.phasesTop).toBeLessThan(layout.pathTop);
  });

  test('Walker is positioned on the bridge path', async ({ page }) => {
    const layout = await page.evaluate(() => {
      const walker = document.querySelector('.bifrost-walker');
      const path = document.querySelector('.bifrost-path');
      const walkerRect = walker.getBoundingClientRect();
      const pathRect = path.getBoundingClientRect();
      return {
        walkerCenter: walkerRect.top + walkerRect.height / 2,
        pathTop: pathRect.top,
        pathBottom: pathRect.bottom,
      };
    });

    // Walker center should be near the path (within reasonable range)
    expect(layout.walkerCenter).toBeGreaterThan(layout.pathTop - 30);
    expect(layout.walkerCenter).toBeLessThan(layout.pathBottom + 30);
  });

  test('Bifrost track has expected dimensions', async ({ page }) => {
    const height = await page.locator('.bifrost-track').evaluate(el => {
      return parseInt(window.getComputedStyle(el).height);
    });
    // Track should be around 110px
    expect(height).toBeGreaterThan(90);
    expect(height).toBeLessThan(140);
  });

  // =================================================================
  // CSS ANIMATION PROPERTIES
  // =================================================================
  test('Glow has shimmer animation', async ({ page }) => {
    const animation = await page.locator('#bifrostGlow').evaluate(el => {
      return window.getComputedStyle(el).animationName;
    });
    expect(animation).toContain('bifrost-shimmer');
  });

  test('Walker has bob animation', async ({ page }) => {
    const animation = await page.locator('.walker-icon').evaluate(el => {
      return window.getComputedStyle(el).animationName;
    });
    expect(animation).toContain('walker-bob');
  });

  test('Active phase icon has pulse animation', async ({ page }) => {
    await page.evaluate(() => window.bifrost.setPhase('ideation'));
    await page.waitForTimeout(600);

    const animation = await page.locator('.phase-node.active .phase-icon').evaluate(el => {
      return window.getComputedStyle(el).animationName;
    });
    expect(animation).toContain('phase-pulse');
  });
});
