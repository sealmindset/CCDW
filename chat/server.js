const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const providers = require('./providers');
const conversations = require('./conversations');

const PORT = parseInt(process.env.CHAT_PORT || '3002', 10);
const PUBLIC_DIR = path.join(__dirname, 'public');

const MIME = {
  '.html': 'text/html', '.css': 'text/css', '.js': 'application/javascript',
  '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon', '.woff2': 'font/woff2',
};

const activeStreams = new Map();

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

function streamToProvider(conv, userContent, model, res) {
  const messages = conv.messages.map(m => ({
    role: m.role,
    content: m.content,
  }));
  messages.push({ role: 'user', content: userContent });

  const body = {
    model: model || conv.model || providers.getDefaultModel(),
    max_tokens: 8192,
    messages,
    stream: true,
  };
  if (conv.system_prompt) {
    body.system = conv.system_prompt;
  }

  let reqOpts;
  try {
    reqOpts = providers.buildRequest(body);
  } catch (e) {
    res.write(`event: chat:error\ndata: ${JSON.stringify({ message: e.message })}\n\n`);
    res.end();
    return;
  }

  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
    'X-Accel-Buffering': 'no',
  });

  const transport = reqOpts.protocol === 'https:' ? https : http;
  const proxyReq = transport.request({
    hostname: reqOpts.hostname,
    port: reqOpts.port,
    path: reqOpts.path,
    method: 'POST',
    headers: reqOpts.headers,
  }, (proxyRes) => {
    if (proxyRes.statusCode !== 200) {
      let errBody = '';
      proxyRes.on('data', c => errBody += c);
      proxyRes.on('end', () => {
        let msg = `API returned ${proxyRes.statusCode}`;
        try { const e = JSON.parse(errBody); msg = e.error?.message || e.message || msg; } catch {}
        res.write(`event: chat:error\ndata: ${JSON.stringify({ message: msg })}\n\n`);
        res.end();
      });
      return;
    }

    let assistantText = '';
    let usage = { input_tokens: 0, output_tokens: 0 };
    let stopReason = '';
    let msgModel = '';

    function onStreamEnd() {
      conversations.addMessage(conv.id, 'user', userContent);
      conversations.addMessage(conv.id, 'assistant',
        [{ type: 'text', text: assistantText }],
        { model: msgModel, usage, stop_reason: stopReason }
      );
      res.write(`event: chat:usage\ndata: ${JSON.stringify(usage)}\n\n`);
      if (conv.messages.length === 0) {
        generateTitle(conv.id, userContent, assistantText, msgModel || model);
      }
      activeStreams.delete(conv.id);
      res.end();
    }

    function onStreamError(e) {
      res.write(`event: chat:error\ndata: ${JSON.stringify({ message: e.message })}\n\n`);
      activeStreams.delete(conv.id);
      res.end();
    }

    function handleEvent(data) {
      if (data.type === 'message_start' && data.message) {
        usage.input_tokens = data.message.usage?.input_tokens || 0;
        msgModel = data.message.model || '';
      }
      if (data.type === 'content_block_delta' && data.delta?.text) {
        assistantText += data.delta.text;
      }
      if (data.type === 'message_delta') {
        stopReason = data.delta?.stop_reason || '';
        usage.output_tokens = data.usage?.output_tokens || 0;
      }
    }

    if (reqOpts.bedrockStream) {
      // Bedrock returns AWS binary event stream, not SSE text
      let bedrockBuf = Buffer.alloc(0);
      proxyRes.on('data', (chunk) => {
        bedrockBuf = Buffer.concat([bedrockBuf, chunk]);
        while (true) {
          const msg = providers.parseEventStreamMessage(bedrockBuf, 0);
          if (!msg) break;
          bedrockBuf = bedrockBuf.slice(msg.totalLen);

          if (msg.headers[':message-type'] === 'exception') {
            try {
              const err = JSON.parse(msg.payload.toString());
              res.write(`event: chat:error\ndata: ${JSON.stringify({ message: err.message || 'Bedrock error' })}\n\n`);
            } catch {}
            continue;
          }

          const event = providers.extractBedrockEvent(msg.payload);
          if (!event) continue;
          res.write(`event: ${event.type || 'unknown'}\ndata: ${JSON.stringify(event)}\n\n`);
          handleEvent(event);
        }
      });
      proxyRes.on('end', onStreamEnd);
      proxyRes.on('error', onStreamError);
    } else {
      // Anthropic/Foundry SSE text stream
      let buf = '';
      proxyRes.on('data', (chunk) => {
        buf += chunk.toString();
        const lines = buf.split('\n');
        buf = lines.pop();

        for (const line of lines) {
          if (line.startsWith('event: ')) {
            res.write(line + '\n');
          } else if (line.startsWith('data: ')) {
            res.write(line + '\n\n');
            try { handleEvent(JSON.parse(line.slice(6))); } catch {}
          }
        }
      });
      proxyRes.on('end', onStreamEnd);
      proxyRes.on('error', onStreamError);
    }
  });

  proxyReq.on('error', (e) => {
    res.write(`event: chat:error\ndata: ${JSON.stringify({ message: e.message })}\n\n`);
    activeStreams.delete(conv.id);
    res.end();
  });

  activeStreams.set(conv.id, proxyReq);
  proxyReq.write(reqOpts.body);
  proxyReq.end();

  res.on('close', () => {
    activeStreams.delete(conv.id);
    proxyReq.destroy();
  });
}

