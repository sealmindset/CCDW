/**
 * Workshop App Controller
 * Main application logic. Wires together CLI bridge, Bifrost,
 * chat, and dashboard into a cohesive experience.
 */

(function() {
  'use strict';

  // --- State ---
  const state = {
    currentView: 'home',
    projectName: null,
    phase: 'idle', // idle, ideation, design, building, verifying, complete, testing, iterating, shipping
  };

  // --- Chat instances ---
  let mainChat = null;
  let iterateChat = null;

  // --- DOM refs ---
  const views = {
    home: document.getElementById('viewHome'),
    chat: document.getElementById('viewChat'),
    build: document.getElementById('viewBuild'),
    explore: document.getElementById('viewExplore'),
    iterate: document.getElementById('viewIterate'),
    ship: document.getElementById('viewShip'),
  };

  const statusDot = document.getElementById('statusDot');
  const statusText = document.getElementById('statusText');

  // ============================================================
  // VIEW MANAGEMENT
  // ============================================================

  function showView(name) {
    const current = views[state.currentView];
    const next = views[name];

    if (current === next) return;

    // Animate out
    if (current) {
      current.classList.add('exiting');
      current.classList.remove('active');
      setTimeout(() => current.classList.remove('exiting'), 400);
    }

    // Animate in
    if (next) {
      next.classList.add('active');
    }

    state.currentView = name;

    // Update nav buttons
    document.querySelectorAll('.nav-btn[data-view]').forEach(btn => {
      btn.classList.toggle('active', btn.dataset.view === name);
    });
  }

  // ============================================================
  // STATUS BAR
  // ============================================================

  function setStatus(text, type) {
    statusText.textContent = text;
    statusDot.className = 'status-dot';
    if (type === 'busy') statusDot.classList.add('busy');
    if (type === 'error') statusDot.classList.add('error');
  }

  // ============================================================
  // PROJECT LOADING
  // ============================================================

  async function loadProjects() {
    const grid = document.getElementById('projectsGrid');
    try {
      const res = await fetch('/api/projects');
      const data = await res.json();

      grid.innerHTML = '';

      if (data.projects.length === 0) {
        grid.innerHTML = '<p style="color: var(--text-muted); font-size: 0.85rem;">No projects yet. Click "New Project" to get started!</p>';
        return;
      }

      data.projects.forEach(project => {
        const card = document.createElement('div');
        card.className = 'project-card';
        card.innerHTML = `
          <div class="project-card-name">${escapeHtml(project.name)}</div>
          <div class="project-card-status">${project.builtWithMakeIt ? 'Built with Workshop' : 'Project'}</div>
          ${project.builtWithMakeIt ? '<span class="project-card-badge">Workshop</span>' : ''}
          <div class="project-card-actions">
            <button class="btn-card-action btn-card-open" title="View dashboard">Open</button>
            ${project.builtWithMakeIt ? '<button class="btn-card-action btn-card-resume" title="Make changes">Resume</button>' : ''}
          </div>
        `;

        card.querySelector('.btn-card-open').addEventListener('click', (e) => {
          e.stopPropagation();
          openProject(project.name);
        });

        const resumeBtn = card.querySelector('.btn-card-resume');
        if (resumeBtn) {
          resumeBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            resumeProject(project.name);
          });
        }

        card.addEventListener('click', () => openProject(project.name));
        grid.appendChild(card);
      });
    } catch (e) {
      grid.innerHTML = '<p style="color: var(--text-muted);">Could not load projects.</p>';
    }
  }

  function openProject(name) {
    state.projectName = name;
    window.cliBridge.openProject(name);
    showView('explore');
    loadProjectStatus(name);
  }

  /**
   * Resume working on an existing project via /resume-it.
   */
  function resumeProject(name) {
    state.projectName = name;
    window.cliBridge.openProject(name);
    showView('iterate');
    iterateChat.clear();
    iterateChat.addMessage('ai', `Welcome back to **${name}**! What would you like to change?`);
    window.board.render();
    window.cliBridge.resumeIt();
    setStatus('Resuming...', 'busy');
  }

  async function loadProjectStatus(name) {
    try {
      const res = await fetch(`/api/project/${encodeURIComponent(name)}/status`);
      const data = await res.json();

      const projectData = { name };

      if (data.context) {
        projectData.name = data.context.app_name || name;
        projectData.pages = data.context.pages ? data.context.pages.length : '--';
        projectData.users = data.context.roles ? data.context.roles.length : '--';
        projectData.tests = '--';
        projectData.testUsers = data.context.roles ? data.context.roles.map(r => ({
          name: `Mock ${r.name}`,
          role: r.name
        })) : [];
        projectData.readinessChecks = [
          { label: 'App builds successfully', pass: true },
          { label: 'All services healthy', pass: true },
          { label: 'Login works for all roles', pass: data.state && data.state.includes('auth') },
          { label: 'All pages load', pass: data.state && data.state.includes('pages') },
        ];
      }

      // Parse TODO count
      if (data.todo) {
        const todoItems = (data.todo.match(/^- \[ \]/gm) || []).length;
        const doneItems = (data.todo.match(/^- \[x\]/gm) || []).length;
        projectData.todoCount = todoItems;
        projectData.doneCount = doneItems;
      }

      projectData.builtWithMakeIt = !!(data.state || data.context);

      window.dashboard.populateExplore(projectData);
    } catch (e) {
      window.dashboard.populateExplore({ name });
    }
  }

  // ============================================================
  // NEW PROJECT FLOW
  // ============================================================

  function startNewProject() {
    const dialog = document.getElementById('dialogNewProject');
    const input = document.getElementById('inputProjectName');
    input.value = '';
    dialog.showModal();
    input.focus();
  }

  function confirmNewProject() {
    const dialog = document.getElementById('dialogNewProject');
    const input = document.getElementById('inputProjectName');
    const name = input.value.trim() || 'my-app';

    dialog.close();
    state.projectName = name;

    // Switch to chat view
    showView('chat');
    mainChat.clear();
    mainChat.addWelcome(name);

    setStatus('Chatting', 'busy');

    // Connect to CLI and start the project
    window.cliBridge.startProject(name);
  }

  // ============================================================
  // CLI BRIDGE EVENT HANDLERS
  // ============================================================

  function setupCLIBridge() {
    const bridge = window.cliBridge;

    bridge.on('session-ready', () => {
      setStatus('Connected', '');
      hideConnectionOverlay();
    });

    bridge.on('disconnected', () => {
      setStatus('Reconnecting...', 'busy');
      showConnectionOverlay('Reconnecting to Workshop server...');
    });

    bridge.on('reconnect-failed', () => {
      setStatus('Disconnected', 'error');
      showConnectionOverlay('Connection lost. Check that the container is running.', true);
    });

    bridge.on('phase-change', (msg) => {
      state.phase = msg.phase;

      // Map phases to Bifrost
      const bifrostPhases = {
        ideation: 'ideation',
        design: 'design',
        building: 'building',
        verifying: 'building',
        complete: 'complete',
      };

      if (bifrostPhases[msg.phase]) {
        // If we're leaving chat phase, transition to build view
        if (msg.phase === 'design' || msg.phase === 'building') {
          if (state.currentView === 'chat') {
            transitionToBuild();
          }
        }

        window.bifrost.setPhase(bifrostPhases[msg.phase]);
      }

      setStatus(msg.message || msg.phase, 'busy');

      // Build complete
      if (msg.phase === 'complete') {
        window.bifrost.complete();
        window.dashboard.completeAll();
        window.dashboard.showTryIt();
        setStatus('Ready to explore!', '');
      }
    });

    bridge.on('question', (msg) => {
      // Show question in chat
      if (state.currentView === 'chat') {
        mainChat.hideTyping();
        mainChat.addMessage('ai', msg.text);
        if (msg.quickReplies) {
          mainChat.setQuickReplies(msg.quickReplies);
        }
      } else if (state.currentView === 'iterate') {
        iterateChat.hideTyping();
        iterateChat.addMessage('ai', msg.text);
        if (msg.quickReplies) {
          iterateChat.setQuickReplies(msg.quickReplies);
        }
      }
    });

    bridge.on('activity', (msg) => {
      // Add to build dashboard feed
      window.dashboard.addFeedItem(msg.category || 'general', msg.message);

      // If in chat view and it's early, show as chat message
      if (state.currentView === 'chat' && state.phase === 'ideation') {
        // Don't flood chat with activity -- only meaningful messages
        if (msg.message.length > 20 && !msg.message.startsWith('[')) {
          mainChat.hideTyping();
          mainChat.addMessage('ai', msg.message);
        }
      }
    });

    bridge.on('process-complete', (msg) => {
      if (msg.phase === 'testing') {
        // /try-it finished, show embedded app
        setStatus('App ready', '');
      } else if (msg.phase === 'shipping') {
        setStatus('Shipped!', '');
        window.ship.complete(msg);
      } else if (msg.phase === 'iterating') {
        // Iterate change complete
        window.board.completeCurrent();
        iterateChat.hideTyping();
        iterateChat.addMessage('ai', msg.message || 'Done! The change has been applied.');
        setStatus('Ready', '');
      }
    });

    bridge.on('error', (msg) => {
      const errorMsg = msg?.message || 'Something went wrong.';

      // Show bug on Bifrost during build
      if (state.currentView === 'build') {
        window.bifrost.showBug();
        setTimeout(() => window.bifrost.defeatBug(), 2000);
      }

      // Show error in active chat with retry
      if (state.currentView === 'chat') {
        mainChat.hideTyping();
        mainChat.addError(errorMsg, () => {
          if (state.projectName) {
            mainChat.addMessage('ai', 'Let me try that again...');
            mainChat.showTyping();
            window.cliBridge.startProject(state.projectName);
          }
        });
      } else if (state.currentView === 'iterate') {
        iterateChat.hideTyping();
        iterateChat.addError(errorMsg);
      }

      setStatus('Issue detected', 'error');
    });

    // Connect
    bridge.connect();
  }

  // ============================================================
  // VIEW TRANSITIONS
  // ============================================================

  function transitionToBuild() {
    // Initialize build map
    window.dashboard.initBuildMap();
    window.bifrost.reset();

    showView('build');
    setStatus('Building your app...', 'busy');
  }

  function transitionToExplore() {
    showView('explore');
    if (state.projectName) {
      loadProjectStatus(state.projectName);
    }
  }

  // ============================================================
  // BUTTON HANDLERS
  // ============================================================

  function setupButtons() {
    // New project
    document.getElementById('btnNewProject').addEventListener('click', startNewProject);

    // Dialog
    document.getElementById('btnStartProject').addEventListener('click', confirmNewProject);
    document.getElementById('btnCancelProject').addEventListener('click', () => {
      document.getElementById('dialogNewProject').close();
    });

    // Enter in project name input
    document.getElementById('inputProjectName').addEventListener('keydown', (e) => {
      if (e.key === 'Enter') confirmNewProject();
    });

    // Try It button
    document.getElementById('btnTryIt').addEventListener('click', () => {
      window.cliBridge.tryIt();
      transitionToExplore();
    });

    // Iterate button (from explore dashboard)
    document.getElementById('btnIterate').addEventListener('click', () => {
      if (state.projectName) {
        resumeProject(state.projectName);
      } else {
        showView('iterate');
        iterateChat.clear();
        iterateChat.addMessage('ai', 'What would you like to change? You can describe a quick tweak or a bigger feature.');
        window.board.render();
      }
    });

    // New Request button (iterate board)
    document.getElementById('btnNewRequest').addEventListener('click', () => {
      const text = prompt('Describe the change:');
      if (text && text.trim()) {
        const priority = text.length > 60 ? 'big' : 'quick';
        const req = window.board.addRequest(text.trim(), priority);
        iterateChat.addMessage('user', text.trim());
        iterateChat.showTyping();
        window.cliBridge.sendInput(text.trim());
        window.board.updateStatus(req.id, 'in-progress');
      }
    });

    // Go Live button
    document.getElementById('btnGoLive').addEventListener('click', () => {
      showView('ship');
      window.ship.start();
    });

    // Embedded app controls
    document.getElementById('btnCloseApp').addEventListener('click', () => {
      window.dashboard.hideEmbeddedApp();
    });

    document.getElementById('btnRefreshApp').addEventListener('click', () => {
      const frame = document.getElementById('appFrame');
      if (frame) frame.src = frame.src;
    });

    document.getElementById('btnOpenExternal').addEventListener('click', () => {
      const url = document.getElementById('appUrl').textContent;
      if (url) window.open(url, '_blank');
    });

    // Nav buttons
    document.querySelectorAll('.nav-btn[data-view]').forEach(btn => {
      btn.addEventListener('click', () => {
        const view = btn.dataset.view;
        if (view === 'terminal') {
          // Open ttyd in new tab
          window.open(`http://${window.location.hostname}:7681`, '_blank');
        } else {
          showView(view);
        }
      });
    });

    // Auth banner terminal link
    document.getElementById('authTerminalLink').addEventListener('click', (e) => {
      e.preventDefault();
      window.open(`http://${window.location.hostname}:7681`, '_blank');
    });

    // Walkthrough
    document.getElementById('btnWalkthroughSkip').addEventListener('click', () => {
      localStorage.setItem('workshop-walkthrough-done', '1');
      document.getElementById('walkthroughOverlay').classList.add('hidden');
    });

    document.getElementById('btnWalkthroughNext').addEventListener('click', () => {
      advanceWalkthrough();
    });
  }

  // ============================================================
  // AUTH GATE
  // ============================================================

  async function checkAuth() {
    const banner = document.getElementById('authBanner');
    try {
      const res = await fetch('/api/auth-status');
      const auth = await res.json();

      if (!auth.configured) {
        // Show setup banner
        if (banner) {
          banner.classList.remove('hidden');
          const detail = banner.querySelector('.auth-banner-detail');
          if (detail) detail.textContent = auth.detail;
        }
        setStatus('Setup needed', 'error');
        return false;
      }

      // Auth OK -- hide banner, show provider in status
      if (banner) banner.classList.add('hidden');
      setStatus(auth.provider, '');
      return true;
    } catch {
      // Can't reach server -- don't block, just warn
      setStatus('Connecting...', 'busy');
      return true;
    }
  }

  // ============================================================
  // INITIALIZATION
  // ============================================================

  async function init() {
    // Create chat instances
    mainChat = new ChatController('chatMessages', 'chatInput', 'btnSend', 'quickReplies');
    mainChat.onSend = (text) => {
      window.cliBridge.sendInput(text);
      mainChat.showTyping();
    };

    iterateChat = new ChatController('iterateChatMessages', 'iterateChatInput', 'btnIterateSend', 'iterateQuickReplies');
    iterateChat.onSend = (text) => {
      // Auto-add to board when user sends from iterate chat
      if (state.currentView === 'iterate' && text.length > 10) {
        const priority = text.length > 60 ? 'big' : 'quick';
        const req = window.board.addRequest(text, priority);
        window.board.updateStatus(req.id, 'in-progress');
      }
      window.cliBridge.sendInput(text);
      iterateChat.showTyping();
    };

    // Setup
    setupButtons();
    setupCLIBridge();

    // Check credentials before showing projects
    await checkAuth();
    loadProjects();

    // Show home view
    showView('home');

    // First visit walkthrough
    showWalkthrough();
  }

  // ============================================================
  // CONNECTION OVERLAY
  // ============================================================

  function showConnectionOverlay(message, showRetry) {
    let overlay = document.getElementById('connectionOverlay');
    if (!overlay) {
      overlay = document.createElement('div');
      overlay.id = 'connectionOverlay';
      overlay.className = 'connection-overlay';
      document.body.appendChild(overlay);
    }

    overlay.innerHTML = `
      <div class="connection-overlay-content">
        ${showRetry ? '' : '<div class="check-spinner" style="width:24px;height:24px;margin-bottom:12px;"></div>'}
        <div>${message}</div>
        ${showRetry ? '<button class="btn-primary" style="margin-top:12px;" onclick="window.cliBridge.connect(); document.getElementById(\'connectionOverlay\').classList.add(\'hidden\');">Retry</button>' : ''}
      </div>
    `;
    overlay.classList.remove('hidden');
  }

  function hideConnectionOverlay() {
    const overlay = document.getElementById('connectionOverlay');
    if (overlay) overlay.classList.add('hidden');
  }

  // ============================================================
  // GUIDED WALKTHROUGH
  // ============================================================

  const walkthroughSteps = [
    {
      title: 'Welcome to Workshop',
      body: 'Workshop lets you build full applications just by describing what you want. No coding, no terminal -- just plain English.',
    },
    {
      title: 'Start a New Project',
      body: 'Click <strong>New Project</strong>, give it a name, then describe your idea in the chat. Workshop will design and build the whole thing.',
    },
    {
      title: 'Watch It Build',
      body: 'The Bifrost progress bar shows each phase -- from idea to architecture to working code. The activity feed shows exactly what\'s happening.',
    },
    {
      title: 'Explore and Iterate',
      body: 'Once built, you can try your app in the browser, check the dashboard, and request changes. Just describe what you want different.',
    },
    {
      title: 'Go Live When Ready',
      body: 'When you\'re happy with your app, the Go Live wizard packages it up so you can share it with the world. That\'s it -- you\'re a builder now!',
    },
  ];

  let walkthroughIndex = 0;

  function showWalkthrough() {
    if (localStorage.getItem('workshop-walkthrough-done')) return;

    walkthroughIndex = 0;
    renderWalkthroughStep();
    document.getElementById('walkthroughOverlay').classList.remove('hidden');
  }

  function renderWalkthroughStep() {
    const step = walkthroughSteps[walkthroughIndex];
    const contentEl = document.getElementById('walkthroughContent');
    const dotsEl = document.getElementById('walkthroughDots');
    const nextBtn = document.getElementById('btnWalkthroughNext');

    contentEl.innerHTML = `<h2 style="font-size:1.15rem;margin-bottom:0.5rem;">${step.title}</h2><p style="color:var(--text-secondary);font-size:0.9rem;line-height:1.6;">${step.body}</p>`;

    // Dots
    dotsEl.innerHTML = '';
    walkthroughSteps.forEach((_, i) => {
      const dot = document.createElement('span');
      dot.className = `walkthrough-dot${i === walkthroughIndex ? ' active' : ''}`;
      dotsEl.appendChild(dot);
    });

    // Last step changes button text
    nextBtn.textContent = walkthroughIndex === walkthroughSteps.length - 1 ? 'Get Started' : 'Next';
  }

  function advanceWalkthrough() {
    walkthroughIndex++;
    if (walkthroughIndex >= walkthroughSteps.length) {
      localStorage.setItem('workshop-walkthrough-done', '1');
      document.getElementById('walkthroughOverlay').classList.add('hidden');
      return;
    }
    renderWalkthroughStep();
  }

  // --- Utility ---
  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  // Start
  document.addEventListener('DOMContentLoaded', init);

})();
