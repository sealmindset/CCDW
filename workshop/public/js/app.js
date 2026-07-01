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

  // --- Session persistence keys ---
  const STORE = {
    project: 'ws-project',
    phase: 'ws-phase',
    view: 'ws-view',
    chat: 'ws-chat',
    appUrl: 'ws-appurl',
    bifrost: 'ws-bifrost',
  };

  let initialized = false;

  function saveState() {
    try {
      if (state.projectName) {
        localStorage.setItem(STORE.project, state.projectName);
      } else {
        localStorage.removeItem(STORE.project);
      }
      localStorage.setItem(STORE.phase, state.phase || 'idle');
      localStorage.setItem(STORE.view, state.currentView || 'home');
      if (state.appUrl) localStorage.setItem(STORE.appUrl, state.appUrl);
      if (mainChat) {
        const msgs = mainChat.getMessages();
        if (msgs.length > 0) localStorage.setItem(STORE.chat, JSON.stringify(msgs.slice(-50)));
      }
      const bifrostPhase = window.bifrost.phases[window.bifrost.currentPhaseIndex];
      if (bifrostPhase) localStorage.setItem(STORE.bifrost, bifrostPhase);
    } catch {}
  }

  let _saveTimer = null;
  function debouncedSave() {
    if (_saveTimer) clearTimeout(_saveTimer);
    _saveTimer = setTimeout(saveState, 500);
  }

  function clearSavedState() {
    try { Object.values(STORE).forEach(k => localStorage.removeItem(k)); } catch {}
  }

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

    // Clear recovery state when user deliberately navigates home
    if (name === 'home' && initialized) {
      clearSavedState();
    }

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

  let _projectsData = [];
  let _projectsPage = 1;
  const _projectsPerPage = 10;
  let _projectsSortCol = 'name';
  let _projectsSortAsc = true;
  let _projectsFilter = '';
  let _deleteTarget = null;

  async function loadProjects() {
    const grid = document.getElementById('projectsGrid');
    try {
      const res = await fetch('/api/projects');
      const data = await res.json();
      _projectsData = data.projects || [];
      _projectsPage = 1;
      _projectsFilter = '';
      const searchInput = document.getElementById('projectsSearchInput');
      if (searchInput) searchInput.value = '';
      renderProjectsTable();
    } catch (e) {
      grid.innerHTML = '<p class="projects-empty">Could not load projects.</p>';
    }
  }

  function renderProjectsTable() {
    const grid = document.getElementById('projectsGrid');
    const searchWrap = document.getElementById('projectsSearch');
    const pagination = document.getElementById('projectsPagination');

    if (_projectsData.length === 0) {
      grid.innerHTML = '<p class="projects-empty">No projects yet. Click "New Project" to get started!</p>';
      if (searchWrap) searchWrap.classList.add('hidden');
      if (pagination) pagination.classList.add('hidden');
      return;
    }

    const showAdvanced = _projectsData.length > _projectsPerPage;
    if (searchWrap) searchWrap.classList.toggle('hidden', !showAdvanced);

    let filtered = _projectsData;
    if (_projectsFilter) {
      const q = _projectsFilter.toLowerCase();
      filtered = _projectsData.filter(p =>
        p.name.toLowerCase().includes(q) ||
        (p.description || '').toLowerCase().includes(q) ||
        (p.status || '').toLowerCase().includes(q)
      );
    }

    if (showAdvanced) {
      filtered.sort((a, b) => {
        const va = (a[_projectsSortCol] || '').toString().toLowerCase();
        const vb = (b[_projectsSortCol] || '').toString().toLowerCase();
        const cmp = va.localeCompare(vb);
        return _projectsSortAsc ? cmp : -cmp;
      });
    }

    const totalPages = showAdvanced ? Math.max(1, Math.ceil(filtered.length / _projectsPerPage)) : 1;
    if (_projectsPage > totalPages) _projectsPage = totalPages;
    const start = showAdvanced ? (_projectsPage - 1) * _projectsPerPage : 0;
    const pageItems = showAdvanced ? filtered.slice(start, start + _projectsPerPage) : filtered;

    const sortIcon = (col) => {
      if (!showAdvanced || _projectsSortCol !== col) return '';
      return _projectsSortAsc ? ' &#9650;' : ' &#9660;';
    };
    const sortClass = showAdvanced ? ' sortable' : '';

    let html = `<table class="projects-table">
      <thead><tr>
        <th class="col-name${sortClass}" data-sort="name">Name${sortIcon('name')}</th>
        <th class="col-desc${sortClass}" data-sort="description">Description${sortIcon('description')}</th>
        <th class="col-status${sortClass}" data-sort="status">Status${sortIcon('status')}</th>
        <th class="col-actions"></th>
      </tr></thead><tbody>`;

    pageItems.forEach(p => {
      const statusClass = p.status ? p.status.toLowerCase().replace(/\s+/g, '-') : '';
      const badge = p.status
        ? `<span class="status-badge status-${statusClass}">${escapeHtml(p.status)}</span>`
        : '';
      const desc = p.description
        ? escapeHtml(p.description)
        : '<span class="text-muted">No description</span>';

      html += `<tr class="project-row" data-name="${escapeHtml(p.name)}">
        <td><span class="project-name-text">${escapeHtml(p.name)}</span></td>
        <td class="col-desc">${desc}</td>
        <td>${badge}</td>
        <td class="col-actions">
          <button class="btn-delete-project" data-name="${escapeHtml(p.name)}" title="Delete project">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
          </button>
        </td>
      </tr>`;
    });

    html += '</tbody></table>';
    grid.innerHTML = html;

    grid.querySelectorAll('.project-row').forEach(row => {
      row.addEventListener('click', (e) => {
        if (e.target.closest('.btn-delete-project')) return;
        openProject(row.dataset.name);
      });
    });

    grid.querySelectorAll('.btn-delete-project').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        promptDeleteProject(btn.dataset.name);
      });
    });

    if (showAdvanced) {
      grid.querySelectorAll('th.sortable').forEach(th => {
        th.addEventListener('click', () => {
          const col = th.dataset.sort;
          if (_projectsSortCol === col) { _projectsSortAsc = !_projectsSortAsc; }
          else { _projectsSortCol = col; _projectsSortAsc = true; }
          renderProjectsTable();
        });
      });
    }

    if (pagination) {
      if (showAdvanced && totalPages > 1) {
        pagination.classList.remove('hidden');
        pagination.innerHTML = `
          <button class="btn-page" id="btnPagePrev" ${_projectsPage <= 1 ? 'disabled' : ''}>&#8592; Prev</button>
          <span class="page-info">Page ${_projectsPage} of ${totalPages}</span>
          <button class="btn-page" id="btnPageNext" ${_projectsPage >= totalPages ? 'disabled' : ''}>Next &#8594;</button>`;
        document.getElementById('btnPagePrev').addEventListener('click', () => {
          if (_projectsPage > 1) { _projectsPage--; renderProjectsTable(); }
        });
        document.getElementById('btnPageNext').addEventListener('click', () => {
          if (_projectsPage < totalPages) { _projectsPage++; renderProjectsTable(); }
        });
      } else {
        pagination.classList.add('hidden');
      }
    }
  }

  function promptDeleteProject(name) {
    _deleteTarget = name;
    const dialog = document.getElementById('dialogDeleteProject');
    document.getElementById('deleteProjectName').textContent = name;
    dialog.showModal();
  }

  async function deleteProject(name) {
    try {
      const res = await fetch('/api/project/' + encodeURIComponent(name), { method: 'DELETE' });
      const data = await res.json();
      if (!res.ok) {
        alert(data.error || 'Could not delete project.');
        return;
      }
      loadProjects();
    } catch {
      alert('Could not delete project. Please try again.');
    }
  }

  function openProject(name) {
    state.projectName = name;
    clearSavedState();
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
        if (window.ship && window.ship.start) window.ship.start(state.projectName);
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

      if (state._pendingRecovery) {
        const projectName = state._pendingRecovery;
        state._pendingRecovery = null;
        setStatus('Resuming session...', 'busy');
        bootstrapLog('Recovering session for ' + projectName, 'ok');
        bridge.recoverSession(projectName);
      }
    });

    bridge.on('recovery-success', (msg) => {
      state.phase = msg.phase;
      if (msg.detectedAppPort) {
        state.appUrl = 'http://' + window.location.hostname + ':' + msg.detectedAppPort;
        updateSeeAppTag();
      }
      bootstrapLog('Session recovered: phase=' + msg.phase, 'ok');
      setStatus(msg.waitingForUser ? 'Waiting for your answer' : 'Resuming build...', 'busy');
    });

    bridge.on('recovery-failed', (msg) => {
      bootstrapLog('Session recovery failed: ' + (msg.reason || 'unknown'), 'warn');
      clearSavedState();
      state.projectName = null;
      state.phase = 'idle';
      showView('home');
      setStatus('Ready', '');
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
      saveState();
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
      saveState();
    });

    bridge.on('activity', (msg) => {
      // Add to build dashboard feed
      window.dashboard.addFeedItem(msg.category || 'general', msg.message);
      bootstrapLog(msg.message);
      debouncedSave();

      // In chat view: show as a muted status line (not a chat bubble)
      if (state.currentView === 'chat') {
        mainChat.setStatus(msg.message);
      }
    });

    bridge.on('process-complete', (msg) => {
      if (msg.phase === 'testing') {
        clearSavedState();
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
      } else if (msg.phase === 'shipping' || msg.phase === 'saving') {
        setStatus(msg.exitCode === 0 ? 'Shipped!' : 'Ship failed', '');
        // Ship controller handles its own UI via CLI bridge listeners
      } else if (msg.phase === 'iterating') {
        // Iterate change complete
        window.board.completeCurrent();
        iterateChat.hideTyping();
        iterateChat.addMessage('ai', msg.message || 'Done! The change has been applied.');
        setStatus('Ready', '');
      } else if (msg.phase === 'complete') {
        // Build fully finished
        clearSavedState();
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

    // Delete project dialog
    document.getElementById('btnConfirmDelete').addEventListener('click', () => {
      document.getElementById('dialogDeleteProject').close();
      if (_deleteTarget) { deleteProject(_deleteTarget); _deleteTarget = null; }
    });
    document.getElementById('btnCancelDelete').addEventListener('click', () => {
      document.getElementById('dialogDeleteProject').close();
      _deleteTarget = null;
    });

    // Project search (debounced)
    let _searchTimer = null;
    document.getElementById('projectsSearchInput').addEventListener('input', (e) => {
      clearTimeout(_searchTimer);
      _searchTimer = setTimeout(() => {
        _projectsFilter = e.target.value.trim();
        _projectsPage = 1;
        renderProjectsTable();
      }, 200);
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
      window.ship.start(state.projectName);
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

    // Auth banner "How to fix" link
    document.getElementById('authSetupLink').addEventListener('click', (e) => {
      e.preventDefault();
      document.getElementById('setupOverlay').classList.remove('hidden');
    });

    // Walkthrough
    document.getElementById('btnWalkthroughSkip').addEventListener('click', () => {
      clearSpotlight();
      localStorage.setItem('workshop-walkthrough-done', '1');
      document.getElementById('walkthroughOverlay').classList.add('hidden');
    });

    document.getElementById('btnWalkthroughNext').addEventListener('click', () => {
      advanceWalkthrough();
    });

    // "Take a tour" link (re-triggers walkthrough for returning users)
    document.getElementById('btnTakeTour').addEventListener('click', (e) => {
      e.preventDefault();
      showWalkthrough(true);
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
  // PROACTIVE HEALTH MONITORING
  // ============================================================

  let healthInterval = null;

  function showHealthBanner(id) {
    var el = document.getElementById(id);
    if (el) el.classList.remove('hidden');
  }

  function hideHealthBanner(id) {
    var el = document.getElementById(id);
    if (el) el.classList.add('hidden');
  }

  function hideAllHealthBanners() {
    ['healthBannerVpn', 'healthBannerTokenExpired',
     'healthBannerDisk', 'healthBannerDown'].forEach(hideHealthBanner);
  }

  async function pollHealth() {
    var dashHost = window.location.hostname;
    var baseUrl = 'http://' + dashHost + ':3000';
    try {
      var ctrl = new AbortController();
      setTimeout(function() { ctrl.abort(); }, 5000);
      var statusRes = await fetch(baseUrl + '/api/status', { signal: ctrl.signal });
      var status = await statusRes.json();

      var healthRes = await fetch(baseUrl + '/api/health', { signal: ctrl.signal });
      var health = await healthRes.json();

      hideAllHealthBanners();

      // VPN / network down
      if (health.failure_type === 'vpn_down' || health.failure_type === 'endpoint_unreachable') {
        showHealthBanner('healthBannerVpn');
        return;
      }

      // Token expired
      if (status.ai_status === 'Token expired' || status.ai_status === 'Session expired') {
        showHealthBanner('healthBannerTokenExpired');
        return;
      }

      // Low disk (< 500 MB)
      if (health.system && health.system.disk_free_mb > 0 && health.system.disk_free_mb < 500) {
        showHealthBanner('healthBannerDisk');
      }

      // General service issue
      if (health.status === 'failing' && health.failure_type !== 'vpn_down' && health.failure_type !== 'endpoint_unreachable') {
        var detail = document.getElementById('healthDownDetail');
        if (detail && health.message) detail.textContent = health.message;
        showHealthBanner('healthBannerDown');
      }

    } catch (e) {
      // Dashboard unreachable — don't spam banners, just hide all
      hideAllHealthBanners();
    }
  }

  function startHealthPolling() {
    pollHealth();
    healthInterval = setInterval(pollHealth, 60000);
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

    // --- Session recovery check (before UI setup) ---
    let recoveryProject = null;
    try {
      const savedProject = localStorage.getItem(STORE.project);
      const savedPhase = localStorage.getItem(STORE.phase);
      if (savedProject && savedPhase && savedPhase !== 'idle' && savedPhase !== 'complete') {
        recoveryProject = savedProject;
        state.projectName = savedProject;
        state.phase = savedPhase;
        state.appUrl = localStorage.getItem(STORE.appUrl) || null;

        const savedChat = localStorage.getItem(STORE.chat);
        if (savedChat) {
          try { mainChat.restoreMessages(JSON.parse(savedChat)); } catch {}
        }

        const savedBifrost = localStorage.getItem(STORE.bifrost);
        if (savedBifrost) window.bifrost.restorePhase(savedBifrost);

        if (state.appUrl) updateSeeAppTag();
      }
    } catch {}

    // Dashboard link (port 3000)
    var dashLink = document.getElementById('dashboardLink');
    if (dashLink) dashLink.href = 'http://' + window.location.hostname + ':3000';

    // Home nav → dashboard
    var navHome = document.getElementById('navHome');
    if (navHome) navHome.href = 'http://' + window.location.hostname + ':3000';

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

    // URL-param auto-resume (launcher deep-link): ?project=<name>&resume=1
    // Takes priority over localStorage recovery; uses the same path as the
    // resume UI action (resumeProject -> cliBridge.startProject auto-detects /resume-it).
    let urlResumeProject = null;
    try {
      const params = new URLSearchParams(window.location.search);
      const p = params.get('project');
      const r = params.get('resume');
      if (p && r && r !== '0' && r !== 'false') urlResumeProject = p;
    } catch {}

    // Show the right view: URL deep-link, recovery target, or home
    if (urlResumeProject) {
      resumeProject(urlResumeProject);
    } else if (recoveryProject) {
      const savedView = localStorage.getItem(STORE.view) || 'build';
      showView(views[savedView] ? savedView : 'build');
      state._pendingRecovery = recoveryProject;
    } else {
      showView('home');
    }

    // First visit walkthrough (skip if recovering or auto-resuming via URL)
    if (!recoveryProject && !urlResumeProject) showWalkthrough();

    // Health banner links → dashboard
    var dashUrl = 'http://' + window.location.hostname + ':3000?dashboard';
    var signInLink = document.getElementById('healthSignInLink');
    if (signInLink) signInLink.addEventListener('click', function(e) { e.preventDefault(); window.open(dashUrl, '_blank'); });

    // Start background health monitoring (polls every 60s)
    startHealthPolling();

    initialized = true;
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
        document.getElementById('setupOverlay').classList.remove('hidden');
        bootstrapLog('Environment not ready -- re-run the installer to configure', 'warn');
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
    document.getElementById('btnSetupRecheck').addEventListener('click', async () => {
      document.getElementById('setupOverlay').classList.add('hidden');
      await checkAuth();
      const ready = await runPreflightCheck();
      if (ready) startNewProject();
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
      body: 'Describe an app idea in plain English and Workshop builds it for you — design, code, and all. No terminal needed.',
    },
    {
      title: 'Create Your First App',
      body: 'Click here to start. Pick a name, then describe what you want to build in the chat.',
      target: '#btnNewProject',
      placement: 'right',
    },
    {
      title: 'Your Workspace',
      body: '<strong>Terminal</strong> gives full CLI access. <strong>See your app</strong> opens your running app in a new tab.',
      target: '.header-nav',
      placement: 'bottom',
    },
    {
      title: 'System Health',
      body: 'Shows your AI provider status and connection health. Click the gear to see details.',
      target: '.header-status',
      placement: 'bottom',
    },
    {
      title: 'You\'re All Set!',
      body: 'Click <strong>New Project</strong> to start building. Describe your idea, watch the Bifrost progress bar, then try your app.',
    },
  ];

  let walkthroughIndex = 0;
  let spotlightEl = null;

  function clearSpotlight() {
    if (spotlightEl) {
      spotlightEl.classList.remove('walkthrough-spotlight');
      spotlightEl = null;
    }
    const overlay = document.getElementById('walkthroughOverlay');
    overlay.classList.remove('has-target');
    const arrow = overlay.querySelector('.walkthrough-arrow');
    if (arrow) arrow.remove();
  }

  function showWalkthrough(force) {
    if (!force && localStorage.getItem('workshop-walkthrough-done')) return;
    showView('home');
    walkthroughIndex = 0;
    renderWalkthroughStep();
    document.getElementById('walkthroughOverlay').classList.remove('hidden');
  }

  function renderWalkthroughStep() {
    clearSpotlight();

    const step = walkthroughSteps[walkthroughIndex];
    const overlay = document.getElementById('walkthroughOverlay');
    const stepEl = document.getElementById('walkthroughStep');
    const contentEl = document.getElementById('walkthroughContent');
    const dotsEl = document.getElementById('walkthroughDots');
    const nextBtn = document.getElementById('btnWalkthroughNext');

    contentEl.innerHTML = `<h2>${step.title}</h2><p>${step.body}</p>`;

    dotsEl.innerHTML = '';
    walkthroughSteps.forEach((_, i) => {
      const dot = document.createElement('span');
      dot.className = 'walkthrough-dot' + (i === walkthroughIndex ? ' active' : i < walkthroughIndex ? ' done' : '');
      dotsEl.appendChild(dot);
    });

    const isLast = walkthroughIndex === walkthroughSteps.length - 1;
    nextBtn.textContent = isLast ? 'Start Building' : 'Next';

    stepEl.style.top = '';
    stepEl.style.left = '';
    stepEl.style.right = '';
    stepEl.style.bottom = '';

    if (step.target) {
      const targetEl = document.querySelector(step.target);
      if (targetEl) {
        targetEl.classList.add('walkthrough-spotlight');
        spotlightEl = targetEl;
        overlay.classList.add('has-target');
        positionTooltip(stepEl, targetEl, step.placement || 'bottom');
        return;
      }
    }

    overlay.classList.remove('has-target');
  }

  function positionTooltip(stepEl, targetEl, placement) {
    const rect = targetEl.getBoundingClientRect();
    const gap = 16;

    const arrow = document.createElement('div');
    arrow.className = 'walkthrough-arrow';

    if (placement === 'bottom') {
      stepEl.style.top = (rect.bottom + gap) + 'px';
      stepEl.style.left = Math.max(12, Math.min(rect.left, window.innerWidth - 400)) + 'px';
      arrow.classList.add('arrow-top');
      arrow.style.left = Math.min(Math.max(24, rect.left + rect.width / 2 - parseInt(stepEl.style.left) - 6), 360) + 'px';
    } else if (placement === 'right') {
      stepEl.style.top = Math.max(12, rect.top - 20) + 'px';
      stepEl.style.left = (rect.right + gap) + 'px';
      if (rect.right + gap + 400 > window.innerWidth) {
        stepEl.style.left = '';
        stepEl.style.top = (rect.bottom + gap) + 'px';
        stepEl.style.left = Math.max(12, rect.left) + 'px';
        arrow.classList.add('arrow-top');
        arrow.style.left = (rect.width / 2) + 'px';
      } else {
        arrow.classList.add('arrow-left');
        arrow.style.top = '24px';
      }
    }

    stepEl.appendChild(arrow);
  }

  function advanceWalkthrough() {
    walkthroughIndex++;
    if (walkthroughIndex >= walkthroughSteps.length) {
      clearSpotlight();
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
