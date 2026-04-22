/**
 * Setup Module Frontend
 * AI Provider configuration wizard for Claude Code Docker.
 * Works standalone at /setup.html and embedded via iframe.
 */
(function () {
  'use strict';

  let providerDefs = {};
  let providerStatus = {};  // { claudeCode: { active, providers: {} }, appDev: { providers: {} } }
  let activePanel = null;

  const STEPS = ['prereqs', 'credentials', 'test'];

  const PROVIDER_ICONS = {
    anthropic: 'A',
    'azure-foundry': 'Az',
    bedrock: 'B',
    openai: 'O',
    'azure-openai': 'AO',
  };

  if (window.self !== window.top) {
    document.addEventListener('DOMContentLoaded', function () {
      document.getElementById('setupPage').classList.add('embedded');
    });
  }

  // -----------------------------------------------------------------------
  // Init
  // -----------------------------------------------------------------------
  document.addEventListener('DOMContentLoaded', async function () {
    await loadDefinitions();
    await refreshStatus();
    renderCards();

    document.getElementById('btnCloseConfig').addEventListener('click', closePanel);
    document.getElementById('configBackdrop').addEventListener('click', closePanel);

    document.getElementById('configFooter').addEventListener('click', function (e) {
      var btn = e.target.closest('button');
      if (!btn || !activePanel) return;
      var action = btn.dataset.action;
      if (!action) return;

      switch (action) {
        case 'cancel': closePanel(); break;
        case 'next': showStep(activePanel.step + 1); break;
        case 'back': showStep(activePanel.step - 1); break;
        case 'test': saveAndTest(); break;
        case 'retry': saveAndTest(); break;
        case 'done':
        case 'keep':
          closePanel();
          refreshStatus().then(function () { renderCards(); notifyParent(); });
          break;
      }
    });
  });

  async function loadDefinitions() {
    try {
      var res = await fetch('/api/providers/definitions');
      providerDefs = await res.json();
    } catch (e) {
      providerDefs = {};
    }
  }

  async function refreshStatus() {
    try {
      var res = await fetch('/api/providers');
      providerStatus = await res.json();
    } catch (e) {
      providerStatus = { claudeCode: { active: null, providers: {} }, appDev: { providers: {} } };
    }
    renderStatusSummary();
    updateBadges();
  }

  // -----------------------------------------------------------------------
  // Status Summary
  // -----------------------------------------------------------------------
  function renderStatusSummary() {
    var el = document.getElementById('statusSummary');
    var chips = [];

    var cc = providerStatus.claudeCode || {};
    if (cc.active) {
      var ccDef = providerDefs[cc.active];
      chips.push(chip('green', 'Claude Code: ' + (ccDef ? ccDef.name : cc.active)));
    } else {
      chips.push(chip('gray', 'Claude Code: not configured'));
    }

    var adProviders = (providerStatus.appDev || {}).providers || {};
    for (var id in adProviders) {
      if (adProviders[id].configured) {
        var def = providerDefs[id];
        chips.push(chip('green', (def ? def.name : id) + ': ready'));
      }
    }

    el.innerHTML = chips.join('');
  }

  function chip(color, text) {
    return '<div class="status-chip"><span class="status-chip-dot ' + color + '"></span>' + esc(text) + '</div>';
  }

  function updateBadges() {
    var ccBadge = document.getElementById('badgeClaudeCode');
    var adBadge = document.getElementById('badgeAppDev');

    var cc = providerStatus.claudeCode || {};
    if (cc.active) {
      ccBadge.textContent = 'configured';
      ccBadge.classList.add('active');
    } else {
      ccBadge.textContent = 'pick one';
      ccBadge.classList.remove('active');
    }

    var adProviders = (providerStatus.appDev || {}).providers || {};
    var count = 0;
    for (var id in adProviders) { if (adProviders[id].configured) count++; }

    if (count > 0) {
      adBadge.textContent = count + ' configured';
      adBadge.classList.add('active');
    } else {
      adBadge.textContent = 'optional';
      adBadge.classList.remove('active');
    }
  }

  // -----------------------------------------------------------------------
  // Provider Cards
  // -----------------------------------------------------------------------
  function renderCards() {
    var ccGrid = document.getElementById('gridClaudeCode');
    var adGrid = document.getElementById('gridAppDev');
    ccGrid.innerHTML = '';
    adGrid.innerHTML = '';

    for (var id in providerDefs) {
      var def = providerDefs[id];
      var card = makeCard(id, def);
      if (def.category === 'claudeCode') {
        ccGrid.appendChild(card);
      } else {
        adGrid.appendChild(card);
      }
    }
  }

  function makeCard(id, def) {
    var div = document.createElement('div');
    div.className = 'provider-card';
    div.dataset.provider = id;

    var isConfigured = false;
    if (def.category === 'claudeCode') {
      var cc = providerStatus.claudeCode || {};
      isConfigured = cc.active === id;
    } else {
      var adProviders = (providerStatus.appDev || {}).providers || {};
      isConfigured = !!(adProviders[id] && adProviders[id].configured);
    }

    if (isConfigured) div.classList.add('configured');

    div.innerHTML =
      '<div class="provider-card-status ' + (isConfigured ? 'configured' : '') + '"></div>' +
      '<div class="provider-card-icon ' + id + '">' + (PROVIDER_ICONS[id] || '?') + '</div>' +
      '<div class="provider-card-name">' + esc(def.name) + '</div>' +
      '<div class="provider-card-desc">' + esc(def.description) + '</div>';

    div.addEventListener('click', function () { openPanel(id, def.category); });
    return div;
  }

  // -----------------------------------------------------------------------
  // Config Panel
  // -----------------------------------------------------------------------
  function openPanel(providerId, category) {
    var def = providerDefs[providerId];
    if (!def) return;

    activePanel = {
      providerId: providerId,
      category: category,
      step: 0,
      config: {},
      prereqResults: null,
      testResult: null,
    };

    document.querySelectorAll('.provider-card').forEach(function (c) { c.classList.remove('selected'); });
    var card = document.querySelector('.provider-card[data-provider="' + providerId + '"]');
    if (card) card.classList.add('selected');

    document.getElementById('configTitle').textContent = def.name;
    document.getElementById('configBackdrop').classList.add('visible');
    document.getElementById('configPanel').classList.add('open');

    renderStepDots();
    showStep(0);
  }

  function closePanel() {
    document.getElementById('configBackdrop').classList.remove('visible');
    document.getElementById('configPanel').classList.remove('open');
    document.querySelectorAll('.provider-card').forEach(function (c) { c.classList.remove('selected'); });
    activePanel = null;
  }

  // -----------------------------------------------------------------------
  // Step Navigation
  // -----------------------------------------------------------------------
  function renderStepDots() {
    var el = document.getElementById('configSteps');
    el.innerHTML = STEPS.map(function (s, i) {
      var labels = { prereqs: 'Prerequisites', credentials: 'Credentials', test: 'Test' };
      return '<div class="config-step-dot ' + (i === 0 ? 'active' : '') + '" data-step="' + i + '" title="' + labels[s] + '"></div>';
    }).join('');
  }

  function updateStepDots() {
    if (!activePanel) return;
    document.querySelectorAll('.config-step-dot').forEach(function (dot, i) {
      dot.classList.toggle('active', i === activePanel.step);
      dot.classList.toggle('done', i < activePanel.step);
    });
  }

  function showStep(stepIndex) {
    if (!activePanel) return;
    activePanel.step = stepIndex;
    updateStepDots();

    var body = document.getElementById('configBody');
    var footer = document.getElementById('configFooter');

    switch (STEPS[stepIndex]) {
      case 'prereqs': renderPrereqs(body, footer); break;
      case 'credentials': renderCredentials(body, footer); break;
      case 'test': break; // driven by saveAndTest()
    }
  }

  // -----------------------------------------------------------------------
  // Step 1: Prerequisites
  // -----------------------------------------------------------------------
  async function renderPrereqs(body, footer) {
    var def = providerDefs[activePanel.providerId];

    if (!def.prereqs || def.prereqs.length === 0) {
      body.innerHTML = '<p style="color:var(--text-secondary)">No prerequisites needed. Ready to configure.</p>';
      footer.innerHTML = footerBtn('primary', 'Next', 'next');
      return;
    }

    body.innerHTML =
      '<p style="color:var(--text-secondary);font-size:0.85rem;margin-bottom:var(--space-md)">Checking requirements...</p>' +
      '<div class="prereq-list" id="prereqList">' +
      def.prereqs.map(function (p) {
        return '<div class="prereq-item" data-prereq="' + esc(p.id) + '">' +
          '<div class="prereq-icon checking"></div>' +
          '<div class="prereq-text">' +
          '<div class="prereq-name">' + esc(p.label) + '</div>' +
          '<div class="prereq-detail">Checking...</div>' +
          '</div></div>';
      }).join('') +
      '</div>';

    footer.innerHTML = footerBtn('secondary', 'Cancel', 'cancel') + footerBtn('primary', 'Next', 'next', true);

    try {
      var res = await fetch('/api/providers/check-prereqs', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ providerId: activePanel.providerId }),
      });
      var result = await res.json();
      activePanel.prereqResults = result;

      // result = { checks: [...], allPass: bool }
      var checks = result.checks || [];
      var allPass = result.allPass !== false;

      checks.forEach(function (r) {
        var item = document.querySelector('.prereq-item[data-prereq="' + r.id + '"]');
        if (!item) return;
        var icon = item.querySelector('.prereq-icon');
        var detail = item.querySelector('.prereq-detail');
        icon.classList.remove('checking');
        icon.classList.add(r.pass ? 'pass' : 'fail');
        icon.textContent = r.pass ? '✓' : '✗';
        detail.textContent = r.detail;
      });

      footer.innerHTML = footerBtn('secondary', 'Cancel', 'cancel') + footerBtn('primary', 'Next', 'next', !allPass);

      var msg = body.querySelector('p');
      if (allPass) {
        msg.textContent = 'All prerequisites met.';
      } else {
        msg.textContent = 'Some requirements are not met. Install them and recheck.';
      }
    } catch (err) {
      body.querySelector('p').textContent = 'Could not check prerequisites: ' + err.message;
    }
  }

  // -----------------------------------------------------------------------
  // Step 2: Credentials
  // -----------------------------------------------------------------------
  function renderCredentials(body, footer) {
    var def = providerDefs[activePanel.providerId];
    var fields = def.fields || [];
    var html = '';

    // Auth mode toggle for Azure Foundry
    if (activePanel.providerId === 'azure-foundry') {
      var mode = activePanel.config.authMode || 'sso';
      html += '<div class="auth-mode-toggle">' +
        '<button class="auth-mode-btn ' + (mode === 'sso' ? 'active' : '') + '" data-mode="sso">Azure SSO</button>' +
        '<button class="auth-mode-btn ' + (mode === 'apikey' ? 'active' : '') + '" data-mode="apikey">API Key</button>' +
        '</div>';
    }

    // Render fields (use 'key' as the field identifier from backend)
    fields.forEach(function (f) {
      // Skip authMode field (handled by toggle above)
      if (f.key === 'authMode') return;

      // Skip fields based on auth mode for Azure Foundry
      if (activePanel.providerId === 'azure-foundry') {
        var authMode = activePanel.config.authMode || 'sso';
        if (f.showWhen) {
          if (f.showWhen.field === 'authMode' && f.showWhen.value !== authMode) return;
        }
      }

      var val = activePanel.config[f.key] || f.default || '';
      var type = (f.type === 'password') ? 'password' : (f.type === 'url' ? 'url' : 'text');
      html += '<div class="config-field">' +
        '<label for="field-' + f.key + '">' + esc(f.label) + '</label>' +
        (f.hint ? '<span class="field-hint">' + esc(f.hint) + '</span>' : '') +
        '<input type="' + type + '" id="field-' + f.key + '" data-field="' + f.key + '"' +
        ' value="' + esc(val) + '" placeholder="' + esc(f.placeholder || '') + '">' +
        '</div>';
    });

    // Model fields (modelFields array from backend, separate from models)
    var modelFields = def.modelFields || [];
    if (modelFields.length > 0) {
      html += '<div class="config-field"><label>Model Deployments</label><div class="model-list">';
      modelFields.forEach(function (m) {
        var val = activePanel.config[m.key] || m.default || '';
        html += '<div class="model-item">' +
          '<span class="model-label">' + esc(m.label) + '</span>' +
          '<input type="text" data-field="' + m.key + '" value="' + esc(val) + '" placeholder="' + esc(m.placeholder || m.default || '') + '">' +
          '</div>';
      });
      html += '</div></div>';
    }

    // SSO login button for Azure Foundry SSO mode
    if (activePanel.providerId === 'azure-foundry' && (activePanel.config.authMode || 'sso') === 'sso') {
      html += '<div style="margin-bottom:var(--space-lg)">' +
        '<button class="btn-primary" id="btnAzureSSO" style="width:100%">Sign in with Azure SSO</button>' +
        '<div id="ssoStatus"></div></div>';
    }

    // SSO login button for Bedrock
    if (activePanel.providerId === 'bedrock') {
      html += '<div style="margin-bottom:var(--space-lg)">' +
        '<button class="btn-primary" id="btnAwsSSO" style="width:100%">Sign in with AWS SSO</button>' +
        '<div id="ssoStatus"></div></div>';
    }

    body.innerHTML = html;
    footer.innerHTML = footerBtn('secondary', 'Back', 'back') + footerBtn('primary', 'Test Connection', 'test');

    // Wire up auth mode toggle
    body.querySelectorAll('.auth-mode-btn').forEach(function (btn) {
      btn.addEventListener('click', function () {
        activePanel.config.authMode = btn.dataset.mode;
        collectFieldValues();
        renderCredentials(body, footer);
      });
    });

    // Wire up SSO buttons
    var btnAzure = body.querySelector('#btnAzureSSO');
    if (btnAzure) btnAzure.addEventListener('click', function () { startAzureSSO(); });

    var btnAws = body.querySelector('#btnAwsSSO');
    if (btnAws) btnAws.addEventListener('click', function () { startAwsSSO(); });
  }

  function collectFieldValues() {
    document.querySelectorAll('#configBody [data-field]').forEach(function (input) {
      if (input.value) {
        activePanel.config[input.dataset.field] = input.value;
      }
    });
  }

  // -----------------------------------------------------------------------
  // SSO Auth Flows
  // -----------------------------------------------------------------------
  async function startAzureSSO() {
    var statusEl = document.getElementById('ssoStatus');
    statusEl.innerHTML = '<div class="test-result testing"><div class="device-code-spinner"></div><span class="test-result-text">Starting Azure SSO...</span></div>';

    try {
      var res = await fetch('/api/providers/auth-flow', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ providerId: 'azure-foundry', action: 'sso-login' }),
      });
      var result = await res.json();

      if (result.pending && result.deviceCode) {
        statusEl.innerHTML =
          '<div class="device-code-box">' +
          '<div class="device-code-label">Go to the URL below and enter this code:</div>' +
          '<div class="device-code-value">' + esc(result.deviceCode) + '</div>' +
          '<div class="device-code-url"><a href="' + esc(result.url) + '" target="_blank">' + esc(result.url) + '</a></div>' +
          '<div class="device-code-status"><div class="device-code-spinner"></div> Waiting for sign-in...</div>' +
          '</div>';
        pollAuthFlow('azure-sso', statusEl);
      } else if (result.error) {
        statusEl.innerHTML = testResultHtml('failure', result.error);
      }
    } catch (err) {
      statusEl.innerHTML = testResultHtml('failure', err.message);
    }
  }

  async function startAwsSSO() {
    collectFieldValues();
    var statusEl = document.getElementById('ssoStatus');
    statusEl.innerHTML = '<div class="test-result testing"><div class="device-code-spinner"></div><span class="test-result-text">Starting AWS SSO...</span></div>';

    try {
      var res = await fetch('/api/providers/auth-flow', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          providerId: 'bedrock',
          action: 'sso-login',
          params: { profileName: activePanel.config.profileName || 'sso-bedrock' },
        }),
      });
      var result = await res.json();

      if (result.pending) {
        statusEl.innerHTML = '<div class="test-result testing"><div class="device-code-spinner"></div><span class="test-result-text">' + esc(result.message) + '</span></div>';
        pollAuthFlow('aws-sso', statusEl);
      } else if (result.error) {
        statusEl.innerHTML = testResultHtml('failure', result.error);
      }
    } catch (err) {
      statusEl.innerHTML = testResultHtml('failure', err.message);
    }
  }

  async function pollAuthFlow(flowId, statusEl) {
    var attempts = 0;
    var maxAttempts = 60;

    var poll = async function () {
      if (attempts++ > maxAttempts) {
        statusEl.innerHTML = testResultHtml('failure', 'Sign-in timed out. Try again.');
        return;
      }

      try {
        var res = await fetch('/api/providers/auth-flow/status?flow=' + flowId);
        var status = await res.json();

        if (status.completed) {
          statusEl.innerHTML = status.error
            ? testResultHtml('failure', status.error)
            : testResultHtml('success', 'Signed in successfully');
          return;
        }

        if (!status.active) {
          statusEl.innerHTML = testResultHtml('success', 'Signed in successfully');
          return;
        }
      } catch (e) {
        // keep polling
      }

      setTimeout(poll, 2000);
    };

    setTimeout(poll, 3000);
  }

  // -----------------------------------------------------------------------
  // Step 3: Save + Test
  // -----------------------------------------------------------------------
  async function saveAndTest() {
    collectFieldValues();
    activePanel.step = 2;
    updateStepDots();

    var body = document.getElementById('configBody');
    var footer = document.getElementById('configFooter');

    body.innerHTML = '<div class="test-result testing"><div class="device-code-spinner"></div><span class="test-result-text">Saving configuration and testing connection...</span></div>';
    footer.innerHTML = '';

    // Save
    try {
      var saveRes = await fetch('/api/providers/configure', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          providerId: activePanel.providerId,
          category: activePanel.category,
          config: activePanel.config,
        }),
      });
      var saveResult = await saveRes.json();

      if (saveResult.error) {
        body.innerHTML = testResultHtml('failure', 'Save failed: ' + saveResult.error);
        footer.innerHTML = footerBtn('secondary', 'Back', 'back') + footerBtn('primary', 'Retry', 'retry');
        return;
      }
    } catch (err) {
      body.innerHTML = testResultHtml('failure', 'Save failed: ' + err.message);
      footer.innerHTML = footerBtn('secondary', 'Back', 'back') + footerBtn('primary', 'Retry', 'retry');
      return;
    }

    // Test
    try {
      var testRes = await fetch('/api/providers/test', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          providerId: activePanel.providerId,
          config: activePanel.config,
        }),
      });
      var testResult = await testRes.json();
      activePanel.testResult = testResult;

      if (testResult.success) {
        body.innerHTML = testResultHtml('success', testResult.detail || 'Connection successful') +
          '<p style="color:var(--text-secondary);font-size:0.85rem;margin-top:var(--space-md)">' +
          esc(providerDefs[activePanel.providerId].name) + ' is configured and ready to use.</p>';
        footer.innerHTML = footerBtn('primary', 'Done', 'done');
      } else {
        body.innerHTML = testResultHtml('failure', testResult.error || 'Connection failed') +
          '<p style="color:var(--text-secondary);font-size:0.85rem;margin-top:var(--space-md)">' +
          'Configuration saved but the connection test failed. Go back to check your credentials, or keep this config and try again later.</p>';
        footer.innerHTML = footerBtn('secondary', 'Back', 'back') + footerBtn('primary', 'Keep & Close', 'keep');
      }
    } catch (err) {
      body.innerHTML = testResultHtml('failure', 'Test error: ' + err.message);
      footer.innerHTML = footerBtn('secondary', 'Back', 'back') + footerBtn('primary', 'Retry', 'retry');
    }
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------
  function footerBtn(style, label, action, disabled) {
    return '<button class="btn-' + style + '" data-action="' + action + '"' +
      (disabled ? ' disabled' : '') + '>' + esc(label) + '</button>';
  }

  function testResultHtml(type, msg) {
    var icon = type === 'success' ? '✓' : '✗';
    return '<div class="test-result ' + type + '">' +
      '<span class="test-result-icon">' + icon + '</span>' +
      '<span class="test-result-text">' + esc(msg) + '</span></div>';
  }

  function esc(str) {
    if (!str) return '';
    var div = document.createElement('div');
    div.textContent = String(str);
    return div.innerHTML;
  }

  function notifyParent() {
    if (window.parent !== window) {
      window.parent.postMessage({ type: 'provider-setup-changed' }, '*');
    }
  }

})();
