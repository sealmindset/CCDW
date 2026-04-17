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
   * Populate the simplified explore header with project data.
   */
  populateExplore(projectData) {
    if (!projectData) return;

    const title = document.getElementById('projectTitle');
    if (title && projectData.name) {
      title.textContent = projectData.name;
    }

    const set = (id, value) => {
      const el = document.getElementById(id);
      if (el) el.textContent = value;
    };

    set('summaryHealth', 'Healthy');
    if (projectData.pages && projectData.pages !== '--') {
      set('summaryPages', projectData.pages + ' pages');
    }
    if (projectData.users && projectData.users !== '--') {
      set('summaryUsers', projectData.users + ' roles');
    }
  }

  /**
   * Show the embedded app iframe with the given URL.
   */
  showEmbeddedApp(url) {
    const frame = document.getElementById('appFrame');
    const urlDisplay = document.getElementById('appUrl');

    if (frame) {
      frame.src = url;
    }
    if (urlDisplay) {
      urlDisplay.textContent = url;
    }
  }
}

// Global instance
window.dashboard = new DashboardController();
