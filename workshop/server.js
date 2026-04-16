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

const PORT = parseInt(process.env.WORKSHOP_PORT || '9200', 10);
const PUBLIC_DIR = path.join(__dirname, 'public');
const PROJECTS_DIR = process.env.PROJECTS_DIR || '/home/coder/Documents/GitHub';

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
function startProject(session, msg) {
  const projectName = sanitizeProjectName(msg.name || 'my-app');
  const projectDir = path.join(PROJECTS_DIR, projectName);

  if (!fs.existsSync(projectDir)) {
    fs.mkdirSync(projectDir, { recursive: true });
  }

  session.projectDir = projectDir;
  session.phase = 'ideation';

  session.ws.send(JSON.stringify({
    type: 'phase-change',
    phase: 'ideation',
    message: 'Starting your project...'
  }));

  spawnCLI(session, projectDir, '/make-it');
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

  session.phase = phaseMap[skill] || 'working';

  session.ws.send(JSON.stringify({
    type: 'phase-change',
    phase: session.phase,
    message: `Running ${skill}...`
  }));

  spawnCLI(session, session.projectDir, skill);
}

/**
 * Spawn Claude Code CLI with bidirectional stream-json.
 *
 * Uses: claude -p --output-format stream-json --input-format stream-json
 *       --permission-mode auto --include-partial-messages
 *
 * This gives us structured JSON events on stdout and accepts JSON messages
 * on stdin, avoiding all the TUI/ANSI parsing complexity.
 */
function spawnCLI(session, cwd, initialPrompt) {
  if (session.process) {
    session.process.kill('SIGTERM');
    session.process = null;
  }

  session.lineBuf = '';

  const args = [
    '-p',
    '--output-format', 'stream-json',
    '--input-format', 'stream-json',
    '--include-partial-messages',
    '--permission-mode', 'auto',
    '--bare',
  ];

  const proc = spawn('claude', args, {
    cwd,
    env: { ...process.env, NO_COLOR: '1' },
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  session.process = proc;

  // Accumulate partial text for the current assistant message
  let currentText = '';

  proc.stdout.on('data', (data) => {
    session.lineBuf += data.toString();

    // Stream-json outputs one JSON object per line
    let newlineIdx;
    while ((newlineIdx = session.lineBuf.indexOf('\n')) !== -1) {
      const line = session.lineBuf.slice(0, newlineIdx).trim();
      session.lineBuf = session.lineBuf.slice(newlineIdx + 1);

      if (!line) continue;

      try {
        const event = JSON.parse(line);
        handleStreamEvent(session, event, { getText: () => currentText, setText: (t) => { currentText = t; } });
      } catch {
        // Not valid JSON -- could be a startup message, ignore
      }
    }
  });

  proc.stderr.on('data', (data) => {
    const text = data.toString().trim();
    if (!text) return;
    // Forward translated errors to the browser
    session.ws.send(JSON.stringify({
      type: 'activity',
      category: 'system',
      message: translateError(text)
    }));
  });

  proc.on('error', (err) => {
    session.process = null;
    session.ws.send(JSON.stringify({
      type: 'error',
      message: err.code === 'ENOENT'
        ? 'Claude Code CLI not found. Is it installed?'
        : `Failed to start: ${err.message}`
    }));
  });

  proc.on('close', (code) => {
    session.process = null;
    session.ws.send(JSON.stringify({
      type: 'process-complete',
      phase: session.phase,
      exitCode: code,
      message: code === 0 ? 'Done!' : 'Something went wrong, but I can try again.'
    }));
  });

  // Send the initial prompt as a stream-json user message
  if (initialPrompt) {
    const inputMsg = JSON.stringify({
      type: 'user_message',
      content: initialPrompt,
    });
    proc.stdin.write(inputMsg + '\n');
  }
}

/**
 * Send a user message to the running CLI process via stream-json.
 */
function sendToProcess(session, text) {
  if (!session.process || !session.process.stdin.writable) return;

  const msg = JSON.stringify({
    type: 'user_message',
    content: text,
  });
  session.process.stdin.write(msg + '\n');
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
// Maps Claude Code stream events to Workshop UI events.
//
// Known event types from stream-json:
//   message_start, content_block_start, content_block_delta,
//   content_block_stop, message_delta, message_stop,
//   result (final), tool_use, tool_result
// ---------------------------------------------------------------------------
function handleStreamEvent(session, event, textAcc) {
  const type = event.type;

  // --- Assistant text content (partial and complete) ---
  if (type === 'content_block_delta' && event.delta?.type === 'text_delta') {
    const chunk = event.delta.text || '';
    textAcc.setText(textAcc.getText() + chunk);
    // Don't flood the browser -- we'll send the full text on block_stop
    return;
  }

  if (type === 'content_block_stop') {
    const fullText = textAcc.getText();
    textAcc.setText('');

    if (fullText) {
      processAssistantText(session, fullText);
    }
    return;
  }

  // --- Tool use (shows what Claude is doing) ---
  if (type === 'content_block_start' && event.content_block?.type === 'tool_use') {
    const toolName = event.content_block.name || 'unknown';
    const activity = toolToActivity(toolName, event.content_block.input);
    if (activity) {
      session.ws.send(JSON.stringify({
        type: 'activity',
        category: activity.category,
        message: activity.message,
      }));
    }
    return;
  }

  // --- Tool result (outcome of a tool call) ---
  if (type === 'tool_result' || (type === 'content_block_start' && event.content_block?.type === 'tool_result')) {
    // Could check for errors here
    return;
  }

  // --- Message complete ---
  if (type === 'message_stop' || type === 'result') {
    // Session ID from result for --resume
    if (event.session_id) {
      session.claudeSessionId = event.session_id;
    }
    return;
  }
}

/**
 * Process a complete assistant text block.
 * Detects phase changes, questions, and general updates.
 */
function processAssistantText(session, text) {
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
 */
function toolToActivity(toolName, input) {
  const toolMap = {
    'Write': { category: 'building', msg: (i) => `Creating ${shortPath(i?.file_path)}` },
    'Edit': { category: 'building', msg: (i) => `Editing ${shortPath(i?.file_path)}` },
    'Read': { category: 'general', msg: (i) => `Reading ${shortPath(i?.file_path)}` },
    'Bash': { category: 'infra', msg: (i) => bashToMessage(i?.command) },
    'Glob': { category: 'general', msg: () => 'Searching for files...' },
    'Grep': { category: 'general', msg: () => 'Searching code...' },
    'Agent': { category: 'building', msg: () => 'Working on a subtask...' },
    'TodoWrite': { category: 'general', msg: () => 'Updating task list...' },
  };

  const handler = toolMap[toolName];
  if (!handler) return { category: 'general', message: `Running ${toolName}...` };

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

function translateError(text) {
  if (/ENOENT/i.test(text)) return 'Setting up a missing piece...';
  if (/ECONNREFUSED/i.test(text)) return 'Waiting for a service to start...';
  if (/permission denied/i.test(text)) return 'Adjusting permissions...';
  if (/timeout/i.test(text)) return 'Taking a bit longer than expected...';
  if (/ANTHROPIC_API_KEY|auth|credential/i.test(text)) return 'Checking credentials...';
  return 'Working through something...';
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
