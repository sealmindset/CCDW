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
    appUrl: null,   // detected URL for the built app (for try-it embed)
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

  function updateSeeAppTag() {
    const btn = document.getElementById('btnSeeApp');
    if (!btn) return;
    btn.classList.remove('hidden');
    btn.classList.toggle('disabled', !state.appUrl);
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
    window.cliBridge.openProject(name);

    showView('chat');
    mainChat.clear();
    mainChat.addMessage('ai',
      `Welcome back to **${name}**! What would you like to do?`
    );
    mainChat.setWelcomeActions([
      { label: 'Add something new',            action: 'resume' },
      { label: 'Take a look at your creation', action: 'tryit'  },
      { label: "We're ready to go live",       action: 'ship'   },
    ], handleWelcomeAction);

    loadProjectStatus(name);
    setStatus('Ready', '');
  }

  function handleWelcomeAction(action) {
    switch (action) {
      case 'resume':
        mainChat.showStartupTips(state.projectName);
        mainChat.showTyping();
        setStatus('Resuming...', 'busy');
        window.cliBridge.startProject(state.projectName);
        break;

      case 'tryit':
        mainChat.addMessage('ai', 'Starting up your app so you can take a look...');
        mainChat.showTyping();
        setStatus('Starting app...', 'busy');
        window.cliBridge.tryIt();
        break;

      case 'ship':
        mainChat.addMessage('ai', "Let's get you live!");
        showView('ship');
        if (window.ship && window.ship.start) window.ship.start();
        break;
    }
  }

  /**
   * Resume working on an existing project.
   * Uses startProject which auto-detects /make-it vs /resume-it.
   */
  function resumeProject(name) {
    state.projectName = name;

    showView('chat');
    mainChat.clear();
    mainChat.showStartupTips(name);

    setStatus('Resuming...', 'busy');

    // startProject auto-detects: empty dir → /make-it, has code → /resume-it
    window.cliBridge.startProject(name);
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

      if (data.appPort) {
        state.appUrl = `http://${window.location.hostname}:${data.appPort}`;
        updateSeeAppTag();
      }

      window.dashboard.populateExplore(projectData);
    } catch (e) {
      window.dashboard.populateExplore({ name });
    }
  }

  // ============================================================
  // NEW PROJECT FLOW
  // ============================================================

  async function startNewProject() {
    setStatus('Checking environment...', 'busy');

    // Run preflight before showing the project dialog
    const ready = await runPreflightCheck();
    if (!ready) return; // Setup wizard is showing -- it will call startNewProject() again

    setStatus('Ready', '');
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
    mainChat.showStartupTips(name);

    setStatus('Starting project...', 'busy');

    // Start the project -- /make-it's response will be the first chat message
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
      updateBootstrapStep('ws', 'pass', 'Connected');
      bootstrapLog('WebSocket connected (session: ' + (bridge.sessionId || '?').slice(0, 8) + ')', 'ok');
    });

    bridge.on('disconnected', () => {
      setStatus('Reconnecting...', 'busy');
      // Don't show blocking overlay for brief disconnects -- just update status
      updateBootstrapStep('ws', 'checking', 'Reconnecting...');
      bootstrapLog('WebSocket disconnected, attempting reconnect...', 'warn');
    });

    bridge.on('reconnect-failed', () => {
      setStatus('Disconnected', 'error');
      showConnectionOverlay('Workshop lost its connection. Click retry or check the bootstrap panel (gear icon) for details.', true);
      updateBootstrapStep('ws', 'fail', 'Connection lost');
      bootstrapLog('WebSocket reconnect failed after 5 attempts', 'err');
    });

    bridge.on('phase-change', (msg) => {
      state.phase = msg.phase;
      updateBootstrapStep('skill', 'pass', msg.message || msg.phase);
      bootstrapLog('Phase: ' + msg.phase + ' -- ' + (msg.message || ''));

      // Map phases to Bifrost
      const bifrostPhases = {
        ideation: 'ideation',
        design: 'design',
        building: 'building',
        verifying: 'building',
        iterating: 'building',
        testing: 'building',
        complete: 'complete',
      };

      if (bifrostPhases[msg.phase]) {
        // If we're leaving chat phase, transition to build view
        if (msg.phase === 'design' || msg.phase === 'building' || msg.phase === 'iterating' || msg.phase === 'testing') {
          if (state.currentView === 'chat') {
            mainChat.stopTips();
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
      // During build, only interrupt for REAL questions (ones with quick replies
      // or that end with '?'). Long informational messages are NOT questions --
      // they just happen to be >200 chars and get classified as 'question' type.
      const isRealQuestion = msg.quickReplies || /\?\s*$/.test((msg.text || '').trim());

      if (state.currentView === 'build') {
        if (isRealQuestion) {
          // Actual question — switch to chat so user can answer
          showView('chat');
          mainChat.clear();
        } else {
          // Informational message during build — show as status, stay on build view
          const short = (msg.text || '').split('\n')[0].substring(0, 120);
          window.dashboard.setStatus(short);
          return;
        }
      }

      // Show question in chat
      if (state.currentView === 'chat') {
        mainChat.stopTips();
        mainChat.hideTyping();
        mainChat.clearStatus();
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
      bootstrapLog(msg.message);

      // In chat view: show as a muted status line (not a chat bubble)
      if (state.currentView === 'chat') {
        mainChat.setStatus(msg.message);
      }
    });

    bridge.on('process-complete', (msg) => {
      if (msg.phase === 'testing') {
        const url = msg.appUrl
          ? msg.appUrl.replace('localhost', window.location.hostname)
          : state.appUrl;

        if (url) { state.appUrl = url; updateSeeAppTag(); }

        if (state.currentView === 'chat' || state.currentView === 'build') {
          if (state.currentView === 'chat') {
            mainChat.hideTyping();
            mainChat.clearStatus();
          }
          window.bifrost.complete();
          setTimeout(() => {
            showView('explore');
            loadProjectStatus(state.projectName);
            if (url) window.dashboard.showEmbeddedApp(url);
          }, 600);
        } else if (url) {
          window.dashboard.showEmbeddedApp(url);
        }
        setStatus('App running', '');
      } else if (msg.phase === 'shipping') {
        setStatus('Shipped!', '');
        window.ship.complete(msg);
      } else if (msg.phase === 'iterating') {
        // Iterate change complete
        window.board.completeCurrent();
        iterateChat.hideTyping();
        iterateChat.addMessage('ai', msg.message || 'Done! The change has been applied.');
        setStatus('Ready', '');
      } else if (msg.phase === 'complete') {
        // Build fully finished
        window.bifrost.complete();
        window.dashboard.completeAll();
        window.dashboard.showTryIt();
        if (msg.appUrl) {
          state.appUrl = msg.appUrl.replace('localhost', window.location.hostname);
          updateSeeAppTag();
        }
        setStatus('Ready to explore!', '');
      } else if (msg.phase === 'ideation' || msg.phase === 'design') {
        // Paused during ideation/design (safety valve or waiting)
        if (state.currentView === 'chat') {
          mainChat.hideTyping();
          mainChat.clearStatus();
        }
        setStatus(msg.message || 'Waiting for your input', '');
      } else if (msg.phase === 'building' || msg.phase === 'verifying') {
        // Build paused (safety valve hit)
        if (state.currentView === 'build') {
          window.dashboard.setStatus(msg.message || 'Paused');
        }
        setStatus(msg.message || 'Paused', '');
      }
    });

    bridge.on('debug', (msg) => {
      const level = msg.source === 'stderr' ? 'warn' : 'info';
      bootstrapLog(`[${msg.source}] ${msg.message}`, level);
    });

    bridge.on('error', (msg) => {
      const errorMsg = msg?.message || 'Something went wrong.';
      bootstrapLog('Error: ' + errorMsg, 'err');

      // Show bug on Bifrost during build
      if (state.currentView === 'build') {
        window.bifrost.showBug();
        setTimeout(() => window.bifrost.defeatBug(), 2000);
      }

      // Show error in active chat with retry
      if (state.currentView === 'chat') {
        mainChat.stopTips();
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
    window.dashboard.reset();
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
      if (state.appUrl) {
        window.dashboard.showEmbeddedApp(state.appUrl);
      }
    });

    // Iterate button (from explore dashboard) — always starts fresh /resume-it
    document.getElementById('btnIterate').addEventListener('click', () => {
      if (state.projectName) {
        showView('chat');
        mainChat.clear();
        mainChat.addMessage('ai', `What would you like to change about **${state.projectName}**?`);
        setStatus('Ready', '');
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

    // "See your app" tag — opens the running app in a new tab
    document.getElementById('btnSeeApp').addEventListener('click', () => {
      if (state.appUrl) {
        window.open(state.appUrl, '_blank');
      }
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
      if (state.projectName && (!state.phase || state.phase === 'idle')) {
        mainChat.showTyping();
        setStatus('Working on it...', 'busy');
        window.cliBridge.startProject(state.projectName, text);
      } else {
        window.cliBridge.sendInput(text);
        mainChat.showTyping();
      }
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
    setupBootstrapPanel();
    setupCLIBridge();

    // Run preflight into bootstrap panel (don't block UI)
    runPreflightCheck().then(ready => {
      if (!ready) {
        // Don't show the setup overlay on load -- just mark the gear icon
        document.getElementById('setupOverlay').classList.add('hidden');
      }
    });

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
  // BOOTSTRAP PANEL + PREFLIGHT
  // ============================================================

  const bootstrapSteps = [
    { id: 'network',  label: 'Network / VPN',       detail: 'Checking connectivity...' },
    { id: 'auth',     label: 'AI Provider Login',    detail: 'Checking credentials...' },
    { id: 'cli',      label: 'Claude Code CLI',      detail: 'Checking installation...' },
    { id: 'ws',       label: 'WebSocket Connection',  detail: 'Waiting...' },
    { id: 'skill',    label: 'Skill Ready',           detail: 'Waiting...' },
  ];

  let bootstrapState = {}; // { stepId: { status, detail } }
  let bootstrapLogLines = [];

  function bootstrapLog(msg, level) {
    const time = new Date().toLocaleTimeString('en-US', { hour12: false });
    bootstrapLogLines.push({ time, msg, level: level || 'info' });
    if (bootstrapLogLines.length > 100) bootstrapLogLines.shift();
    renderBootstrapLog();
  }

  function updateBootstrapStep(id, status, detail) {
    bootstrapState[id] = { status, detail };
    renderBootstrapSequence();

    // Update the header icon -- show red dot if any step fails
    const btn = document.getElementById('btnBootstrap');
    const hasFail = Object.values(bootstrapState).some(s => s.status === 'fail');
    btn.classList.toggle('has-issue', hasFail);
  }

  function renderBootstrapSequence() {
    const el = document.getElementById('bootstrapSequence');
    el.innerHTML = bootstrapSteps.map(step => {
      const s = bootstrapState[step.id] || { status: 'pending', detail: step.detail };
      const iconMap = { pass: '\u2713', fail: '\u2717', checking: '\u2026', pending: '\u2022' };
      const icon = iconMap[s.status] || '\u2022';

      let actionHtml = '';
      if (s.status === 'fail') {
        if (step.id === 'auth' || step.id === 'network') {
          actionHtml = `<span class="bootstrap-step-action" onclick="window.open('http://${window.location.hostname}:7681','_blank')">Open Terminal</span>`;
        }
      }

      return `<div class="bootstrap-step">
        <div class="bootstrap-step-icon ${s.status}">${icon}</div>
        <div class="bootstrap-step-body">
          <div class="bootstrap-step-label">${step.label}</div>
          <div class="bootstrap-step-detail">${s.detail}</div>
          ${actionHtml}
        </div>
        <div class="bootstrap-step-connector"></div>
      </div>`;
    }).join('');
  }

  function renderBootstrapLog() {
    const el = document.getElementById('bootstrapLogEntries');
    if (!el) return;
    el.innerHTML = bootstrapLogLines.map(entry =>
      `<div class="bootstrap-log-entry ${entry.level === 'ok' ? 'log-ok' : entry.level === 'err' ? 'log-err' : entry.level === 'warn' ? 'log-warn' : ''}">` +
      `<span class="log-time">${entry.time}</span>${entry.msg}</div>`
    ).join('');
    el.scrollTop = el.scrollHeight;
  }

  /**
   * Run preflight checks, update bootstrap panel, and return readiness.
   */
  async function runPreflightCheck() {
    // Mark all as checking
    ['network', 'auth', 'cli'].forEach(id => updateBootstrapStep(id, 'checking', 'Checking...'));
    bootstrapLog('Running preflight checks...');

    try {
      const res = await fetch('/api/preflight');
      const data = await res.json();

      // Update each step
      for (const [key, check] of Object.entries(data.checks)) {
        updateBootstrapStep(key, check.pass ? 'pass' : 'fail', check.detail);
        bootstrapLog(`${check.label}: ${check.pass ? 'OK' : 'FAILED'} -- ${check.detail}`, check.pass ? 'ok' : 'err');
      }

      if (!data.ready) {
        // Show setup wizard for failing steps
        const overlay = document.getElementById('setupOverlay');
        const checksEl = document.getElementById('setupChecks');
        const stepsEl = document.getElementById('setupSteps');

        renderSetupChecks(data, checksEl);
        renderSetupSteps(data.steps, stepsEl);
        overlay.classList.remove('hidden');
        bootstrapLog('Environment not ready -- showing setup wizard', 'warn');
        return false;
      }

      bootstrapLog('All preflight checks passed', 'ok');
      document.getElementById('setupOverlay').classList.add('hidden');
      return true;

    } catch (e) {
      updateBootstrapStep('network', 'fail', 'Cannot reach Workshop server');
      bootstrapLog('Failed to reach /api/preflight: ' + e.message, 'err');
      return false;
    }
  }

  function renderSetupChecks(data, checksEl) {
    const order = ['network', 'auth', 'cli'];
    checksEl.innerHTML = order.map(key => {
      const check = data.checks[key];
      if (!check) return '';
      return `<div class="setup-check">
        <div class="setup-check-icon ${check.pass ? 'pass' : 'fail'}">${check.pass ? '\u2713' : '\u2717'}</div>
        <span class="setup-check-label">${check.label}</span>
        <span class="setup-check-detail">${check.detail}</span>
      </div>`;
    }).join('');
  }

  function renderSetupSteps(steps, stepsEl) {
    if (!steps || steps.length === 0) {
      stepsEl.classList.add('hidden');
      return;
    }
    stepsEl.classList.remove('hidden');
    stepsEl.innerHTML = '<div style="font-size:0.8rem;font-weight:600;color:var(--text-muted);text-transform:uppercase;letter-spacing:0.05em;margin-bottom:0.5rem;">What to do</div>' +
      steps.map((step, i) => `<div class="setup-step">
        <span class="setup-step-num">${i + 1}.</span>
        <span>${step.instruction}</span>
      </div>`).join('');
  }

  function setupBootstrapPanel() {
    // Toggle panel
    document.getElementById('btnBootstrap').addEventListener('click', () => {
      document.getElementById('bootstrapPanel').classList.toggle('hidden');
    });
    document.getElementById('btnCloseBootstrap').addEventListener('click', () => {
      document.getElementById('bootstrapPanel').classList.add('hidden');
    });

    // Recheck button
    document.getElementById('btnBootstrapRefresh').addEventListener('click', async () => {
      const ready = await runPreflightCheck();
      if (ready) bootstrapLog('Environment ready!', 'ok');
    });

    // Terminal button
    document.getElementById('btnBootstrapTerminal').addEventListener('click', () => {
      window.open(`http://${window.location.hostname}:7681`, '_blank');
    });

    // Setup wizard buttons
    document.getElementById('btnSetupTerminal').addEventListener('click', () => {
      window.open(`http://${window.location.hostname}:7681`, '_blank');
    });
    document.getElementById('btnSetupRecheck').addEventListener('click', async () => {
      const ready = await runPreflightCheck();
      if (ready) {
        document.getElementById('setupOverlay').classList.add('hidden');
        startNewProject();
      }
    });

    // Initial render
    renderBootstrapSequence();
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
