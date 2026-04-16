/**
 * Workshop Server
 * Business User IDE for Claude Code Docker
 *
 * HTTP server + WebSocket for real-time CLI orchestration.
 * Serves the Workshop SPA and bridges the browser to Claude Code CLI
 * using bidirectional stream-json for structured, reliable communication.
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');
const { spawn, execSync } = require('child_process');

// Crash guard -- log what kills the process
process.on('uncaughtException', (err) => {
  console.error('[FATAL] Uncaught exception:', err.stack || err.message || err);
});
process.on('unhandledRejection', (reason) => {
  console.error('[FATAL] Unhandled rejection:', reason);
});

const PORT = parseInt(process.env.WORKSHOP_PORT || '9200', 10);
const PUBLIC_DIR = path.join(__dirname, 'public');
const PROJECTS_DIR = process.env.PROJECTS_DIR || '/home/coder/Documents/GitHub';
const COMMANDS_DIR = process.env.COMMANDS_DIR || '/home/coder/.claude/commands';
const HOME_DIR = process.env.HOME || '/home/coder';

// MIME types for static file serving
const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff2': 'font/woff2',
  '.woff': 'font/woff',
};

// ---------------------------------------------------------------------------
// Active CLI sessions (one per WebSocket connection)
// ---------------------------------------------------------------------------
const sessions = new Map();

// ---------------------------------------------------------------------------
// Credential Detection
// ---------------------------------------------------------------------------
function detectAuthStatus() {
  const result = { configured: false, provider: 'none', detail: '' };

  // Check for direct API key (highest priority)
  if (process.env.ANTHROPIC_API_KEY) {
    result.configured = true;
    result.provider = 'Anthropic API';
    result.detail = 'API key configured';
    return result;
  }

  // Check for Azure AI Foundry with API key
  if (process.env.ANTHROPIC_FOUNDRY_BASE_URL && process.env.ANTHROPIC_FOUNDRY_API_KEY) {
    result.configured = true;
    result.provider = 'Azure AI Foundry (API Key)';
    result.detail = 'Foundry endpoint + API key configured';
    return result;
  }

  // Check for Azure AI Foundry with token auth
  if (process.env.ANTHROPIC_FOUNDRY_BASE_URL) {
    try {
      execSync('az account get-access-token --resource https://cognitiveservices.azure.com 2>/dev/null', { timeout: 5000 });
      result.configured = true;
      result.provider = 'Azure AI Foundry (Token)';
      result.detail = 'Foundry endpoint + Azure token active';
    } catch {
      result.configured = false;
      result.provider = 'Azure AI Foundry';
      result.detail = 'Foundry endpoint set but Azure token expired or missing';
    }
    return result;
  }

  // Check for settings.json with provider config
  const settingsPath = '/home/coder/.claude/settings.json';
  if (fs.existsSync(settingsPath)) {
    try {
      const settings = JSON.parse(fs.readFileSync(settingsPath, 'utf-8'));
      if (settings.env && (settings.env.ANTHROPIC_API_KEY || settings.env.ANTHROPIC_FOUNDRY_BASE_URL)) {
        result.configured = true;
        result.provider = 'Settings file';
        result.detail = 'Credentials in settings.json';
        return result;
      }
    } catch { /* ignore parse errors */ }
  }

  result.detail = 'No AI provider credentials found. Open the Web Terminal and run "claude" to set up.';
  return result;
}

// ---------------------------------------------------------------------------
// HTTP Server
// ---------------------------------------------------------------------------
const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);

  // API: Health check
  if (url.pathname === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', service: 'workshop', sessions: sessions.size }));
    return;
  }

  // API: Auth status (credential check)
  if (url.pathname === '/api/auth-status') {
    const auth = detectAuthStatus();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(auth));
    return;
  }

  // API: Preflight -- comprehensive environment check
  if (url.pathname === '/api/preflight') {
    runPreflight(res);
    return;
  }

  // API: List projects
  if (url.pathname === '/api/projects') {
    listProjects(res);
    return;
  }

  // API: Project status (reads .make-it-state.md + app-context.json)
  if (url.pathname.startsWith('/api/project/') && url.pathname.endsWith('/status')) {
    const projectName = decodeURIComponent(url.pathname.split('/')[3]);
    projectStatus(projectName, res);
    return;
  }

  // Serve static files from public/
  serveStatic(url.pathname, res);
});

// ---------------------------------------------------------------------------
// WebSocket Server -- CLI Bridge
// ---------------------------------------------------------------------------
const wss = new WebSocketServer({ server, path: '/ws' });

wss.on('connection', (ws) => {
  const sessionId = crypto.randomUUID();
  const session = {
    id: sessionId,
    ws,
    process: null,
    phase: 'idle',
    projectDir: null,
    claudeSessionId: null,  // for --resume
    lineBuf: '',            // line buffer for stream-json parsing
    lastSentText: '',       // dedup: skip result text if same as last assistant text
    lastActivity: null,     // merge consecutive same-verb activities
    activityTimer: null,    // debounce timer for activity batching
    waitingForUser: false,  // true when a question was sent and we're awaiting user reply
    autoContCount: 0,       // safety counter: how many auto-continuations in a row
  };
  sessions.set(sessionId, session);

  ws.send(JSON.stringify({
    type: 'connected',
    sessionId,
    message: 'Workshop connected. Ready to build something amazing.'
  }));

  ws.on('message', (raw) => {
    try {
      const msg = JSON.parse(raw.toString());
      handleMessage(session, msg);
    } catch (e) {
      ws.send(JSON.stringify({ type: 'error', message: 'Invalid message format' }));
    }
  });

  ws.on('close', () => {
    if (session.process) {
      session.process.kill('SIGTERM');
    }
    sessions.delete(sessionId);
  });
});

