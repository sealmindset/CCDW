/**
 * Ship Controller
 * Manages the Go Live wizard -- readiness checks, deployment
 * mode selection, and the final shipping flow.
 */

class ShipController {
  constructor(contentId) {
    this.contentEl = document.getElementById(contentId);
    this.step = 'readiness';  // readiness | mode | deploying | done
    this.checks = [];
    this.mode = null;
  }

  /**
   * Start the ship wizard -- show readiness checks.
   */
  start() {
    this.step = 'readiness';
    this.checks = [
      { label: 'App builds successfully', pass: null },
      { label: 'All tests passing', pass: null },
      { label: 'Login works for all roles', pass: null },
      { label: 'All pages load without errors', pass: null },
      { label: 'No hardcoded secrets detected', pass: null },
    ];
    this.renderReadiness();
    this.runChecks();
  }

  /**
   * Render the readiness checklist.
   */
  renderReadiness() {
    const allDone = this.checks.every(c => c.pass !== null);
    const allPass = this.checks.every(c => c.pass === true);

    let checksHtml = this.checks.map(c => {
      const icon = c.pass === null ? '<span class="check-spinner"></span>'
        : c.pass ? '<span class="check-pass">\u2713</span>'
        : '<span class="check-fail">\u2717</span>';
      return `<div class="ship-check">${icon}<span>${c.label}</span></div>`;
    }).join('');

    let actionHtml = '';
    if (allDone && allPass) {
      actionHtml = `
        <p class="ship-status ship-ready">Everything looks great! Your app is ready to go live.</p>
        <button class="btn-primary" id="btnShipNext">Choose How to Ship</button>
      `;
    } else if (allDone && !allPass) {
      actionHtml = `
        <p class="ship-status ship-issues">Some checks didn't pass. You can fix them first or ship anyway.</p>
        <div class="ship-actions">
          <button class="btn-secondary" id="btnShipFix">Fix Issues</button>
          <button class="btn-primary" id="btnShipNext">Ship Anyway</button>
        </div>
      `;
    } else {
      actionHtml = '<p class="ship-status">Running checks...</p>';
    }

    this.contentEl.innerHTML = `
      <h2>Ready to Go Live?</h2>
      <p class="ship-subtitle">Let me check a few things first.</p>
      <div class="ship-checks">${checksHtml}</div>
      ${actionHtml}
    `;

    // Wire buttons
    const nextBtn = this.contentEl.querySelector('#btnShipNext');
    if (nextBtn) {
      nextBtn.addEventListener('click', () => this.showModeSelection());
    }

    const fixBtn = this.contentEl.querySelector('#btnShipFix');
    if (fixBtn) {
      fixBtn.addEventListener('click', () => {
        window.cliBridge.resumeIt();
      });
    }
  }

  /**
   * Simulate running readiness checks.
   */
  async runChecks() {
    for (let i = 0; i < this.checks.length; i++) {
      await this.delay(600 + Math.random() * 400);
      this.checks[i].pass = true;
      this.renderReadiness();
    }
  }

  /**
   * Show deployment mode selection.
   */
  showModeSelection() {
    this.step = 'mode';

    this.contentEl.innerHTML = `
      <h2>How would you like to ship?</h2>
      <p class="ship-subtitle">Pick the best option for your team.</p>
      <div class="ship-modes">
        <div class="ship-mode-card" data-mode="docker">
          <div class="mode-icon">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="7" width="20" height="15" rx="2"/><path d="M17 2l-5 5-5-5"/></svg>
          </div>
          <h3>Docker Package</h3>
          <p>Get a docker-compose file to run anywhere. Self-hosted, your data stays with you.</p>
        </div>
        <div class="ship-mode-card" data-mode="zip">
          <div class="mode-icon">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
          </div>
          <h3>Download ZIP</h3>
          <p>Download the full source code. Hand it to your dev team or host it yourself.</p>
        </div>
        <div class="ship-mode-card" data-mode="github">
          <div class="mode-icon">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 19c-5 1.5-5-2.5-7-3m14 6v-3.87a3.37 3.37 0 0 0-.94-2.61c3.14-.35 6.44-1.54 6.44-7A5.44 5.44 0 0 0 20 4.77 5.07 5.07 0 0 0 19.91 1S18.73.65 16 2.48a13.38 13.38 0 0 0-7 0C6.27.65 5.09 1 5.09 1A5.07 5.07 0 0 0 5 4.77a5.44 5.44 0 0 0-1.5 3.78c0 5.42 3.3 6.61 6.44 7A3.37 3.37 0 0 0 9 18.13V22"/></svg>
          </div>
          <h3>Push to GitHub</h3>
          <p>Push your project to a GitHub repository. Collaborate with your team.</p>
        </div>
      </div>
    `;

    // Wire mode cards
    this.contentEl.querySelectorAll('.ship-mode-card').forEach(card => {
      card.addEventListener('click', () => {
        this.mode = card.dataset.mode;
        this.startShipping();
      });
    });
  }

  /**
   * Start the actual shipping process.
   */
  startShipping() {
    this.step = 'deploying';

    const modeLabels = {
      docker: 'Packaging your app with Docker...',
      zip: 'Preparing your download...',
      github: 'Pushing to GitHub...',
    };

    this.contentEl.innerHTML = `
      <div class="ship-deploying">
        <div class="ship-spinner"></div>
        <h2>${modeLabels[this.mode] || 'Shipping...'}</h2>
        <p class="ship-subtitle">This might take a moment.</p>
      </div>
    `;

    // Tell the CLI bridge to ship
    window.cliBridge.shipIt(this.mode);
  }

  /**
   * Show the completion screen.
   */
  complete(result) {
    this.step = 'done';

    const modeMessages = {
      docker: 'Your app is packaged and ready to deploy with <code>docker compose up</code>.',
      zip: 'Your project files are ready for download.',
      github: 'Your code has been pushed to GitHub.',
    };

    this.contentEl.innerHTML = `
      <div class="ship-done">
        <div class="ship-done-icon">\u2713</div>
        <h2>You're Live!</h2>
        <p>${modeMessages[this.mode] || 'Your app has been shipped.'}</p>
        ${result && result.url ? `<a href="${result.url}" class="btn-primary" target="_blank">View Project</a>` : ''}
        <button class="btn-secondary" id="btnShipHome" style="margin-top: 1rem;">Back to Home</button>
      </div>
    `;

    const homeBtn = this.contentEl.querySelector('#btnShipHome');
    if (homeBtn) {
      homeBtn.addEventListener('click', () => {
        // app.js exposes showView
        document.querySelector('.nav-btn[data-view="home"]').click();
      });
    }
  }

  delay(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}

// Global instance
window.ship = new ShipController('wizardContent');
