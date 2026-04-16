/**
 * Workshop Server
 * Business User IDE for Claude Code Docker
 *
 * HTTP server + WebSocket for real-time CLI orchestration.
 * Serves the Workshop SPA and bridges the browser to Claude Code CLI.
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');
const { spawn } = require('child_process');

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
  const session = { id: sessionId, ws, process: null, phase: 'idle', projectDir: null };
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
    // Kill CLI process if still running
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

  // Create project directory if it doesn't exist
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

  // Spawn Claude Code CLI with /make-it
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

function spawnCLI(session, cwd, initialInput) {
  // Kill any existing process
  if (session.process) {
    session.process.kill('SIGTERM');
  }

  const proc = spawn('claude', ['--no-browser'], {
    cwd,
    env: { ...process.env, TERM: 'dumb', NO_COLOR: '1' },
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  session.process = proc;

  // Buffer for parsing CLI output
  let outputBuffer = '';

  proc.stdout.on('data', (data) => {
    const text = data.toString();
    outputBuffer += text;
    parseCLIOutput(session, text, outputBuffer);
  });

  proc.stderr.on('data', (data) => {
    const text = data.toString();
    // Don't forward raw errors -- translate them
    session.ws.send(JSON.stringify({
      type: 'activity',
      category: 'system',
      message: translateError(text)
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

  // Send the initial skill command after a brief delay
  if (initialInput) {
    setTimeout(() => {
      proc.stdin.write(initialInput + '\n');
    }, 1000);
  }
}

function sendToProcess(session, text) {
  if (session.process && session.process.stdin.writable) {
    session.process.stdin.write(text + '\n');
  }
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
// CLI Output Parser -- Translates raw output to Workshop events
// ---------------------------------------------------------------------------
function parseCLIOutput(session, chunk, fullBuffer) {
  // Detect phase transitions from /make-it output
  const phasePatterns = [
    { pattern: /ideation|describe.*app|what.*build/i, phase: 'ideation', label: 'Understanding your idea' },
    { pattern: /design|architecture|stack|database/i, phase: 'design', label: 'Designing the architecture' },
    { pattern: /building|generating|creating.*file|writing.*code/i, phase: 'building', label: 'Building your app' },
    { pattern: /build-verify|testing|smoke.?test|verif/i, phase: 'verifying', label: 'Testing everything' },
    { pattern: /try-it|handoff|your app is/i, phase: 'complete', label: 'Ready to explore' },
  ];

  // Check for phase changes
  for (const { pattern, phase, label } of phasePatterns) {
    if (pattern.test(chunk) && session.phase !== phase) {
      session.phase = phase;
      session.ws.send(JSON.stringify({ type: 'phase-change', phase, message: label }));
    }
  }

  // Detect questions (lines ending with ?)
  const lines = chunk.split('\n').filter(l => l.trim());
  for (const line of lines) {
    const trimmed = line.trim();

    // Skip empty lines and control characters
    if (!trimmed || /^[\x00-\x1f]+$/.test(trimmed)) continue;

    // Detect yes/no questions for quick-reply buttons
    if (/\?\s*$/.test(trimmed)) {
      const isYesNo = /\b(yes|no|y\/n)\b/i.test(trimmed) ||
                      /\b(do you|will|should|is this|does|are you|would you)\b/i.test(trimmed);

      session.ws.send(JSON.stringify({
        type: 'question',
        text: cleanTerminalOutput(trimmed),
        quickReplies: isYesNo ? ['Yes', 'No'] : null
      }));
    } else if (trimmed.length > 10) {
      // Regular output -- send as activity
      session.ws.send(JSON.stringify({
        type: 'activity',
        category: detectCategory(trimmed),
        message: cleanTerminalOutput(trimmed)
      }));
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function detectCategory(text) {
  if (/creat|generat|writ|build|add/i.test(text)) return 'building';
  if (/test|verif|check|pass|fail/i.test(text)) return 'testing';
  if (/fix|error|issue|bug/i.test(text)) return 'fixing';
  if (/auth|login|oidc|permission/i.test(text)) return 'auth';
  if (/docker|container|compose/i.test(text)) return 'infra';
  if (/datab|migrat|seed|table/i.test(text)) return 'database';
  return 'general';
}

function cleanTerminalOutput(text) {
  // Strip ANSI escape codes, control chars, spinner chars
  return text
    .replace(/\x1b\[[0-9;]*[a-zA-Z]/g, '')
    .replace(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g, '')
    .replace(/[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏●◯⣾⣽⣻⢿⡿⣟⣯⣷]/g, '')
    .trim();
}

function translateError(text) {
  if (/ENOENT/i.test(text)) return 'Setting up a missing piece...';
  if (/ECONNREFUSED/i.test(text)) return 'Waiting for a service to start...';
  if (/permission denied/i.test(text)) return 'Adjusting permissions...';
  if (/timeout/i.test(text)) return 'Taking a bit longer than expected...';
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
      // SPA fallback -- serve index.html for unmatched routes
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

  // Read state file
  try {
    result.state = fs.readFileSync(path.join(dir, '.make-it-state.md'), 'utf-8');
  } catch { result.state = null; }

  // Read app context
  try {
    result.context = JSON.parse(fs.readFileSync(path.join(dir, '.make-it', 'app-context.json'), 'utf-8'));
  } catch { result.context = null; }

  // Read TODO
  try {
    result.todo = fs.readFileSync(path.join(dir, 'TODO.md'), 'utf-8');
  } catch { result.todo = null; }

  // Read CHANGELOG
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
