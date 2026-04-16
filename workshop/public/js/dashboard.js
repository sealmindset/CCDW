/**
 * Dashboard Controller
 * Manages the build status display (component label + status line),
 * explore dashboard, and project management.
 */

class DashboardController {
  constructor() {
    this.componentLabelEl = document.getElementById('buildComponentLabel');
    this.statusTextEl = document.getElementById('buildStatusText');
    this.buildCompleteEl = document.getElementById('buildComplete');
  }

  /**
   * Set the component label above Bifrost (what's being built).
   * e.g. "Setting up Authentication" or "Building the Dashboard"
   */
  setComponent(text) {
    if (this.componentLabelEl) {
      this.componentLabelEl.textContent = text;
    }
  }

  /**
   * Update the single status line below Bifrost.
   * Overwrites in place — always shows only the latest.
   */
  setStatus(text) {
    if (this.statusTextEl) {
      this.statusTextEl.textContent = text;
    }
  }

  /**
   * Process an activity message — detect component and update display.
   */
  addFeedItem(category, message) {
    // Update the status line (overwrites previous)
    this.setStatus(message);

    // Detect component from message and update the label
    const component = this.detectComponent(message);
    if (component) {
      this.setComponent(component);
    }
  }

  /**
   * Detect what app component is being worked on from an activity message.
   */
  detectComponent(message) {
    const lower = message.toLowerCase();
    const mappings = [
      { keywords: ['database', 'migration', 'seed', 'table', 'postgresql', 'alembic'], label: 'Setting up the Database' },
      { keywords: ['auth', 'oidc', 'login', 'jwt', 'cookie', 'session'], label: 'Building Authentication' },
      { keywords: ['permission', 'rbac', 'role', 'admin.users'], label: 'Configuring Permissions' },
      { keywords: ['dashboard', 'home page', 'main page', 'landing'], label: 'Building the Dashboard' },
      { keywords: ['api', 'endpoint', 'route', 'router'], label: 'Setting up API Routes' },
      { keywords: ['admin', 'user management', 'role management'], label: 'Building the Admin Panel' },
      { keywords: ['settings', 'app_settings', 'configuration'], label: 'Adding Settings' },
      { keywords: ['notification', 'bell', 'alert'], label: 'Adding Notifications' },
      { keywords: ['activity', 'log', 'logstore', 'audit'], label: 'Setting up Activity Logs' },
      { keywords: ['test', 'pytest', 'playwright', 'verify', 'smoke'], label: 'Running Tests' },
      { keywords: ['docker', 'compose', 'container', 'dockerfile'], label: 'Configuring Docker' },
      { keywords: ['frontend', 'react', 'next', 'component', 'page.tsx'], label: 'Building the Frontend' },
      { keywords: ['backend', 'fastapi', 'express', 'server'], label: 'Building the Backend' },
      { keywords: ['install', 'dependencies', 'npm', 'pip'], label: 'Installing Dependencies' },
    ];

    for (const { keywords, label } of mappings) {
      if (keywords.some(kw => lower.includes(kw))) {
        return label;
      }
    }
    return null;
  }

  /**
   * Mark all as complete.
   */
  completeAll() {
    this.setComponent('All done!');
    this.setStatus('');
  }

  /**
   * Show the "Try It" button.
   */
  showTryIt() {
    if (this.buildCompleteEl) {
      this.buildCompleteEl.classList.remove('hidden');
    }
  }

  /**
   * Clear status and reset.
   */
  reset() {
    this.setComponent('');
    this.setStatus('');
    if (this.buildCompleteEl) {
      this.buildCompleteEl.classList.add('hidden');
    }
  }

  // --- Explore Dashboard ---

  /**
   * Populate the explore dashboard with project data.
   */
  populateExplore(projectData) {
    if (!projectData) return;

    const title = document.getElementById('projectTitle');
    if (title && projectData.name) {
      title.textContent = projectData.name;
    }

    const setStatSafe = (id, value) => {
      const el = document.getElementById(id);
      if (el) el.textContent = value;
    };

    setStatSafe('statHealth', 'Healthy');
    setStatSafe('statPages', projectData.pages || '--');
    setStatSafe('statUsers', projectData.users || '--');
    setStatSafe('statTests', projectData.tests || '--');

    // Test users
    const usersList = document.getElementById('usersList');
    if (usersList && projectData.testUsers) {
      usersList.innerHTML = '';
      projectData.testUsers.forEach(user => {
        const card = document.createElement('div');
        card.className = 'user-card';

        const avatar = document.createElement('div');
        avatar.className = 'user-avatar';
        avatar.textContent = user.name.charAt(0).toUpperCase();

        const info = document.createElement('span');
        info.textContent = `${user.name} (${user.role})`;

        card.appendChild(avatar);
        card.appendChild(info);
        usersList.appendChild(card);
      });
    }

    // Readiness
    const readiness = document.getElementById('readinessItems');
    if (readiness && projectData.readinessChecks) {
      readiness.innerHTML = '';
      projectData.readinessChecks.forEach(check => {
        const item = document.createElement('div');
        item.className = 'readiness-item';

        const box = document.createElement('div');
        box.className = `readiness-check ${check.pass ? 'pass' : 'fail'}`;
        if (check.pass) box.textContent = '\u2713';

        const label = document.createElement('span');
        label.textContent = check.label;

        item.appendChild(box);
        item.appendChild(label);
        readiness.appendChild(item);
      });
    }
  }

  /**
   * Show the embedded app iframe.
   */
  showEmbeddedApp(url) {
    const appPanel = document.getElementById('exploreApp');
    const frame = document.getElementById('appFrame');
    const urlDisplay = document.getElementById('appUrl');

    if (appPanel && frame) {
      frame.src = url;
      if (urlDisplay) urlDisplay.textContent = url;
      appPanel.classList.remove('hidden');
    }
  }

  /**
   * Hide the embedded app.
   */
  hideEmbeddedApp() {
    const appPanel = document.getElementById('exploreApp');
    if (appPanel) appPanel.classList.add('hidden');
  }
}

// Global instance
window.dashboard = new DashboardController();
