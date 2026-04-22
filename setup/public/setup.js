/**
 * Host-Side Setup Wizard
 * Runs before docker compose up. Configures .env with AI provider settings.
 * Adapted from workshop/public/js/setup.js — removed SSO flows (happen in-container),
 * added "Finish" flow that signals server to shut down.
 */
(function () {
  'use strict';

  var providerDefs = {};
  var providerStatus = {};
  var activePanel = null;

  var STEPS = ['prereqs', 'credentials', 'test'];

  var PROVIDER_ICONS = {
    anthropic: 'A',
    'azure-foundry': 'Az',
    bedrock: 'B',
    openai: 'O',
    'azure-openai': 'AO',
  };

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
          refreshStatus().then(function () { renderCards(); });
          break;
      }
    });

    document.getElementById('btnFinish').addEventListener('click', finishSetup);
    document.getElementById('btnSkip').addEventListener('click', finishSetup);
  });

  async function loadDefinitions() {
    try {
      var res = await fetch('/api/definitions');
      providerDefs = await res.json();
    } catch (e) {
      providerDefs = {};
    }
  }

  async function refreshStatus() {
    try {
      var res = await fetch('/api/status');
      providerStatus = await res.json();
    } catch (e) {
      providerStatus = { claudeCode: { active: null, providers: {} }, appDev: { providers: {} } };
    }
    renderStatusSummary();
    updateBadges();
    updateFinishButton();
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

  function updateFinishButton() {
    var cc = providerStatus.claudeCode || {};
    var btn = document.getElementById('btnFinish');
    var skip = document.getElementById('btnSkip');
    if (cc.active) {
      btn.style.display = '';
      btn.textContent = 'Start Claude Code Docker';
      skip.style.display = 'none';
    } else {
      btn.style.display = 'none';
      skip.style.display = '';
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
      return '<div class="config-step-dot ' + (i === 0 ? 'active' : '') + '" title="' + labels[s] + '"></div>';
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
      case 'test': break;
    }
  }

  // -----------------------------------------------------------------------
  // Step 1: Prerequisites
  // -----------------------------------------------------------------------
  async function renderPrereqs(body, footer) {
    var def = providerDefs[activePanel.providerId];

    if (!def.prereqs || def.prereqs.length === 0) {
      body.innerHTML = '<p style="color:var(--text-secondary)">No prerequisites needed. Ready to configure.</p>';
      if (def.ssoNote) {
        body.innerHTML += '<div class="sso-note">' + esc(def.ssoNote) + '</div>';
      }
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
      var res = await fetch('/api/check-prereqs', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ providerId: activePanel.providerId }),
      });
      var result = await res.json();
      activePanel.prereqResults = result;

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
        if (def.ssoNote) {
          body.insertAdjacentHTML('beforeend', '<div class="sso-note">' + esc(def.ssoNote) + '</div>');
        }
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

    if (activePanel.providerId === 'azure-foundry') {
      var mode = activePanel.config.authMode || 'sso';
      html += '<div class="auth-mode-toggle">' +
        '<button class="auth-mode-btn ' + (mode === 'sso' ? 'active' : '') + '" data-mode="sso">Azure SSO</button>' +
        '<button class="auth-mode-btn ' + (mode === 'apikey' ? 'active' : '') + '" data-mode="apikey">API Key</button>' +
        '</div>';
    }

    fields.forEach(function (f) {
      if (f.key === 'authMode') return;

      if (activePanel.providerId === 'azure-foundry' && f.showWhen) {
        var authMode = activePanel.config.authMode || 'sso';
        if (f.showWhen.field === 'authMode' && f.showWhen.value !== authMode) return;
      }

      var val = activePanel.config[f.key] || f.default || '';
      var type = (f.type === 'password') ? 'password' : 'text';
      html += '<div class="config-field">' +
        '<label for="field-' + f.key + '">' + esc(f.label) + '</label>' +
        '<input type="' + type + '" id="field-' + f.key + '" data-field="' + f.key + '"' +
        ' value="' + esc(val) + '" placeholder="' + esc(f.placeholder || '') + '">' +
        '</div>';
    });

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

    if (def.ssoNote && activePanel.providerId !== 'azure-foundry') {
      html += '<div class="sso-note">' + esc(def.ssoNote) + '</div>';
    }
    if (activePanel.providerId === 'azure-foundry' && (activePanel.config.authMode || 'sso') === 'sso') {
      html += '<div class="sso-note">After setup, Azure SSO sign-in happens automatically when the container starts.</div>';
    }

    body.innerHTML = html;
    footer.innerHTML = footerBtn('secondary', 'Back', 'back') + footerBtn('primary', 'Save & Test', 'test');

    body.querySelectorAll('.auth-mode-btn').forEach(function (btn) {
      btn.addEventListener('click', function () {
        activePanel.config.authMode = btn.dataset.mode;
        collectFieldValues();
        renderCredentials(body, footer);
      });
    });
  }

  function collectFieldValues() {
    document.querySelectorAll('#configBody [data-field]').forEach(function (input) {
      if (input.value) {
        activePanel.config[input.dataset.field] = input.value;
      }
    });
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

    try {
      var saveRes = await fetch('/api/configure', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          providerId: activePanel.providerId,
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

    try {
      var testRes = await fetch('/api/test', {
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
        var extra = testResult.skippedAuth
          ? '<p style="color:var(--text-secondary);font-size:0.85rem;margin-top:var(--space-md)">' +
            'Configuration saved to .env. ' + esc(testResult.detail) + '</p>'
          : '<p style="color:var(--text-secondary);font-size:0.85rem;margin-top:var(--space-md)">' +
            esc(providerDefs[activePanel.providerId].name) + ' is configured and ready to use.</p>';
        body.innerHTML = testResultHtml('success', testResult.detail || 'Connection successful') + extra;
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
  // Finish — signal server to shut down so install script continues
  // -----------------------------------------------------------------------
  async function finishSetup() {
    document.getElementById('setupPage').innerHTML =
      '<div style="display:flex;align-items:center;justify-content:center;min-height:100vh;text-align:center">' +
      '<div>' +
      '<h1 style="font-size:1.4rem;margin-bottom:0.5rem;color:var(--success)">Setup Complete</h1>' +
      '<p style="color:var(--text-secondary)">Starting Claude Code Docker... you can close this tab.</p>' +
      '</div></div>';

    try { await fetch('/api/done', { method: 'POST' }); } catch {}
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

})();