// ---------------------------------------------------------------------------
// Message Handler -- Routes browser messages to CLI actions
// ---------------------------------------------------------------------------
function handleMessage(session, msg) {
  switch (msg.type) {
    case 'start-project':
      startProject(session, msg);
      break;

    case 'user-input':
      sendToProcess(session, msg.text);
      break;

    case 'quick-reply':
      sendToProcess(session, msg.value);
      break;

    case 'cancel':
      cancelProcess(session);
      break;

    case 'open-project':
      openProject(session, msg);
      break;

    case 'try-it':
      runSkill(session, '/try-it');
      break;

    case 'resume-it':
      runSkill(session, '/resume-it');
      break;

    case 'ship-it':
      runSkill(session, msg.mode === 'save' ? '/ship-it save' : '/ship-it');
      break;

    default:
      session.ws.send(JSON.stringify({ type: 'error', message: `Unknown message type: ${msg.type}` }));
  }
}

// ---------------------------------------------------------------------------
// CLI Process Management
// ---------------------------------------------------------------------------

/**
 * Detect whether a project directory has been built by /make-it.
 * Returns '/resume-it' if the project has code, '/make-it' if it's new/empty.
 *
 * Signals that /make-it was used:
 *   - .make-it-state.md      (make-it breadcrumb)
 *   - .make-it/app-context.json (make-it context)
 *   - CHANGELOG.md           (make-it always creates this)
 *   - TODO.md                (make-it always creates this)
 *   - docker-compose.yml     (make-it scaffolded app)
 *   - package.json or pyproject.toml (code exists)
 */
function detectSkill(projectDir) {
  const makeItSignals = [
    '.make-it-state.md',
    '.make-it/app-context.json',
    'CHANGELOG.md',
    'TODO.md',
    'docker-compose.yml',
    'docker-compose.yaml',
    'package.json',
    'pyproject.toml',
  ];

  for (const file of makeItSignals) {
    if (fs.existsSync(path.join(projectDir, file))) {
      return '/resume-it';
    }
  }

  return '/make-it';
}

function startProject(session, msg) {
  const projectName = sanitizeProjectName(msg.name || 'my-app');
  const projectDir = path.join(PROJECTS_DIR, projectName);

  if (!fs.existsSync(projectDir)) {
    fs.mkdirSync(projectDir, { recursive: true });
  }

  session.projectDir = projectDir;

  // Auto-detect: /make-it for new projects, /resume-it for existing ones
  const skill = detectSkill(projectDir);
  const phase = skill === '/resume-it' ? 'iterating' : 'ideation';
  const phaseMsg = skill === '/resume-it'
    ? `Picking up where you left off on ${projectName}...`
    : 'Starting your project...';

  session.phase = phase;
  debugLog(session, 'cli', `Auto-detected skill: ${skill} (project: ${projectName})`);

  session.ws.send(JSON.stringify({
    type: 'phase-change',
    phase,
    message: phaseMsg,
  }));

  const prompt = buildSkillPrompt(skill, projectName, msg.description);
  spawnCLI(session, projectDir, prompt);
}

/**
 * Open an existing project -- sets projectDir and reports status.
 * The client decides what to do next (view dashboard, run resume-it, etc.).
 */
function openProject(session, msg) {
  const projectName = sanitizeProjectName(msg.name || '');
  if (!projectName) {
    session.ws.send(JSON.stringify({ type: 'error', message: 'No project name provided' }));
    return;
  }

  const projectDir = path.join(PROJECTS_DIR, projectName);
  if (!fs.existsSync(projectDir)) {
    session.ws.send(JSON.stringify({ type: 'error', message: 'Project not found' }));
    return;
  }

  session.projectDir = projectDir;
  const skill = detectSkill(projectDir);

  session.ws.send(JSON.stringify({
    type: 'project-opened',
    name: projectName,
    dir: projectDir,
    hasCode: skill === '/resume-it',
  }));
}

function runSkill(session, skill) {
  if (!session.projectDir) {
    session.ws.send(JSON.stringify({ type: 'error', message: 'No active project' }));
    return;
  }

  const phaseMap = {
    '/try-it': 'testing',
    '/resume-it': 'iterating',
    '/ship-it': 'shipping',
    '/ship-it save': 'saving',
  };

  // Extract base skill name (strip arguments like "save" from "/ship-it save")
  const skillName = skill.split(' ')[0];
  session.phase = phaseMap[skill] || 'working';

  session.ws.send(JSON.stringify({
    type: 'phase-change',
    phase: session.phase,
    message: `Running ${skillName}...`
  }));

  // Resolve the skill into a full prompt
  const projectName = path.basename(session.projectDir);
  const prompt = buildSkillPrompt(skillName, projectName);
  spawnCLI(session, session.projectDir, prompt);
}

/**
 * Send a debug log entry to the browser's bootstrap panel.
 */
function debugLog(session, source, msg) {
  const line = `[${source}] ${msg}`;
  console.log(`[session:${session.id.slice(0,8)}] ${line}`);
  try {
    session.ws.send(JSON.stringify({ type: 'debug', source, message: msg }));
  } catch { /* ws might be closed */ }
}

