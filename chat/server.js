// =============================================================================
// Claude Chat
//
// A chat/DM interface over the real Claude Code CLI. People reach for a
// messaging UI over a terminal, so the terminal is the implementation detail:
// every conversation is a live Claude Code session with the full tool set,
// bound to a folder on the mounted host tree.
//
// The conversation UUID is the Claude Code session id, so a thread started in
// the browser continues in the web terminal with `claude --resume <id>` and
// back again. See chat/agent.js.
// =============================================================================

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const providers = require('./providers');
const conversations = require('./conversations');
const agent = require('./agent');
const workdir = require('./workdir');

const PORT = parseInt(process.env.CHAT_PORT || '3002', 10);
const PUBLIC_DIR = path.join(__dirname, 'public');

const MIME = {
  '.html': 'text/html', '.css': 'text/css', '.js': 'application/javascript',
  '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon', '.woff2': 'font/woff2',
};

// convId -> running child process, so /stop can kill the turn.
const activeTurns = new Map();

function json(res, data, status = 200) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', c => chunks.push(c));
    req.on('end', () => {
      try { resolve(JSON.parse(Buffer.concat(chunks).toString())); }
      catch { resolve({}); }
    });
    req.on('error', reject);
  });
}

function serveStatic(req, res) {
  let fp = path.join(PUBLIC_DIR, req.url === '/' ? 'index.html' : req.url);
  fp = path.normalize(fp);
  if (!fp.startsWith(PUBLIC_DIR)) { res.writeHead(403); res.end(); return; }
  if (!fs.existsSync(fp)) {
    fp = path.join(PUBLIC_DIR, 'index.html');
  }
  const ext = path.extname(fp);
  const mime = MIME[ext] || 'application/octet-stream';
  try {
    const data = fs.readFileSync(fp);
    // no-store: a rebuilt bundle must show on plain reload (no stale cache).
    res.writeHead(200, {
      'Content-Type': mime,
      'Cache-Control': 'no-store, no-cache, must-revalidate, max-age=0',
      'Pragma': 'no-cache',
      'Expires': '0'
    });
    res.end(data);
  } catch {
    res.writeHead(404);
    res.end('Not found');
  }
}

function extractConvId(pathname) {
  const m = pathname.match(/^\/api\/conversations\/([a-f0-9-]+)/);
  return m ? m[1] : null;
}

function textOf(content) {
  if (typeof content === 'string') return content;
  return (content || []).filter(c => c.type === 'text').map(c => c.text).join('\n');
}

