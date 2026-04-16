/**
 * Dashboard Controller
 * Manages the build dashboard (activity feed + build map),
 * explore dashboard, and project management.
 */

class DashboardController {
  constructor() {
    this.feedEl = document.getElementById('feedItems');
    this.mapEl = document.getElementById('mapCards');
    this.buildCompleteEl = document.getElementById('buildComplete');
    this.feedItems = [];
    this.buildComponents = [];
  }

  /**
   * Initialize the build map with expected components.
   */
  initBuildMap(components) {
    this.buildComponents = components || [
      'Database', 'Authentication', 'Permissions',
      'Dashboard', 'API Routes', 'Admin Panel',
      'Settings', 'Activity Logs', 'Tests', 'Docker'
    ];

    this.mapEl.innerHTML = '';
    this.buildComponents.forEach(name => {
      const card = document.createElement('div');
      card.className = 'map-card';
      card.textContent = name;
      card.dataset.component = name.toLowerCase().replace(/\s+/g, '-');
      this.mapEl.appendChild(card);
    });
  }

  /**
   * Add an item to the activity feed.
   */
  addFeedItem(category, message) {
    const item = document.createElement('div');
    item.className = 'feed-item';

    const dot = document.createElement('span');
    dot.className = `feed-category ${category}`;

    item.appendChild(dot);
    item.appendChild(document.createTextNode(message));

    // Prepend (newest first)
    this.feedEl.prepend(item);

    // Keep feed manageable
    while (this.feedEl.children.length > 50) {
      this.feedEl.lastChild.remove();
    }

    // Try to mark matching build map card
    this.detectComponentProgress(message);
  }

  /**
   * Detect if an activity message relates to a build component.
   */
  detectComponentProgress(message) {
    const lower = message.toLowerCase();
    const mappings = {
      'database': ['database', 'migration', 'seed', 'table', 'postgresql'],
      'authentication': ['auth', 'oidc', 'login', 'jwt', 'cookie'],
      'permissions': ['permission', 'rbac', 'role', 'admin.users'],
      'dashboard': ['dashboard', 'home page', 'main page'],
      'api-routes': ['api', 'endpoint', 'route', 'router'],
      'admin-panel': ['admin', 'user management', 'role management'],
      'settings': ['settings', 'app_settings', 'configuration'],
      'activity-logs': ['activity', 'log', 'logstore', 'circular buffer'],
      'tests': ['test', 'pytest', 'playwright', 'verify'],
      'docker': ['docker', 'compose', 'container', 'dockerfile'],
    };

    for (const [component, keywords] of Object.entries(mappings)) {
      if (keywords.some(kw => lower.includes(kw))) {
        this.markComponent(component, 'in-progress');
      }
    }
  }

  /**
   * Mark a build map card as in-progress or complete.
   */
  markComponent(componentId, status) {
    const card = this.mapEl.querySelector(`[data-component="${componentId}"]`);
    if (!card) return;

    if (status === 'complete') {
      card.classList.remove('in-progress');
      card.classList.add('complete');
    } else if (status === 'in-progress' && !card.classList.contains('complete')) {
      card.classList.add('in-progress');
    }
  }

  /**
   * Mark all components as complete.
   */
  completeAll() {
    this.mapEl.querySelectorAll('.map-card').forEach(card => {
      card.classList.remove('in-progress');
      card.classList.add('complete');
    });
  }

  /**
   * Show the "Try It" button.
   */
  showTryIt() {
    this.buildCompleteEl.classList.remove('hidden');
  }

  /**
   * Clear the feed and reset the build map.
   */
  reset() {
    this.feedEl.innerHTML = '';
    this.mapEl.querySelectorAll('.map-card').forEach(card => {
      card.classList.remove('in-progress', 'complete');
    });
    this.buildCompleteEl.classList.add('hidden');
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

    // Stats
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