/**
 * Spawn Claude Code CLI with stream-json output.
 *
 * For small prompts (<128KB), passes the prompt as a -p argument.
 * For large prompts (>=128KB, e.g. fully resolved skill content),
 * writes to a temp file and pipes via stdin to avoid ARG_MAX limits.
 *
 * @param {Object} session   - WebSocket session
 * @param {string} cwd       - Working directory for the CLI
 * @param {string} prompt    - The prompt text
 * @param {string} [resumeId] - Optional Claude session ID for --resume (multi-turn)
 */
function spawnCLI(session, cwd, prompt, resumeId) {
  if (session.process) {
    session.process.kill('SIGTERM');
    session.process = null;
  }

  session.lineBuf = '';
  session.pendingInput = null;

  const promptBytes = Buffer.byteLength(prompt || '', 'utf-8');
  const useStdin = promptBytes > 120000; // 120KB threshold (ARG_MAX is 128KB on Alpine)

  const resumeArg = resumeId ? ` --resume ${resumeId}` : '';

  let proc;

  if (useStdin) {
    // Large prompt: write to temp file, pipe via shell to avoid ARG_MAX
    const tmpFile = `/tmp/workshop-${session.id.slice(0, 8)}-${Date.now()}.txt`;
    fs.writeFileSync(tmpFile, prompt, 'utf-8');

    const cmd = `cat "${tmpFile}" | claude -p --verbose --output-format stream-json --permission-mode bypassPermissions${resumeArg}; rm -f "${tmpFile}"`;

    debugLog(session, 'cli', `Spawning (stdin pipe, ${(promptBytes / 1024).toFixed(0)}KB prompt): claude -p [stdin]${resumeArg}`);
    debugLog(session, 'cli', `CWD: ${cwd}${resumeId ? ` | Resume: ${resumeId.slice(0, 8)}` : ''}`);

    proc = spawn('sh', ['-c', cmd], {
      cwd,
      env: { ...process.env, NO_COLOR: '1' },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } else {
    // Small prompt: pass as -p argument (normal path for --resume continuations)
    const args = [
      '-p',
      prompt || '',
      '--verbose',
      '--output-format', 'stream-json',
      '--permission-mode', 'bypassPermissions',
    ];
    if (resumeId) args.push('--resume', resumeId);

    debugLog(session, 'cli', `Spawning: claude -p "${(prompt || '').substring(0, 120)}..."${resumeArg}`);
    debugLog(session, 'cli', `CWD: ${cwd}${resumeId ? ` | Resume: ${resumeId.slice(0, 8)}` : ''}`);

    proc = spawn('claude', args, {
      cwd,
      env: { ...process.env, NO_COLOR: '1' },
      stdio: ['ignore', 'pipe', 'pipe'],  // stdin not needed for -p arg mode
    });
  }

  session.process = proc;
  debugLog(session, 'cli', `Process spawned, PID: ${proc.pid}`);

  // Accumulate partial text for the current assistant message
  let currentText = '';
  let eventCount = 0;

  proc.stdout.on('data', (data) => {
    const raw = data.toString();
    session.lineBuf += raw;

    // Stream-json outputs one JSON object per line
    let newlineIdx;
    while ((newlineIdx = session.lineBuf.indexOf('\n')) !== -1) {
      const line = session.lineBuf.slice(0, newlineIdx).trim();
      session.lineBuf = session.lineBuf.slice(newlineIdx + 1);

      if (!line) continue;

      try {
        const event = JSON.parse(line);
        eventCount++;
        // Log event type for debugging
        const evType = event.type || 'unknown';
        const extra = event.content_block?.type || event.delta?.type || '';
        debugLog(session, 'stdout', `Event #${eventCount}: ${evType}${extra ? '/' + extra : ''}`);

        handleStreamEvent(session, event, { getText: () => currentText, setText: (t) => { currentText = t; } });
      } catch {
        // Not valid JSON -- log it for debugging
        debugLog(session, 'stdout', `Non-JSON: ${line.substring(0, 150)}`);
      }
    }
  });

  proc.stderr.on('data', (data) => {
    const text = data.toString().trim();
    if (!text) return;

    debugLog(session, 'stderr', text.substring(0, 300));

    if (isStderrNoise(text)) return;

    // Detect auth failures -- these are critical and need user action
    if (/Azure token expired|not logged in.*az login|authentication_failed/i.test(text)) {
      session.authFailed = true;
      session.ws.send(JSON.stringify({
        type: 'error',
        message: 'Your login session has expired. Open the Web Terminal (port 7681) and run: az login --use-device-code'
      }));
      return;
    }

    const friendly = translateError(text);
    if (!friendly) return;

    session.ws.send(JSON.stringify({
      type: 'activity',
      category: 'system',
      message: friendly
    }));
  });

  proc.on('error', (err) => {
    session.process = null;
    debugLog(session, 'cli', `Process error: ${err.code} -- ${err.message}`);
    session.ws.send(JSON.stringify({
      type: 'error',
      message: err.code === 'ENOENT'
        ? 'Claude Code CLI not found. Is it installed?'
        : `Failed to start: ${err.message}`
    }));
  });

  proc.on('close', (code, signal) => {
    session.process = null;
    debugLog(session, 'cli', `Process exited: code=${code} signal=${signal} events=${eventCount}`);

    // If there's a pending user message, send it as a follow-up via --resume
    if (session.pendingInput && code === 0 && session.claudeSessionId) {
      const pending = session.pendingInput;
      session.pendingInput = null;
      debugLog(session, 'cli', `Sending pending input via --resume`);
      spawnCLI(session, session.projectDir || cwd, pending, session.claudeSessionId);
      return;
    }

    // ---------------------------------------------------------------
    // Auto-continuation: keep the build going across single-turn exits.
    //
    // `-p` mode is single-turn -- Claude responds once and exits.
    // Skills like /make-it need many turns (ideation → design → build → verify).
    // When the process exits successfully and we're NOT waiting for the user
    // to answer a question, automatically spawn a continuation via --resume
    // so the skill keeps executing.
    // ---------------------------------------------------------------
    const activePhases = new Set([
      'ideation', 'design', 'building', 'verifying', 'testing', 'iterating',
    ]);

    if (
      code === 0 &&
      session.claudeSessionId &&
      !session.waitingForUser &&
      activePhases.has(session.phase) &&
      session.projectDir
    ) {
      session.autoContCount = (session.autoContCount || 0) + 1;

      // Safety valve: stop after too many consecutive auto-continuations
      if (session.autoContCount > 80) {
        debugLog(session, 'cli', `Auto-continuation limit reached (${session.autoContCount}), pausing`);
        session.ws.send(JSON.stringify({
          type: 'process-complete',
          phase: session.phase,
          exitCode: code,
          message: 'Build paused after many steps. Let me know how to continue.',
        }));
        return;
      }

      debugLog(session, 'cli', `Auto-continuing (count: ${session.autoContCount}, phase: ${session.phase})`);

      // Brief delay to prevent tight loops and let UI updates land
      setTimeout(() => {
        // Guard: another process may have started (user input, etc.)
        if (session.process) return;

        const contPrompt = session.autoContCount <= 2
          ? 'Continue executing the skill. Pick up exactly where you left off and proceed with the next step. Do not repeat any work already completed. Do not summarize what you did -- just keep going.'
          : 'Continue. Keep building. Do not stop until you need user input or the skill is complete.';

        spawnCLI(session, session.projectDir, contPrompt, session.claudeSessionId);
      }, 1500);
      return;
    }

    session.ws.send(JSON.stringify({
      type: 'process-complete',
      phase: session.phase,
      exitCode: code,
      message: code === 0 ? 'Done!' : 'Something went wrong, but I can try again.'
    }));
  });

  debugLog(session, 'cli', `Prompt: ${promptBytes} bytes (${useStdin ? 'stdin pipe' : '-p arg'})`);
}

/**
 * Send a user message to the CLI.
 *
 * `-p` mode is single-turn: the process exits after one response.
 * For follow-up messages we spawn a NEW `claude -p` with `--resume <sessionId>`
 * so the conversation continues in the same Claude session.
 *
 * If the previous process is still running (e.g. Claude is still responding),
 * we queue the message by writing to stdin -- but this only works if the CLI
 * is in an interactive input state (rare in -p mode).
 */
function sendToProcess(session, text) {
  // User is responding -- reset continuation state
  session.waitingForUser = false;
  session.autoContCount = 0;

  // If a process is still running, it might be waiting for input (unlikely in -p mode)
  if (session.process && !session.process.killed) {
    debugLog(session, 'cli', `Process still running (PID ${session.process.pid}), queueing message for after completion`);
    // Store the pending message; it will be sent when the process completes
    session.pendingInput = text;
    return;
  }

  // No running process -- spawn a new one with --resume to continue the conversation
  if (!session.claudeSessionId) {
    debugLog(session, 'cli', 'No Claude session ID available -- cannot resume. Starting fresh.');
    // Fall back to a fresh prompt
    const cwd = session.projectDir || PROJECTS_DIR;
    spawnCLI(session, cwd, text);
    return;
  }

  if (!session.projectDir) {
    session.ws.send(JSON.stringify({ type: 'error', message: 'No active project' }));
    return;
  }

  debugLog(session, 'cli', `Resuming session ${session.claudeSessionId.slice(0, 8)} with user message`);
  spawnCLI(session, session.projectDir, text, session.claudeSessionId);
}

function cancelProcess(session) {
  if (session.process) {
    session.process.kill('SIGTERM');
    session.process = null;
    session.phase = 'idle';
    session.ws.send(JSON.stringify({ type: 'cancelled', message: 'Stopped.' }));
  }
}

// ---------------------------------------------------------------------------
// Stream-JSON Event Handler
// Maps Claude Code CLI verbose stream-json events to Workshop UI events.
//
// Actual event types from `claude -p --verbose --output-format stream-json`:
//   system  -- init info (tools, model, session_id)
//   assistant -- assistant message with content blocks (text, tool_use)
//   result  -- final result with cost, usage, duration
// ---------------------------------------------------------------------------
function handleStreamEvent(session, event, textAcc) {
  const type = event.type;

  // --- System init ---
  if (type === 'system' && event.subtype === 'init') {
    session.claudeSessionId = event.session_id;
    debugLog(session, 'event', `Init: model=${event.model}, tools=${(event.tools || []).length}, session=${event.session_id?.slice(0, 8)}`);

    // Check for auth errors in the init event
    if (event.error) {
      session.authFailed = true;
      const isLoginNeeded = /auth|login|credential|token/i.test(event.error);
      session.ws.send(JSON.stringify({
        type: 'error',
        message: isLoginNeeded
          ? 'Your login session has expired. Open the Web Terminal (port 7681) and run: az login --use-device-code'
          : `Setup issue: ${event.error}`
      }));
    }
    return;
  }

  // --- Assistant message ---
  if (type === 'assistant') {
    const msg = event.message;
    if (!msg || !msg.content) return;

    // Check for auth error
    if (event.error) {
      session.ws.send(JSON.stringify({ type: 'error', message: msg.content?.[0]?.text || event.error }));
      return;
    }

    // Process each content block
    for (const block of msg.content) {
      if (block.type === 'text' && block.text) {
        processAssistantText(session, block.text);
      } else if (block.type === 'tool_use') {
        // AskUserQuestion: extract question(s) and send as chat message with options
        if (block.name === 'AskUserQuestion') {
          const questions = block.input?.questions || [];
          if (questions.length > 0) {
            flushActivity(session);
            // Build a combined question text with options
            const parts = [];
            const quickReplies = [];
            for (const q of questions) {
              if (q.header) parts.push(`**${q.header}**`);
              if (q.question) parts.push(q.question);
              if (q.options && q.options.length > 0) {
                for (const opt of q.options) {
                  parts.push(`- **${opt.label}**${opt.description ? ' -- ' + opt.description : ''}`);
                  quickReplies.push(opt.label);
                }
              }
            }
            const text = parts.join('\n');
            if (text) {
              session.lastSentText = text;
              session.waitingForUser = true;
              session.ws.send(JSON.stringify({
                type: 'question',
                text,
                quickReplies: quickReplies.length > 0 ? quickReplies : null,
              }));
            }
          }
          continue;
        }

        const activity = toolToActivity(block.name, block.input);
        if (activity) {
          batchActivity(session, activity.category, activity.message);
        }
      } else if (block.type === 'tool_result') {
        if (block.is_error) {
          debugLog(session, 'event', `Tool error: ${JSON.stringify(block.content).substring(0, 200)}`);
        }
      }
    }
    return;
  }

  // --- Result (final) ---
  if (type === 'result') {
    if (event.session_id) {
      session.claudeSessionId = event.session_id;
    }
    debugLog(session, 'event', `Result: turns=${event.num_turns}, cost=$${event.total_cost_usd}, duration=${event.duration_ms}ms`);

    // Flush any pending batched activity
    flushActivity(session);

    // Only send result text if it differs from the last assistant message
    // (the assistant event already sent this text -- result is a duplicate)
    if (event.result && typeof event.result === 'string' && event.result.length > 0) {
      if (event.result !== session.lastSentText) {
        processAssistantText(session, event.result);
      }
    }
    return;
  }
}

// ---------------------------------------------------------------------------
// Activity Batching -- merge consecutive same-verb activities into one line.
//
// "Reading X" + "Reading Y" → "Reading X, Y"
// "Searching for files..." + "Searching for files..." → "Searching for files..."
// Different verbs flush the previous batch and start a new one.
// A 500ms debounce ensures rapid-fire activities get merged.
// ---------------------------------------------------------------------------

/**
 * Extract the verb prefix from an activity message.
 * "Reading commands/make-it.md" → "Reading"
 * "Searching for files..." → "Searching for files"
 * "Creating test-resume/index.html" → "Creating"
 * "Running a command..." → "Running a command"
 */
function activityVerb(msg) {
  // Match "Verb" or "Verb ... ..." patterns
  const m = msg.match(/^(\w+(?:\s+\w+)*?)(?:\s+\S+\/|\s*\.\.\.| --)/);
  if (m) return m[1];
  // Fallback: first word
  return msg.split(/\s/)[0];
}

/**
 * Extract the short detail from an activity message (the part after the verb).
 * "Reading commands/make-it.md" → "commands/make-it.md"
 * "Searching for files..." → null (no distinct detail)
 */
function activityDetail(msg) {
  const verb = activityVerb(msg);
  const rest = msg.slice(verb.length).replace(/^[\s.]+/, '').replace(/\.+$/, '').trim();
  return rest || null;
}

function batchActivity(session, category, message) {
  const verb = activityVerb(message);
  const detail = activityDetail(message);

  // If same verb as pending batch, merge into it
  if (session.lastActivity && session.lastActivity.verb === verb) {
    if (detail && !session.lastActivity.details.includes(detail)) {
      session.lastActivity.details.push(detail);
    }
    // Reset the debounce timer
    if (session.activityTimer) clearTimeout(session.activityTimer);
    session.activityTimer = setTimeout(() => flushActivity(session), 500);
    return;
  }

  // Different verb -- flush previous, start new batch
  flushActivity(session);

  session.lastActivity = {
    category,
    verb,
    details: detail ? [detail] : [],
    message,  // original full message as fallback
  };

  // Debounce: wait 500ms for more same-verb activities before sending
  session.activityTimer = setTimeout(() => flushActivity(session), 500);
}

function flushActivity(session) {
  if (session.activityTimer) {
    clearTimeout(session.activityTimer);
    session.activityTimer = null;
  }

  const batch = session.lastActivity;
  if (!batch) return;
  session.lastActivity = null;

  let message;
  if (batch.details.length === 0) {
    // No distinct details (e.g. "Searching for files...")
    message = batch.message;
  } else if (batch.details.length === 1) {
    // Single item: "Reading commands/make-it.md"
    message = `${batch.verb} ${batch.details[0]}`;
  } else {
    // Multiple items: "Reading commands/make-it.md, references/prerequisites.md, references/guardrails.md"
    message = `${batch.verb} ${batch.details.join(', ')}`;
  }

  session.ws.send(JSON.stringify({
    type: 'activity',
    category: batch.category,
    message,
  }));
}

/**
 * Process a complete assistant text block.
 * Detects phase changes, questions, and general updates.
 * Tracks lastSentText for dedup against the result event.
 */
function processAssistantText(session, text) {
  // Flush any pending batched activity before sending text
  flushActivity(session);

  // Track for dedup (result event sends the same text again)
  session.lastSentText = text;

  // Phase detection
  const phasePatterns = [
    { pattern: /ideation|describe.*app|what.*build|what kind/i, phase: 'ideation', label: 'Understanding your idea' },
    { pattern: /design|architecture|stack|planning|blueprint/i, phase: 'design', label: 'Designing the architecture' },
    { pattern: /building|generating|creating.*file|writing.*code|implementing/i, phase: 'building', label: 'Building your app' },
    { pattern: /build-verify|testing|smoke.?test|verification|verif/i, phase: 'verifying', label: 'Testing everything' },
    { pattern: /try-it|your app is.*running|ready to explore|everything.*(pass|look)/i, phase: 'complete', label: 'Ready to explore' },
  ];

  for (const { pattern, phase, label } of phasePatterns) {
    if (pattern.test(text) && session.phase !== phase) {
      session.phase = phase;
      session.ws.send(JSON.stringify({ type: 'phase-change', phase, message: label }));
      break;
    }
  }

  // Question detection: look for a question at the end of the text
  const lines = text.split('\n').filter(l => l.trim());
  const lastLine = lines[lines.length - 1]?.trim() || '';

  if (/\?\s*$/.test(lastLine)) {
    const isYesNo = /\b(yes|no|y\/n)\b/i.test(lastLine) ||
                    /\b(do you|will you|should|is this|does|are you|would you|want me)\b/i.test(lastLine);

    // Detect option-style questions (A, B, C, D patterns)
    const optionMatch = text.match(/\*\*([A-D])\.\*\*|^([A-D])\.\s/gm);
    let quickReplies = null;
    if (optionMatch && optionMatch.length >= 2) {
      quickReplies = optionMatch.map(m => m.replace(/\*\*/g, '').trim().charAt(0));
    } else if (isYesNo) {
      quickReplies = ['Yes', 'No'];
    }

    session.waitingForUser = true;
    session.ws.send(JSON.stringify({
      type: 'question',
      text: text,
      quickReplies,
    }));
  } else {
    // General assistant message -- send as activity or AI message
    // Long messages go as questions (they likely need a response)
    // Short messages go as activity feed items
    if (text.length > 200) {
      session.ws.send(JSON.stringify({
        type: 'question',
        text: text,
        quickReplies: null,
      }));
    } else {
      session.ws.send(JSON.stringify({
        type: 'activity',
        category: detectCategory(text),
        message: text.length > 120 ? text.substring(0, 120) + '...' : text,
      }));
    }
  }
}

/**
 * Map tool names to user-friendly activity messages.
 * Returns null for internal tools that shouldn't be shown to business users.
 */
function toolToActivity(toolName, input) {
  // Tools with user-visible status messages
  const toolMap = {
    'Write': { category: 'building', msg: (i) => `Creating ${shortPath(i?.file_path)}` },
    'Edit': { category: 'building', msg: (i) => `Editing ${shortPath(i?.file_path)}` },
    'Read': { category: 'general', msg: (i) => `Reading ${shortPath(i?.file_path)}` },
    'Bash': { category: 'infra', msg: (i) => bashToMessage(i?.command) },
    'Glob': { category: 'general', msg: () => 'Searching for files...' },
    'Grep': { category: 'general', msg: () => 'Searching code...' },
    'Agent': { category: 'building', msg: () => 'Working on a subtask...' },
  };

  // Internal tools -- never shown to business users
  const hidden = new Set([
    'AskUserQuestion',  // handled separately (extracted as chat question)
    'ToolSearch',
    'TodoWrite',
    'Task',
    'TaskOutput',
    'TaskStop',
    'Skill',
    'EnterPlanMode',
    'ExitPlanMode',
    'EnterWorktree',
    'ExitWorktree',
    'NotebookEdit',
    'WebSearch',
    'WebFetch',
    'ScheduleWakeup',
    'CronCreate',
    'CronDelete',
    'CronList',
  ]);

  if (hidden.has(toolName)) return null;

  const handler = toolMap[toolName];
  if (!handler) return null;  // unknown tools: log only, don't show

  return { category: handler.category, message: handler.msg(input || {}) };
}

function shortPath(filePath) {
  if (!filePath) return 'a file';
  const parts = filePath.split('/');
  return parts.length > 2 ? parts.slice(-2).join('/') : filePath;
}

function bashToMessage(command) {
  if (!command) return 'Running a command...';
  if (/docker|compose/i.test(command)) return 'Setting up Docker services...';
  if (/npm|yarn|pip|install/i.test(command)) return 'Installing dependencies...';
  if (/test|pytest|playwright/i.test(command)) return 'Running tests...';
  if (/git/i.test(command)) return 'Working with git...';
  if (/mkdir|touch|cp|mv/i.test(command)) return 'Organizing project files...';
  if (/curl|wget/i.test(command)) return 'Fetching resources...';
  if (/alembic|migrate/i.test(command)) return 'Running database migrations...';
  if (/seed/i.test(command)) return 'Seeding the database...';
  return 'Running a command...';
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function detectCategory(text) {
  if (/creat|generat|writ|build|add|implement/i.test(text)) return 'building';
  if (/test|verif|check|pass|fail/i.test(text)) return 'testing';
  if (/fix|error|issue|bug/i.test(text)) return 'fixing';
  if (/auth|login|oidc|permission/i.test(text)) return 'auth';
  if (/docker|container|compose/i.test(text)) return 'infra';
  if (/datab|migrat|seed|table/i.test(text)) return 'database';
  return 'general';
}

/**
 * Filter out harmless stderr noise that doesn't need to reach the UI.
 */
function isStderrNoise(text) {
  return /^npm warn/i.test(text) ||
    /^deprecat/i.test(text) ||
    /^warning:/i.test(text) ||
    /experimentalwarning/i.test(text) ||
    /punycode/i.test(text) ||
    /update available/i.test(text) ||
    /Run .* to update/i.test(text) ||
    /^\(node:\d+\) \w*Warning/i.test(text) ||
    /debugger listening/i.test(text) ||
    /waiting for the debugger/i.test(text) ||
    /^Cloning into/i.test(text);
}

/**
 * Translate a known stderr pattern to a user-friendly message.
 * Returns null for unrecognized errors -- caller should suppress those.
 */
function translateError(text) {
  if (/ENOENT/i.test(text)) return 'Setting up a missing piece...';
  if (/ECONNREFUSED/i.test(text)) return 'Waiting for a service to start...';
  if (/permission denied/i.test(text)) return 'Adjusting permissions...';
  if (/timeout/i.test(text)) return 'Taking a bit longer than expected...';
  if (/ANTHROPIC_API_KEY|auth|credential/i.test(text)) return 'Checking credentials...';
  if (/ENOSPC|no space/i.test(text)) return 'Running low on disk space...';
  if (/ENOMEM|out of memory/i.test(text)) return 'Running low on memory...';
  if (/EADDRINUSE|address already in use/i.test(text)) return 'A port is busy, switching...';
  if (/docker|container|daemon/i.test(text)) return 'Setting up services...';
  if (/npm ERR|install.*fail/i.test(text)) return 'Installing a dependency...';
  if (/syntax.?error|unexpected token/i.test(text)) return 'Fixing a small code issue...';
  return null;
}

// ---------------------------------------------------------------------------
// Skill Resolver -- expand command .md files with @references
// ---------------------------------------------------------------------------

/**
 * Resolve a skill/command name into a fully expanded prompt.
 * Reads the .md file from COMMANDS_DIR, strips YAML frontmatter,
 * and inlines all @~/.claude/... file references.
 *
 * Returns null if the skill file doesn't exist.
 */
function resolveSkill(skillName) {
  // Strip leading slash
  const name = skillName.replace(/^\//, '');
  const filePath = path.join(COMMANDS_DIR, `${name}.md`);

  if (!fs.existsSync(filePath)) {
    console.error(`[skill-resolver] Skill not found: ${filePath}`);
    return null;
  }

  let content = fs.readFileSync(filePath, 'utf-8');

  // Strip YAML frontmatter (--- ... ---)
  content = content.replace(/^---\n[\s\S]*?\n---\n/, '');

  // Resolve @~/.claude/... references by inlining file content
  content = content.replace(/^@(~\/.+)$/gm, (match, refPath) => {
    const absPath = refPath.replace(/^~/, HOME_DIR);
    try {
      const refContent = fs.readFileSync(absPath, 'utf-8');
      return `<!-- BEGIN ${path.basename(absPath)} -->\n${refContent}\n<!-- END ${path.basename(absPath)} -->`;
    } catch (err) {
      console.error(`[skill-resolver] Cannot read reference: ${absPath}`);
      return `<!-- Reference not found: ${refPath} -->`;
    }
  });

  return content;
}

/**
 * Build the full skill prompt with all @references inlined -- TUI parity.
 *
 * In TUI mode, Claude Code resolves all @references in the skill file and injects
 * them as a single system prompt before Claude starts. Workshop replicates this by
 * using resolveSkill() to produce the same expanded content.
 *
 * This eliminates 10+ "reading" turns where Claude had to manually Read each
 * reference file, and gives Claude the full roadmap from the very first turn.
 */
function buildSkillPrompt(skillName, projectName, description) {
  const name = skillName.replace(/^\//, '');

  // Attempt full resolution (skill content + all @references inlined)
  const resolvedContent = resolveSkill(name);

  const parts = [];

  // Workshop preamble -- always present
  parts.push(`IMPORTANT CONTEXT: You are running inside Workshop, a GUI for non-technical business users.`);
  parts.push(`The user CANNOT run terminal commands, slash commands, or CLI tools.`);
  parts.push(`Never tell them to "run /make-it", "run /try-it", "type a command", or anything similar.`);
  parts.push(`YOU must do everything directly -- execute each step of the skill yourself.`);
  parts.push('');

  if (projectName) parts.push(`Project name: ${projectName}`);
  if (description) parts.push(`User's initial description: ${description}`);
  parts.push('');

  if (resolvedContent) {
    // Full skill content with inlined references (TUI parity)
    parts.push(`You are now executing the /${name} skill. The full skill content follows (all @references have been resolved and inlined for you). Execute it step by step, starting from the first phase.`);
    parts.push('');
    parts.push(resolvedContent);
  } else {
    // Fallback: tell Claude to read it manually (original approach)
    const skillPath = path.join(COMMANDS_DIR, `${name}.md`);
    const resolvedPath = fs.existsSync(skillPath) ? skillPath : '~/.claude/commands/' + name + '.md';
    parts.push(`You are executing the /${name} skill. Read ${resolvedPath} and follow its instructions step by step.`);
    parts.push(`Read any files referenced with @ in the <execution_context> section as you need them.`);
  }

  return parts.join('\n');
}

// ---------------------------------------------------------------------------
// Preflight Check -- verify environment before starting CLI
// ---------------------------------------------------------------------------
async function runPreflight(res) {
  const checks = {
    cli: { pass: false, label: 'Claude Code CLI', detail: '' },
    auth: { pass: false, label: 'AI Provider Auth', detail: '' },
    network: { pass: false, label: 'Network / VPN', detail: '' },
  };

  // 1. Check Claude Code CLI is installed
  try {
    const version = execSync('claude --version 2>/dev/null', { timeout: 5000 }).toString().trim();
    checks.cli.pass = true;
    checks.cli.detail = version;
  } catch {
    checks.cli.detail = 'Claude Code CLI not found or not responding';
  }

  // 2. Check auth (reuse existing detection)
  const auth = detectAuthStatus();
  checks.auth.pass = auth.configured;
  checks.auth.detail = auth.configured ? auth.provider : auth.detail;
  checks.auth.provider = auth.provider;

  // 3. Check network -- if Azure Foundry, verify we can reach the endpoint
  if (process.env.ANTHROPIC_FOUNDRY_BASE_URL) {
    try {
      // TCP-level reachability check -- any HTTP response (even 404) means network is OK
      const host = new URL(process.env.ANTHROPIC_FOUNDRY_BASE_URL).hostname;
      execSync(`curl --connect-timeout 5 --max-time 5 -o /dev/null -w "%{http_code}" https://${host} 2>/dev/null`, { timeout: 10000 });
      checks.network.pass = true;
      checks.network.detail = 'Connected to Azure AI Foundry';
    } catch {
      checks.network.detail = 'Cannot reach Azure AI Foundry -- VPN may be required';
    }
  } else if (process.env.ANTHROPIC_API_KEY) {
    // Direct API key -- check api.anthropic.com reachability
    try {
      execSync('curl -sf --connect-timeout 5 --max-time 5 https://api.anthropic.com -o /dev/null', { timeout: 10000 });
      checks.network.pass = true;
      checks.network.detail = 'Connected to Anthropic API';
    } catch {
      checks.network.detail = 'Cannot reach Anthropic API -- check your network connection';
    }
  } else {
    // No provider configured -- network check is N/A
    checks.network.pass = true;
    checks.network.detail = 'No provider configured yet';
  }

  const allPass = checks.cli.pass && checks.auth.pass && checks.network.pass;

  // Build step-by-step instructions for failing checks
  const steps = [];
  if (!checks.network.pass) {
    steps.push({
      id: 'vpn',
      label: 'Connect to VPN',
      instruction: 'If you\'re not on the corporate network, connect to VPN first.',
      terminal: false,
    });
  }
  if (!checks.auth.pass) {
    if (process.env.ANTHROPIC_FOUNDRY_BASE_URL) {
      steps.push({
        id: 'az-login',
        label: 'Sign in to Azure',
        instruction: 'Open the Web Terminal and run: az login --use-device-code',
        terminal: true,
      });
    } else {
      steps.push({
        id: 'api-key',
        label: 'Set up AI credentials',
        instruction: 'Open the Web Terminal and run: claude to configure your API key',
        terminal: true,
      });
    }
  }

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ ready: allPass, checks, steps }));
}

function sanitizeProjectName(name) {
  return name.toLowerCase()
    .replace(/[^a-z0-9-_]/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '')
    .substring(0, 64) || 'my-app';
}

function serveStatic(pathname, res) {
  let filePath = pathname === '/' ? '/index.html' : pathname;
  filePath = path.join(PUBLIC_DIR, filePath);

  // Prevent directory traversal
  if (!filePath.startsWith(PUBLIC_DIR)) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }

  const ext = path.extname(filePath);
  const contentType = MIME_TYPES[ext] || 'application/octet-stream';

  fs.readFile(filePath, (err, data) => {
    if (err) {
      if (err.code === 'ENOENT' && !ext) {
        fs.readFile(path.join(PUBLIC_DIR, 'index.html'), (err2, html) => {
          if (err2) { res.writeHead(500); res.end('Internal Error'); return; }
          res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
          res.end(html);
        });
        return;
      }
      res.writeHead(404);
      res.end('Not Found');
      return;
    }
    res.writeHead(200, { 'Content-Type': contentType });
    res.end(data);
  });
}

function listProjects(res) {
  try {
    const entries = fs.readdirSync(PROJECTS_DIR, { withFileTypes: true })
      .filter(e => e.isDirectory() && !e.name.startsWith('.'))
      .map(e => {
        const dir = path.join(PROJECTS_DIR, e.name);
        const hasState = fs.existsSync(path.join(dir, '.make-it-state.md'));
        const hasContext = fs.existsSync(path.join(dir, '.make-it', 'app-context.json'));
        return {
          name: e.name,
          hasState,
          hasContext,
          builtWithMakeIt: hasState || hasContext,
        };
      })
      .sort((a, b) => b.builtWithMakeIt - a.builtWithMakeIt);

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ projects: entries }));
  } catch (e) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ projects: [] }));
  }
}

function projectStatus(projectName, res) {
  const dir = path.join(PROJECTS_DIR, projectName);
  const result = { name: projectName, exists: false };

  if (!fs.existsSync(dir)) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(result));
    return;
  }

  result.exists = true;

  try {
    result.state = fs.readFileSync(path.join(dir, '.make-it-state.md'), 'utf-8');
  } catch { result.state = null; }

  try {
    result.context = JSON.parse(fs.readFileSync(path.join(dir, '.make-it', 'app-context.json'), 'utf-8'));
  } catch { result.context = null; }

  try {
    result.todo = fs.readFileSync(path.join(dir, 'TODO.md'), 'utf-8');
  } catch { result.todo = null; }

  try {
    result.changelog = fs.readFileSync(path.join(dir, 'CHANGELOG.md'), 'utf-8');
  } catch { result.changelog = null; }

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(result));
}

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------
server.listen(PORT, '0.0.0.0', () => {
  console.log(`Workshop server listening on http://0.0.0.0:${PORT}`);
});