// ---------------------------------------------------------------------------
// One user message -> one `claude -p` process -> one SSE stream.
// ---------------------------------------------------------------------------
function streamTurn(conv, userContent, model, res) {
  const cwd = workdir.normalize(conv.cwd);
  if (cwd !== conv.cwd) conversations.update(conv.id, { cwd });

  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
    'X-Accel-Buffering': 'no',
  });

  let closed = false;
  res.on('close', () => {
    closed = true;
    const proc = activeTurns.get(conv.id);
    if (proc) { proc.kill('SIGTERM'); activeTurns.delete(conv.id); }
  });

  const send = (event, data) => {
    if (closed) return;
    try { res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`); } catch { /* client gone */ }
  };

  // A conversation can only be resumed once the CLI has written its transcript.
  // If the record claims a session but the file is gone (volume reset, folder
  // changed), start fresh rather than failing the turn outright.
  const resume = !!conv.session_started && agent.sessionExists(conv.id, cwd);

  send('agent:start', { cwd, resume, model: model || conv.model || null });

  const isFirstTurn = (conv.messages || []).length === 0;
  const userText = textOf(userContent);

  const proc = agent.runTurn({
    sessionId: conv.id,
    resume,
    cwd,
    prompt: userText,
    model: model || conv.model || undefined,
    systemPrompt: conv.system_prompt || undefined,
    onEvent: send,
    onDone: async ({ messages, usage, error, started }) => {
      activeTurns.delete(conv.id);

      conversations.addMessage(conv.id, 'user', userContent);
      for (const m of messages) {
        conversations.addMessage(conv.id, m.role, m.content,
          m.role === 'assistant' ? { model: model || conv.model, usage } : undefined);
      }
      if (started && !conv.session_started) {
        conversations.update(conv.id, { session_started: true });
      }
      if (usage) send('chat:usage', usage);

      // Name the thread from the first exchange, like Claude.ai does. Held
      // open briefly so the sidebar gets the real title instead of flashing
      // "New conversation" -- bounded, because it is a network call.
      if (isFirstTurn && !error) {
        const title = await generateTitle(userText, model).catch(() => null);
        conversations.update(conv.id, { title: title || fallbackTitle(userText) });
        send('chat:title_updated', { title: title || fallbackTitle(userText) });
      }

      if (!closed) res.end();
    },
  });

  if (proc) activeTurns.set(conv.id, proc);
}

// ---------------------------------------------------------------------------
// Title generation
// ---------------------------------------------------------------------------
function fallbackTitle(text) {
  const words = (text || '').trim().split(/\s+/).slice(0, 7).join(' ');
  return words ? words.slice(0, 60) : 'New conversation';
}

// Uses the Messages API directly rather than another CLI process -- it is a
// 30-token call and spinning up Claude Code for it would cost seconds.
// Providers without a direct HTTP path (Claude account login) throw here, and
// the caller falls back to the first words of the message.
function generateTitle(userText, model) {
  return new Promise((resolve, reject) => {
    const snippet = (userText || '').slice(0, 200);
    if (!snippet) return reject(new Error('empty'));

    let reqOpts;
    try {
      const titleModel = providers.getModels().find(m => m.tier === 'light')?.id || model;
      reqOpts = providers.buildRequest({
        model: titleModel,
        max_tokens: 30,
        messages: [{ role: 'user', content: `Generate a 4-6 word title for this conversation. Respond with ONLY the title, no quotes or punctuation.\n\nUser message: ${snippet}` }],
      });
    } catch (e) { return reject(e); }

    const transport = reqOpts.protocol === 'https:' ? https : http;
    const req = transport.request({
      hostname: reqOpts.hostname,
      port: reqOpts.port,
      path: reqOpts.path,
      method: 'POST',
      headers: reqOpts.headers,
      timeout: 8000,
    }, (r) => {
      let body = '';
      r.on('data', c => body += c);
      r.on('end', () => {
        try {
          const data = JSON.parse(body);
          const title = data.content?.[0]?.text?.trim();
          if (title) resolve(title.replace(/^["']|["']$/g, '')); else reject(new Error('no title'));
        } catch (e) { reject(e); }
      });
    });
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
    req.on('error', reject);
    req.write(reqOpts.body);
    req.end();
  });
}

// ---------------------------------------------------------------------------
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const pathname = url.pathname;

  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  try {
    if (pathname === '/health') {
      return json(res, { status: 'ok', service: 'claude-chat' });
    }

    if (pathname === '/api/providers') {
      return json(res, providers.getProviderInfo());
    }

    if (pathname === '/api/models') {
      return json(res, { models: providers.getModels(), default: providers.getDefaultModel() });
    }

    // Folder picker: roots are the host directories the container binds.
    if (pathname === '/api/workdir/roots') {
      return json(res, { roots: workdir.roots(), default: workdir.DEFAULT_CWD });
    }

    if (pathname === '/api/workdir/list') {
      return json(res, workdir.list(url.searchParams.get('path')));
    }

    if (pathname === '/api/conversations' && req.method === 'GET') {
      return json(res, conversations.list());
    }

    if (pathname === '/api/conversations' && req.method === 'POST') {
      const body = await readBody(req);
      const conv = conversations.create(body.model, body.system_prompt, workdir.normalize(body.cwd));
      return json(res, conv, 201);
    }

    const convId = extractConvId(pathname);
    if (convId) {
      if (pathname.endsWith('/messages') && req.method === 'POST') {
        const conv = conversations.get(convId);
        if (!conv) return json(res, { error: 'Not found' }, 404);
        if (activeTurns.has(convId)) return json(res, { error: 'A turn is already running' }, 409);
        const body = await readBody(req);
        const content = body.content || [{ type: 'text', text: body.text || '' }];
        return streamTurn(conv, content, body.model || conv.model, res);
      }

      if (pathname.endsWith('/stop') && req.method === 'POST') {
        const proc = activeTurns.get(convId);
        if (proc) { proc.kill('SIGTERM'); activeTurns.delete(convId); }
        return json(res, { stopped: !!proc });
      }

      if (pathname.endsWith('/export')) {
        const format = url.searchParams.get('format') || 'markdown';
        if (format === 'json') {
          const conv = conversations.get(convId);
          if (!conv) return json(res, { error: 'Not found' }, 404);
          return json(res, conv);
        }
        const md = conversations.exportMarkdown(convId);
        if (!md) return json(res, { error: 'Not found' }, 404);
        res.writeHead(200, { 'Content-Type': 'text/markdown', 'Content-Disposition': 'attachment; filename="conversation.md"' });
        return res.end(md);
      }

      if (req.method === 'GET') {
        const conv = conversations.get(convId);
        if (!conv) return json(res, { error: 'Not found' }, 404);
        return json(res, conv);
      }

      if (req.method === 'PUT') {
        const body = await readBody(req);
        // Changing the folder mid-thread would resume a session whose
        // transcript lives under the old path; normalise and let agent.js fall
        // back to a fresh session if the transcript can't be found.
        if (body.cwd !== undefined) body.cwd = workdir.normalize(body.cwd);
        const conv = conversations.update(convId, body);
        if (!conv) return json(res, { error: 'Not found' }, 404);
        return json(res, conv);
      }

      if (req.method === 'DELETE') {
        const proc = activeTurns.get(convId);
        if (proc) { proc.kill('SIGTERM'); activeTurns.delete(convId); }
        conversations.remove(convId);
        return json(res, { deleted: true });
      }
    }

    serveStatic(req, res);
  } catch (e) {
    console.error('[chat] Error:', e.message);
    json(res, { error: e.message }, 500);
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[chat] Claude Chat running on port ${PORT}`);
});