function generateTitle(convId, userContent, assistantText, model) {
  const userText = typeof userContent === 'string' ? userContent
    : userContent.filter(c => c.type === 'text').map(c => c.text).join(' ');
  const snippet = userText.slice(0, 200);

  try {
    const titleModel = providers.getModels().find(m => m.tier === 'light')?.id || model;
    const reqOpts = providers.buildRequest({
      model: titleModel,
      max_tokens: 30,
      messages: [{ role: 'user', content: `Generate a 4-6 word title for this conversation. Respond with ONLY the title, no quotes or punctuation.\n\nUser message: ${snippet}` }],
    });

    const transport = reqOpts.protocol === 'https:' ? https : http;
    const req = transport.request({
      hostname: reqOpts.hostname,
      port: reqOpts.port,
      path: reqOpts.path,
      method: 'POST',
      headers: reqOpts.headers,
    }, (res) => {
      let body = '';
      res.on('data', c => body += c);
      res.on('end', () => {
        try {
          const data = JSON.parse(body);
          const title = data.content?.[0]?.text?.trim();
          if (title) conversations.update(convId, { title });
        } catch {}
      });
    });
    req.on('error', () => {});
    req.write(reqOpts.body);
    req.end();
  } catch {}
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const pathname = url.pathname;

  // CORS for same-origin
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

    if (pathname === '/api/conversations' && req.method === 'GET') {
      return json(res, conversations.list());
    }

    if (pathname === '/api/conversations' && req.method === 'POST') {
      const body = await readBody(req);
      const conv = conversations.create(body.model, body.system_prompt);
      return json(res, conv, 201);
    }

    const convId = extractConvId(pathname);
    if (convId) {
      if (pathname.endsWith('/messages') && req.method === 'POST') {
        const conv = conversations.get(convId);
        if (!conv) return json(res, { error: 'Not found' }, 404);
        const body = await readBody(req);
        const content = body.content || [{ type: 'text', text: body.text || '' }];
        const model = body.model || conv.model;
        return streamToProvider(conv, content, model, res);
      }

      if (pathname.endsWith('/stop') && req.method === 'POST') {
        const stream = activeStreams.get(convId);
        if (stream) { stream.destroy(); activeStreams.delete(convId); }
        return json(res, { stopped: true });
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
        const conv = conversations.update(convId, body);
        if (!conv) return json(res, { error: 'Not found' }, 404);
        return json(res, conv);
      }

      if (req.method === 'DELETE') {
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
