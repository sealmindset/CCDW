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
        `;
        card.addEventListener('click', () => openProject(project.name));
        grid.appendChild(card);
      });
    } catch (e) {
      grid.innerHTML = '<p style="color: var(--text-muted);">Could not load projects.</p>';
    }
  }

  function openProject(name) {
    state.projectName = name;
    // For existing projects, go to explore view
    showView('explore');
    loadProjectStatus(name);
  }

  async function loadProjectStatus(name) {
    try {
      const res = await fetch(`/api/project/${encodeURIComponent(name)}/status`);
      const data = await res.json();

      if (data.context) {
        window.dashboard.populateExplore({
          name: data.context.app_name || name,
          pages: data.context.pages ? data.context.pages.length : '--',
          users: data.context.roles ? data.context.roles.length : '--',
          tests: '--',
          testUsers: data.context.roles ? data.context.roles.map(r => ({
            name: `Mock ${r.name}`,
            role: r.name
          })) : [],
          readinessChecks: [
            { label: 'App builds successfully', pass: true },
            { label: 'All services healthy', pass: true },
            { label: 'Login works for all roles', pass: data.state && data.state.includes('auth') },
            { label: 'All pages load', pass: data.state && data.state.includes('pages') },
          ]
        });
      } else {
        window.dashboard.populateExplore({ name });
      }
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
    });

    bridge.on('disconnected', () => {
      setStatus('Reconnecting...', 'busy');
    });

    bridge.on('reconnect-failed', () => {
      setStatus('Disconnected', 'error');
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
      // Show bug on Bifrost
      if (state.currentView === 'build') {
        window.bifrost.showBug();
        setTimeout(() => window.bifrost.defeatBug(), 2000);
      }
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

    // Iterate button
    document.getElementById('btnIterate').addEventListener('click', () => {
      showView('iterate');
      iterateChat.clear();
      iterateChat.addMessage('ai', 'What would you like to change? You can describe a quick tweak or a bigger feature.');
      window.board.render();
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

    // Walkthrough
    document.getElementById('btnWalkthroughSkip').addEventListener('click', () => {
      document.getElementById('walkthroughOverlay').classList.add('hidden');
    });

    document.getElementById('btnWalkthroughNext').addEventListener('click', () => {
      document.getElementById('walkthroughOverlay').classList.add('hidden');
    });
  }

  // ============================================================
  // INITIALIZATION
  // ============================================================

  function init() {
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
    loadProjects();

    // Show home view
    showView('home');
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
