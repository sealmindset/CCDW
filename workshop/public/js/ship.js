/**
 * Ship Controller
 * Manages the Go Live wizard -- real readiness checks, deployment
 * mode selection (/ship-it, /ship-it save, /argo-it), and live
 * progress tracking through the CLI bridge.
 */

class ShipController {
  constructor(contentId) {
    this.contentEl = document.getElementById(contentId);
    this.step = 'readiness';  // readiness | mode | deploying | done
    this.checks = [];
    this.capabilities = {};
    this.mode = null;
    this.projectName = null;
  }

  /**
   * Start the ship wizard -- run real readiness checks.
   * @param {string} projectName - Project directory name (server resolves full path)
   */
  start(projectName) {
    this.step = 'readiness';
    this.projectName = projectName;
    this.checks = [];
    this.renderLoading();
    this.runChecks();
  }

  renderLoading() {
    this.contentEl.innerHTML = `
      <h2>Ready to Go Live?</h2>
      <p class="ship-subtitle">Checking your project...</p>
      <div class="ship-checks">
        <div class="ship-check"><span class="check-spinner"></span><span>Running readiness checks...</span></div>
      </div>
    `;
  }

  /**
   * Run real readiness checks via the server API.
   */
  async runChecks() {
    try {
      const resp = await fetch('/api/ship/readiness', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ projectName: this.projectName }),
      });
      const data = await resp.json();
      this.checks = data.checks || [];
      this.capabilities = data.capabilities || {};
      this.renderReadiness(data.ready);
    } catch (err) {
      this.contentEl.innerHTML = `
        <h2>Readiness Check</h2>
        <p class="ship-status ship-issues">Could not run readiness checks. Is the Workshop server running?</p>
        <button class="btn-secondary" id="btnShipRetry">Retry</button>
      `;
      const retryBtn = this.contentEl.querySelector('#btnShipRetry');
      if (retryBtn) retryBtn.addEventListener('click', () => this.start(this.projectName));
    }
  }

  /**
   * Render the readiness checklist with real results.
   */
  renderReadiness(allReady) {
    const checksHtml = this.checks.map(c => {
      const icon = c.pass
        ? '<span class="check-pass">✓</span>'
        : c.severity === 'info'
          ? '<span class="check-info">i</span>'
          : '<span class="check-fail">✗</span>';
      const detail = c.detail ? `<span class="check-detail">${c.detail}</span>` : '';
      return `<div class="ship-check">${icon}<span>${c.label}</span>${detail}</div>`;
    }).join('');

    const ghFailed = this.checks.some(c => c.id === 'gh-auth' && !c.pass);

    let actionHtml;
    if (ghFailed) {
      actionHtml = `
        <p class="ship-status ship-issues">You need to connect your GitHub account first.</p>
        <p class="ship-hint">Open the Web Terminal and run: <code>gh auth login</code></p>
        <button class="btn-secondary" id="btnShipRecheck">Recheck</button>
      `;
    } else {
      actionHtml = `
        <p class="ship-status ship-ready">Your project is ready to ship!</p>
        <button class="btn-primary" id="btnShipNext">Choose How to Ship</button>
      `;
    }

    this.contentEl.innerHTML = `
      <h2>Ready to Go Live?</h2>
      <p class="ship-subtitle">Here's what I found.</p>
      <div class="ship-checks">${checksHtml}</div>
      ${actionHtml}
    `;

    const nextBtn = this.contentEl.querySelector('#btnShipNext');
    if (nextBtn) nextBtn.addEventListener('click', () => this.showModeSelection());

    const recheckBtn = this.contentEl.querySelector('#btnShipRecheck');
    if (recheckBtn) recheckBtn.addEventListener('click', () => this.start(this.projectName));
  }

  /**
   * Show deployment mode selection with real options.
   */
  showModeSelection() {
    this.step = 'mode';

    const argoAvailable = this.capabilities.kubectl;

    this.contentEl.innerHTML = `
      <h2>How would you like to ship?</h2>
      <p class="ship-subtitle">Pick the best option for your situation.</p>
      <div class="ship-modes">
        <div class="ship-mode-card" data-mode="ship-it">
          <div class="mode-icon">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 2L11 13"/><path d="M22 2L15 22 11 13 2 9 22 2z"/></svg>
          </div>
          <h3>Ship for Review</h3>
          <p>Create a pull request with security checks, tests, and reviewer assignment. Full CI/CD pipeline.</p>
          <span class="mode-tag mode-tag-recommended">Recommended</span>
        </div>
        <div class="ship-mode-card" data-mode="ship-it-save">
          <div class="mode-icon">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z"/><polyline points="17 21 17 13 7 13 7 21"/><polyline points="7 3 7 8 15 8"/></svg>
          </div>
          <h3>Save Progress</h3>
          <p>Push your work and create a draft PR. No reviewers, no deployment -- just save your spot.</p>
          <span class="mode-tag">Quick save</span>
        </div>
        <div class="ship-mode-card ${argoAvailable ? '' : 'mode-disabled'}" data-mode="argo-it" ${argoAvailable ? '' : 'title="kubectl not available in this container"'}>
          <div class="mode-icon">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><polyline points="7.5 4.21 12 6.81 16.5 4.21"/><polyline points="7.5 19.79 7.5 14.6 3 12"/><polyline points="21 12 16.5 14.6 16.5 19.79"/><polyline points="3.27 6.96 12 12.01 20.73 6.96"/><line x1="12" y1="22.08" x2="12" y2="12"/></svg>
          </div>
          <h3>Deploy to Kubernetes</h3>
          <p>Generate K8s manifests, Helm chart, and Argo CD pipeline. Full GitOps deployment.</p>
          <span class="mode-tag">${argoAvailable ? 'GitOps' : 'kubectl required'}</span>
        </div>
      </div>
      <div class="ship-back">
        <button class="btn-text" id="btnShipBack">&larr; Back to checks</button>
      </div>
    `;

    this.contentEl.querySelectorAll('.ship-mode-card:not(.mode-disabled)').forEach(card => {
      card.addEventListener('click', () => {
        this.mode = card.dataset.mode;
        this.startShipping();
      });
    });

    const backBtn = this.contentEl.querySelector('#btnShipBack');
    if (backBtn) backBtn.addEventListener('click', () => this.start(this.projectName));
  }

  /**
   * Start the actual shipping process via CLI bridge.
   */
  startShipping() {
    this.step = 'deploying';

    const modeConfig = {
      'ship-it': { label: 'Shipping for review...', description: 'Creating PR with security checks and CI/CD' },
      'ship-it-save': { label: 'Saving your progress...', description: 'Committing and pushing to a draft PR' },
      'argo-it': { label: 'Setting up Kubernetes deployment...', description: 'Generating manifests, Helm chart, and Argo CD pipeline' },
    };

    const config = modeConfig[this.mode] || { label: 'Shipping...', description: '' };

    this.contentEl.innerHTML = `
      <div class="ship-deploying">
        <div class="ship-progress-ring">
          <svg width="64" height="64" viewBox="0 0 64 64">
            <circle cx="32" cy="32" r="28" fill="none" stroke="var(--border)" stroke-width="4"/>
            <circle cx="32" cy="32" r="28" fill="none" stroke="var(--accent)" stroke-width="4"
              stroke-dasharray="176" stroke-dashoffset="176" stroke-linecap="round"
              class="ship-progress-circle"/>
          </svg>
        </div>
        <h2>${config.label}</h2>
        <p class="ship-subtitle">${config.description}</p>
        <div class="ship-activity-feed" id="shipActivityFeed"></div>
      </div>
    `;

    // Wire up activity listener to show real-time progress
    this._activityHandler = (msg) => {
      const feed = document.getElementById('shipActivityFeed');
      if (!feed) return;
      const entry = document.createElement('div');
      entry.className = 'ship-activity-entry';
      entry.textContent = msg.message || msg.text || '';
      feed.appendChild(entry);
      feed.scrollTop = feed.scrollHeight;
      // Keep only last 8 entries visible
      while (feed.children.length > 8) feed.removeChild(feed.firstChild);
    };
    window.cliBridge.on('activity', this._activityHandler);

    // Wire up completion listener
    this._completeHandler = (msg) => {
      window.cliBridge.off('activity', this._activityHandler);
      window.cliBridge.off('process-complete', this._completeHandler);
      window.cliBridge.off('question', this._questionHandler);
      if (msg.exitCode === 0) {
        this.complete({ url: msg.appUrl });
      } else {
        this.failed(msg.message);
      }
    };
    window.cliBridge.on('process-complete', this._completeHandler);

    // Wire up question handler (skill may ask questions during shipping)
    this._questionHandler = (msg) => {
      const feed = document.getElementById('shipActivityFeed');
      if (!feed) return;
      const entry = document.createElement('div');
      entry.className = 'ship-activity-entry ship-activity-question';
      entry.textContent = msg.text ? msg.text.substring(0, 200) : '';
      feed.appendChild(entry);
      feed.scrollTop = feed.scrollHeight;
    };
    window.cliBridge.on('question', this._questionHandler);

    // Trigger the actual skill
    if (this.mode === 'ship-it') {
      window.cliBridge.shipIt();
    } else if (this.mode === 'ship-it-save') {
      window.cliBridge.shipIt('save');
    } else if (this.mode === 'argo-it') {
      window.cliBridge.argoIt();
    }
  }

  /**
   * Show the completion screen.
   */
  complete(result) {
    this.step = 'done';

    const modeMessages = {
      'ship-it': 'Your PR has been created with security checks and reviewers assigned. The team will take it from here!',
      'ship-it-save': 'Your progress has been saved to a draft PR. Come back anytime to keep working.',
      'argo-it': 'Kubernetes manifests and Argo CD pipeline have been generated. Your PR is ready for DevOps review.',
    };

    this.contentEl.innerHTML = `
      <div class="ship-done">
        <div class="ship-done-icon">✓</div>
        <h2>${this.mode === 'ship-it-save' ? 'Progress Saved!' : 'Shipped!'}</h2>
        <p>${modeMessages[this.mode] || 'Your app has been shipped.'}</p>
        ${result && result.url ? `<a href="${result.url}" class="btn-primary" target="_blank">View PR</a>` : ''}
        <button class="btn-secondary" id="btnShipHome" style="margin-top: 1rem;">Back to Home</button>
      </div>
    `;

    const homeBtn = this.contentEl.querySelector('#btnShipHome');
    if (homeBtn) {
      homeBtn.addEventListener('click', () => {
        document.querySelector('.nav-btn[data-view="home"]').click();
      });
    }
  }

  /**
   * Show failure screen with option to retry.
   */
  failed(message) {
    this.step = 'readiness';

    this.contentEl.innerHTML = `
      <div class="ship-done">
        <div class="ship-done-icon ship-fail-icon">✗</div>
        <h2>Something went wrong</h2>
        <p>${message || 'The shipping process encountered an issue.'}</p>
        <div class="ship-fail-actions">
          <button class="btn-primary" id="btnShipRetry">Try Again</button>
          <button class="btn-secondary" id="btnShipHome">Back to Home</button>
        </div>
      </div>
    `;

    const retryBtn = this.contentEl.querySelector('#btnShipRetry');
    if (retryBtn) retryBtn.addEventListener('click', () => this.start(this.projectName));

    const homeBtn = this.contentEl.querySelector('#btnShipHome');
    if (homeBtn) {
      homeBtn.addEventListener('click', () => {
        document.querySelector('.nav-btn[data-view="home"]').click();
      });
    }
  }
}

// Global instance
window.ship = new ShipController('wizardContent');
